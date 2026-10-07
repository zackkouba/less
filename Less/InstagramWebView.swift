import Observation
import SwiftUI
import UIKit
import WebKit

struct InstagramWebView: UIViewRepresentable {
    let browser: InstagramBrowser

    func makeUIView(context: Context) -> WKWebView {
        browser.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

@MainActor
@Observable
final class InstagramBrowser: NSObject {
    let webView: WKWebView
    private(set) var statusMessage = ""
    private(set) var profilePath: String?

    private var blockReels = true
    private var exitReelOnScroll = true
    private var authorizedReelPath: String?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: InstagramScripts.bootstrap,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .page
            )
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        configuration.userContentController.add(self, name: InstagramScripts.messageHandler)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.clipsToBounds = true
        webView.scrollView.clipsToBounds = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        open(.home)
    }

    func open(_ tab: AppTab) {
        authorizedReelPath = nil

        switch tab {
        case .home:
            load(path: "/")
        case .search:
            load(path: "/explore/")
        case .messages:
            load(path: "/direct/inbox/")
        case .profile:
            if let profilePath {
                load(path: profilePath)
            } else {
                webView.evaluateJavaScript(InstagramScripts.openProfile)
            }
        case .settings:
            break
        }
    }

    func updatePolicy(blockReels: Bool, exitReelOnScroll: Bool) {
        self.blockReels = blockReels
        self.exitReelOnScroll = exitReelOnScroll
        sendConfigurationToPage()

        if blockReels, isReelsFeed(webView.url) {
            returnHome(reason: "Reels feed blocked")
        }
    }

    func applyAppearance(_ appearance: AppAppearance) {
        let value = appearance == .system ? "normal" : appearance.rawValue
        webView.evaluateJavaScript("window.lessApp?.setAppearance('\(value)')")
    }

    func clearInstagramData() {
        statusMessage = "Clearing session…"
        let store = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        store.fetchDataRecords(ofTypes: dataTypes) { [weak self] records in
            let metaRecords = records.filter { record in
                let name = record.displayName.lowercased()
                return name.contains("instagram") || name.contains("facebook") || name.contains("meta")
            }

            store.removeData(ofTypes: dataTypes, for: metaRecords) { [weak self] in
                guard let self else { return }
                self.profilePath = nil
                self.authorizedReelPath = nil
                self.statusMessage = "Session cleared"
                self.load(path: "/accounts/login/")
            }
        }
    }

    private func load(path: String) {
        guard let url = URL(string: path, relativeTo: InstagramRoute.baseURL)?.absoluteURL else { return }
        if webView.url?.absoluteURL == url {
            webView.reload()
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    private func sendConfigurationToPage() {
        let script = "window.lessApp?.configure({blockReels: \(blockReels), exitOnScroll: \(exitReelOnScroll)})"
        webView.evaluateJavaScript(script)
    }

    private func returnHome(reason: String) {
        authorizedReelPath = nil
        statusMessage = reason
        load(path: "/")
    }

    private func isReelsFeed(_ url: URL?) -> Bool {
        guard let path = url?.path.lowercased() else { return false }
        return path == "/reels" || path.hasPrefix("/reels/")
    }

    private func isReel(_ url: URL?) -> Bool {
        url?.path.lowercased().hasPrefix("/reel/") == true
    }

    private func normalizedReelPath(_ path: String) -> String? {
        guard path.lowercased().hasPrefix("/reel/") else { return nil }
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return "/reel/\(parts[1])/"
    }
}

private enum InstagramRoute {
    static let baseURL = URL(string: "https://www.instagram.com")!

    static func isAllowedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "instagram.com"
            || host.hasSuffix(".instagram.com")
            || host == "facebook.com"
            || host.hasSuffix(".facebook.com")
            || host == "meta.com"
            || host.hasSuffix(".meta.com")
    }
}

extension InstagramBrowser: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.cancel)
            return
        }

        guard InstagramRoute.isAllowedHost(url.host) else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
            }
            return
        }

        if blockReels, isReelsFeed(url) {
            decisionHandler(.cancel)
            returnHome(reason: "Reels feed blocked")
            return
        }

        if blockReels, isReel(url) {
            let requestedPath = normalizedReelPath(url.path)
            guard requestedPath == authorizedReelPath else {
                decisionHandler(.cancel)
                returnHome(reason: "Only reels opened from DMs are allowed")
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusMessage = ""
        sendConfigurationToPage()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        statusMessage = "Instagram restarted after a web content error"
        webView.reload()
    }
}

extension InstagramBrowser: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == InstagramScripts.messageHandler,
              let payload = message.body as? [String: Any],
              let type = payload["type"] as? String else { return }

        switch type {
        case "dmReelTapped":
            if let path = payload["path"] as? String {
                authorizedReelPath = normalizedReelPath(path)
            }
        case "profilePath":
            if let path = payload["path"] as? String, path.hasPrefix("/") {
                profilePath = path
            }
        case "blockedReel":
            if blockReels {
                returnHome(reason: "Only reels opened from DMs are allowed")
            }
        case "reelAdvanceAttempt":
            if blockReels, exitReelOnScroll {
                returnHome(reason: "Returned Home after leaving the shared reel")
            }
        default:
            break
        }
    }
}

extension InstagramBrowser: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if InstagramRoute.isAllowedHost(url.host) {
                webView.load(URLRequest(url: url))
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }
}

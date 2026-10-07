import Observation
import SwiftUI
import UIKit
import WebKit

struct InstagramWebView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let browser: InstagramBrowser

    func makeUIView(context: Context) -> WKWebView {
        browser.updateBackground(for: colorScheme)
        return browser.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        browser.updateBackground(for: colorScheme)
    }
}

@MainActor
@Observable
final class InstagramBrowser: NSObject {
    let webView: WKWebView
    private(set) var statusMessage = ""
    private(set) var pageBackgroundColor = UIColor.systemBackground
    private var hasReportedPageBackgroundColor = false
    private var blockReels = true
    private var exitReelOnScroll = true
    private var authorizedReelPath: String?
    private var reelReturnPath: String?
    private var isDiagnosingDMContentTransition = false

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
        load(path: "/")
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

    func updateBackground(for colorScheme: ColorScheme) {
        guard !hasReportedPageBackgroundColor else { return }
        let fallback = colorScheme == .dark
            ? UIColor(red: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1)
            : UIColor.white
        applyBackgroundColor(fallback)
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

    private func applyBackgroundColor(_ color: UIColor) {
        pageBackgroundColor = color
        webView.backgroundColor = color
        webView.scrollView.backgroundColor = color
        webView.underPageBackgroundColor = color
    }

    private func color(fromCSS value: String) -> UIColor? {
        let components = value
            .replacingOccurrences(of: "rgba(", with: "")
            .replacingOccurrences(of: "rgb(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }

        guard components.count >= 3 else { return nil }
        if components.count == 4, components[3] == 0 { return nil }

        return UIColor(
            red: components[0] / 255,
            green: components[1] / 255,
            blue: components[2] / 255,
            alpha: 1
        )
    }

    private func returnHome(reason: String) {
        authorizedReelPath = nil
        statusMessage = reason
        load(path: "/")
    }

    private func returnToConversation() {
        authorizedReelPath = nil
        statusMessage = "Returned to the conversation after leaving the shared reel"

        if let reelReturnPath {
            load(path: reelReturnPath)
        } else if webView.url?.path.lowercased().hasPrefix("/direct/") == true {
            webView.reload()
        } else if webView.canGoBack {
            webView.goBack()
        } else {
            load(path: "/")
        }
        reelReturnPath = nil
    }

    private func compactLogValue(_ value: String) -> String {
        guard value.count > 50 else { return value }
        return "\(value.prefix(50))…"
    }

    private func isReelsFeed(_ url: URL?) -> Bool {
        guard let path = url?.path.lowercased() else { return false }
        return path == "/reels" || path == "/reels/"
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
            if authorizedReelPath == nil {
                returnHome(reason: "Reels feed blocked")
            } else {
                returnToConversation()
            }
            return
        }

        if blockReels, isReel(url) {
            let requestedPath = normalizedReelPath(url.path)
            if isDiagnosingDMContentTransition {
                decisionHandler(.allow)
                return
            }
            guard requestedPath == authorizedReelPath else {
                decisionHandler(.cancel)
                returnToConversation()
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
        case "dmVideoSessionStarted":
            isDiagnosingDMContentTransition = true
            if let url = webView.url,
               url.path.lowercased().hasPrefix("/direct/") {
                reelReturnPath = url.path + (url.query.map { "?\($0)" } ?? "")
            }
            if let value = payload["value"] as? String {
                print("[Less] Started DM video session from visible video: \(compactLogValue(value))")
            }
        case "dmVideoObserved":
            if let value = payload["value"] as? String {
                print("[Less] Tracking first active DM video: \(compactLogValue(value))")
            }
        case "dmVideoTransition":
            let from = payload["from"] as? String ?? "unknown"
            let to = payload["to"] as? String ?? "unknown"
            print("[Less] Detected active video transition after DM: \(compactLogValue(from)) -> \(compactLogValue(to))")
            if isDiagnosingDMContentTransition {
                isDiagnosingDMContentTransition = false
                returnToConversation()
            }
        case "dmVideoSessionEnded":
            isDiagnosingDMContentTransition = false
            reelReturnPath = nil
        case "dmContentTapped":
            isDiagnosingDMContentTransition = true
            if let returnPath = payload["returnPath"] as? String,
               returnPath.lowercased().hasPrefix("/direct/") {
                reelReturnPath = returnPath
            }
        case "dmContentTransition":
            let from = payload["from"] as? String ?? "unknown"
            let to = payload["to"] as? String ?? "unknown"
            print("[Less] Detected content transition after DM: \(from) -> \(to)")
        case "dmContentSessionEnded":
            isDiagnosingDMContentTransition = false
            reelReturnPath = nil
        case "dmReelTapped":
            if let path = payload["path"] as? String {
                authorizedReelPath = normalizedReelPath(path)
            }
            if let returnPath = payload["returnPath"] as? String,
               returnPath.lowercased().hasPrefix("/direct/") {
                reelReturnPath = returnPath
            }
        case "blockedReel":
            if blockReels {
                if authorizedReelPath == nil {
                    returnHome(reason: "Only reels opened from DMs are allowed")
                } else {
                    returnToConversation()
                }
            }
        case "reelAdvanceAttempt":
            if blockReels, exitReelOnScroll {
                returnToConversation()
            }
        case "pageBackgroundColor":
            if let value = payload["value"] as? String,
               let color = color(fromCSS: value) {
                hasReportedPageBackgroundColor = true
                applyBackgroundColor(color)
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

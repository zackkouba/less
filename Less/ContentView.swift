import SwiftUI

struct ContentView: View {
    @State private var browser = InstagramBrowser()
    @AppStorage("selectedTab") private var selectedTab = AppTab.home.rawValue
    @AppStorage("blockReels") private var blockReels = true
    @AppStorage("exitReelOnScroll") private var exitReelOnScroll = true
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    private var activeTab: AppTab {
        get { AppTab(rawValue: selectedTab) ?? .home }
        nonmutating set { selectedTab = newValue.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                InstagramWebView(browser: browser)
                    .opacity(activeTab == .settings ? 0 : 1)
                    .allowsHitTesting(activeTab != .settings)

                if activeTab == .settings {
                    SettingsView(
                        browser: browser,
                        blockReels: $blockReels,
                        exitReelOnScroll: $exitReelOnScroll,
                        appearance: $appearance
                    )
                }
            }

            LessTabBar(selectedTab: activeTab) { tab in
                activeTab = tab
                guard tab != .settings else { return }
                browser.open(tab)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .onAppear {
            browser.updatePolicy(
                blockReels: blockReels,
                exitReelOnScroll: exitReelOnScroll
            )
            browser.applyAppearance(AppAppearance(rawValue: appearance) ?? .system)
            if activeTab != .settings {
                browser.open(activeTab)
            }
        }
        .onChange(of: blockReels) { _, newValue in
            browser.updatePolicy(
                blockReels: newValue,
                exitReelOnScroll: exitReelOnScroll
            )
        }
        .onChange(of: exitReelOnScroll) { _, newValue in
            browser.updatePolicy(
                blockReels: blockReels,
                exitReelOnScroll: newValue
            )
        }
        .onChange(of: appearance) { _, _ in
            browser.applyAppearance(AppAppearance(rawValue: appearance) ?? .system)
        }
    }
}

#Preview {
    ContentView()
}

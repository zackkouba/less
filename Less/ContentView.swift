import SwiftUI

struct ContentView: View {
    @State private var browser = InstagramBrowser()
    @State private var navigation = AppNavigation.shared
    @AppStorage("blockReels") private var blockReels = true
    @AppStorage("exitReelOnScroll") private var exitReelOnScroll = true
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    var body: some View {
        ZStack {
            Color(uiColor: browser.pageBackgroundColor)
                .ignoresSafeArea()

            InstagramWebView(browser: browser)
        }
        .sheet(isPresented: $navigation.showsSettings) {
            SettingsView(
                browser: browser,
                blockReels: $blockReels,
                exitReelOnScroll: $exitReelOnScroll,
                appearance: $appearance
            )
        }
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .onAppear {
            browser.updatePolicy(
                blockReels: blockReels,
                exitReelOnScroll: exitReelOnScroll
            )
            browser.applyAppearance(AppAppearance(rawValue: appearance) ?? .system)
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

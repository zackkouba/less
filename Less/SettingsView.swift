import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let browser: InstagramBrowser
    @Binding var blockReels: Bool
    @Binding var exitReelOnScroll: Bool
    @Binding var appearance: String
    @State private var showsClearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                ReelsSettingsSection(
                    blockReels: $blockReels,
                    exitReelOnScroll: $exitReelOnScroll
                )
                AppearanceSettingsSection(appearance: $appearance)
                SessionSettingsSection(
                    status: browser.statusMessage,
                    clearSession: { showsClearConfirmation = true }
                )
                AboutSettingsSection()
            }
            .navigationTitle("Less Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Clear Instagram session?",
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Session and Log Out", role: .destructive) {
                    browser.clearInstagramData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes Instagram and Meta cookies and website data stored by Less. Your password is never stored by the app.")
            }
        }
    }
}

private struct ReelsSettingsSection: View {
    @Binding var blockReels: Bool
    @Binding var exitReelOnScroll: Bool

    var body: some View {
        Section {
            Toggle("Hide and block Reels", isOn: $blockReels)
            Toggle("Return to chat after swiping a DM reel", isOn: $exitReelOnScroll)
                .disabled(!blockReels)
        } header: {
            Text("Focus")
        } footer: {
            Text("A reel opened directly from a conversation remains available. Trying to advance to another reel returns you to the conversation.")
        }
    }
}

private struct AppearanceSettingsSection: View {
    @Binding var appearance: String

    var body: some View {
        Section("Appearance") {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
        }
    }
}

private struct SessionSettingsSection: View {
    let status: String
    let clearSession: () -> Void

    var body: some View {
        Section {
            if !status.isEmpty {
                Label(status, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            Button("Clear Session and Log Out", role: .destructive, action: clearSession)
        } header: {
            Text("Instagram Session")
        } footer: {
            Text("Less stores Instagram's normal WebKit session cookies. It never reads or saves your Instagram password.")
        }
    }
}

private struct AboutSettingsSection: View {
    var body: some View {
        Section {
            LabeledContent("App", value: "Less")
            LabeledContent("Instagram integration", value: InstagramScripts.version)
        } header: {
            Text("About")
        } footer: {
            Text("Instagram may change its website without notice. Less fails closed when it cannot verify that a reel came from DMs.")
        }
    }
}

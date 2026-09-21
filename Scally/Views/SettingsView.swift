import SwiftUI
import SwiftData

/// Settings, transcribed from the design's S2 and S2b.
///
/// The design's two cards are reproduced exactly. Everything below them is an
/// addition and is kept in a third card so the designed part stays the
/// designed part: Licenses because both model licences oblige reproducing
/// their notice with the binary, and Sharpening and Compare models because
/// they are real features the design predates.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [UpscaleRecord]
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("sharpen") private var sharpen = 0.45

    /// Harness seam, as in `HistoryView`.
    var startConfirmingClear = false

    @State private var confirmingClear = false
    @State private var storedBytes = 0

    private let store = LibraryStore()

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Button("Back") { dismiss() }
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.label(0.7))
                        Spacer()
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 6)

                    HStack {
                        Text("Settings")
                            .font(.system(size: 32, weight: .semibold))
                            .tracking(-0.8)
                            .foregroundStyle(Palette.primaryText)
                        Spacer()
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 14)
                    .padding(.bottom, 22)

                    ScrollView {
                        VStack(spacing: 26) {
                            storage
                            preferences
                            additions
                            colophon
                        }
                        .padding(.horizontal, Metrics.gutter)
                    }
                }

                if confirmingClear {
                    ConfirmSheet(
                        message: "All \(records.count) results and their \(formatted(storedBytes)) will be removed from Scally.",
                        detail: "The originals in your Photos library are untouched.",
                        confirm: "Clear All \(records.count) Results",
                        onConfirm: {
                            try? store.deleteAll(context: context)
                            storedBytes = store.totalBytes()
                            confirmingClear = false
                        },
                        onCancel: { confirmingClear = false })
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                storedBytes = store.totalBytes()
                if startConfirmingClear { confirmingClear = true }
            }
        }
    }

    private var storage: some View {
        SettingsCard {
            SettingsRow(label: "Storage used", value: formatted(storedBytes), mono: true)
            SettingsDivider()
            SettingsRow(label: "Results kept", value: "\(records.count)", mono: true)
            SettingsDivider()
            Button { confirmingClear = true } label: {
                HStack {
                    Text("Clear history")
                        .font(.system(size: 16))
                        .foregroundStyle(records.isEmpty ? Palette.label(0.3) : Palette.destructive)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(records.isEmpty)
        }
    }

    private var preferences: some View {
        SettingsCard {
            Menu {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            } label: {
                SettingsRow(label: "Appearance", value: appearanceName)
            }
            SettingsDivider()
            SettingsRow(label: "Save location", value: "Photos")
        }
    }

    private var additions: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Sharpening").font(.system(size: 16)).foregroundStyle(Palette.primaryText)
                    Spacer()
                    Text(sharpen < 0.01 ? "OFF" : String(format: "%.2f", sharpen))
                        .font(.system(size: 14).monospaced())
                        .foregroundStyle(Palette.label(0.56))
                }
                Slider(value: $sharpen, in: 0...1.2, step: 0.05).tint(Palette.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            SettingsDivider()
            NavigationLink { LicensesView() } label: {
                SettingsRow(label: "Licenses", value: "", chevron: true)
            }
            .buttonStyle(.plain)
            SettingsDivider()
            NavigationLink { CompareModelsView() } label: {
                SettingsRow(label: "Compare models", value: "", chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var colophon: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scally never connects to the internet. There is no account, no analytics, no upload, and nothing to pay for. Your photos and results stay in this app's own storage until you delete them.")
                .font(.system(size: 12.5))
                .lineSpacing(4)
                .foregroundStyle(Palette.label(0.42))
                .fixedSize(horizontal: false, vertical: true)
            Text("VERSION \(appVersion) · BUILD \(buildNumber)")
                .font(Typography.caption)
                .foregroundStyle(Palette.label(0.28))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 20)
    }

    private var appearanceName: String {
        switch appearance {
        case "light": "Light"
        case "dark": "Dark"
        default: "System"
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// The design's settings card: surface, a 7% border - a step softer than the
/// 8% used elsewhere - and rows that rule against each other, not against the
/// card edge.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.card))
            .overlay(RoundedRectangle(cornerRadius: Metrics.card)
                .strokeBorder(Palette.outline(0.07)))
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Palette.outline(0.07)).frame(height: 1)
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    var mono = false
    var chevron = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(Palette.primaryText)
            Spacer(minLength: 12)
            if !value.isEmpty {
                Text(value)
                    .font(mono ? .system(size: 14).monospaced() : .system(size: 15))
                    .foregroundStyle(Palette.label(mono ? 0.56 : 0.5))
            }
            if chevron {
                Chevron().foregroundStyle(Palette.label(0.3))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

/// Required, not optional. Both licences below oblige reproducing their notice
/// with the binary, and both are NON-COMMERCIAL - which is why Scally is free.
/// The design omits this row; it is added deliberately.
struct LicensesView: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let title: String
        let blurb: String
        let resource: String
    }

    private let entries = [
        Entry(title: "4xNomosWebPhoto_RealPLKSR",
              blurb: "The model Scally runs, by Philip Hofmann. CC BY 4.0 - attribution only, commercial use permitted.",
              resource: "NomosWebPhoto-RealPLKSR-CC-BY-4.0"),
    ]

    private func text(_ resource: String) -> String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "License text unavailable."
        }
        return contents
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Scally upscales images with a single convolutional model trained on realistic web-photo degradation. It is licensed for any use, including commercial, so long as its author is credited - which is what this screen is for.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.label(0.55))

                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(entry.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Palette.primaryText)
                        Text(entry.blurb)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.label(0.55))
                        Text(text(entry.resource))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.label(0.7))
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.gutter)
        }
        .background(Palette.background)
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// S4. States what the app can and cannot see, rather than apologising.
struct LibraryDeniedView: View {
    let onSettings: () -> Void
    let onChooseSpecific: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Scally")
                    .font(Typography.wordmark)
                    .tracking(Tracking.wordmark)
                    .foregroundStyle(Palette.primaryText)
                Spacer()
                Button("Settings", action: onSettings)
                    .font(Typography.navAction)
                    .foregroundStyle(Palette.label(0.56))
            }
            .padding(.horizontal, 2)
            .padding(.top, 14)

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("No access to your library")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)

                Text("Scally can only see photos you give it. Nothing is read in the background and nothing is uploaded either way.")
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.label(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onSettings) { FilledButtonLabel(title: "Open Settings") }
                    .padding(.top, 4)
                Button(action: onChooseSpecific) {
                    OutlineButtonLabel(title: "Choose specific photos", height: 54, size: 16)
                }
            }
            .padding(18)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.card))
            .overlay(RoundedRectangle(cornerRadius: Metrics.card).strokeBorder(Palette.hairline))

            Text("SETTINGS → PRIVACY → PHOTOS → SCALLY")
                .font(Typography.captionTiny)
                .tracking(Tracking.sectionLabel)
                .foregroundStyle(Palette.label(0.34))
                .padding(.top, 18)

            Spacer()

            VStack(spacing: 3) {
                Text("Runs entirely on this iPhone.")
                Text("Nothing is uploaded. No account. No internet.")
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.label(0.34))
            .multilineTextAlignment(.center)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, Metrics.gutter)
    }
}

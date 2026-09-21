import SwiftUI
import SwiftData

/// Built from the design's tokens rather than a stock `List`.
///
/// The grouped-list default brought its own background, its own separators and
/// its own type, none of which are this app's, so the one screen that is
/// nothing but rows was the one screen that did not look like the app.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [UpscaleRecord]
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("sharpen") private var sharpen = 0.45

    @State private var confirmingClear = false
    @State private var storedBytes = 0

    private let store = LibraryStore()

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        storage
                        sharpening
                        preferences
                        footer
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Palette.accent)
                }
            }
            .task { storedBytes = store.totalBytes() }
            .confirmationDialog("Clear history?", isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("Clear All \(records.count) Results", role: .destructive) {
                    try? store.deleteAll(context: context)
                    storedBytes = store.totalBytes()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All \(records.count) results and their \(formatted(storedBytes)) will be removed from Scally. The originals in your Photos library are untouched.")
            }
        }
    }

    private var storage: some View {
        SettingsCard {
            SettingsRow(label: "Storage used", value: formatted(storedBytes))
            SettingsDivider()
            SettingsRow(label: "Results kept", value: "\(records.count)")
            SettingsDivider()
            Button { confirmingClear = true } label: {
                HStack {
                    Text("Clear history")
                        .font(Typography.body)
                        .foregroundStyle(records.isEmpty ? Palette.tertiaryText : Palette.destructive)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(records.isEmpty)
        }
    }

    private var sharpening: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sharpening").font(Typography.body).foregroundStyle(Palette.primaryText)
                        Spacer()
                        Text(sharpen < 0.01 ? "OFF" : String(format: "%.2f", sharpen))
                            .font(Typography.metric)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Slider(value: $sharpen, in: 0...1.2, step: 0.05)
                        .tint(Palette.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            Text("Applied after upscaling. It cannot invent detail, but it raises edge contrast, which is what reads as sharp. Too much produces halos.")
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
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
                SettingsRow(label: "Appearance", value: appearanceName, chevron: true)
            }
            SettingsDivider()
            SettingsRow(label: "Save location", value: "Photos")
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

    private var footer: some View {
        VStack(spacing: 10) {
            Text("Runs entirely on this iPhone. Nothing is uploaded. No account. No internet.")
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            FieldLabel("VERSION \(appVersion) · BUILD \(buildNumber)")
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
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

/// One bordered surface holding a run of rows - the app's card, not the
/// system's inset group.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.card))
            .overlay(RoundedRectangle(cornerRadius: Metrics.card).strokeBorder(Palette.border))
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(Palette.border).padding(.leading, 14)
    }
}

/// Label left, monospaced value right - the same shape as `MetricRow`, in the
/// sentence case the design uses for settings rather than mono capitals.
struct SettingsRow: View {
    let label: String
    let value: String
    var chevron = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Typography.body)
                .foregroundStyle(Palette.primaryText)
            Spacer(minLength: 12)
            if !value.isEmpty {
                Text(value)
                    .font(Typography.metric)
                    .foregroundStyle(Palette.secondaryText)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
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
        Entry(title: "ResShift",
              blurb: "The diffusion architecture and its VQ autoencoder. S-Lab License 1.0, non-commercial.",
              resource: "ResShift-SLab"),
        Entry(title: "RSD",
              blurb: "The one-step distilled student Scally runs. CC BY-NC-SA 4.0, non-commercial and share-alike.",
              resource: "RSD-CC-BY-NC-SA"),
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
                Text("Scally upscales images with a one-step diffusion model distilled from ResShift. Both components are licensed for non-commercial use, which is why Scally is free and has no in-app purchases.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)

                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(entry.title).font(Typography.screenTitle)
                        Text(entry.blurb)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                        Text(text(entry.resource))
                            .font(.system(size: 11, design: .monospaced))
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

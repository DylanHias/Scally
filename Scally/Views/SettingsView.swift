import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [UpscaleRecord]
    @AppStorage("appearance") private var appearance = "system"

    @State private var confirmingClear = false
    @State private var storedBytes = 0

    private let store = LibraryStore()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Storage used") {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(storedBytes), countStyle: .file))
                            .font(Typography.metric)
                    }
                    LabeledContent("Results kept") {
                        Text("\(records.count)").font(Typography.metric)
                    }
                    Button("Clear history", role: .destructive) { confirmingClear = true }
                        .disabled(records.isEmpty)
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    LabeledContent("Save location", value: "Photos")
                    NavigationLink("Licenses") { LicensesView() }
                }

                Section {
                    Text("Runs entirely on this iPhone. Nothing is uploaded. No account. No internet.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                } footer: {
                    Text("VERSION \(appVersion) · BUILD \(buildNumber)")
                        .font(Typography.sectionLabel)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
                Text("All \(records.count) results and their \(ByteCountFormatter.string(fromByteCount: Int64(storedBytes), countStyle: .file)) will be removed from Scally. The originals in your Photos library are untouched.")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
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

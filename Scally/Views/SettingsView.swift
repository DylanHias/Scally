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

/// Required, not optional: BSD-3-Clause obliges reproducing the copyright
/// notice and disclaimer in materials distributed with the binary (spec
/// section 2). The design omits this row; it is added here deliberately.
struct LicensesView: View {
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "RealESRGAN-BSD3", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "License text unavailable."
        }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Real-ESRGAN").font(Typography.screenTitle)
                Text("Scally upscales images using Real-ESRGAN (realesr-general-x4v3).")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                Text(licenseText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.gutter)
        }
        .background(Palette.background)
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI
import SwiftData
import PhotosUI

struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UpscaleRecord.createdAt, order: .reverse) private var records: [UpscaleRecord]

    @State private var selection: PhotosPickerItem?
    @State private var pending: PendingImage?
    @State private var showingSettings = false
    @State private var showingFiles = false
    @State private var libraryDenied = false

    private let store = LibraryStore()

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                if libraryDenied {
                    LibraryDeniedView { libraryDenied = false }
                } else {
                    content
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .navigationDestination(item: $pending) { ConfigureView(pending: $0) }
            .photosPicker(isPresented: .constant(false), selection: $selection)
            .fileImporter(isPresented: $showingFiles,
                          allowedContentTypes: [.image]) { handleFileImport($0) }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task {
                    let loaded = await PendingImage.load(from: item)
                    selection = nil
                    pending = PendingImage.resolve(current: pending, loaded: loaded)
                }
            }
        }
    }

    /// The wordmark lives in the content, not the toolbar: iOS renders toolbar
    /// items as fixed-width glass capsules, which truncated this to "S...".
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scally")
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.primaryText)
                FieldLabel("ON-DEVICE UPSCALER")
            }
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.primaryText)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            actions
            recent
            Spacer(minLength: 0)
            TrustPanel(storedBytes: store.totalBytes())
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                Text("Choose a photo")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Palette.background)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.primaryText, in: RoundedRectangle(cornerRadius: Metrics.control))
            }

            HStack(spacing: 10) {
                SecondaryButton(title: "Paste", systemImage: "doc.on.clipboard", action: pasteImage)
                SecondaryButton(title: "Files", systemImage: "folder") { showingFiles = true }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FieldLabel("RECENT")
                Spacer()
                if !records.isEmpty {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Text("All \(records.count)")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.accent)
                    }
                }
            }

            if records.isEmpty {
                Text("No files yet.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(records.prefix(3)) { record in
                        NavigationLink { SavedResultView(record: record) } label: {
                            RecentRow(record: record, thumbnailURL: store.thumbnailURL(for: record))
                        }
                        .buttonStyle(.plain)
                        if record.id != records.prefix(3).last?.id {
                            Divider().overlay(Palette.border)
                        }
                    }
                }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.card))
                .overlay(RoundedRectangle(cornerRadius: Metrics.card).strokeBorder(Palette.border))
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 26)
    }

    private func pasteImage() {
        guard let image = UIPasteboard.general.image,
              let data = image.pngData() else { return }
        pending = PendingImage.make(from: data, filename: "Pasted.png")
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        pending = PendingImage.make(from: data, filename: url.lastPathComponent)
    }
}

private struct SecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Typography.body)
                .foregroundStyle(Palette.primaryText)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.control))
                .overlay(RoundedRectangle(cornerRadius: Metrics.control).strokeBorder(Palette.border))
        }
    }
}

private struct RecentRow: View {
    let record: UpscaleRecord
    let thumbnailURL: URL

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = UIImage(contentsOfFile: thumbnailURL.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Palette.surfaceRaised)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.originalFilename)
                    .font(Typography.body)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Text(record.dimensionSummary)
                    .font(Typography.caption.monospaced())
                    .foregroundStyle(Palette.secondaryText)
            }

            Spacer(minLength: 8)
            ScaleBadge(scale: record.appliedScale)
            Text(RelativeDate.short(record.createdAt))
                .font(Typography.caption.monospaced())
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// The two-column panel that states, plainly, what the app does and does not do.
private struct TrustPanel: View {
    let storedBytes: Int

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                column(label: "ENGINE", value: DeviceChip.engineLabel)
                column(label: "NETWORK", value: "NOT USED")
            }
            if storedBytes > 0 {
                HStack {
                    FieldLabel("STORED LOCALLY")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(storedBytes), countStyle: .file))
                        .font(Typography.caption.monospaced())
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .padding(Metrics.gutter)
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    private func column(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(label)
            Text(value)
                .font(Typography.caption.monospaced())
                .foregroundStyle(Palette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The design's trust panel names the silicon - `NEURAL · A17 PRO` - because
/// "neural engine" alone tells someone nothing about the machine in their hand.
/// Read from the hardware rather than hardcoded, so it stays true on the next
/// phone; anything unrecognised falls back to the plain claim rather than
/// guessing at a chip.
enum DeviceChip {
    static var engineLabel: String {
        guard let chip else { return "NEURAL ENGINE" }
        return "NEURAL · \(chip)"
    }

    static let chip: String? = {
        var system = utsname()
        uname(&system)
        let identifier = withUnsafeBytes(of: &system.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return chips[identifier]
    }()

    private static let chips: [String: String] = [
        "iPhone11,2": "A12", "iPhone11,4": "A12", "iPhone11,6": "A12", "iPhone11,8": "A12",
        "iPhone12,1": "A13", "iPhone12,3": "A13", "iPhone12,5": "A13", "iPhone12,8": "A13",
        "iPhone13,1": "A14", "iPhone13,2": "A14", "iPhone13,3": "A14", "iPhone13,4": "A14",
        "iPhone14,2": "A15", "iPhone14,3": "A15", "iPhone14,4": "A15", "iPhone14,5": "A15",
        "iPhone14,6": "A15", "iPhone14,7": "A15", "iPhone14,8": "A15",
        "iPhone15,2": "A16", "iPhone15,3": "A16", "iPhone15,4": "A16", "iPhone15,5": "A16",
        "iPhone16,1": "A17 PRO", "iPhone16,2": "A17 PRO",
        "iPhone17,1": "A18 PRO", "iPhone17,2": "A18 PRO",
        "iPhone17,3": "A18", "iPhone17,4": "A18", "iPhone17,5": "A18",
        "iPhone18,1": "A19 PRO", "iPhone18,2": "A19 PRO",
        "iPhone18,3": "A19", "iPhone18,4": "A19 PRO",
    ]
}

enum RelativeDate {
    /// The History form: `TODAY 09:38`, `TUE 18:02`, `12 SEP`. A result from
    /// this morning and one from last Tuesday must not both read as a bare
    /// time, which is why History does not reuse `short`.
    static func long(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "TODAY \(time)" }
        // No YESTERDAY case: it is the longest label of the set and it forced
        // the row to truncate, while the weekday form already covers the day
        // before. The design only ever shows TODAY, a weekday, or a date.
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return "\(date.formatted(.dateTime.weekday(.abbreviated)).uppercased()) \(time)"
        }
        return date.formatted(.dateTime.day().month(.abbreviated)).uppercased()
    }

    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        }
        return date.formatted(.dateTime.day().month(.abbreviated)).uppercased()
    }
}

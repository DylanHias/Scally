import SwiftUI
import SwiftData
import PhotosUI

/// Import, transcribed from the design's screens 1 and 2.
///
/// The two states are not the same screen with a list hidden: with no history
/// the footer states what the engine is and that the network is unused; with
/// history it states how much is stored locally instead. The design swaps
/// them, and it is right to - the trust claim earns its place once, and after
/// that the useful number is the one about the user's own disk.
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
                    LibraryDeniedView(onSettings: { showingSettings = true },
                                      onChooseSpecific: { libraryDenied = false })
                } else {
                    content
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showingSettings) { SettingsView() }
            .navigationDestination(item: $pending) { ConfigureView(pending: $0) }
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

    private var content: some View {
        VStack(spacing: 0) {
            header
            chooseRow.padding(.top, 30)
            secondaryRow.padding(.top, 10)
            recentHeader.padding(.top, records.isEmpty ? 36 : 32)
            recentBody
            footer
        }
        .padding(.horizontal, Metrics.gutter)
    }

    /// The wordmark lives in the content, not the toolbar: iOS renders toolbar
    /// items as fixed-width glass capsules, which truncated this to "S...".
    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Scally")
                    .font(Typography.wordmark)
                    .tracking(Tracking.wordmark)
                    .foregroundStyle(Palette.primaryText)
                Text("ON-DEVICE UPSCALER")
                    .font(Typography.caption)
                    .tracking(Tracking.subtitle)
                    .foregroundStyle(Palette.label(0.4))
            }
            Spacer()
            Button("Settings") { showingSettings = true }
                .font(Typography.navAction)
                .foregroundStyle(Palette.label(0.56))
        }
        .padding(.horizontal, 2)
        .padding(.top, 14)
    }

    /// The design's primary action is a surface row with a ringed plus, not a
    /// filled slab. The filled slab is reserved for Upscale and Save - the two
    /// actions that commit something.
    private var chooseRow: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 0) {
                Text("Choose a photo")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.primaryText)
                Spacer()
                PlusRing()
            }
            .padding(.horizontal, 18)
            .frame(height: Metrics.primaryRowHeight)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.card))
            .overlay(RoundedRectangle(cornerRadius: Metrics.card).strokeBorder(Palette.hairline))
        }
    }

    private var secondaryRow: some View {
        HStack(spacing: 10) {
            secondary("Paste", action: pasteImage)
            secondary("Files") { showingFiles = true }
        }
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.rowLabel)
                .foregroundStyle(Palette.label(0.72))
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.secondaryRowHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.card))
                .overlay(RoundedRectangle(cornerRadius: Metrics.card).strokeBorder(Palette.hairline))
        }
    }

    private var recentHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("RECENT")
                Spacer()
                if !records.isEmpty {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        HStack(spacing: 7) {
                            Text("All \(records.count)")
                            Chevron()
                        }
                        .font(Typography.bodySmall)
                        .foregroundStyle(Palette.label(0.56))
                    }
                }
            }
            .padding(.bottom, 10)
            Hairline()
        }
    }

    @ViewBuilder
    private var recentBody: some View {
        if records.isEmpty {
            HStack {
                Text("No files yet.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.label(0.34))
                Spacer()
            }
            .padding(.top, 22)
            Spacer(minLength: 0)
        } else {
            VStack(spacing: 0) {
                ForEach(records.prefix(3)) { record in
                    NavigationLink { SavedResultView(record: record) } label: {
                        RecentRow(record: record, thumbnailURL: store.thumbnailURL(for: record))
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Palette.hairlineSoft).frame(height: 1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            VStack(spacing: 6) {
                if records.isEmpty {
                    TrustRow(label: "ENGINE", value: DeviceChip.engineLabel)
                    TrustRow(label: "NETWORK", value: "NOT USED")
                } else {
                    TrustRow(label: "STORED LOCALLY",
                             value: ByteCountFormatter.string(
                                fromByteCount: Int64(store.totalBytes()), countStyle: .file))
                }
            }
            .padding(.vertical, 14)
        }
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

/// The ringed plus on the Choose a photo row: a 26 pt ring at 28% with two
/// 11 x 1.5 bars, drawn rather than borrowed from SF Symbols so its weight
/// matches the design instead of the system's.
struct PlusRing: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.plusRing, lineWidth: 1)
                .frame(width: 26, height: 26)
            Rectangle().fill(Palette.label(0.85)).frame(width: 11, height: 1.5)
            Rectangle().fill(Palette.label(0.85)).frame(width: 1.5, height: 11)
        }
    }
}

/// The design draws its disclosure chevron as a rotated corner, not a glyph.
struct Chevron: View {
    var body: some View {
        Rectangle()
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5))
            .frame(width: 6, height: 6)
            .mask(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    Rectangle().frame(height: 1.5)
                    HStack(spacing: 0) { Spacer(); Rectangle().frame(width: 1.5) }
                }
            }
            .rotationEffect(.degrees(45))
    }
}

private struct RecentRow: View {
    let record: UpscaleRecord
    let thumbnailURL: URL

    var body: some View {
        HStack(spacing: 13) {
            Thumbnail(url: thumbnailURL, side: 46, radius: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.originalFilename)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Text(record.dimensionSummary)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.label(0.45))
                    .lineLimit(1)
            }

            VStack(alignment: .trailing, spacing: 4) {
                RecentBadge(scale: record.appliedScale)
                Text(RelativeDate.short(record.createdAt))
                    .font(Typography.captionTiny)
                    .foregroundStyle(Palette.label(0.34))
            }
            .fixedSize()
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// The recent row's badge: mono, on a 10% wash, not the accent.
struct RecentBadge: View {
    let scale: Int

    var body: some View {
        Text("\(scale)×")
            .font(.system(size: 11, weight: .semibold).monospaced())
            .foregroundStyle(Palette.primaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct Thumbnail: View {
    let url: URL
    let side: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Palette.surfaceRaised)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// The design's trust panel names the silicon - `NEURAL · A17 PRO` - because
/// "neural engine" alone tells someone nothing about the machine in their hand.
/// Read from the hardware rather than hardcoded, so it stays true on the next
/// phone; anything unrecognised falls back to the plain claim.
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
    /// Import's compact form: `09:38`, `TUE`, `12 SEP`.
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

    /// History's form, captioned under each tile: `TODAY 09:38`, `TUE 18:02`,
    /// `12 SEP`. A grid of thumbnails has no other place to carry a date, so
    /// unlike Import's list this one always says which day it means.
    static func long(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "TODAY \(time)" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return "\(date.formatted(.dateTime.weekday(.abbreviated)).uppercased()) \(time)"
        }
        return date.formatted(.dateTime.day().month(.abbreviated)).uppercased()
    }
}

import SwiftUI
import SwiftData

/// History, transcribed from the design's S1, S1b and S1c.
///
/// A two-column grid of square tiles, each captioned with its date - not a
/// list. The prose extract of the design said the opposite, and the list was
/// built from that; this is what the design actually draws.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UpscaleRecord.createdAt, order: .reverse) private var records: [UpscaleRecord]

    @State private var isSelecting = false
    @State private var selected: Set<UUID> = []
    @State private var confirmingDelete = false

    private let store = LibraryStore()
    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                bar
                title
                grid
                if isSelecting && !selected.isEmpty { selectionBar } else { footer }
            }

            if confirmingDelete {
                ConfirmSheet(
                    message: "These \(selected.count) results will be removed from Scally.",
                    detail: "The originals in your Photos library are untouched.",
                    confirm: "Delete \(selected.count) Results",
                    onConfirm: deleteSelected,
                    onCancel: { confirmingDelete = false })
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }

    private var bar: some View {
        HStack {
            Button(isSelecting ? "Select All" : "Back") {
                if isSelecting { selected = Set(records.map(\.id)) } else { dismiss() }
            }
            Spacer()
            if !records.isEmpty {
                Button(isSelecting ? "Cancel" : "Select") {
                    isSelecting.toggle()
                    selected.removeAll()
                }
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(Palette.label(0.7))
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
    }

    private var title: some View {
        HStack {
            Text(isSelecting ? "\(selected.count) selected" : "History")
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Palette.primaryText)
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var grid: some View {
        if records.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Text("Nothing yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text("Upscaled photos you save will appear here.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.label(0.45))
                Spacer()
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(records) { record in
                        tile(for: record)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
        }
    }

    @ViewBuilder
    private func tile(for record: UpscaleRecord) -> some View {
        let content = HistoryTile(record: record,
                                  thumbnailURL: store.thumbnailURL(for: record),
                                  selecting: isSelecting,
                                  selected: selected.contains(record.id))
        if isSelecting {
            Button { toggle(record) } label: { content }.buttonStyle(.plain)
        } else {
            NavigationLink { SavedResultView(record: record) } label: { content }
                .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        Text("\(records.count) RESULTS · \(formatted(store.totalBytes())) ON THIS IPHONE")
            .font(Typography.caption)
            .foregroundStyle(Palette.label(0.34))
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 10)
    }

    private var selectionBar: some View {
        HStack {
            ShareLink(items: selectedRecords.map { store.outputURL(for: $0) }) {
                Text("Share").font(.system(size: 16)).foregroundStyle(Palette.primaryText)
            }
            Spacer()
            Text("\(selected.count) ITEMS · \(formatted(selectedBytes))")
                .font(Typography.caption)
                .foregroundStyle(Palette.label(0.34))
            Spacer()
            Button("Delete") { confirmingDelete = true }
                .font(.system(size: 16))
                .foregroundStyle(Palette.destructive)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 14)
    }

    private var selectedRecords: [UpscaleRecord] { records.filter { selected.contains($0.id) } }
    private var selectedBytes: Int { selectedRecords.reduce(0) { $0 + $1.totalBytes } }

    private func toggle(_ record: UpscaleRecord) {
        if selected.contains(record.id) { selected.remove(record.id) }
        else { selected.insert(record.id) }
    }

    private func deleteSelected() {
        try? store.delete(selectedRecords, context: context)
        selected.removeAll()
        isSelecting = false
        confirmingDelete = false
    }

    private func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// One square tile plus its date. Selecting moves the scale badge to the
/// bottom-left so the check can take the corner it was in.
private struct HistoryTile: View {
    let record: UpscaleRecord
    let thumbnailURL: URL
    let selecting: Bool
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                if let image = UIImage(contentsOfFile: thumbnailURL.path) {
                    PhotoFill(image: image)
                } else {
                    Rectangle().fill(Palette.surfaceRaised)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Palette.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: selecting ? .bottomLeading : .topTrailing) {
                TileBadge(scale: record.appliedScale).padding(7)
            }
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.9),
                                         selected ? Color.white : Color.white.opacity(0.35))
                        .padding(7)
                }
            }

            Text(RelativeDate.long(record.createdAt))
                .font(Typography.captionTiny)
                .foregroundStyle(Palette.label(0.34))
                .lineLimit(1)
        }
    }
}

/// The tile's scale badge: mono on a 60% black wash, which reads on any photo.
private struct TileBadge: View {
    let scale: Int

    var body: some View {
        Text("\(scale)×")
            .font(.system(size: 9.5, weight: .semibold).monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// S1c and S2b: the design's own confirmation, not the system's.
///
/// `confirmationDialog` brings its own type, its own corner radius and its own
/// scrim, none of which are this app's, and the destructive verb ends up in a
/// tint the palette never chose.
struct ConfirmSheet: View {
    let message: String
    let detail: String
    let confirm: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    VStack(spacing: 3) {
                        Text(message)
                        Text(detail)
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.label(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)

                    Rectangle().fill(Palette.hairline).frame(height: 1)

                    Button(action: onConfirm) {
                        Text(confirm)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.destructive)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                }
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.card))
                .overlay(RoundedRectangle(cornerRadius: Metrics.card).strokeBorder(Palette.hairline))

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Palette.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: Metrics.card))
                        .overlay(RoundedRectangle(cornerRadius: Metrics.card)
                            .strokeBorder(Palette.hairline))
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 10)
        }
        .transition(.opacity)
    }
}

/// A saved result. The retained original means this is a real comparison, not
/// an image held up against itself.
struct SavedResultView: View {
    let record: UpscaleRecord
    private let store = LibraryStore()

    @Environment(\.dismiss) private var dismiss
    @State private var before: UIImage?
    @State private var after: UIImage?
    @State private var compare = CompareState()

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenBar(leading: "Back",
                          title: "\(record.originalFilename) · \(record.appliedScale)×",
                          titleAlpha: 0.6) { dismiss() }
                    trailing: { ZoomBadge(state: compare) }
                    .padding(.vertical, 8)

                Group {
                    if let before, let after {
                        HoldToCompare(before: before, after: after, state: compare)
                    } else {
                        Palette.photoWell.overlay { ProgressView().tint(Palette.accent) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 18)
                .padding(.top, 12)

                VStack(spacing: 0) {
                    DetailRow(label: "INPUT",
                              value: "\(record.inputWidth) × \(record.inputHeight) · \(formatted(record.inputBytes))",
                              labelAlpha: 0.45, valueSize: 11.5)
                        .padding(.bottom, 6)
                    DetailRow(label: "OUTPUT",
                              value: "\(record.outputWidth) × \(record.outputHeight) · \(formatted(record.outputBytes))",
                              labelAlpha: 0.45, valueSize: 11.5)
                        .padding(.bottom, 16)

                    ShareLink(item: store.outputURL(for: record)) {
                        FilledButtonLabel(title: "Share")
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 16)
                .padding(.bottom, 14)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .task {
            before = UIImage(contentsOfFile: store.inputURL(for: record).path)
            after = UIImage(contentsOfFile: store.outputURL(for: record).path)
        }
    }

    private func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

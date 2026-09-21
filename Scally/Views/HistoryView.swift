import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UpscaleRecord.createdAt, order: .reverse) private var records: [UpscaleRecord]

    @State private var isSelecting = false
    @State private var selected: Set<UUID> = []
    @State private var confirmingDelete = false

    private let store = LibraryStore()

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            if records.isEmpty {
                ContentUnavailableView {
                    Text("Nothing yet").font(Typography.screenTitle)
                } description: {
                    Text("Upscaled photos you save will appear here.")
                        .font(Typography.body)
                }
            } else {
                list
            }
        }
        .navigationTitle(isSelecting ? "\(selected.count) selected" : "History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .confirmationDialog("Delete \(selected.count) results?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete \(selected.count) Results", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These \(selected.count) results will be removed from Scally. The originals in your Photos library are untouched.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button("Cancel") {
                    isSelecting = false
                    selected.removeAll()
                }
            } else if !records.isEmpty {
                Button("Select") { isSelecting = true }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button("Select All") { selected = Set(records.map(\.id)) }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(records) { record in
                    row(for: record)
                    Divider().overlay(Palette.border).padding(.leading, 68)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)

            Text("\(records.count) RESULTS · \(formatted(store.totalBytes())) ON THIS IPHONE")
                .font(Typography.sectionLabel)
                .tracking(0.9)
                .foregroundStyle(Palette.tertiaryText)
                .padding(.vertical, 22)
        }
    }

    @ViewBuilder
    private func row(for record: UpscaleRecord) -> some View {
        if isSelecting {
            Button { toggle(record) } label: {
                HistoryRow(record: record,
                           thumbnailURL: store.thumbnailURL(for: record),
                           selected: selected.contains(record.id),
                           selecting: true)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { SavedResultView(record: record) } label: {
                HistoryRow(record: record,
                           thumbnailURL: store.thumbnailURL(for: record),
                           selected: false,
                           selecting: false)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isSelecting && !selected.isEmpty {
            HStack {
                ShareLink(items: selectedRecords.map { store.outputURL(for: $0) }) {
                    Text("Share").font(Typography.body).foregroundStyle(Palette.primaryText)
                }
                Spacer()
                Text("\(selected.count) ITEMS · \(formatted(selectedBytes))")
                    .font(Typography.sectionLabel)
                    .foregroundStyle(Palette.tertiaryText)
                Spacer()
                Button("Delete") { confirmingDelete = true }
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Palette.destructive)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 14)
            .background(Palette.surface)
            .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
        }
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
    }

    private func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct HistoryRow: View {
    let record: UpscaleRecord
    let thumbnailURL: URL
    let selected: Bool
    let selecting: Bool

    var body: some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Palette.accent : Palette.tertiaryText)
            }

            Group {
                if let image = UIImage(contentsOfFile: thumbnailURL.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Palette.surfaceRaised)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.originalFilename)
                    .font(Typography.body).foregroundStyle(Palette.primaryText).lineLimit(1)
                Text(record.dimensionSummary)
                    .font(Typography.caption.monospaced())
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            ScaleBadge(scale: record.appliedScale)
            // History uses the long form the design specifies - TODAY 09:38,
            // TUE 18:02, 12 SEP - where Import's compact list uses the short.
            Text(RelativeDate.long(record.createdAt))
                .font(Typography.badge)
                .tracking(0.5)
                .foregroundStyle(Palette.tertiaryText)
                // The date keeps its width and the filename gives way. The
                // other order truncates the one column that is never
                // recoverable from anywhere else on the row.
                .fixedSize()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// A saved result. The retained original means this is a real comparison, not
/// an image held up against itself.
struct SavedResultView: View {
    let record: UpscaleRecord
    private let store = LibraryStore()

    @State private var before: UIImage?
    @State private var after: UIImage?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                if let before, let after {
                    HoldToCompare(before: before, after: after)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.card))
                        .padding(.horizontal, Metrics.gutter)
                } else {
                    ProgressView().tint(Palette.accent).frame(maxHeight: .infinity)
                }

                VStack(spacing: 10) {
                    MetricRow(label: "INPUT",
                              value: "\(record.inputWidth) × \(record.inputHeight) · \(formatted(record.inputBytes))")
                    MetricRow(label: "OUTPUT",
                              value: "\(record.outputWidth) × \(record.outputHeight) · \(formatted(record.outputBytes))")
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 14)

                ShareLink(item: store.outputURL(for: record)) {
                    Text("Share")
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(Palette.background)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Palette.primaryText, in: RoundedRectangle(cornerRadius: Metrics.control))
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle("\(record.originalFilename) · \(record.appliedScale)×")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .task {
            before = UIImage(contentsOfFile: store.inputURL(for: record).path)
            after = UIImage(contentsOfFile: store.outputURL(for: record).path)
        }
    }

    private func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

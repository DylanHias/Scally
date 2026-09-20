import SwiftUI
import SwiftData
import ScallyKit

struct ResultView: View {
    let pending: PendingImage
    let result: UpscaleResult

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var afterImage: UIImage?
    @State private var saveState: SaveState = .idle

    enum SaveState: Equatable { case idle, saving, saved, failed(String) }

    private let store = LibraryStore()

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if let afterImage {
                    HoldToCompare(before: pending.preview, after: afterImage)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.card))
                        .padding(.horizontal, Metrics.gutter)
                } else {
                    ProgressView().tint(Palette.accent).frame(maxHeight: .infinity)
                }

                if case .failed(let message) = saveState {
                    SaveFailureBanner(message: message)
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 12)
                }

                if result.wasClamped {
                    Text("Upscaled at \(result.appliedScale)×. \(result.requestedScale)× needed more memory than this iPhone had free.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 10)
                }

                metrics
                actions
            }
        }
        .navigationTitle("\(pending.filename) · \(result.appliedScale)×")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Discard", role: .destructive) { dismiss() }
                    .tint(Palette.secondaryText)
            }
        }
        .task { afterImage = UIImage(contentsOfFile: result.outputURL.path) }
    }

    private var metrics: some View {
        VStack(spacing: 10) {
            MetricRow(label: "INPUT",
                      value: "\(pending.width) × \(pending.height) · \(formatted(pending.byteCount))")
            MetricRow(label: "OUTPUT",
                      value: "\(result.outputWidth) × \(result.outputHeight) · \(formatted(outputBytes))")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: save) {
                Text(saveLabel)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Palette.background)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.primaryText, in: RoundedRectangle(cornerRadius: Metrics.control))
            }
            .disabled(saveState == .saving || saveState == .saved)

            ShareLink(item: result.outputURL) {
                Text("Share")
                    .font(Typography.body)
                    .foregroundStyle(Palette.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.control))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.control).strokeBorder(Palette.border))
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var saveLabel: String {
        switch saveState {
        case .saved: "Saved"
        case .saving: "Saving…"
        case .failed: "Try again"
        default: "Save to Photos"
        }
    }

    private var outputBytes: Int {
        (try? result.outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func save() {
        saveState = .saving
        Task {
            do {
                try await PhotoSaver.save(fileURL: result.outputURL)
                // Persisting MOVES the output, so it must follow the Photos
                // save, which reads from that same path.
                let thumbnail = Thumbnailer.make(from: result.outputURL) ?? Data()
                try store.save(result: result, sourceURL: pending.url,
                               originalFilename: pending.filename,
                               inputWidth: pending.width, inputHeight: pending.height,
                               thumbnail: thumbnail, context: context)
                saveState = .saved
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }
}

private struct SaveFailureBanner: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Couldn't save to Photos")
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Palette.destructive)
            Text("\(message) The result is still here.")
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: Metrics.control))
    }
}

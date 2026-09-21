import SwiftUI
import SwiftData
import ScallyKit

/// Result, transcribed from the design's screen 5 and its S5 edge case.
struct ResultView: View {
    let pending: PendingImage
    let result: UpscaleResult

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Harness seam, as in `HistoryView`.
    var startSaveState: SaveState = .idle

    @State private var afterImage: UIImage?
    @State private var saveState: SaveState = .idle
    @State private var compare = CompareState()

    enum SaveState: Equatable { case idle, saving, saved, failed(String) }

    private let store = LibraryStore()

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenBar(leading: "Discard",
                          title: "\(pending.filename) · \(result.appliedScale)×",
                          leadingColor: Palette.primaryText,
                          titleAlpha: 0.6) { dismiss() }
                    trailing: { ZoomBadge(state: compare) }
                    .padding(.vertical, 8)

                Group {
                    if let afterImage {
                        HoldToCompare(before: pending.preview, after: afterImage, state: compare)
                    } else {
                        Palette.photoWell.overlay { ProgressView().tint(Palette.accent) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 18)
                .padding(.top, 12)

                footer
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .task {
            afterImage = UIImage(contentsOfFile: result.outputURL.path)
            if startSaveState != .idle { saveState = startSaveState }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            // The design replaces the metrics with the banner rather than
            // stacking both: S5 carries no INPUT/OUTPUT rows at all. Two
            // blocks of small text under a failure reads as clutter at exactly
            // the moment the screen has one thing to say.
            if case .failed(let message) = saveState {
                SaveFailureBanner(message: message).padding(.bottom, 14)
            }

            if result.wasClamped {
                ClampNotice(text: "Upscaled at \(result.appliedScale)×. \(result.requestedScale)× needed more memory than this iPhone had free.")
                    .padding(.bottom, 14)
            }

            if !isShowingFailure {
                DetailRow(label: "INPUT",
                          value: "\(pending.width) × \(pending.height) · \(formatted(pending.byteCount))",
                          labelAlpha: 0.45, valueSize: 11.5)
                    .padding(.bottom, 6)
                DetailRow(label: "OUTPUT",
                          value: "\(result.outputWidth) × \(result.outputHeight) · \(formatted(outputBytes))",
                          labelAlpha: 0.45, valueSize: 11.5)
                    .padding(.bottom, 16)
            }

            HStack(spacing: 10) {
                Button(action: save) { FilledButtonLabel(title: saveLabel) }
                    .disabled(saveState == .saving || saveState == .saved)

                ShareLink(item: result.outputURL) {
                    OutlineButtonLabel(title: "Share", height: 54, alpha: 0.22, size: 16)
                        .frame(width: 96)
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var isShowingFailure: Bool {
        if case .failed = saveState { return true }
        return false
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

/// S5. The design keeps the destructive colour for the headline only - the
/// explanation is ordinary text, because the result is not lost.
struct SaveFailureBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .strokeBorder(Palette.destructive, lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn't save to Photos")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text("\(message) The result is still here — free up space and try again.")
                    .font(.system(size: 12.5))
                    .lineSpacing(2.5)
                    .foregroundStyle(Palette.bannerText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(Palette.destructiveWash, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.destructiveBorder))
    }
}

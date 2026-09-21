#if DEBUG
import SwiftUI
import ScallyKit

/// A way to put any designed screen on the display without navigating to it.
///
/// Comparing the build against `docs/design/flow-board/` means reaching
/// screens that are otherwise behind a photo pick, a completed upscale or a
/// memory condition that will not occur on the machine doing the comparing.
/// Driving that through the UI is slow and flaky - the photo picker wedged the
/// simulator twice - so each screen can be addressed directly instead:
///
///     xcrun simctl launch <udid> dh.Scally -designScreen result
///
/// DEBUG only. It is a comparison rig, not a feature.
enum DesignHarness {
    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-designScreen"),
              arguments.index(after: index) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: index)]
    }

    /// A synthetic photograph. Deterministic, so two runs are comparable, and
    /// structured enough that a fill, a crop and a scrim are all visible.
    static func image(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colours = [UIColor(red: 0.42, green: 0.52, blue: 0.72, alpha: 1).cgColor,
                           UIColor(red: 0.78, green: 0.58, blue: 0.45, alpha: 1).cgColor,
                           UIColor(red: 0.22, green: 0.26, blue: 0.34, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colours as CFArray, locations: [0, 0.55, 1])!
            context.cgContext.drawLinearGradient(
                gradient, start: .zero,
                end: CGPoint(x: size.width, y: size.height), options: [])

            UIColor(white: 0.97, alpha: 0.9).setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: size.width * 0.28, y: size.height * 0.22,
                                                   width: size.width * 0.44,
                                                   height: size.width * 0.44))
            ring.lineWidth = max(2, size.width * 0.012)
            ring.stroke()

            UIColor(white: 0.1, alpha: 0.8).setStroke()
            let rule = UIBezierPath()
            rule.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.82))
            rule.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.76))
            rule.lineWidth = max(2, size.width * 0.008)
            rule.stroke()
        }
    }

    static func pending(width: Int = 240, height: Int = 240,
                        filename: String = "IMG_4471.JPG") -> PendingImage {
        let image = self.image(width: width, height: height)
        let data = image.jpegData(compressionQuality: 0.85) ?? Data()
        let url = FileManager.default.temporaryDirectory
            .appending(path: "harness-input-\(width)x\(height).jpg")
        try? data.write(to: url)
        return PendingImage(url: url, preview: image, width: width, height: height,
                            byteCount: data.count, filename: filename)
    }

    static func result(scale: Int = 4, requested: Int = 4) -> UpscaleResult {
        let image = self.image(width: 960, height: 960)
        let data = image.jpegData(compressionQuality: 0.9) ?? Data()
        let url = FileManager.default.temporaryDirectory.appending(path: "harness-output.jpg")
        try? data.write(to: url)
        return UpscaleResult(outputURL: url, outputWidth: 960, outputHeight: 960,
                             appliedScale: scale, requestedScale: requested, duration: 6.1)
    }
}

/// Renders whichever screen the launch argument names.
struct DesignHarnessView: View {
    let screen: String

    var body: some View {
        switch screen {
        case "configure":
            NavigationStack { ConfigureView(pending: DesignHarness.pending()) }
        case "clamp":
            NavigationStack {
                ConfigureView(pending: DesignHarness.pending(width: 3024, height: 4032,
                                                             filename: "IMG_9920.HEIC"))
            }
        case "result":
            NavigationStack {
                ResultView(pending: DesignHarness.pending(), result: DesignHarness.result())
            }
        case "denied":
            ZStack {
                Palette.background.ignoresSafeArea()
                LibraryDeniedView(onSettings: {}, onChooseSpecific: {})
            }
        case "confirm":
            ZStack {
                Palette.background.ignoresSafeArea()
                ConfirmSheet(message: "These 3 results will be removed from Scally.",
                             detail: "The originals in your Photos library are untouched.",
                             confirm: "Delete 3 Results",
                             onConfirm: {}, onCancel: {})
            }
        case "settings":
            SettingsView()
        case "selecting":
            NavigationStack { HistoryView(startSelecting: true) }
        case "confirm-clear":
            SettingsView(startConfirmingClear: true)
        case "save-failed":
            NavigationStack {
                ResultView(pending: DesignHarness.pending(),
                           result: DesignHarness.result(),
                           startSaveState: .failed("Your iPhone storage is full."))
            }
        default:
            ImportView()
        }
    }
}
#endif

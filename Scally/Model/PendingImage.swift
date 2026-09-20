import SwiftUI
import PhotosUI

/// A photo the user picked, written to a file the pipeline can read.
///
/// `PhotosPickerItem` yields data, not a URL, and the pipeline reads from disk,
/// so the bytes are staged into a temporary file here.
struct PendingImage: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let preview: UIImage
    let width: Int
    let height: Int
    let byteCount: Int
    let filename: String

    // Identity is the staged file, not the pixels: UIImage is not Hashable and
    // two picks of the same photo are still two separate jobs.
    static func == (lhs: PendingImage, rhs: PendingImage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func load(from item: PhotosPickerItem?) async -> PendingImage? {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let name = item.supportedContentTypes.first?.preferredFilenameExtension.map {
            "IMG_\(Int.random(in: 1000...9999)).\($0.uppercased())"
        } ?? "IMG.JPG"
        return make(from: data, filename: name)
    }

    static func make(from data: Data, filename: String) -> PendingImage? {
        guard let image = UIImage(data: data) else { return nil }
        let ext = (filename as NSString).pathExtension.lowercased()
        let url = FileManager.default.temporaryDirectory
            .appending(path: "input-\(UUID().uuidString).\(ext.isEmpty ? "img" : ext)")
        guard (try? data.write(to: url)) != nil else { return nil }

        return PendingImage(
            url: url,
            preview: downsampled(image, maxPixel: 1400),
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale),
            byteCount: data.count,
            filename: filename
        )
    }

    /// Display copy only. The pipeline always reads the original file.
    private static func downsampled(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPixel else { return image }
        let ratio = maxPixel / longest
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

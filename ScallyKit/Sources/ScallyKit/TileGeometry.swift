import Foundation

public struct PixelRect: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// The same rect in an output image scaled by `scale`.
    public func scaled(by scale: Int) -> PixelRect {
        PixelRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }
}

/// A raster-order grid of overlapping tiles covering an image.
///
/// Tiles advance by `tileSize - overlap`, so each tile shares `overlap`
/// columns with its left neighbour and `overlap` rows with the tile above.
/// `TileComposer` relies on that regularity - and on the raster ordering - to
/// crossfade without accumulator buffers, so do not change the stride without
/// revisiting it.
public struct TileGrid: Sendable {
    public let imageWidth: Int
    public let imageHeight: Int
    public let tileSize: Int
    public let overlap: Int
    public let tiles: [PixelRect]

    public init(imageWidth: Int, imageHeight: Int, tileSize: Int, overlap: Int) {
        precondition(tileSize > overlap * 2, "tile must be larger than twice its overlap")
        precondition(imageWidth > 0 && imageHeight > 0, "image must have area")
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.tileSize = tileSize
        self.overlap = overlap

        let step = tileSize - overlap
        var result: [PixelRect] = []

        var y = 0
        while y < imageHeight {
            let height = min(tileSize, imageHeight - y)
            var x = 0
            while x < imageWidth {
                let width = min(tileSize, imageWidth - x)
                result.append(PixelRect(x: x, y: y, width: width, height: height))
                if x + width >= imageWidth { break }
                x += step
            }
            if y + height >= imageHeight { break }
            y += step
        }
        self.tiles = result
    }
}

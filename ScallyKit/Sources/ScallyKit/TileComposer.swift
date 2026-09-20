import Foundation

/// Writes upscaled tiles into a `MappedPixelBuffer`, crossfading overlaps.
///
/// The blend exploits raster order: a tile fades in from its left edge over
/// `overlap` pixels when it has a left neighbour, and from its top edge
/// likewise. Because tiles arrive left to right then top to bottom,
/// `dst = dst*(1-a) + src*a` yields an exact linear crossfade with no
/// accumulator buffers - which matters, because accumulators at output
/// resolution would reintroduce the memory problem this design exists to avoid.
struct TileComposer {
    private let buffer: MappedPixelBuffer
    private let overlap: Int

    init(buffer: MappedPixelBuffer, overlap: Int) {
        self.buffer = buffer
        self.overlap = overlap
    }

    /// Blends one RGBA8 tile into the destination at `tile`'s origin.
    ///
    /// Tiles must arrive in raster order for the crossfade to be correct;
    /// `TileGrid` guarantees that ordering.
    func write(tile: PixelRect, pixels: UnsafeRawPointer, bytesPerRow: Int) {
        let destination = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
        let source = pixels.assumingMemoryBound(to: UInt8.self)

        let fadeLeft = tile.x > 0
        let fadeTop = tile.y > 0

        for row in 0..<tile.height {
            let destinationY = tile.y + row
            guard destinationY < buffer.height else { break }

            let verticalWeight = fadeTop ? rampWeight(row) : 1.0
            let sourceRow = source + row * bytesPerRow
            let destinationRow = destination + destinationY * buffer.bytesPerRow

            for column in 0..<tile.width {
                let destinationX = tile.x + column
                guard destinationX < buffer.width else { break }

                let horizontalWeight = fadeLeft ? rampWeight(column) : 1.0
                let alpha = verticalWeight * horizontalWeight

                let sourceIndex = column * 4
                let destinationIndex = destinationX * 4

                if alpha >= 1.0 {
                    for channel in 0..<4 {
                        destinationRow[destinationIndex + channel] = sourceRow[sourceIndex + channel]
                    }
                } else {
                    for channel in 0..<4 {
                        let existing = Float(destinationRow[destinationIndex + channel])
                        let incoming = Float(sourceRow[sourceIndex + channel])
                        let blended = existing * (1 - alpha) + incoming * alpha
                        destinationRow[destinationIndex + channel] =
                            UInt8(max(0, min(255, blended.rounded())))
                    }
                }
            }
        }
    }

    /// Linear 0->1 ramp across the overlap band, 1 beyond it.
    private func rampWeight(_ offset: Int) -> Float {
        guard overlap > 0, offset < overlap else { return 1.0 }
        return Float(offset + 1) / Float(overlap + 1)
    }
}

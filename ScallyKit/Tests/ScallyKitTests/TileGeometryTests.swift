import Testing
@testable import ScallyKit

@Test func gridCoversEveryPixelOfTheImage() {
    let grid = TileGrid(imageWidth: 700, imageHeight: 500, tileSize: 256, overlap: 16)
    var covered = Set<Int>()
    for tile in grid.tiles {
        for y in tile.y..<(tile.y + tile.height) {
            for x in tile.x..<(tile.x + tile.width) {
                covered.insert(y * 700 + x)
            }
        }
    }
    #expect(covered.count == 700 * 500)
}

@Test func tilesNeverExceedImageBounds() {
    let grid = TileGrid(imageWidth: 700, imageHeight: 500, tileSize: 256, overlap: 16)
    for tile in grid.tiles {
        #expect(tile.x >= 0 && tile.y >= 0)
        #expect(tile.x + tile.width <= 700)
        #expect(tile.y + tile.height <= 500)
    }
}

@Test func adjacentTilesOverlapByTheRequestedAmount() {
    let grid = TileGrid(imageWidth: 1000, imageHeight: 256, tileSize: 256, overlap: 16)
    let row = grid.tiles.filter { $0.y == 0 }.sorted { $0.x < $1.x }
    #expect(row.count > 1)
    let first = row[0], second = row[1]
    #expect(first.x + first.width - second.x == 16)
}

@Test func imageSmallerThanOneTileProducesASingleTile() {
    let grid = TileGrid(imageWidth: 100, imageHeight: 80, tileSize: 256, overlap: 16)
    #expect(grid.tiles.count == 1)
    #expect(grid.tiles[0] == PixelRect(x: 0, y: 0, width: 100, height: 80))
}

@Test func tilesAreEmittedInRasterOrder() {
    // TileComposer's crossfade depends on this ordering; assert it explicitly.
    let grid = TileGrid(imageWidth: 700, imageHeight: 500, tileSize: 256, overlap: 16)
    for (previous, next) in zip(grid.tiles, grid.tiles.dropFirst()) {
        #expect(next.y > previous.y || (next.y == previous.y && next.x > previous.x),
                "tile \(next) is not after \(previous) in raster order")
    }
}

@Test func scalingARectMultipliesEveryComponent() {
    let scaled = PixelRect(x: 10, y: 20, width: 30, height: 40).scaled(by: 4)
    #expect(scaled == PixelRect(x: 40, y: 80, width: 120, height: 160))
}

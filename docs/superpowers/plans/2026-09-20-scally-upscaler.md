# Scally Image Upscaler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a free iOS app that upscales a photo 2x or 4x entirely on-device, shows the user the improvement convincingly, and keeps a history of past results.

**Architecture:** A UI-free Swift package (`ScallyKit`) owns all algorithmic risk: it tiles an input image, runs each tile through a Core ML conversion of Real-ESRGAN `realesr-general-x4v3`, and blends tiles into a memory-mapped scratch buffer so resident memory stays flat regardless of output size. A thin SwiftUI app consumes the package's single public entry point and persists results with SwiftData.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, SwiftData, Core ML, Core Image, Accelerate/vImage, Core Graphics, PhotosUI. Python 3.11 with PyTorch and coremltools for the offline conversion.

**Spec:** `docs/superpowers/specs/2026-09-20-scally-upscaler-design.md`

## Global Constraints

- **Minimum deployment target: iOS 18.0.** This provisionally resolves the open decision in spec §4. Raising it is cheap; lowering it after SwiftData code exists is not.
- **The bundled model is 4x only.** `realesr-general-x4v3` has a single scale factor. A 2x request runs the 4x model and downsamples the result by 0.5 with Lanczos. There is no second model.
- **Tile size 256×256 on the input, 16px overlap.** Model input shape is fixed at `1×3×256×256`.
- **Edge tiles are reflect-padded, never zero-padded.** Zero padding produces dark fringes at image borders.
- **Inference colour space is sRGB.** Inputs are converted in, outputs re-tagged sRGB. Display P3 gamut loss is accepted for v1.
- **Conversion parity thresholds:** max absolute difference 2/255 per channel, mean absolute difference below 0.5/255, over at least 16 fixture tiles.
- **Scratch buffers live in Caches and are deleted after encoding. Final outputs live in Application Support and are excluded from iCloud backup.** These are different files; do not conflate them.
- **The app ships no in-app purchases, advertising, analytics, accounts, or network calls.** If a task appears to require a network call, the task is wrong.
- **A Licenses screen reproducing the BSD-3-Clause notice for Real-ESRGAN is a release requirement,** not a nicety (spec §2).
- **`FaceRestorer` must remain a protocol with only a no-op implementation in v1.** Do not inline face logic into the pipeline.

---

## File Structure

```
ScallyKit/
  Package.swift
  Sources/ScallyKit/
    UpscalePipeline.swift      Public entry point; orchestration, progress, cancellation
    Upscaler.swift             Protocol + IdentityUpscaler (test double)
    CoreMLUpscaler.swift       Core ML inference, reflect padding
    FaceRestorer.swift         Protocol + NoopFaceRestorer
    ImageLoader.swift          Decode, EXIF orientation, colour space, alpha split
    TileGeometry.swift         PixelRect, TileGrid — pure geometry, no pixels
    MappedPixelBuffer.swift    mmap-backed RGBA8 scratch buffer
    TileComposer.swift         Ramp-blended tile writes into the buffer
    OutputWriter.swift         Encode buffer to HEIC/PNG on disk
    MemoryBudget.swift         os_proc_available_memory + scale clamping
    UpscaleError.swift         Typed errors
    Resources/RealESRGANx4.mlpackage
  Tests/ScallyKitTests/
    TileGeometryTests.swift
    MappedPixelBufferTests.swift
    TileComposerTests.swift
    ReconstructionTests.swift  The identity-upscaler proof
    ImageLoaderTests.swift
    MemoryBudgetTests.swift
    OutputWriterTests.swift
    PipelineTests.swift
    GoldenImageTests.swift
    Fixtures/

tools/
  requirements.txt
  convert.py
  test_parity.py

Scally/                        Xcode app target
  ScallyApp.swift
  Model/UpscaleRecord.swift
  Storage/LibraryStore.swift
  Views/ImportView.swift
  Views/ProcessingView.swift
  Views/ResultView.swift
  Views/CompareView.swift      Divider + pinch zoom
  Views/HistoryView.swift
  Views/SettingsView.swift
  Views/LicensesView.swift
  Resources/Licenses/RealESRGAN-BSD3.txt
  Info.plist
```

---

## Phase 0 — Foundation

### Task 1: ScallyKit package skeleton

**Files:**
- Create: `ScallyKit/Package.swift`
- Create: `ScallyKit/Sources/ScallyKit/UpscaleError.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/UpscaleErrorTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `UpscaleError` enum; a package that builds and runs tests on macOS

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/UpscaleErrorTests.swift
import Testing
@testable import ScallyKit

@Test func errorsCarryReadableDescriptions() {
    let error = UpscaleError.unsupportedImageFormat
    #expect(error.errorDescription?.isEmpty == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test`
Expected: FAIL — no such module `ScallyKit`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScallyKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "ScallyKit", targets: ["ScallyKit"])],
    targets: [
        .target(name: "ScallyKit"),
        .testTarget(name: "ScallyKitTests", dependencies: ["ScallyKit"])
    ]
)
```

```swift
// ScallyKit/Sources/ScallyKit/UpscaleError.swift
import Foundation

public enum UpscaleError: Error, LocalizedError, Equatable {
    case unsupportedImageFormat
    case imageTooLarge(pixels: Int)
    case scratchAllocationFailed(underlying: Int32)
    case modelUnavailable
    case inferenceFailed(tileIndex: Int)
    case encodingFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupportedImageFormat: "That image format isn't supported."
        case .imageTooLarge(let pixels): "That image is too large to process (\(pixels) pixels)."
        case .scratchAllocationFailed(let code): "Couldn't allocate working storage (errno \(code))."
        case .modelUnavailable: "The upscaling model failed to load."
        case .inferenceFailed(let index): "Upscaling failed on tile \(index)."
        case .encodingFailed: "Couldn't write the finished image."
        case .cancelled: "Cancelled."
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test`
Expected: PASS, 1 test.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "feat: add ScallyKit package skeleton with typed errors"
```

---

## Phase 1 — Model conversion

Built first because it is the only component whose failure invalidates the project (spec §6).

### Task 2: PyTorch to Core ML conversion script

**Files:**
- Create: `tools/requirements.txt`
- Create: `tools/convert.py`

**Interfaces:**
- Consumes: nothing
- Produces: `ScallyKit/Sources/ScallyKit/Resources/RealESRGANx4.mlpackage`, fixed input `1×3×256×256`, FP16, output `1×3×1024×1024`

- [ ] **Step 1: Pin dependencies**

```text
# tools/requirements.txt
torch==2.4.1
numpy==1.26.4
coremltools==8.1
Pillow==10.4.0
requests==2.32.3
```

- [ ] **Step 2: Write the conversion script**

The `realesr-general-x4v3` checkpoint uses the SRVGGNetCompact architecture. Define it inline so the script has no dependency on the `basicsr` package.

```python
# tools/convert.py
"""Convert Real-ESRGAN realesr-general-x4v3 to Core ML.

Source weights: BSD-3-Clause, https://github.com/xinntao/Real-ESRGAN
"""
import pathlib
import requests
import torch
import torch.nn as nn
import coremltools as ct

WEIGHTS_URL = (
    "https://github.com/xinntao/Real-ESRGAN/releases/download/"
    "v0.2.5.0/realesr-general-x4v3.pth"
)
ROOT = pathlib.Path(__file__).resolve().parent.parent
WEIGHTS = ROOT / "tools" / "realesr-general-x4v3.pth"
OUTPUT = ROOT / "ScallyKit/Sources/ScallyKit/Resources/RealESRGANx4.mlpackage"
TILE = 256
SCALE = 4


class SRVGGNetCompact(nn.Module):
    """Compact VGG-style super-resolution net used by realesr-general-x4v3."""

    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=32, upscale=4):
        super().__init__()
        self.upscale = upscale
        self.body = nn.ModuleList()
        self.body.append(nn.Conv2d(num_in_ch, num_feat, 3, 1, 1))
        self.body.append(nn.PReLU(num_parameters=num_feat))
        for _ in range(num_conv):
            self.body.append(nn.Conv2d(num_feat, num_feat, 3, 1, 1))
            self.body.append(nn.PReLU(num_parameters=num_feat))
        self.body.append(nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.upsampler = nn.PixelShuffle(upscale)

    def forward(self, x):
        out = x
        for layer in self.body:
            out = layer(out)
        out = self.upsampler(out)
        # The reference implementation adds a nearest-neighbour skip connection.
        base = nn.functional.interpolate(x, scale_factor=self.upscale, mode="nearest")
        return out + base


def download_weights():
    if WEIGHTS.exists():
        return
    print(f"downloading {WEIGHTS_URL}")
    response = requests.get(WEIGHTS_URL, timeout=120)
    response.raise_for_status()
    WEIGHTS.write_bytes(response.content)


def load_model():
    download_weights()
    state = torch.load(WEIGHTS, map_location="cpu")
    weights = state.get("params") or state.get("params_ema") or state
    model = SRVGGNetCompact()
    model.load_state_dict(weights, strict=True)
    model.eval()
    return model


def main():
    model = load_model()
    example = torch.rand(1, 3, TILE, TILE)
    traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input", shape=(1, 3, TILE, TILE), dtype=float)],
        outputs=[ct.TensorType(name="output", dtype=float)],
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS18,
    )
    mlmodel.short_description = (
        "Real-ESRGAN realesr-general-x4v3, 4x super-resolution. "
        "Weights BSD-3-Clause, Xintao Wang et al."
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(OUTPUT))
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run the conversion**

Run:
```bash
python3 -m venv tools/.venv && source tools/.venv/bin/activate
pip install -r tools/requirements.txt
python tools/convert.py
```
Expected: `wrote .../RealESRGANx4.mlpackage`. If `load_state_dict` raises on unexpected keys, print `weights.keys()` and reconcile the layer naming before proceeding — do not pass `strict=False` to make the error disappear, because that silently loads a partly random model.

- [ ] **Step 4: Verify the artifact**

Run: `du -sh ScallyKit/Sources/ScallyKit/Resources/RealESRGANx4.mlpackage`
Expected: roughly 2–4MB. Materially larger means FP16 precision did not apply.

- [ ] **Step 5: Commit**

```bash
git add tools ScallyKit/Sources/ScallyKit/Resources
git commit -m "feat: add Real-ESRGAN to Core ML conversion script and model"
```

---

### Task 3: Numerical parity gate

**Files:**
- Create: `tools/test_parity.py`

**Interfaces:**
- Consumes: `RealESRGANx4.mlpackage` and `SRVGGNetCompact` from Task 2
- Produces: a pass/fail gate enforcing the thresholds in Global Constraints

- [ ] **Step 1: Write the failing test**

```python
# tools/test_parity.py
"""Assert the Core ML conversion matches PyTorch within tolerance.

A silently wrong conversion still produces plausible-looking images, so this
gate is the only thing standing between us and shipping a degraded model.
"""
import numpy as np
import torch
import coremltools as ct
import pytest

from convert import load_model, OUTPUT, TILE

MAX_ABS_TOLERANCE = 2.0 / 255.0
MEAN_ABS_TOLERANCE = 0.5 / 255.0
FIXTURE_COUNT = 16


def make_fixtures(seed=0):
    """Smooth gradients, high-frequency texture, and hard edges."""
    rng = np.random.default_rng(seed)
    fixtures = []
    for i in range(FIXTURE_COUNT):
        kind = i % 4
        if kind == 0:  # smooth gradient
            ramp = np.linspace(0, 1, TILE, dtype=np.float32)
            tile = np.stack([np.tile(ramp, (TILE, 1))] * 3)
        elif kind == 1:  # high-frequency noise
            tile = rng.random((3, TILE, TILE)).astype(np.float32)
        elif kind == 2:  # hard edges
            tile = np.zeros((3, TILE, TILE), dtype=np.float32)
            tile[:, :, TILE // 2:] = 1.0
        else:  # flat mid-grey with a dot
            tile = np.full((3, TILE, TILE), 0.5, dtype=np.float32)
            tile[:, TILE // 2, TILE // 2] = 1.0
        fixtures.append(tile[np.newaxis, ...])
    return fixtures


@pytest.fixture(scope="module")
def models():
    torch_model = load_model()
    coreml_model = ct.models.MLModel(str(OUTPUT), compute_units=ct.ComputeUnit.CPU_ONLY)
    return torch_model, coreml_model


def test_conversion_matches_pytorch(models):
    torch_model, coreml_model = models
    worst_max = 0.0
    worst_mean = 0.0

    for index, fixture in enumerate(make_fixtures()):
        with torch.no_grad():
            expected = torch_model(torch.from_numpy(fixture)).numpy()
        actual = coreml_model.predict({"input": fixture})["output"]

        assert actual.shape == expected.shape, f"tile {index} shape mismatch"
        diff = np.abs(actual - expected)
        worst_max = max(worst_max, float(diff.max()))
        worst_mean = max(worst_mean, float(diff.mean()))

    print(f"max abs diff {worst_max:.5f}, mean abs diff {worst_mean:.5f}")
    assert worst_max <= MAX_ABS_TOLERANCE, f"max abs diff {worst_max:.5f} exceeds tolerance"
    assert worst_mean <= MEAN_ABS_TOLERANCE, f"mean abs diff {worst_mean:.5f} exceeds tolerance"
```

- [ ] **Step 2: Run the test**

Run: `cd tools && python -m pytest test_parity.py -v -s`
Expected: PASS, with the printed diffs well inside tolerance.

If it fails, the cause is almost always the skip connection in `forward` or a transposed weight, not FP16 rounding — FP16 alone lands near 1e-3. Fix the architecture, do not loosen the threshold.

- [ ] **Step 3: Record the Neural Engine discrepancy**

The gate above runs CPU-only for determinism. Re-run once with `ct.ComputeUnit.ALL` and note the resulting max diff in a comment at the top of the file. Per spec §6, an ANE discrepancy is recorded, not silently accepted.

- [ ] **Step 4: Commit**

```bash
git add tools/test_parity.py
git commit -m "test: add PyTorch/Core ML numerical parity gate"
```

---

## Phase 2 — Geometry and composition

No machine learning in this phase. Every task here is pure and exactly testable, which is the point: tiling bugs must never be debugged through a neural network.

### Task 4: Tile geometry

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/TileGeometry.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/TileGeometryTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `PixelRect(x:y:width:height:)`, `TileGrid(imageWidth:imageHeight:tileSize:overlap:)` with `.tiles: [PixelRect]`

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/TileGeometryTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter TileGeometryTests`
Expected: FAIL — `TileGrid` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/TileGeometry.swift
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
/// `TileComposer` relies on that regularity to crossfade without accumulator
/// buffers, so do not change the stride without revisiting it.
public struct TileGrid: Sendable {
    public let imageWidth: Int
    public let imageHeight: Int
    public let tileSize: Int
    public let overlap: Int
    public let tiles: [PixelRect]

    public init(imageWidth: Int, imageHeight: Int, tileSize: Int, overlap: Int) {
        precondition(tileSize > overlap * 2, "tile must be larger than twice its overlap")
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.tileSize = tileSize
        self.overlap = overlap

        let step = tileSize - overlap
        var result: [PixelRect] = []

        var y = 0
        while y < imageHeight {
            var x = 0
            while x < imageWidth {
                let width = min(tileSize, imageWidth - x)
                let height = min(tileSize, imageHeight - y)
                result.append(PixelRect(x: x, y: y, width: width, height: height))
                if x + width >= imageWidth { break }
                x += step
            }
            if y + min(tileSize, imageHeight - y) >= imageHeight { break }
            y += step
        }
        self.tiles = result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter TileGeometryTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "feat: add overlapping tile grid geometry"
```

---

### Task 5: Memory-mapped pixel buffer

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/MappedPixelBuffer.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/MappedPixelBufferTests.swift`

**Interfaces:**
- Consumes: `UpscaleError` from Task 1
- Produces: `MappedPixelBuffer(width:height:directory:)` with `.baseAddress`, `.bytesPerRow`, `.makeCGImage()`

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/MappedPixelBufferTests.swift
import Testing
import Foundation
@testable import ScallyKit

@Test func bufferIsZeroFilledAndWritable() throws {
    let buffer = try MappedPixelBuffer(width: 64, height: 32, directory: FileManager.default.temporaryDirectory)
    let pixels = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)

    #expect(pixels[0] == 0)
    pixels[0] = 200
    #expect(pixels[0] == 200)
    #expect(buffer.bytesPerRow == 64 * 4)
}

@Test func bufferBackingFileIsRemovedOnDeinit() throws {
    var url: URL?
    do {
        let buffer = try MappedPixelBuffer(width: 16, height: 16, directory: FileManager.default.temporaryDirectory)
        url = buffer.fileURL
        #expect(FileManager.default.fileExists(atPath: buffer.fileURL.path))
    }
    #expect(FileManager.default.fileExists(atPath: url!.path) == false)
}

@Test func bufferProducesACGImageOfMatchingSize() throws {
    let buffer = try MappedPixelBuffer(width: 40, height: 20, directory: FileManager.default.temporaryDirectory)
    let image = try buffer.makeCGImage()
    #expect(image.width == 40)
    #expect(image.height == 20)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter MappedPixelBufferTests`
Expected: FAIL — `MappedPixelBuffer` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/MappedPixelBuffer.swift
import Foundation
import CoreGraphics

/// An RGBA8 image buffer backed by a memory-mapped scratch file.
///
/// A 4x upscale of a 12MP photo is ~770MB of pixels. Holding that in the heap
/// gets the process killed, so it lives in a file the kernel pages in and out
/// on demand, keeping resident memory flat regardless of output size.
///
/// The backing file is deleted when this object deinitialises. It is scratch
/// storage in Caches, not the final output.
public final class MappedPixelBuffer {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let fileURL: URL
    public let baseAddress: UnsafeMutableRawPointer

    private let descriptor: Int32
    private let byteCount: Int

    public init(width: Int, height: Int, directory: URL) throws {
        self.width = width
        self.height = height
        self.bytesPerRow = width * 4
        self.byteCount = bytesPerRow * height
        self.fileURL = directory.appendingPathComponent("scally-\(UUID().uuidString).raw")

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        descriptor = open(fileURL.path, O_RDWR)
        guard descriptor >= 0 else { throw UpscaleError.scratchAllocationFailed(underlying: errno) }

        guard ftruncate(descriptor, off_t(byteCount)) == 0 else {
            let code = errno
            close(descriptor)
            throw UpscaleError.scratchAllocationFailed(underlying: code)
        }

        let mapped = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0)
        guard let mapped, mapped != MAP_FAILED else {
            let code = errno
            close(descriptor)
            throw UpscaleError.scratchAllocationFailed(underlying: code)
        }
        self.baseAddress = mapped
    }

    deinit {
        munmap(baseAddress, byteCount)
        close(descriptor)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Wraps the mapping in a CGImage without copying it.
    public func makeCGImage() throws -> CGImage {
        guard let provider = CGDataProvider(
            dataInfo: nil,
            data: baseAddress,
            size: byteCount,
            releaseData: { _, _, _ in }
        ) else { throw UpscaleError.encodingFailed }

        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { throw UpscaleError.encodingFailed }

        return image
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter MappedPixelBufferTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "feat: add mmap-backed pixel buffer for large outputs"
```

---

### Task 6: Ramp-blended tile composer

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/TileComposer.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/TileComposerTests.swift`

**Interfaces:**
- Consumes: `PixelRect` (Task 4), `MappedPixelBuffer` (Task 5)
- Produces: `TileComposer(buffer:overlap:)` with `write(tile:pixels:bytesPerRow:)`

The blend exploits raster order: a tile fades in from its left edge over `overlap` pixels when it has a left neighbour, and from its top edge likewise. Because tiles are written left-to-right then top-to-bottom, `dst = dst·(1−a) + src·a` yields an exact linear crossfade with no accumulator buffers — which matters, because accumulators at output resolution would reintroduce the memory problem this whole design exists to avoid.

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/TileComposerTests.swift
import Testing
import Foundation
@testable import ScallyKit

private func solidTile(width: Int, height: Int, value: UInt8) -> [UInt8] {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        pixels[index] = value; pixels[index + 1] = value; pixels[index + 2] = value
    }
    return pixels
}

@Test func writingASingleTileCopiesItVerbatim() throws {
    let buffer = try MappedPixelBuffer(width: 8, height: 8, directory: FileManager.default.temporaryDirectory)
    let composer = TileComposer(buffer: buffer, overlap: 4)
    var tile = solidTile(width: 8, height: 8, value: 120)

    tile.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 0, y: 0, width: 8, height: 8),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }

    let out = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    #expect(out[0] == 120)
    #expect(out[(7 * 8 + 7) * 4] == 120)
}

@Test func identicalOverlappingTilesLeaveNoSeam() throws {
    // Two tiles of the same value must blend to exactly that value everywhere,
    // whatever the ramp does — this is what makes the reconstruction test exact.
    let buffer = try MappedPixelBuffer(width: 12, height: 4, directory: FileManager.default.temporaryDirectory)
    let composer = TileComposer(buffer: buffer, overlap: 4)

    var left = solidTile(width: 8, height: 4, value: 90)
    left.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 0, y: 0, width: 8, height: 4),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }
    var right = solidTile(width: 8, height: 4, value: 90)
    right.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 4, y: 0, width: 8, height: 4),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }

    let out = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    for x in 0..<12 {
        #expect(out[x * 4] == 90, "seam at column \(x)")
    }
}

@Test func overlapBlendIsMonotonicBetweenDifferingTiles() throws {
    let buffer = try MappedPixelBuffer(width: 12, height: 1, directory: FileManager.default.temporaryDirectory)
    let composer = TileComposer(buffer: buffer, overlap: 4)

    var left = solidTile(width: 8, height: 1, value: 0)
    left.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 0, y: 0, width: 8, height: 1),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }
    var right = solidTile(width: 8, height: 1, value: 255)
    right.withUnsafeMutableBytes { raw in
        composer.write(tile: PixelRect(x: 4, y: 0, width: 8, height: 1),
                       pixels: raw.baseAddress!, bytesPerRow: 32)
    }

    let out = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    let band = (4..<8).map { Int(out[$0 * 4]) }
    #expect(band == band.sorted(), "blend must ramp monotonically, got \(band)")
    #expect(band.first! < band.last!)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter TileComposerTests`
Expected: FAIL — `TileComposer` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/TileComposer.swift
import Foundation

/// Writes upscaled tiles into a `MappedPixelBuffer`, crossfading overlaps.
public struct TileComposer {
    private let buffer: MappedPixelBuffer
    private let overlap: Int

    public init(buffer: MappedPixelBuffer, overlap: Int) {
        self.buffer = buffer
        self.overlap = overlap
    }

    /// Blends one RGBA8 tile into the destination at `tile`'s origin.
    ///
    /// Tiles must arrive in raster order (left to right, top to bottom) for the
    /// crossfade to be correct.
    public func write(tile: PixelRect, pixels: UnsafeRawPointer, bytesPerRow: Int) {
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
                        destinationRow[destinationIndex + channel] = UInt8(max(0, min(255, blended.rounded())))
                    }
                }
            }
        }
    }

    /// Linear 0→1 ramp across the overlap band, 1 beyond it.
    private func rampWeight(_ offset: Int) -> Float {
        guard overlap > 0 else { return 1.0 }
        guard offset < overlap else { return 1.0 }
        return Float(offset + 1) / Float(overlap + 1)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter TileComposerTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "feat: add ramp-blended tile composer"
```

---

### Task 7: Upscaler protocol and the reconstruction proof

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/Upscaler.swift`
- Create: `ScallyKit/Sources/ScallyKit/FaceRestorer.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/ReconstructionTests.swift`

**Interfaces:**
- Consumes: `PixelRect`, `MappedPixelBuffer`, `TileComposer`
- Produces: `Upscaler` protocol with `scale: Int` and `upscale(tile:width:height:bytesPerRow:) throws -> TilePixels`; `IdentityUpscaler`; `FaceRestorer` protocol; `NoopFaceRestorer`

This task implements spec §5's correctness strategy. It is the gate that proves tiling and blending are right with no neural network involved, so a later image-quality problem can never be ambiguous between "the model is bad" and "the tiler is broken".

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/ReconstructionTests.swift
import Testing
import Foundation
@testable import ScallyKit

@Test func identityUpscalerReconstructsTheSourceExactly() throws {
    // Deterministic noise source: every pixel distinct enough that a seam,
    // an off-by-one, or a dropped tile shows up as an exact mismatch.
    let width = 700, height = 500
    var source = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            source[i] = UInt8((x * 7 + y * 13) % 256)
            source[i + 1] = UInt8((x * 3 + y * 29) % 256)
            source[i + 2] = UInt8((x &* y) % 256)
            source[i + 3] = 255
        }
    }

    let buffer = try MappedPixelBuffer(width: width, height: height,
                                       directory: FileManager.default.temporaryDirectory)
    let composer = TileComposer(buffer: buffer, overlap: 16)
    let grid = TileGrid(imageWidth: width, imageHeight: height, tileSize: 256, overlap: 16)
    let upscaler = IdentityUpscaler()

    for tile in grid.tiles {
        var tilePixels = [UInt8](repeating: 0, count: tile.width * tile.height * 4)
        for row in 0..<tile.height {
            let sourceStart = ((tile.y + row) * width + tile.x) * 4
            let destinationStart = row * tile.width * 4
            for byte in 0..<(tile.width * 4) {
                tilePixels[destinationStart + byte] = source[sourceStart + byte]
            }
        }
        let result = try tilePixels.withUnsafeBytes { raw in
            try upscaler.upscale(tile: raw.baseAddress!, width: tile.width,
                                 height: tile.height, bytesPerRow: tile.width * 4)
        }
        result.pixels.withUnsafeBytes { raw in
            composer.write(tile: tile, pixels: raw.baseAddress!, bytesPerRow: result.bytesPerRow)
        }
    }

    let output = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    var mismatches = 0
    for index in 0..<(width * height * 4) where output[index] != source[index] {
        mismatches += 1
    }
    #expect(mismatches == 0, "\(mismatches) bytes differ after tiled reconstruction")
}

@Test func noopFaceRestorerReturnsItsInputUnchanged() throws {
    let restorer = NoopFaceRestorer()
    let pixels: [UInt8] = [1, 2, 3, 255, 4, 5, 6, 255]
    let result = try pixels.withUnsafeBytes { raw in
        try restorer.restore(image: raw.baseAddress!, width: 2, height: 1, bytesPerRow: 8)
    }
    #expect(result == false, "v1 must report that it changed nothing")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter ReconstructionTests`
Expected: FAIL — `IdentityUpscaler` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/Upscaler.swift
import Foundation

/// RGBA8 pixels produced by an upscaler.
public struct TilePixels: Sendable {
    public let pixels: [UInt8]
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int

    public init(pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) {
        self.pixels = pixels; self.width = width; self.height = height; self.bytesPerRow = bytesPerRow
    }
}

public protocol Upscaler: Sendable {
    /// Linear magnification factor applied to both axes.
    var scale: Int { get }

    func upscale(tile: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> TilePixels
}

/// Copies its input unchanged. Exists so the tiler and composer can be proven
/// correct without a model in the loop; see ReconstructionTests.
public struct IdentityUpscaler: Upscaler {
    public let scale = 1
    public init() {}

    public func upscale(tile: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> TilePixels {
        let source = tile.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for byte in 0..<(width * 4) {
                pixels[row * width * 4 + byte] = source[row * bytesPerRow + byte]
            }
        }
        return TilePixels(pixels: pixels, width: width, height: height, bytesPerRow: width * 4)
    }
}
```

```swift
// ScallyKit/Sources/ScallyKit/FaceRestorer.swift
import Foundation

/// Restores faces in an already-upscaled image, in place.
///
/// This protocol exists in v1 with only a no-op implementation, deliberately.
/// Every strong open face-restoration model (CodeFormer, GFPGAN, and most
/// alternatives via FFHQ) carries non-commercial licensing, so keeping this
/// behind an interface is what makes the decision to add or abandon it a
/// one-type change rather than a rewrite. See spec §2.
public protocol FaceRestorer: Sendable {
    /// Returns true if any pixels were modified.
    func restore(image: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> Bool
}

public struct NoopFaceRestorer: FaceRestorer {
    public init() {}

    public func restore(image: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> Bool {
        false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter ReconstructionTests`
Expected: PASS, 2 tests, zero mismatched bytes.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "feat: add Upscaler/FaceRestorer protocols and tiling reconstruction proof"
```

---

## Phase 3 — Image input and output

### Task 8: Image loading, orientation and colour space

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/ImageLoader.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/ImageLoaderTests.swift`

**Interfaces:**
- Consumes: `UpscaleError` (Task 1)
- Produces: `LoadedImage` struct with `.pixels: [UInt8]`, `.width`, `.height`, `.bytesPerRow`, `.hasAlpha`; `ImageLoader.load(url:)` and `ImageLoader.render(_:orientation:)`

Orientation and colour conversion are one task because they are one operation: getting arbitrary camera output into a single canonical form — RGBA8, sRGB, upright — that everything downstream can assume. A reviewer could not sensibly accept one and reject the other.

Use `CIImage.oriented(_:)` rather than hand-rolling affine transforms. All eight EXIF cases are easy to get subtly wrong by hand, and the mirrored ones are where it happens.

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/ImageLoaderTests.swift
import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import ScallyKit

/// A 2×1 image: left pixel red, right pixel blue.
private func makeTwoPixelImage() -> CGImage {
    var bytes: [UInt8] = [255, 0, 0, 255,   0, 0, 255, 255]
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

@Test func upOrientationLeavesPixelsAlone() throws {
    let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: .up)
    #expect(loaded.width == 2 && loaded.height == 1)
    #expect(loaded.pixels[0] > 200)   // left is red
    #expect(loaded.pixels[6] > 200)   // right is blue
}

@Test func mirroredOrientationSwapsLeftAndRight() throws {
    let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: .upMirrored)
    #expect(loaded.pixels[2] > 200, "left pixel should now be blue")
    #expect(loaded.pixels[4] > 200, "right pixel should now be red")
}

@Test func rotatedOrientationsSwapTheAxes() throws {
    for orientation in [CGImagePropertyOrientation.left, .right, .leftMirrored, .rightMirrored] {
        let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: orientation)
        #expect(loaded.width == 1, "\(orientation) should produce a 1×2 image")
        #expect(loaded.height == 2)
    }
}

@Test func allEightOrientationsLoadWithoutError() throws {
    let all: [CGImagePropertyOrientation] = [.up, .upMirrored, .down, .downMirrored,
                                             .left, .leftMirrored, .right, .rightMirrored]
    for orientation in all {
        let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: orientation)
        #expect(loaded.pixels.count == loaded.width * loaded.height * 4)
    }
}

@Test func opaqueImagesReportNoAlpha() throws {
    let loaded = try ImageLoader.render(makeTwoPixelImage(), orientation: .up)
    #expect(loaded.hasAlpha == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter ImageLoaderTests`
Expected: FAIL — `ImageLoader` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/ImageLoader.swift
import Foundation
import CoreGraphics
import CoreImage
import ImageIO

/// An image in canonical form: RGBA8, sRGB, upright.
public struct LoadedImage: Sendable {
    public let pixels: [UInt8]
    public let width: Int
    public let height: Int
    public let hasAlpha: Bool

    public var bytesPerRow: Int { width * 4 }
}

public enum ImageLoader {
    private static let workingColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func load(url: URL) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw UpscaleError.unsupportedImageFormat
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: raw) ?? .up
        return try render(image, orientation: orientation)
    }

    /// Applies EXIF orientation and converts to sRGB RGBA8.
    ///
    /// Display P3 and HDR inputs are flattened to sRGB here. That loses gamut
    /// on vivid photographs and is an accepted v1 tradeoff (spec §6) — the
    /// model was trained on sRGB and feeding it P3 shifts colours far worse.
    public static func render(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> LoadedImage {
        let oriented = CIImage(cgImage: image).oriented(orientation)
        let context = CIContext(options: [.workingColorSpace: workingColorSpace])

        guard let converted = context.createCGImage(
            oriented,
            from: oriented.extent,
            format: .RGBA8,
            colorSpace: workingColorSpace
        ) else { throw UpscaleError.unsupportedImageFormat }

        let width = converted.width
        let height = converted.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        try pixels.withUnsafeMutableBytes { raw in
            guard let bitmap = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: workingColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw UpscaleError.unsupportedImageFormat }
            bitmap.draw(converted, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let alphaInfo = image.alphaInfo
        let hasAlpha = !(alphaInfo == .none || alphaInfo == .noneSkipFirst || alphaInfo == .noneSkipLast)

        return LoadedImage(pixels: pixels, width: width, height: height, hasAlpha: hasAlpha)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter ImageLoaderTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "feat: add image loader with EXIF orientation and sRGB conversion"
```

---

### Task 9: Alpha channel preservation

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/AlphaChannel.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/AlphaChannelTests.swift`

**Interfaces:**
- Consumes: `LoadedImage` (Task 8)
- Produces: `AlphaChannel.extract(from:)`, `AlphaChannel.scaled(_:from:to:)`, `AlphaChannel.apply(_:to:width:height:bytesPerRow:)`

The model has three input channels and no concept of transparency. A screenshot with rounded corners or a PNG logo would come back with its transparency filled in as black if alpha were simply dropped. So alpha travels separately: extracted before inference, scaled with Lanczos, and reapplied afterwards.

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/AlphaChannelTests.swift
import Testing
import Foundation
@testable import ScallyKit

@Test func extractPullsTheFourthByteOfEveryPixel() {
    let pixels: [UInt8] = [10, 20, 30, 40,   50, 60, 70, 80]
    let alpha = AlphaChannel.extract(from: pixels, width: 2, height: 1, bytesPerRow: 8)
    #expect(alpha == [40, 80])
}

@Test func scalingEnlargesTheAlphaPlane() {
    let alpha: [UInt8] = [0, 255, 255, 0]
    let scaled = AlphaChannel.scaled(alpha, from: (width: 2, height: 2), to: (width: 4, height: 4))
    #expect(scaled.count == 16)
}

@Test func applyWritesAlphaBackIntoRGBA() {
    var pixels: [UInt8] = [1, 2, 3, 255,   4, 5, 6, 255]
    AlphaChannel.apply([0, 128], to: &pixels, width: 2, height: 1, bytesPerRow: 8)
    #expect(pixels[3] == 0)
    #expect(pixels[7] == 128)
    #expect(pixels[0] == 1, "colour channels must be untouched")
}

@Test func roundTripPreservesATransparentCorner() {
    // A 2×2 with one transparent pixel must survive extract → scale → apply.
    let pixels: [UInt8] = [9, 9, 9, 0,    9, 9, 9, 255,
                           9, 9, 9, 255,  9, 9, 9, 255]
    let alpha = AlphaChannel.extract(from: pixels, width: 2, height: 2, bytesPerRow: 8)
    let scaled = AlphaChannel.scaled(alpha, from: (2, 2), to: (8, 8))
    var output = [UInt8](repeating: 255, count: 8 * 8 * 4)
    AlphaChannel.apply(scaled, to: &output, width: 8, height: 8, bytesPerRow: 32)
    #expect(output[3] < 64, "the transparent corner must still be transparent")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter AlphaChannelTests`
Expected: FAIL — `AlphaChannel` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/AlphaChannel.swift
import Foundation
import Accelerate

/// Carries transparency around the model, which only handles RGB.
public enum AlphaChannel {
    public static func extract(from pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> [UInt8] {
        var alpha = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                alpha[y * width + x] = pixels[y * bytesPerRow + x * 4 + 3]
            }
        }
        return alpha
    }

    /// Lanczos resampling of the single-channel alpha plane.
    public static func scaled(_ alpha: [UInt8],
                              from source: (width: Int, height: Int),
                              to destination: (width: Int, height: Int)) -> [UInt8] {
        var input = alpha
        var output = [UInt8](repeating: 0, count: destination.width * destination.height)

        input.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                var sourceBuffer = vImage_Buffer(
                    data: inputBuffer.baseAddress,
                    height: vImagePixelCount(source.height),
                    width: vImagePixelCount(source.width),
                    rowBytes: source.width
                )
                var destinationBuffer = vImage_Buffer(
                    data: outputBuffer.baseAddress,
                    height: vImagePixelCount(destination.height),
                    width: vImagePixelCount(destination.width),
                    rowBytes: destination.width
                )
                vImageScale_Planar8(&sourceBuffer, &destinationBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        return output
    }

    public static func apply(_ alpha: [UInt8], to pixels: inout [UInt8],
                             width: Int, height: Int, bytesPerRow: Int) {
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * bytesPerRow + x * 4 + 3] = alpha[y * width + x]
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter AlphaChannelTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "feat: preserve alpha channel across upscaling"
```

---

### Task 10: Output encoding

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/OutputWriter.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/OutputWriterTests.swift`

**Interfaces:**
- Consumes: `MappedPixelBuffer` (Task 5), `UpscaleError` (Task 1)
- Produces: `OutputWriter.write(buffer:to:format:)` and `OutputWriter.Format` enum

Format selection: HEIC for opaque images (far smaller at equal quality), PNG when alpha is present (HEIC alpha support is inconsistent and lossy compression on transparency edges looks bad).

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/OutputWriterTests.swift
import Testing
import Foundation
import ImageIO
@testable import ScallyKit

@Test func writesAPNGThatReloadsAtTheSameSize() throws {
    let buffer = try MappedPixelBuffer(width: 32, height: 16, directory: FileManager.default.temporaryDirectory)
    let pixels = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    for index in 0..<(32 * 16 * 4) { pixels[index] = 180 }

    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("out-\(UUID().uuidString).png")
    try OutputWriter.write(buffer: buffer, to: destination, format: .png)

    let source = CGImageSourceCreateWithURL(destination as CFURL, nil)!
    let reloaded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    #expect(reloaded.width == 32)
    #expect(reloaded.height == 16)

    try? FileManager.default.removeItem(at: destination)
}

@Test func writesHEICForOpaqueOutput() throws {
    let buffer = try MappedPixelBuffer(width: 16, height: 16, directory: FileManager.default.temporaryDirectory)
    let pixels = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
    for index in 0..<(16 * 16 * 4) { pixels[index] = 90 }

    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("out-\(UUID().uuidString).heic")
    try OutputWriter.write(buffer: buffer, to: destination, format: .heic(quality: 0.9))

    #expect(FileManager.default.fileExists(atPath: destination.path))
    let size = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as! Int
    #expect(size > 0)

    try? FileManager.default.removeItem(at: destination)
}

@Test func formatSelectionFollowsAlphaPresence() {
    #expect(OutputWriter.Format.preferred(hasAlpha: true).isPNG)
    #expect(OutputWriter.Format.preferred(hasAlpha: false).isPNG == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter OutputWriterTests`
Expected: FAIL — `OutputWriter` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/OutputWriter.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum OutputWriter {
    public enum Format: Sendable {
        case png
        case heic(quality: Double)

        public static func preferred(hasAlpha: Bool) -> Format {
            // HEIC's alpha handling is inconsistent and lossy edges on
            // transparency look bad, so anything with alpha goes to PNG.
            hasAlpha ? .png : .heic(quality: 0.92)
        }

        public var isPNG: Bool { if case .png = self { return true } else { return false } }

        var contentType: UTType {
            switch self {
            case .png: .png
            case .heic: .heic
            }
        }

        var fileExtension: String { isPNG ? "png" : "heic" }
    }

    /// Encodes the scratch buffer to a real image file.
    ///
    /// Reading back through the mapping is sequential, which is the access
    /// pattern the pager handles best — memory stays flat even for very large
    /// outputs.
    public static func write(buffer: MappedPixelBuffer, to url: URL, format: Format) throws {
        let image = try buffer.makeCGImage()

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.contentType.identifier as CFString, 1, nil
        ) else { throw UpscaleError.encodingFailed }

        var options: [CFString: Any] = [:]
        if case .heic(let quality) = format {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw UpscaleError.encodingFailed }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter OutputWriterTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "feat: encode upscaled output to HEIC or PNG"
```

---

## Phase 4 — Memory budget

### Task 11: Budget calculation and scale clamping

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/MemoryBudget.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/MemoryBudgetTests.swift`

**Interfaces:**
- Consumes: `UpscaleError` (Task 1)
- Produces: `MemoryBudget(availableBytes:)`, `.resolveScale(requested:inputWidth:inputHeight:) -> ScaleDecision`, `ScaleDecision` enum

The available budget is injectable so the clamp path is testable without needing a device under real memory pressure — otherwise the single most important safety mechanism in the app would only ever be exercised by accident.

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/MemoryBudgetTests.swift
import Testing
@testable import ScallyKit

@Test func generousBudgetGrantsTheRequestedScale() {
    let budget = MemoryBudget(availableBytes: 4_000_000_000)
    let decision = budget.resolveScale(requested: 4, inputWidth: 4032, inputHeight: 3024)
    #expect(decision == .granted(scale: 4))
}

@Test func tightBudgetClampsFourToTwo() {
    // 4032×3024 at 4x is ~780MB; at 2x it is ~195MB.
    let budget = MemoryBudget(availableBytes: 400_000_000)
    let decision = budget.resolveScale(requested: 4, inputWidth: 4032, inputHeight: 3024)
    #expect(decision == .clamped(scale: 2, requested: 4))
}

@Test func budgetTooSmallForEvenTwoIsRefused() {
    let budget = MemoryBudget(availableBytes: 10_000_000)
    let decision = budget.resolveScale(requested: 4, inputWidth: 4032, inputHeight: 3024)
    if case .refused = decision {} else {
        Issue.record("expected refusal, got \(decision)")
    }
}

@Test func smallImagesAreAlwaysGranted() {
    let budget = MemoryBudget(availableBytes: 200_000_000)
    let decision = budget.resolveScale(requested: 4, inputWidth: 800, inputHeight: 600)
    #expect(decision == .granted(scale: 4))
}

@Test func outputByteCountIsWidthTimesHeightTimesFour() {
    #expect(MemoryBudget.outputBytes(width: 100, height: 50, scale: 2) == 100 * 2 * 50 * 2 * 4)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter MemoryBudgetTests`
Expected: FAIL — `MemoryBudget` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/MemoryBudget.swift
import Foundation
import os  // os_proc_available_memory

public enum ScaleDecision: Sendable, Equatable {
    case granted(scale: Int)
    case clamped(scale: Int, requested: Int)
    case refused(requiredBytes: Int, availableBytes: Int)

    public var scale: Int? {
        switch self {
        case .granted(let scale): scale
        case .clamped(let scale, _): scale
        case .refused: nil
        }
    }
}

/// Decides whether an upscale fits before it starts.
///
/// The scratch buffer is memory-mapped, so the kernel can page it out — but
/// dirty pages still count against the process while they are being written,
/// and an old iPhone on a 12MP photo is a case that genuinely happens. Better
/// to clamp and tell the user up front than to be killed mid-run.
public struct MemoryBudget: Sendable {
    /// Fraction of the remaining allowance we are willing to commit.
    private static let safetyFactor = 0.6

    public let availableBytes: Int

    public init(availableBytes: Int) {
        self.availableBytes = availableBytes
    }

    /// Reads the real remaining allowance for this process.
    public static func current() -> MemoryBudget {
        MemoryBudget(availableBytes: Int(os_proc_available_memory()))
    }

    public static func outputBytes(width: Int, height: Int, scale: Int) -> Int {
        width * scale * height * scale * 4
    }

    public func resolveScale(requested: Int, inputWidth: Int, inputHeight: Int) -> ScaleDecision {
        let ceiling = Int(Double(availableBytes) * Self.safetyFactor)

        let requestedBytes = Self.outputBytes(width: inputWidth, height: inputHeight, scale: requested)
        if requestedBytes <= ceiling {
            return .granted(scale: requested)
        }

        for fallback in stride(from: requested - 1, through: 2, by: -1) {
            let bytes = Self.outputBytes(width: inputWidth, height: inputHeight, scale: fallback)
            if bytes <= ceiling {
                return .clamped(scale: fallback, requested: requested)
            }
        }

        let minimumBytes = Self.outputBytes(width: inputWidth, height: inputHeight, scale: 2)
        return .refused(requiredBytes: minimumBytes, availableBytes: ceiling)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter MemoryBudgetTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "feat: add memory budget with scale clamping"
```

---

## Phase 5 — Model integration

### Task 12: Core ML upscaler

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/CoreMLUpscaler.swift`
- Modify: `ScallyKit/Package.swift` — add the resource bundle
- Test: `ScallyKit/Tests/ScallyKitTests/CoreMLUpscalerTests.swift`

**Interfaces:**
- Consumes: `Upscaler`, `TilePixels` (Task 7), `UpscaleError` (Task 1)
- Produces: `CoreMLUpscaler()` conforming to `Upscaler` with `scale == 4`

Two details carry the risk. The model's input shape is fixed at 256×256, so tiles smaller than that — every edge tile — must be reflect-padded up to full size and the result cropped back. And padding must be *reflect*, not zero: zero padding puts a black border inside the model's receptive field and produces dark fringes along every image edge.

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/CoreMLUpscalerTests.swift
import Testing
import Foundation
@testable import ScallyKit

@Test func reflectPaddingMirrorsEdgePixels() {
    // 2×1 source [10, 20] padded to width 4 reflects as [10, 20, 10, 20]... the
    // exact mirror depends on the reflection point; assert no zeros appear.
    let source: [UInt8] = [10, 10, 10, 255,  20, 20, 20, 255]
    let padded = CoreMLUpscaler.reflectPad(source, width: 2, height: 1,
                                           bytesPerRow: 8, to: 4)
    for y in 0..<4 {
        for x in 0..<4 {
            #expect(padded[(y * 4 + x) * 4] != 0, "zero at \(x),\(y) — padding must reflect, not zero-fill")
        }
    }
}

@Test func modelLoadsFromTheBundle() throws {
    let upscaler = try CoreMLUpscaler()
    #expect(upscaler.scale == 4)
}

@Test func upscalingAFullTileQuadruplesItsDimensions() throws {
    let upscaler = try CoreMLUpscaler()
    let tile = [UInt8](repeating: 128, count: 256 * 256 * 4)
    let result = try tile.withUnsafeBytes { raw in
        try upscaler.upscale(tile: raw.baseAddress!, width: 256, height: 256, bytesPerRow: 256 * 4)
    }
    #expect(result.width == 1024)
    #expect(result.height == 1024)
}

@Test func upscalingAPartialTileCropsBackToTheScaledSize() throws {
    let upscaler = try CoreMLUpscaler()
    let tile = [UInt8](repeating: 90, count: 100 * 60 * 4)
    let result = try tile.withUnsafeBytes { raw in
        try upscaler.upscale(tile: raw.baseAddress!, width: 100, height: 60, bytesPerRow: 100 * 4)
    }
    #expect(result.width == 400)
    #expect(result.height == 240)
}

@Test func aFlatGreyTileStaysFlatGrey() throws {
    // Sanity check that the conversion is not producing garbage: a uniform
    // input must produce a near-uniform output.
    let upscaler = try CoreMLUpscaler()
    let tile = [UInt8](repeating: 128, count: 256 * 256 * 4)
    let result = try tile.withUnsafeBytes { raw in
        try upscaler.upscale(tile: raw.baseAddress!, width: 256, height: 256, bytesPerRow: 256 * 4)
    }
    let samples = stride(from: 0, to: result.pixels.count, by: 4096).map { Int(result.pixels[$0]) }
    #expect(samples.allSatisfy { abs($0 - 128) < 12 }, "flat input produced \(samples.prefix(8))")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter CoreMLUpscalerTests`
Expected: FAIL — `CoreMLUpscaler` not found.

- [ ] **Step 3: Register the model as a package resource**

```swift
// ScallyKit/Package.swift — replace the target declaration
.target(
    name: "ScallyKit",
    resources: [.process("Resources/RealESRGANx4.mlpackage")]
),
```

- [ ] **Step 4: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/CoreMLUpscaler.swift
import Foundation
import CoreML

/// Runs Real-ESRGAN realesr-general-x4v3 on one tile at a time.
///
/// Model weights are BSD-3-Clause (Xintao Wang et al.); the app must reproduce
/// that notice — see the Licenses screen.
public final class CoreMLUpscaler: Upscaler, @unchecked Sendable {
    public let scale = 4

    static let tileSize = 256
    private let model: MLModel

    public init(computeUnits: MLComputeUnits = .all) throws {
        guard let url = Bundle.module.url(forResource: "RealESRGANx4", withExtension: "mlmodelc")
                ?? Bundle.module.url(forResource: "RealESRGANx4", withExtension: "mlpackage") else {
            throw UpscaleError.modelUnavailable
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        do {
            self.model = try MLModel(contentsOf: url, configuration: configuration)
        } catch {
            throw UpscaleError.modelUnavailable
        }
    }

    public func upscale(tile: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) throws -> TilePixels {
        let padded = Self.reflectPad(
            UnsafeBufferPointer(start: tile.assumingMemoryBound(to: UInt8.self),
                                count: bytesPerRow * height),
            width: width, height: height, bytesPerRow: bytesPerRow, to: Self.tileSize
        )

        let input = try MLMultiArray(shape: [1, 3, NSNumber(value: Self.tileSize), NSNumber(value: Self.tileSize)],
                                     dataType: .float32)
        let inputPointer = input.dataPointer.assumingMemoryBound(to: Float32.self)
        let plane = Self.tileSize * Self.tileSize
        for y in 0..<Self.tileSize {
            for x in 0..<Self.tileSize {
                let source = (y * Self.tileSize + x) * 4
                let offset = y * Self.tileSize + x
                inputPointer[offset] = Float32(padded[source]) / 255.0
                inputPointer[plane + offset] = Float32(padded[source + 1]) / 255.0
                inputPointer[2 * plane + offset] = Float32(padded[source + 2]) / 255.0
            }
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: input)])
        guard let output = try? model.prediction(from: provider),
              let array = output.featureValue(for: "output")?.multiArrayValue else {
            throw UpscaleError.inferenceFailed(tileIndex: -1)
        }

        let outputSize = Self.tileSize * scale
        let outputPointer = array.dataPointer.assumingMemoryBound(to: Float32.self)
        let outputPlane = outputSize * outputSize

        // Crop straight back to the scaled size of the real (unpadded) tile.
        let cropWidth = width * scale
        let cropHeight = height * scale
        var pixels = [UInt8](repeating: 255, count: cropWidth * cropHeight * 4)

        for y in 0..<cropHeight {
            for x in 0..<cropWidth {
                let source = y * outputSize + x
                let destination = (y * cropWidth + x) * 4
                pixels[destination] = Self.clampToByte(outputPointer[source])
                pixels[destination + 1] = Self.clampToByte(outputPointer[outputPlane + source])
                pixels[destination + 2] = Self.clampToByte(outputPointer[2 * outputPlane + source])
                pixels[destination + 3] = 255
            }
        }

        return TilePixels(pixels: pixels, width: cropWidth, height: cropHeight, bytesPerRow: cropWidth * 4)
    }

    private static func clampToByte(_ value: Float32) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }

    /// Mirrors edge pixels outward to fill a `size`×`size` tile.
    ///
    /// Zero padding would put black inside the model's receptive field and
    /// leave a dark fringe along every border of the finished image.
    static func reflectPad(_ source: UnsafeBufferPointer<UInt8>, width: Int, height: Int,
                           bytesPerRow: Int, to size: Int) -> [UInt8] {
        var padded = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            let sourceY = reflect(y, limit: height)
            for x in 0..<size {
                let sourceX = reflect(x, limit: width)
                let from = sourceY * bytesPerRow + sourceX * 4
                let to = (y * size + x) * 4
                padded[to] = source[from]
                padded[to + 1] = source[from + 1]
                padded[to + 2] = source[from + 2]
                padded[to + 3] = source[from + 3]
            }
        }
        return padded
    }

    /// Array-form convenience used by tests.
    static func reflectPad(_ source: [UInt8], width: Int, height: Int,
                           bytesPerRow: Int, to size: Int) -> [UInt8] {
        source.withUnsafeBufferPointer { reflectPad($0, width: width, height: height, bytesPerRow: bytesPerRow, to: size) }
    }

    private static func reflect(_ index: Int, limit: Int) -> Int {
        guard limit > 1 else { return 0 }
        let period = 2 * limit - 2
        var wrapped = index % period
        if wrapped < 0 { wrapped += period }
        return wrapped < limit ? wrapped : period - wrapped
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter CoreMLUpscalerTests`
Expected: PASS, 5 tests.

If `aFlatGreyTileStaysFlatGrey` fails, stop and revisit Task 3 — a flat input producing non-flat output means the conversion is wrong, not that the threshold is too tight.

- [ ] **Step 6: Record the Neural Engine performance profile**

Open the `.mlpackage` in Xcode and run the Core ML performance report against a real device. Note in a comment on `CoreMLUpscaler` which compute unit actually executes, and the per-tile latency. Spec §6 requires this be measured rather than assumed; GPU fallback is acceptable, silent GPU fallback is not.

- [ ] **Step 7: Commit**

```bash
git add ScallyKit
git commit -m "feat: add Core ML upscaler with reflect-padded edge tiles"
```

---

### Task 13: The pipeline

**Files:**
- Create: `ScallyKit/Sources/ScallyKit/UpscalePipeline.swift`
- Test: `ScallyKit/Tests/ScallyKitTests/PipelineTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 4–12
- Produces: `UpscalePipeline(upscaler:faceRestorer:)`, `.run(source:requestedScale:progress:) async throws -> UpscaleResult`, `UpscaleResult` struct

This is the only public entry point. Everything else in the package becomes internal in this task.

- [ ] **Step 1: Write the failing test**

```swift
// ScallyKit/Tests/ScallyKitTests/PipelineTests.swift
import Testing
import Foundation
@testable import ScallyKit

private func writeFixture(width: Int, height: Int) throws -> URL {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        pixels[index] = UInt8(index % 256); pixels[index + 1] = 120
        pixels[index + 2] = 200; pixels[index + 3] = 255
    }
    let buffer = try MappedPixelBuffer(width: width, height: height,
                                       directory: FileManager.default.temporaryDirectory)
    pixels.withUnsafeBytes { raw in
        buffer.baseAddress.copyMemory(from: raw.baseAddress!, byteCount: pixels.count)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).png")
    try OutputWriter.write(buffer: buffer, to: url, format: .png)
    return url
}

@Test func pipelineProducesAnOutputFourTimesLarger() async throws {
    let source = try writeFixture(width: 120, height: 80)
    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(), faceRestorer: NoopFaceRestorer())
    let result = try await pipeline.run(source: source, requestedScale: 4) { _ in }

    #expect(result.outputWidth == 480)
    #expect(result.outputHeight == 320)
    #expect(FileManager.default.fileExists(atPath: result.outputURL.path))
    #expect(result.appliedScale == 4)
}

@Test func progressReachesOne() async throws {
    let source = try writeFixture(width: 300, height: 200)
    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(), faceRestorer: NoopFaceRestorer())

    var samples: [Double] = []
    _ = try await pipeline.run(source: source, requestedScale: 4) { samples.append($0) }

    #expect(samples.count > 1)
    #expect(samples == samples.sorted(), "progress must be monotonic")
    #expect(samples.last! >= 0.999)
}

@Test func cancellationStopsTheRunAndLeavesNoScratchFiles() async throws {
    let source = try writeFixture(width: 900, height: 700)
    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(), faceRestorer: NoopFaceRestorer())

    let task = Task {
        try await pipeline.run(source: source, requestedScale: 4) { _ in }
    }
    task.cancel()

    // Task.checkCancellation() throws CancellationError, not UpscaleError.cancelled.
    await #expect(throws: CancellationError.self) { try await task.value }

    let leftovers = try FileManager.default
        .contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        .filter { $0.hasPrefix("scally-") }
    #expect(leftovers.isEmpty, "scratch files leaked: \(leftovers)")
}

@Test func requestingTwoTimesDownsamplesTheFourTimesResult() async throws {
    let source = try writeFixture(width: 100, height: 100)
    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(), faceRestorer: NoopFaceRestorer())
    let result = try await pipeline.run(source: source, requestedScale: 2) { _ in }

    #expect(result.outputWidth == 200)
    #expect(result.appliedScale == 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ScallyKit && swift test --filter PipelineTests`
Expected: FAIL — `UpscalePipeline` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// ScallyKit/Sources/ScallyKit/UpscalePipeline.swift
import Foundation
import Accelerate

public struct UpscaleResult: Sendable, Identifiable, Equatable {
    /// `navigationDestination(item:)` needs Identifiable; `ProcessingModel.State`
    /// is Equatable and wraps this, so it needs Equatable too.
    public var id: URL { outputURL }

    public let outputURL: URL
    public let outputWidth: Int
    public let outputHeight: Int
    public let appliedScale: Int
    public let requestedScale: Int
    public let duration: TimeInterval

    public var wasClamped: Bool { appliedScale != requestedScale }
}

/// The only public entry point into ScallyKit.
public struct UpscalePipeline: Sendable {
    private let upscaler: any Upscaler
    private let faceRestorer: any FaceRestorer
    private let overlap = 16
    private let tileSize = 256

    public init(upscaler: any Upscaler, faceRestorer: any FaceRestorer = NoopFaceRestorer()) {
        self.upscaler = upscaler
        self.faceRestorer = faceRestorer
    }

    public func run(source: URL,
                    requestedScale: Int,
                    destinationDirectory: URL? = nil,
                    progress: @Sendable (Double) -> Void) async throws -> UpscaleResult {
        let started = Date()
        let input = try ImageLoader.load(url: source)

        let decision = MemoryBudget.current()
            .resolveScale(requested: requestedScale, inputWidth: input.width, inputHeight: input.height)
        guard let effectiveScale = decision.scale else {
            throw UpscaleError.imageTooLarge(pixels: input.width * input.height)
        }

        // The model is 4x only; 2x is the 4x result downsampled (Global Constraints).
        let modelScale = upscaler.scale
        let intermediateWidth = input.width * modelScale
        let intermediateHeight = input.height * modelScale

        let scratchDirectory = FileManager.default.temporaryDirectory
        let buffer = try MappedPixelBuffer(width: intermediateWidth, height: intermediateHeight,
                                           directory: scratchDirectory)
        let composer = TileComposer(buffer: buffer, overlap: overlap * modelScale)
        let grid = TileGrid(imageWidth: input.width, imageHeight: input.height,
                            tileSize: tileSize, overlap: overlap)

        for (index, tile) in grid.tiles.enumerated() {
            try Task.checkCancellation()

            try autoreleasepool {
                var tilePixels = [UInt8](repeating: 0, count: tile.width * tile.height * 4)
                for row in 0..<tile.height {
                    let from = ((tile.y + row) * input.bytesPerRow) + tile.x * 4
                    let to = row * tile.width * 4
                    for byte in 0..<(tile.width * 4) {
                        tilePixels[to + byte] = input.pixels[from + byte]
                    }
                }

                let upscaled = try tilePixels.withUnsafeBytes { raw in
                    try upscaler.upscale(tile: raw.baseAddress!, width: tile.width,
                                         height: tile.height, bytesPerRow: tile.width * 4)
                }

                upscaled.pixels.withUnsafeBytes { raw in
                    composer.write(tile: tile.scaled(by: modelScale),
                                   pixels: raw.baseAddress!, bytesPerRow: upscaled.bytesPerRow)
                }
            }

            progress(Double(index + 1) / Double(grid.tiles.count))
        }

        try Task.checkCancellation()

        // v1's restorer is a no-op; the call site exists so adding one later
        // is a single-line change (spec §2).
        _ = try faceRestorer.restore(image: buffer.baseAddress,
                                     width: intermediateWidth, height: intermediateHeight,
                                     bytesPerRow: buffer.bytesPerRow)

        if input.hasAlpha {
            let alpha = AlphaChannel.extract(from: input.pixels, width: input.width,
                                             height: input.height, bytesPerRow: input.bytesPerRow)
            let scaledAlpha = AlphaChannel.scaled(alpha,
                                                  from: (input.width, input.height),
                                                  to: (intermediateWidth, intermediateHeight))
            let destination = buffer.baseAddress.assumingMemoryBound(to: UInt8.self)
            for y in 0..<intermediateHeight {
                for x in 0..<intermediateWidth {
                    destination[y * buffer.bytesPerRow + x * 4 + 3] = scaledAlpha[y * intermediateWidth + x]
                }
            }
        }

        let finalBuffer: MappedPixelBuffer
        if effectiveScale == modelScale {
            finalBuffer = buffer
        } else {
            finalBuffer = try Self.downsample(buffer,
                                              to: (input.width * effectiveScale, input.height * effectiveScale),
                                              directory: scratchDirectory)
        }

        let format = OutputWriter.Format.preferred(hasAlpha: input.hasAlpha)
        let directory = destinationDirectory ?? FileManager.default.temporaryDirectory
        let outputURL = directory
            .appendingPathComponent("scally-output-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)

        try OutputWriter.write(buffer: finalBuffer, to: outputURL, format: format)

        return UpscaleResult(
            outputURL: outputURL,
            outputWidth: finalBuffer.width,
            outputHeight: finalBuffer.height,
            appliedScale: effectiveScale,
            requestedScale: requestedScale,
            duration: Date().timeIntervalSince(started)
        )
    }

    private static func downsample(_ buffer: MappedPixelBuffer,
                                   to size: (width: Int, height: Int),
                                   directory: URL) throws -> MappedPixelBuffer {
        let output = try MappedPixelBuffer(width: size.width, height: size.height, directory: directory)
        var source = vImage_Buffer(data: buffer.baseAddress,
                                   height: vImagePixelCount(buffer.height),
                                   width: vImagePixelCount(buffer.width),
                                   rowBytes: buffer.bytesPerRow)
        var destination = vImage_Buffer(data: output.baseAddress,
                                        height: vImagePixelCount(output.height),
                                        width: vImagePixelCount(output.width),
                                        rowBytes: output.bytesPerRow)
        vImageScale_ARGB8888(&source, &destination, nil, vImage_Flags(kvImageHighQualityResampling))
        return output
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ScallyKit && swift test --filter PipelineTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Narrow the public surface**

Change `public` to package-internal on `TileGrid`, `TileComposer`, `MappedPixelBuffer`, `AlphaChannel` and `OutputWriter`. `UpscalePipeline`, `UpscaleResult`, `UpscaleError`, `Upscaler`, `FaceRestorer`, `TilePixels` and `MemoryBudget` stay public. Re-run the full suite; tests use `@testable` so they keep compiling.

Run: `cd ScallyKit && swift test`
Expected: PASS, all tests.

- [ ] **Step 6: Commit**

```bash
git add ScallyKit
git commit -m "feat: add UpscalePipeline as the package's sole entry point"
```

---

### Task 14: Golden image regression tests

**Files:**
- Create: `ScallyKit/Tests/ScallyKitTests/GoldenImageTests.swift`
- Create: `ScallyKit/Tests/ScallyKitTests/Fixtures/` (3 source images + 3 references)

**Interfaces:**
- Consumes: `UpscalePipeline` (Task 13)
- Produces: a PSNR-thresholded regression gate

Thresholded rather than exact: ANE and GPU numerics differ across devices, and exact-match golden tests on neural output generate false failures forever (spec §9).

- [ ] **Step 1: Add fixtures**

Place three small source images in `Fixtures/`: `portrait.png` (a face, ~200px wide), `text.png` (a screenshot with small type), `texture.png` (foliage or fabric). Keep each under 300px on the long edge so tests stay fast.

- [ ] **Step 2: Write the test with reference generation**

```swift
// ScallyKit/Tests/ScallyKitTests/GoldenImageTests.swift
import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import ScallyKit

private let minimumPSNR = 35.0

private func loadPixels(_ url: URL) throws -> LoadedImage {
    try ImageLoader.load(url: url)
}

private func psnr(_ a: LoadedImage, _ b: LoadedImage) -> Double {
    guard a.width == b.width, a.height == b.height else { return 0 }
    var sumSquaredError = 0.0
    for index in 0..<a.pixels.count where index % 4 != 3 {
        let difference = Double(a.pixels[index]) - Double(b.pixels[index])
        sumSquaredError += difference * difference
    }
    let meanSquaredError = sumSquaredError / Double(a.pixels.count * 3 / 4)
    guard meanSquaredError > 0 else { return .infinity }
    return 10 * log10(255 * 255 / meanSquaredError)
}

@Test(arguments: ["portrait", "text", "texture"])
func upscaleMatchesGoldenReference(name: String) async throws {
    let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    let source = fixtures.appendingPathComponent("\(name).png")
    let reference = fixtures.appendingPathComponent("\(name)-4x-reference.png")

    let pipeline = UpscalePipeline(upscaler: try CoreMLUpscaler(), faceRestorer: NoopFaceRestorer())
    let result = try await pipeline.run(source: source, requestedScale: 4) { _ in }

    guard FileManager.default.fileExists(atPath: reference.path) else {
        // First run: record the reference, then commit it and re-run.
        try FileManager.default.copyItem(at: result.outputURL, to: reference)
        Issue.record("recorded new reference for \(name) — commit it and re-run")
        return
    }

    let score = psnr(try loadPixels(result.outputURL), try loadPixels(reference))
    #expect(score >= minimumPSNR, "\(name) regressed to \(String(format: "%.1f", score))dB")
}
```

- [ ] **Step 3: Generate references**

Run: `cd ScallyKit && swift test --filter GoldenImageTests`
Expected: three recorded-reference failures on the first run. Inspect each generated reference by eye before committing it — a golden test locks in whatever you record, including bugs.

- [ ] **Step 4: Re-run to confirm the gate passes**

Run: `cd ScallyKit && swift test --filter GoldenImageTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add ScallyKit
git commit -m "test: add PSNR-thresholded golden image regression tests"
```

---

## Phase 6 — App data layer

### Task 15: App target, SwiftData model and library store

**Files:**
- Create: `Scally/ScallyApp.swift`
- Create: `Scally/Model/UpscaleRecord.swift`
- Create: `Scally/Storage/LibraryStore.swift`
- Create: `Scally/Info.plist`
- Test: `ScallyTests/LibraryStoreTests.swift`

**Interfaces:**
- Consumes: `UpscaleResult` (Task 13)
- Produces: `UpscaleRecord` `@Model`; `LibraryStore(root:)` with `save(result:sourceThumbnail:context:)`, `outputURL(for:)`, `thumbnailURL(for:)`, `delete(_:context:)`, `totalBytes()`

Create the Xcode project with an iOS App target named `Scally`, add `ScallyKit` as a local package dependency, and add a unit test target `ScallyTests`.

- [ ] **Step 1: Write the failing test**

```swift
// ScallyTests/LibraryStoreTests.swift
import Testing
import Foundation
import SwiftData
@testable import Scally
@testable import ScallyKit

private func makeContext() throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: UpscaleRecord.self, configurations: configuration)
    return ModelContext(container)
}

private func makeTempRoot() -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func savingMovesTheOutputIntoTheLibrary() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()

    let produced = root.appendingPathComponent("incoming.png")
    try Data([1, 2, 3]).write(to: produced)

    let result = UpscaleResult(outputURL: produced, outputWidth: 400, outputHeight: 300,
                               appliedScale: 4, requestedScale: 4, duration: 1.5)
    let record = try store.save(result: result, inputWidth: 100, inputHeight: 75,
                                thumbnail: Data([9, 9]), context: context)

    #expect(FileManager.default.fileExists(atPath: store.outputURL(for: record).path))
    #expect(FileManager.default.fileExists(atPath: store.thumbnailURL(for: record).path))
    #expect(record.appliedScale == 4)
    #expect(record.outputWidth == 400)
}

@Test func deletingRemovesBothFilesAndTheRecord() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()

    let produced = root.appendingPathComponent("incoming.png")
    try Data([1, 2, 3]).write(to: produced)
    let result = UpscaleResult(outputURL: produced, outputWidth: 40, outputHeight: 30,
                               appliedScale: 4, requestedScale: 4, duration: 0.2)
    let record = try store.save(result: result, inputWidth: 10, inputHeight: 8,
                                thumbnail: Data([9]), context: context)

    let outputPath = store.outputURL(for: record).path
    let thumbnailPath = store.thumbnailURL(for: record).path
    try store.delete(record, context: context)

    #expect(FileManager.default.fileExists(atPath: outputPath) == false)
    #expect(FileManager.default.fileExists(atPath: thumbnailPath) == false)
    let remaining = try context.fetch(FetchDescriptor<UpscaleRecord>())
    #expect(remaining.isEmpty)
}

@Test func outputsAreExcludedFromBackup() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()

    let produced = root.appendingPathComponent("incoming.png")
    try Data([1, 2, 3]).write(to: produced)
    let result = UpscaleResult(outputURL: produced, outputWidth: 40, outputHeight: 30,
                               appliedScale: 4, requestedScale: 4, duration: 0.2)
    let record = try store.save(result: result, inputWidth: 10, inputHeight: 8,
                                thumbnail: Data([9]), context: context)

    let values = try store.outputURL(for: record).resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
}

@Test func totalBytesSumsStoredFiles() throws {
    let root = makeTempRoot()
    let store = LibraryStore(root: root)
    let context = try makeContext()

    let produced = root.appendingPathComponent("incoming.png")
    try Data(repeating: 7, count: 1000).write(to: produced)
    _ = try store.save(result: UpscaleResult(outputURL: produced, outputWidth: 4, outputHeight: 4,
                                             appliedScale: 4, requestedScale: 4, duration: 0.1),
                       inputWidth: 1, inputHeight: 1, thumbnail: Data(repeating: 1, count: 50),
                       context: context)

    #expect(store.totalBytes() >= 1050)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run in Xcode: ⌘U, or `xcodebuild test -scheme Scally -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: FAIL — `LibraryStore` not found.

- [ ] **Step 3: Write the model**

```swift
// Scally/Model/UpscaleRecord.swift
import Foundation
import SwiftData

@Model
final class UpscaleRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var appliedScale: Int
    var requestedScale: Int
    var inputWidth: Int
    var inputHeight: Int
    var outputWidth: Int
    var outputHeight: Int
    var duration: TimeInterval
    var fileExtension: String

    init(id: UUID = UUID(), createdAt: Date = .now, appliedScale: Int, requestedScale: Int,
         inputWidth: Int, inputHeight: Int, outputWidth: Int, outputHeight: Int,
         duration: TimeInterval, fileExtension: String) {
        self.id = id
        self.createdAt = createdAt
        self.appliedScale = appliedScale
        self.requestedScale = requestedScale
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.duration = duration
        self.fileExtension = fileExtension
    }

    var wasClamped: Bool { appliedScale != requestedScale }
}
```

- [ ] **Step 4: Write the store**

```swift
// Scally/Storage/LibraryStore.swift
import Foundation
import SwiftData

/// Owns the on-disk half of the library. SwiftData holds metadata; the images
/// live here.
///
/// Files go in Application Support, not Caches: the system may purge Caches,
/// and a history that silently empties itself is worse than no history. They
/// are excluded from iCloud backup because they are large and fully
/// regenerable (spec §7).
struct LibraryStore {
    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("Library", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func outputURL(for record: UpscaleRecord) -> URL {
        root.appendingPathComponent("\(record.id.uuidString).\(record.fileExtension)")
    }

    func thumbnailURL(for record: UpscaleRecord) -> URL {
        root.appendingPathComponent("\(record.id.uuidString)-thumb.jpg")
    }

    @discardableResult
    func save(result: UpscaleResult, inputWidth: Int, inputHeight: Int,
              thumbnail: Data, context: ModelContext) throws -> UpscaleRecord {
        let record = UpscaleRecord(
            appliedScale: result.appliedScale,
            requestedScale: result.requestedScale,
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            outputWidth: result.outputWidth,
            outputHeight: result.outputHeight,
            duration: result.duration,
            fileExtension: result.outputURL.pathExtension
        )

        var destination = outputURL(for: record)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: result.outputURL, to: destination)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try destination.setResourceValues(values)

        try thumbnail.write(to: thumbnailURL(for: record))

        context.insert(record)
        try context.save()
        return record
    }

    func delete(_ record: UpscaleRecord, context: ModelContext) throws {
        try? FileManager.default.removeItem(at: outputURL(for: record))
        try? FileManager.default.removeItem(at: thumbnailURL(for: record))
        context.delete(record)
        try context.save()
    }

    func deleteAll(context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<UpscaleRecord>()) {
            try delete(record, context: context)
        }
    }

    func totalBytes() -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return contents.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
```

- [ ] **Step 5: Wire up the app entry point**

```swift
// Scally/ScallyApp.swift
import SwiftUI
import SwiftData

@main
struct ScallyApp: App {
    var body: some Scene {
        WindowGroup {
            ImportView()
        }
        .modelContainer(for: UpscaleRecord.self)
    }
}
```

Add to `Info.plist`:
```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Scally saves your upscaled images to your photo library.</string>
```

- [ ] **Step 6: Run tests to verify they pass**

Expected: PASS, 4 tests.

- [ ] **Step 7: Commit**

```bash
git add Scally ScallyTests Scally.xcodeproj
git commit -m "feat: add app target, SwiftData record and library store"
```

---

## Phase 7 — User interface

### Task 16: Import screen and scale configuration

**Files:**
- Create: `Scally/Views/ImportView.swift`
- Create: `Scally/Views/ConfigureSheet.swift`
- Create: `Scally/ViewModels/ConfigureModel.swift`
- Test: `ScallyTests/ConfigureModelTests.swift`

**Interfaces:**
- Consumes: `MemoryBudget`, `ScaleDecision` (Task 11)
- Produces: `ConfigureModel(inputWidth:inputHeight:budget:)` with `.isAvailable(scale:)`, `.outputDimensions(scale:)`, `.estimatedBytes(scale:)`, `.unavailableReason(scale:)`

The clamp must surface *before* the user commits (spec §8). That logic is a plain testable type; the view only renders it.

- [ ] **Step 1: Write the failing test**

```swift
// ScallyTests/ConfigureModelTests.swift
import Testing
@testable import Scally
@testable import ScallyKit

@Test func generousBudgetOffersBothScales() {
    let model = ConfigureModel(inputWidth: 1000, inputHeight: 800,
                               budget: MemoryBudget(availableBytes: 4_000_000_000))
    #expect(model.isAvailable(scale: 2))
    #expect(model.isAvailable(scale: 4))
}

@Test func tightBudgetDisablesFourTimes() {
    let model = ConfigureModel(inputWidth: 4032, inputHeight: 3024,
                               budget: MemoryBudget(availableBytes: 400_000_000))
    #expect(model.isAvailable(scale: 2))
    #expect(model.isAvailable(scale: 4) == false)
    #expect(model.unavailableReason(scale: 4)?.isEmpty == false)
}

@Test func outputDimensionsMultiplyBothAxes() {
    let model = ConfigureModel(inputWidth: 300, inputHeight: 200,
                               budget: MemoryBudget(availableBytes: 4_000_000_000))
    let size = model.outputDimensions(scale: 4)
    #expect(size.width == 1200)
    #expect(size.height == 800)
}

@Test func defaultScaleIsTheLargestAvailable() {
    let generous = ConfigureModel(inputWidth: 500, inputHeight: 500,
                                  budget: MemoryBudget(availableBytes: 4_000_000_000))
    #expect(generous.defaultScale == 4)

    let tight = ConfigureModel(inputWidth: 4032, inputHeight: 3024,
                               budget: MemoryBudget(availableBytes: 400_000_000))
    #expect(tight.defaultScale == 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `ConfigureModel` not found.

- [ ] **Step 3: Write the model**

```swift
// Scally/ViewModels/ConfigureModel.swift
import Foundation
import ScallyKit

struct ConfigureModel {
    let inputWidth: Int
    let inputHeight: Int
    let budget: MemoryBudget

    static let offeredScales = [2, 4]

    init(inputWidth: Int, inputHeight: Int, budget: MemoryBudget = .current()) {
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.budget = budget
    }

    func outputDimensions(scale: Int) -> (width: Int, height: Int) {
        (inputWidth * scale, inputHeight * scale)
    }

    /// Rough encoded size. HEIC lands near 0.35 bytes per pixel at our quality;
    /// this is for setting expectations, not accounting.
    func estimatedBytes(scale: Int) -> Int {
        let size = outputDimensions(scale: scale)
        return Int(Double(size.width * size.height) * 0.35)
    }

    func isAvailable(scale: Int) -> Bool {
        budget.resolveScale(requested: scale, inputWidth: inputWidth, inputHeight: inputHeight)
            == .granted(scale: scale)
    }

    func unavailableReason(scale: Int) -> String? {
        guard !isAvailable(scale: scale) else { return nil }
        return "\(scale)× is too large for this photo on this device."
    }

    var defaultScale: Int {
        Self.offeredScales.filter { isAvailable(scale: $0) }.max() ?? 2
    }
}
```

- [ ] **Step 4: Write the shared input type**

Every screen after Import passes the chosen photo along, so it needs one
concrete type. `PhotosPickerItem` cannot be used directly — it yields data, not
a file, and the pipeline reads from a URL.

```swift
// Scally/Model/PendingImage.swift
import SwiftUI
import PhotosUI

/// A photo the user picked, written to a temporary file the pipeline can read.
struct PendingImage: Identifiable {
    let id = UUID()
    let url: URL
    let preview: UIImage
    let width: Int
    let height: Int

    static func load(from item: PhotosPickerItem?) async -> PendingImage? {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("input-\(UUID().uuidString).img")
        guard (try? data.write(to: url)) != nil else { return nil }

        // Downsample for display only; the pipeline always reads the original
        // file, never this preview.
        let preview = await downsampled(image, maxPixel: 1200)

        return PendingImage(url: url, preview: preview,
                            width: Int(image.size.width * image.scale),
                            height: Int(image.size.height * image.scale))
    }

    private static func downsampled(_ image: UIImage, maxPixel: CGFloat) async -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPixel else { return image }
        let ratio = maxPixel / longest
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
```

```swift
// Scally/Views/RecentStrip.swift
import SwiftUI

/// The horizontal row of recent results on the import screen.
struct RecentStrip: View {
    let records: [UpscaleRecord]
    private let store = LibraryStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(records) { record in
                        NavigationLink {
                            SavedResultView(record: record)
                        } label: {
                            if let image = UIImage(contentsOfFile: store.thumbnailURL(for: record).path) {
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.quaternary).frame(width: 72, height: 72)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
```

- [ ] **Step 5: Write the views**

```swift
// Scally/Views/ImportView.swift
import SwiftUI
import SwiftData
import PhotosUI

struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UpscaleRecord.createdAt, order: .reverse) private var records: [UpscaleRecord]

    @State private var selection: PhotosPickerItem?
    @State private var pendingImage: PendingImage?
    @State private var showingHistory = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 44, weight: .light))
                        Text("Choose a photo")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal)

                if records.isEmpty {
                    Text("Upscaled photos will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    RecentStrip(records: Array(records.prefix(10)))
                }

                Spacer()
            }
            .navigationTitle("Scally")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHistory = true } label: { Image(systemName: "clock") }
                        .disabled(records.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .navigationDestination(isPresented: $showingHistory) { HistoryView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $pendingImage) { ConfigureSheet(pending: $0) }
            .onChange(of: selection) { _, item in
                Task { pendingImage = await PendingImage.load(from: item) }
            }
        }
    }
}
```

```swift
// Scally/Views/ConfigureSheet.swift
import SwiftUI

struct ConfigureSheet: View {
    let pending: PendingImage
    @State private var scale: Int
    @State private var isProcessing = false
    @Environment(\.dismiss) private var dismiss

    private var model: ConfigureModel {
        ConfigureModel(inputWidth: pending.width, inputHeight: pending.height)
    }

    init(pending: PendingImage) {
        self.pending = pending
        _scale = State(initialValue: ConfigureModel(inputWidth: pending.width,
                                                    inputHeight: pending.height).defaultScale)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(uiImage: pending.preview)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Picker("Scale", selection: $scale) {
                    ForEach(ConfigureModel.offeredScales, id: \.self) { candidate in
                        Text("\(candidate)×").tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                let size = model.outputDimensions(scale: scale)
                VStack(spacing: 4) {
                    Text("\(pending.width) × \(pending.height)  →  \(size.width) × \(size.height)")
                        .font(.subheadline.monospacedDigit())
                    Text(ByteCountFormatter.string(fromByteCount: Int64(model.estimatedBytes(scale: scale)),
                                                   countStyle: .file) + " approx.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let reason = model.unavailableReason(scale: 4) {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                NavigationLink {
                    ProcessingView(pending: pending, scale: scale)
                } label: {
                    Text("Upscale").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Upscale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
```

Disable the unavailable segment by rendering only `ConfigureModel.offeredScales.filter { model.isAvailable(scale: $0) }` in the picker, keeping the explanatory label visible so the absence is explained rather than mysterious.

- [ ] **Step 6: Run tests to verify they pass**

Expected: PASS, 4 tests.

- [ ] **Step 7: Manual check**

Build and run. Pick a small photo — both 2× and 4× offered. Pick a 12MP photo on a low-memory device — 4× absent with the explanation visible.

- [ ] **Step 8: Commit**

```bash
git add Scally ScallyTests
git commit -m "feat: add import screen and scale configuration with memory clamp"
```

---

### Task 17: Processing screen

**Files:**
- Create: `Scally/Views/ProcessingView.swift`
- Create: `Scally/ViewModels/ProcessingModel.swift`
- Test: `ScallyTests/ProcessingModelTests.swift`

**Interfaces:**
- Consumes: `UpscalePipeline` (Task 13), `LibraryStore` (Task 15)
- Produces: `ProcessingModel` observable with `.progress`, `.state`, `.start(...)`, `.cancel()`

- [ ] **Step 1: Write the failing test**

```swift
// ScallyTests/ProcessingModelTests.swift
import Testing
import Foundation
@testable import Scally
@testable import ScallyKit

@Test func estimatedRemainingIsNilBeforeAnyProgress() {
    let model = ProcessingModel()
    #expect(model.estimatedRemaining == nil)
}

@Test func estimatedRemainingShrinksAsProgressGrows() {
    let model = ProcessingModel()
    model.recordProgress(0.25, elapsed: 4)
    let early = model.estimatedRemaining
    model.recordProgress(0.75, elapsed: 12)
    let late = model.estimatedRemaining

    #expect(early != nil && late != nil)
    #expect(late! < early!)
}

@Test func cancellingMovesStateToCancelled() {
    let model = ProcessingModel()
    model.cancel()
    #expect(model.state == .cancelled)
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `ProcessingModel` not found.

- [ ] **Step 3: Write the model**

```swift
// Scally/ViewModels/ProcessingModel.swift
import Foundation
import Observation
import ScallyKit

@Observable
final class ProcessingModel {
    enum State: Equatable {
        case idle, running, finished(UpscaleResult), failed(String), cancelled
    }

    private(set) var progress: Double = 0
    private(set) var state: State = .idle
    private var elapsedAtLastSample: TimeInterval = 0
    private var task: Task<Void, Never>?

    /// Linear extrapolation from observed throughput. Tiles are uniform work,
    /// so this is honest rather than decorative.
    var estimatedRemaining: TimeInterval? {
        guard progress > 0.01, elapsedAtLastSample > 0 else { return nil }
        return elapsedAtLastSample / progress - elapsedAtLastSample
    }

    func recordProgress(_ value: Double, elapsed: TimeInterval) {
        progress = value
        elapsedAtLastSample = elapsed
    }

    func start(source: URL, scale: Int, pipeline: UpscalePipeline) {
        state = .running
        let started = Date()
        task = Task { [weak self] in
            do {
                let result = try await pipeline.run(source: source, requestedScale: scale) { value in
                    Task { @MainActor in
                        self?.recordProgress(value, elapsed: Date().timeIntervalSince(started))
                    }
                }
                await MainActor.run { self?.state = .finished(result) }
            } catch is CancellationError {
                await MainActor.run { self?.state = .cancelled }
            } catch let error as UpscaleError where error == .cancelled {
                await MainActor.run { self?.state = .cancelled }
            } catch {
                await MainActor.run { self?.state = .failed(error.localizedDescription) }
            }
        }
    }

    func cancel() {
        task?.cancel()
        state = .cancelled
    }
}
```

- [ ] **Step 4: Write the view**

```swift
// Scally/Views/ProcessingView.swift
import SwiftUI

struct ProcessingView: View {
    let pending: PendingImage
    let scale: Int

    @State private var model = ProcessingModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Image(uiImage: pending.preview)
                .resizable().scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))

            VStack(spacing: 10) {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(Int(model.progress * 100))%").monospacedDigit()
                    Spacer()
                    if let remaining = model.estimatedRemaining {
                        Text("about \(Int(remaining.rounded()))s left")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Button("Cancel", role: .cancel) {
                model.cancel()
                dismiss()
            }

            Spacer()
        }
        .padding(.top, 40)
        .navigationTitle("Upscaling")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            model.start(source: pending.url, scale: scale,
                        pipeline: UpscalePipeline(upscaler: try! CoreMLUpscaler()))
        }
        .navigationDestination(item: resultBinding) { result in
            ResultView(pending: pending, result: result)
        }
    }

    private var resultBinding: Binding<UpscaleResult?> {
        Binding(
            get: { if case .finished(let result) = model.state { result } else { nil } },
            set: { _ in }
        )
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Expected: PASS, 3 tests.

- [ ] **Step 6: Manual check**

Run a 4× upscale on a 3000px photo. Progress must advance smoothly and monotonically, never jump to 100% and hang. Cancel mid-run and confirm it returns promptly.

- [ ] **Step 7: Commit**

```bash
git add Scally ScallyTests
git commit -m "feat: add processing screen with honest progress and cancellation"
```

---

### Task 18: Before/after comparison with zoom

**Files:**
- Create: `Scally/Views/CompareView.swift`
- Create: `Scally/Views/ResultView.swift`
- Test: `ScallyTests/CompareGeometryTests.swift`

**Interfaces:**
- Consumes: `UpscaleResult` (Task 13)
- Produces: `CompareView(before:after:)`; `CompareGeometry.fitScale(content:in:)` and `.oneToOneScale(content:in:)`

This is the highest-value screen in the app. Fitted to a phone display, a 4× upscale is visually identical to its input — without real zoom the app appears to do nothing at all (spec §8). The "100%" button is not a convenience; it is how the product demonstrates that it worked.

- [ ] **Step 1: Write the failing test**

```swift
// ScallyTests/CompareGeometryTests.swift
import Testing
import CoreGraphics
@testable import Scally

@Test func fitScaleShrinksLargeContentToTheViewport() {
    let scale = CompareGeometry.fitScale(content: CGSize(width: 4000, height: 3000),
                                         in: CGSize(width: 400, height: 600))
    #expect(abs(scale - 0.1) < 0.0001)
}

@Test func fitScaleUsesTheLimitingAxis() {
    let scale = CompareGeometry.fitScale(content: CGSize(width: 1000, height: 4000),
                                         in: CGSize(width: 500, height: 500))
    #expect(abs(scale - 0.125) < 0.0001)
}

@Test func oneToOneAccountsForScreenScale() {
    // At 1:1 an image pixel maps to a device pixel, so the view-space scale is
    // the reciprocal of the screen scale.
    let scale = CompareGeometry.oneToOneScale(screenScale: 3)
    #expect(abs(scale - (1.0 / 3.0)) < 0.0001)
}

@Test func clampKeepsZoomWithinBounds() {
    #expect(CompareGeometry.clamp(zoom: 0.01, minimum: 0.1, maximum: 4) == 0.1)
    #expect(CompareGeometry.clamp(zoom: 99, minimum: 0.1, maximum: 4) == 4)
    #expect(CompareGeometry.clamp(zoom: 1.5, minimum: 0.1, maximum: 4) == 1.5)
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `CompareGeometry` not found.

- [ ] **Step 3: Write the geometry helper**

```swift
// Scally/Views/CompareView.swift  (geometry section)
import SwiftUI

enum CompareGeometry {
    static func fitScale(content: CGSize, in viewport: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0 else { return 1 }
        return min(viewport.width / content.width, viewport.height / content.height)
    }

    /// One image pixel per device pixel.
    static func oneToOneScale(screenScale: CGFloat) -> CGFloat {
        1.0 / screenScale
    }

    static func clamp(zoom: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(zoom, minimum), maximum)
    }
}
```

- [ ] **Step 4: Write the comparison view**

```swift
// Scally/Views/CompareView.swift  (view section)
struct CompareView: View {
    let before: UIImage
    let after: UIImage

    @State private var dividerFraction: CGFloat = 0.5
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let content = after.size
            let fit = CompareGeometry.fitScale(content: content, in: viewport)
            let dividerX = viewport.width * dividerFraction

            ZStack {
                Color.black.ignoresSafeArea()

                ZStack {
                    Image(uiImage: before)
                        .resizable().interpolation(.none).scaledToFit()

                    Image(uiImage: after)
                        .resizable().interpolation(.none).scaledToFit()
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: viewport.width * (1 - dividerFraction))
                        }
                }
                .scaleEffect(zoom)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                zoom = CompareGeometry.clamp(zoom: committedZoom * value.magnification,
                                                             minimum: fit, maximum: 12)
                            }
                            .onEnded { _ in committedZoom = zoom },
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(width: committedOffset.width + value.translation.width,
                                                height: committedOffset.height + value.translation.height)
                            }
                            .onEnded { _ in committedOffset = offset }
                    )
                )

                // Divider sits above the zoom layer so dragging it never pans.
                DividerHandle(x: dividerX, height: viewport.height)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dividerFraction = min(max(value.location.x / viewport.width, 0), 1)
                            }
                    )

                VStack {
                    HStack {
                        Label("Before", systemImage: "arrow.left").labelStyle(.titleOnly)
                        Spacer()
                        Label("After", systemImage: "arrow.right").labelStyle(.titleOnly)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding()
                    Spacer()
                    Button {
                        withAnimation(.snappy) {
                            zoom = CompareGeometry.oneToOneScale(screenScale: UIScreen.main.scale) / fit
                            committedZoom = zoom
                            offset = .zero
                            committedOffset = .zero
                        }
                    } label: {
                        Text("100%").font(.caption.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

private struct DividerHandle: View {
    let x: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.white).frame(width: 2, height: height)
            Circle().fill(.white).frame(width: 34, height: 34)
                .overlay(Image(systemName: "arrow.left.and.right")
                    .font(.caption.weight(.bold)).foregroundStyle(.black))
                .shadow(radius: 4)
        }
        .position(x: x, y: height / 2)
        .contentShape(Rectangle().size(CGSize(width: 60, height: height)))
    }
}
```

```swift
// Scally/Views/ResultView.swift
import SwiftUI
import SwiftData
import ScallyKit

struct ResultView: View {
    let pending: PendingImage
    let result: UpscaleResult

    @Environment(\.modelContext) private var context
    @State private var afterImage: UIImage?
    @State private var saveState: SaveState = .idle

    enum SaveState: Equatable { case idle, saving, saved, failed(String) }

    var body: some View {
        VStack(spacing: 0) {
            if let afterImage {
                CompareView(before: pending.preview, after: afterImage)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }

            if result.wasClamped {
                Label("Upscaled at \(result.appliedScale)× — \(result.requestedScale)× needed more memory than this device had free.",
                      systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.top, 8)
            }

            HStack(spacing: 12) {
                Button { save() } label: {
                    Label(saveState == .saved ? "Saved" : "Save", systemImage: saveState == .saved ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveState == .saving || saveState == .saved)

                ShareLink(item: result.outputURL) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding()
        }
        .navigationTitle("\(result.outputWidth) × \(result.outputHeight)")
        .navigationBarTitleDisplayMode(.inline)
        .task { afterImage = UIImage(contentsOfFile: result.outputURL.path) }
    }

    private func save() { /* implemented in Task 19 */ }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Expected: PASS, 4 tests.

- [ ] **Step 6: Manual check — this is the one that matters**

On a device, upscale a deliberately poor photo. Drag the divider across the face or text; tap 100%. The difference must be unmistakable. If it is not, the problem is either `interpolation(.none)` missing (SwiftUI will smooth the "before" image and hide the difference) or the zoom not actually reaching 1:1. Verify the divider drags without panning the image, and that pinch does not move the divider.

- [ ] **Step 7: Commit**

```bash
git add Scally ScallyTests
git commit -m "feat: add before/after comparison with pinch zoom to 1:1"
```

---

### Task 19: Save to Photos and persist to the library

**Files:**
- Modify: `Scally/Views/ResultView.swift` — implement `save()`
- Create: `Scally/Storage/PhotoSaver.swift`
- Create: `Scally/Storage/Thumbnailer.swift`
- Test: `ScallyTests/ThumbnailerTests.swift`

**Interfaces:**
- Consumes: `LibraryStore` (Task 15)
- Produces: `PhotoSaver.save(fileURL:) async throws`; `Thumbnailer.make(from:maxPixel:) -> Data?`

- [ ] **Step 1: Write the failing test**

```swift
// ScallyTests/ThumbnailerTests.swift
import Testing
import Foundation
import UIKit
@testable import Scally

@Test func thumbnailFitsWithinTheRequestedBound() throws {
    let large = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
    try large.pngData()!.write(to: url)

    let data = try #require(Thumbnailer.make(from: url, maxPixel: 512))
    let thumbnail = try #require(UIImage(data: data))

    #expect(max(thumbnail.size.width, thumbnail.size.height) <= 512)
    #expect(data.count < 200_000)

    try? FileManager.default.removeItem(at: url)
}

@Test func thumbnailingAMissingFileReturnsNil() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope.png")
    #expect(Thumbnailer.make(from: missing, maxPixel: 512) == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `Thumbnailer` not found.

- [ ] **Step 3: Write the implementations**

```swift
// Scally/Storage/Thumbnailer.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Thumbnailer {
    /// Downsamples without fully decoding the source — important, since the
    /// source here is a freshly written 200-megapixel file.
    static func make(from url: URL, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail,
                                   [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
```

```swift
// Scally/Storage/PhotoSaver.swift
import Foundation
import Photos

enum PhotoSaver {
    enum SaveError: Error { case notAuthorised }

    /// Add-only authorisation: the app never needs to read the library.
    static func save(fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.notAuthorised }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: fileURL, options: nil)
        }
    }
}
```

- [ ] **Step 4: Wire into ResultView**

```swift
// Scally/Views/ResultView.swift — replace the save() stub
private func save() {
    saveState = .saving
    Task {
        do {
            try await PhotoSaver.save(fileURL: result.outputURL)

            // Persisting to the library MOVES the output file, so it must come
            // after the Photos save, which reads from that same path.
            let store = LibraryStore()
            let thumbnail = Thumbnailer.make(from: result.outputURL, maxPixel: 512) ?? Data()
            try store.save(result: result, inputWidth: pending.width, inputHeight: pending.height,
                           thumbnail: thumbnail, context: context)

            saveState = .saved
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Expected: PASS, 2 tests.

- [ ] **Step 6: Manual check**

Save an upscale, then open Photos and confirm the image is there at full resolution. Deny the permission prompt once and confirm the app reports it rather than failing silently.

- [ ] **Step 7: Commit**

```bash
git add Scally ScallyTests
git commit -m "feat: save results to Photos and the on-device library"
```

---

### Task 20: History

**Files:**
- Create: `Scally/Views/HistoryView.swift`
- Test: none — this screen is a `@Query` over tested storage

- [ ] **Step 1: Write the view**

```swift
// Scally/Views/HistoryView.swift
import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UpscaleRecord.createdAt, order: .reverse) private var records: [UpscaleRecord]

    private let store = LibraryStore()
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(records) { record in
                    NavigationLink {
                        SavedResultView(record: record)
                    } label: {
                        HistoryCell(record: record, thumbnailURL: store.thumbnailURL(for: record))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            try? store.delete(record, context: context)
                        }
                    }
                }
            }
            .padding(8)
        }
        .navigationTitle("History")
        .overlay {
            if records.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "clock",
                                       description: Text("Upscaled photos you save will appear here."))
            }
        }
    }
}

private struct HistoryCell: View {
    let record: UpscaleRecord
    let thumbnailURL: URL

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = UIImage(contentsOfFile: thumbnailURL.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }

            Text("\(record.appliedScale)×")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 2: Add SavedResultView**

```swift
// Scally/Views/HistoryView.swift (continued)
struct SavedResultView: View {
    let record: UpscaleRecord
    private let store = LibraryStore()

    var body: some View {
        VStack {
            if let image = UIImage(contentsOfFile: store.outputURL(for: record).path) {
                CompareView(before: image, after: image)
            }
            ShareLink(item: store.outputURL(for: record)) {
                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).padding()
        }
        .navigationTitle(record.createdAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

Note: the original input is not retained, so a saved result has no true "before". Show the result alone here rather than a fake comparison — replace `CompareView(before: image, after: image)` with a plain zoomable image, or store a downscaled copy of the input in Task 15 if you want real comparison in history. Decide before implementing; do not ship a comparison that compares an image to itself.

- [ ] **Step 3: Manual check**

Save three upscales. Confirm the grid shows them newest-first with correct scale badges, that tapping opens the image, and that deleting removes both the cell and the underlying files (check storage size in Settings afterwards).

- [ ] **Step 4: Commit**

```bash
git add Scally
git commit -m "feat: add history grid with delete"
```

---

### Task 21: Settings and licenses

**Files:**
- Create: `Scally/Views/SettingsView.swift`
- Create: `Scally/Views/LicensesView.swift`
- Create: `Scally/Resources/Licenses/RealESRGAN-BSD3.txt`

**Interfaces:**
- Consumes: `LibraryStore.totalBytes()`, `.deleteAll(context:)` (Task 15)

The Licenses screen is a release requirement, not a nicety: BSD-3-Clause obliges reproducing the copyright notice and disclaimer in materials distributed with the binary (spec §2).

- [ ] **Step 1: Add the licence text**

Copy the full BSD-3-Clause text from `https://github.com/xinntao/Real-ESRGAN/blob/master/LICENSE` verbatim into `Scally/Resources/Licenses/RealESRGAN-BSD3.txt`, including the copyright line. Do not paraphrase or truncate it.

- [ ] **Step 2: Write the views**

```swift
// Scally/Views/SettingsView.swift
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false
    @State private var totalBytes = 0

    private let store = LibraryStore()

    var body: some View {
        NavigationStack {
            List {
                Section("Storage") {
                    LabeledContent("Used",
                                   value: ByteCountFormatter.string(fromByteCount: Int64(totalBytes),
                                                                    countStyle: .file))
                    Button("Clear history", role: .destructive) { showingClearConfirmation = true }
                        .disabled(totalBytes == 0)
                }

                Section("About") {
                    NavigationLink("Licenses") { LicensesView() }
                    LabeledContent("Processing", value: "On device")
                }

                Section {
                    Text("Scally never uploads your photos. Everything happens on your iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { totalBytes = store.totalBytes() }
            .confirmationDialog("Delete all saved upscales?", isPresented: $showingClearConfirmation,
                                titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    try? store.deleteAll(context: context)
                    totalBytes = store.totalBytes()
                }
            } message: {
                Text("Photos you already saved to your library are not affected.")
            }
        }
    }
}
```

```swift
// Scally/Views/LicensesView.swift
import SwiftUI

struct LicensesView: View {
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "RealESRGAN-BSD3", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "License text unavailable."
        }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Real-ESRGAN").font(.headline)
                Text("Scally upscales images using Real-ESRGAN (realesr-general-x4v3).")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(licenseText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 3: Manual check**

Open Settings, confirm storage reflects reality, clear history and confirm it drops to zero. Open Licenses and confirm the full BSD-3-Clause text renders, including the copyright line and the warranty disclaimer.

- [ ] **Step 4: Commit**

```bash
git add Scally
git commit -m "feat: add settings with storage management and required license notice"
```

---

## Phase 8 — Device validation

### Task 22: Device matrix and performance verification

**Files:**
- Create: `docs/device-testing.md`

No unit tests here. The memory clamp only truly executes under real pressure, so it cannot be proven in a simulator (spec §9).

- [ ] **Step 1: Run the matrix**

On at least one older iPhone and one current one, record for each:

| Check | Old device | Current device |
|---|---|---|
| 12MP photo at 4× — completes or clamps, never terminates | | |
| Peak memory (Xcode Memory gauge) | | |
| Per-tile latency and executing compute unit (Core ML report) | | |
| Total time for a 12MP 4× run | | |
| Thermal state after three consecutive runs | | |
| Divider drag does not pan; pinch does not move divider | | |
| 100% button reaches true 1:1 | | |
| Saving a 4× output to Photos succeeds | | |

- [ ] **Step 2: Confirm the clamp actually fires**

On the old device, open a 12MP photo and verify 4× is unavailable with the explanation shown — the path proven in Task 11 must be observed working end to end at least once on real hardware.

- [ ] **Step 3: Record results**

Write the filled table into `docs/device-testing.md` with device models and OS versions. If peak memory exceeds half the device's total RAM at any point, stop and revisit the tile size before shipping.

- [ ] **Step 4: Commit**

```bash
git add docs/device-testing.md
git commit -m "docs: record device test matrix results"
```

---

## Open items for the human

1. **Deployment target** — set provisionally to iOS 18.0 in Global Constraints. Confirm or change before Task 15.
2. **History comparison** — a saved record has no stored "before". Either accept result-only viewing in history (default) or store a downscaled input copy in Task 15. Decide before Task 20.
3. **App display name and icon** — "Scally" is taken from the directory name. No icon is specified anywhere in this plan.
4. **Fixture images for Task 14** — three are needed, and their licensing matters if they ship inside the test bundle. Use your own photographs.

# Scally — On-Device Image Upscaler for iOS

**Status:** Approved design, pre-implementation
**Date:** 2026-09-20

## 1. Purpose

An iOS app that makes small, low-resolution photos larger and cleaner, running
entirely on-device. Target inputs are compressed phone photos and screenshots
(the primary case) and scanned family photographs (secondary, partially served
in v1 — see §3).

The app is free. No in-app purchases, no advertising, no subscription, no
account, and no server. Every upscale runs on the user's device, which means
zero marginal cost per operation and no privacy surface to defend.

### Success criteria

1. A user can pick a photo, upscale it, visibly verify the improvement, and save
   it, without reading instructions.
2. A 12-megapixel input completes without a memory-pressure termination on a
   device two generations old, at 4x where the memory budget allows it and at a
   clamped 2x where it does not (§5). Termination is a failure; clamping with
   the user informed beforehand is not.
3. The improvement is obvious at 1:1 zoom on a phone screen.

### Non-goals

Batch processing, video, generative detail synthesis, cloud processing,
accounts, and monetisation are all explicitly out of scope for v1. Batch is the
most likely first addition after launch.

## 2. Licensing constraints

This section is load-bearing. It is the reason the feature set looks the way it
does.

### Cleared for use

**Real-ESRGAN** is BSD-3-Clause, verified against the repository's LICENSE file.
It permits commercial and non-commercial use. The specific checkpoint is
`realesr-general-x4v3` (SRVGGNetCompact, ~1.2M parameters).

Obligations: the app must reproduce the BSD-3-Clause copyright notice and
disclaimer in its documentation or materials, satisfied by a Licenses screen in
Settings. The authors' names may not be used to promote the app.

Residual risk, accepted: Real-ESRGAN was trained on DIV2K, Flickr2K and OST,
datasets generally distributed for research. Prevailing practice treats model
weights as not a derivative work of training data, and the authors released
these checkpoints under BSD-3-Clause themselves. This assumption underpins
essentially every commercial ESRGAN-derived product.

**Swin2SR / SwinIR** are Apache-2.0 and serve as fallback if conversion or
performance of the primary model disappoints. Transformer architectures are
slower on the Neural Engine.

### Blocked for commercial use

Face restoration is encumbered across the board, and not by a single license:

| Model | License | Commercial use |
|---|---|---|
| CodeFormer | S-Lab License 1.0 | No — requires contacting contributors |
| GFPGAN | Apache-2.0 badge; builds on DFDNet + StyleGAN2 | No — DFDNet is CC BY-NC-SA 4.0, StyleGAN2 is NVIDIA Source Code License-NC |
| Most alternatives | trained on FFHQ | No — FFHQ is CC BY-NC-SA 4.0 |

The FFHQ row is the structural problem: nearly all blind face restoration traces
back to a dataset that is both non-commercial and share-alike. GFPGAN is
specifically misleading, presenting an Apache-2.0 badge while its own
acknowledgements credit two non-commercial ancestors.

### How "free" interacts with this

Because Scally is genuinely free — no ads, no IAP, no data monetisation — it has
a credible claim to the non-commercial permission these licenses grant. That
potentially unblocks face restoration later.

Three caveats are recorded deliberately. "Non-commercial" is ambiguous and this
document is not legal advice. CC BY-NC-SA carries ShareAlike, and converting
weights to Core ML is plausibly an adaptation, which would oblige publishing the
converted model under the same license — an obligation, not a blocker.
Distribution via the App Store does not by itself make use commercial, but it is
not irrelevant either.

**Consequence for the architecture:** any non-commercially-licensed model must
sit behind a protocol boundary, so that a future decision to monetise removes
one type rather than requiring a rewrite. See §4.

## 3. Scope of v1

In scope: single-image pick, 2x or 4x upscale, before/after comparison with
zoom, save to Photos, share, and a persistent history.

Deferred: face restoration, batch processing.

**Positioning consequence:** v1 must not be marketed as restoring old family
photographs. Plain super-resolution sharpens a blurry face into a crisper blurry
face; the capability that would deliver on that promise is deferred and may
never ship in a form compatible with a commercial version.

## 4. Architecture

Two targets: `ScallyKit`, a UI-free Swift package, and the SwiftUI app. The kit
holds all algorithmic risk and is testable against fixture images on macOS
without a simulator.

### Pipeline

```
ImageLoader → Tiler → [Upscaler] → [FaceRestorer] → TileComposer → OutputWriter
```

`Upscaler` and `FaceRestorer` are protocols. v1 ships `CoreMLUpscaler` and
`NoopFaceRestorer`, the latter returning its input unchanged. This is the
boundary required by §2: stage two adds one type, and abandoning it removes one
type.

`UpscalePipeline` is the sole public entry point. It accepts a source URL, a
scale factor and a progress callback, and returns an output URL or a typed
error. All other kit types are internal, preventing the app layer from growing
dependencies on tiling internals.

### App layer

Four screens — import, processing, result, history — each with a thin view
model. Persistence is SwiftData for metadata with image files on disk (§6).

### Open decision

Minimum deployment target is unresolved. Recommendation is current-minus-two for
reach; the alternative is targeting the newest release to avoid availability
checks around Core ML and SwiftData APIs.

## 5. Memory and tiling

The constraint: a 12MP input at 4x yields 192 megapixels, roughly 770MB as
RGBA8. iOS will terminate the process well before that on most devices.

The exploitable asymmetry: the input is cheap. 12MP decoded is about 48MB. Only
the output is dangerous. The design therefore holds the source in memory and
streams the destination.

### Output buffer

A memory-mapped scratch file, sized `W × H × 4` up front, wrapped in a
`CGContext` via a `CGDataProvider`. This scratch file lives in Caches and is
deleted once encoding completes — it is distinct from the final encoded output,
which is written to Application Support (§7). Tiles are drawn directly into it; the kernel
pages dirty regions out under pressure, holding resident memory flat regardless
of output dimensions. Final encoding reads back sequentially, the access pattern
paging handles best.

### Tiling

Input tiles are 256×256 with 16px overlap, producing 1024×1024 output tiles of
about 4MB each. The Core ML model is compiled with a fixed input shape, which
the Neural Engine strongly prefers. Edge tiles are reflect-padded; zero padding
produces visible dark fringes at image borders.

Each tile is processed inside its own `autoreleasepool` on a serial queue, with
a cancellation check between tiles. Overlapping regions blend with a linear
alpha ramp. Overlap is required, not defensive: ESRGAN-family models produce
real artifacts at tile edges.

### Budget enforcement

Before processing, the pipeline computes the required output budget and compares
it against `os_proc_available_memory()`. If 4x does not fit, it clamps to 2x and
surfaces this in the UI before the user commits, rather than failing mid-run.

### Correctness strategy

Injecting an identity `Upscaler` (nearest-neighbour) must produce a composed
output equal to a plain resize of the input. This validates the tiler and
blender with no neural network in the loop.

## 6. Model and conversion

Source checkpoint: `realesr-general-x4v3` from the official Real-ESRGAN release.
At FP16 this is roughly 2–3MB, small enough to bundle — no download, no CDN, no
first-launch wait. The architecture uses convolutions, PReLU and pixel-shuffle
upsampling, all supported by `coremltools` without custom layers.

Conversion lives in `tools/convert.py` with pinned dependencies. The resulting
`.mlpackage` is committed so the app builds without a Python environment.
Configuration: fixed input shape `1×3×256×256`, FP16, all compute units.

### Validation gate

Conversion must be validated numerically. Over a fixture set of at least 16
tiles spanning smooth, textured and high-contrast content, PyTorch and Core ML
outputs must agree to a maximum absolute difference of 2/255 per channel, with
mean absolute difference below 0.5/255. These thresholds accommodate FP16
rounding while still catching a genuinely wrong conversion; if the Neural Engine
path cannot meet them, the gate is evaluated against the CPU compute unit and
the ANE discrepancy recorded rather than silently accepted. Silently incorrect conversions are the characteristic failure mode
here: output still looks plausible while being measurably worse than intended.

### Integration hazards

- EXIF orientation must be applied before tiling, or portrait inputs emerge
  rotated.
- Alpha must be separated and scaled with Lanczos; the model has no alpha
  channel.
- Colour space: iPhone photos are Display P3 and increasingly HDR. v1 converts
  to sRGB for inference and re-tags output, accepting gamut loss on vivid
  images.
- Neural Engine op support must be measured with Xcode's Core ML performance
  report, not assumed. GPU fallback is acceptable.

### Fallbacks

Swin2SR (Apache-2.0) if conversion or performance fails. Lanczos as a final
fallback guaranteeing the app is functional, if unremarkable.

### Build ordering

This is built and validated before any UI exists. It is the only component whose
failure invalidates the project, and it is verifiable from a command line.

## 7. History and persistence

SwiftData stores one `UpscaleRecord` per job: timestamp, scale factor, source
and output filenames, input and output pixel dimensions, and duration.

**The input image is retained** (design §6, divergence 7). Result and history both display
INPUT alongside OUTPUT, and press-and-hold compares against the real original, so a copy of
the source is stored beside the output rather than discarded.

Images live on disk in Application Support, not Caches — the system may purge
Caches, and a history that empties itself is worse than no history. Each record
carries a 512px thumbnail so the grid never decodes a full-size output to draw a
cell.

Output files are excluded from iCloud backup: large and fully regenerable.
Settings displays total storage used and offers a clear-history action. Deleting
a record removes its files and row together.

## 8. UI

> **Superseded in part.** A design now exists at
> `docs/design/2026-09-20-flow-board.md`, extracted from the claude.ai design project on
> 2026-09-20. Where it disagrees with this section, **the design wins**; its §6 lists the
> eight divergences. The largest: the result screen uses press-and-hold to reveal the
> original rather than a draggable divider, and the input image is retained so both the
> result and history screens can show INPUT alongside OUTPUT. That last point resolves the
> open question about history having no "before".

**Import** — photo picker, recent-history strip, and a 2x/4x selector showing
resulting dimensions and approximate file size. This is where the memory clamp
(§5) surfaces, before the user commits.

**Processing** — determinate progress derived from tile count, cancel button,
idle timer disabled.

**Result** — before/after comparison with a drag divider, and **pinch-zoom to
1:1, which is mandatory**. Fitted to a phone screen, a 4x upscale is visually
indistinguishable from its input; without zoom the app's entire value is
invisible. This is the highest-priority piece of UI polish in the project.

**History** — thumbnail grid, tap to open, swipe to delete.

Saving to Photos requires add-only authorisation and the corresponding
Info.plist usage description.

## 9. Testing

Kit tests run on macOS without a simulator:

- Tiler reconstruction via identity upscaler (§5)
- Seam detection: no discontinuity above threshold across tile boundaries
- All eight EXIF orientations round-trip correctly
- RGBA input preserves alpha
- Memory clamp selects 2x under an injected constrained budget
- Cancellation halts promptly and leaves no temporary files

Conversion parity is a Python test (§6). Golden-image fixtures are compared by
PSNR against committed references, thresholded rather than exact — ANE and GPU
numerics differ across devices, and exact-match golden tests on neural output
produce false failures.

The app layer is tested manually; four screens does not justify snapshot
infrastructure. The device matrix must include at least one genuinely old
iPhone, since the memory-clamp path only truly executes under real pressure.

## 10. Decisions taken without explicit approval

Recorded so they can be overturned.

| Decision | Cost if wrong |
|---|---|
| Application Support over Caches for outputs | Consumes user disk if history is never cleared |
| sRGB conversion for inference | Gamut loss on vivid Display P3 photos |
| `.mlpackage` committed to the repository | ~3MB binary in git; buys a Python-free build |
| Manual testing for the app layer | UI regressions go uncaught |
| Batch processing deferred entirely | The family-scans use case stays awkward until it lands |
| Training-data reach-through treated as non-issue | Would invalidate the licensing position in §2 |

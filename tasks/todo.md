# Scally — Task Status

Live progress for `docs/superpowers/plans/2026-09-20-scally-upscaler.md`. Branch: `master`.

**Legend:** `[x]` complete & reviewed · `[~]` in progress · `[ ]` not started

## Phase 0 — Foundation
- [x] **Task 1** — ScallyKit package skeleton and typed errors
      `3492bd0..HEAD` · 2 tests pass (Swift Testing) · project scaffolded with XcodeGen,
      app builds and its test target runs on iPhone 17 Pro / iOS 26.5

## Phase 1 — Model conversion (highest risk, built first)
- [x] **Task 2** — PyTorch to Core ML conversion script
      Converted first try; `load_state_dict(strict=True)` passed, so the architecture
      guess (SRVGGNetCompact, 32 conv, nearest skip) was right. 2.4 MB at FP16.
- [x] **Task 3** — Numerical parity gate — **1 fix round**
      First run failed at 0.0286 vs 0.00784. Root-caused to FP16 accumulation, not
      architecture: an FP32 conversion of the same graph matches PyTorch to 2.1e-5.
      Gate rebuilt as three tests (structural FP32 / photographic FP16 / PSNR floor).
      All 3 pass. See the plan's Task 3 note for the known 1% margin fragility.

## Phase 2 — Geometry and composition (no ML)
- [x] **Task 4** — Tile geometry — 6 tests, no fix rounds
- [x] **Task 5** — Memory-mapped pixel buffer — 5 tests, no fix rounds
- [x] **Task 6** — Ramp-blended tile composer — 5 tests, no fix rounds
- [x] **Task 7** — Upscaler/FaceRestorer protocols + reconstruction proof — 3 tests
      (one parameterised over 5 awkward sizes), no fix rounds. Tiled reconstruction
      is byte-exact at 700x500, 100x80, 256x256, 257x257, 1000x13 and 13x1000.

## Phase 3 — Image input and output
- [x] **Task 8** — Loading, EXIF orientation, sRGB conversion — 8 tests, **1 fix round**
      (alpha detection changed from declared alphaInfo to an actual channel scan,
      so opaque PNG screenshots route to HEIC rather than bloating to PNG)
- [x] **Task 9** — Alpha channel preservation — 6 tests, no fix rounds
- [x] **Task 10** — Output encoding (HEIC/PNG) — 6 tests, no fix rounds

## Phase 4 — Memory budget
- [x] **Task 11** — Budget calculation and scale clamping — 8 tests, no fix rounds

## Phase 5 — Model integration
- [x] **Task 12** — Core ML upscaler with reflect padding — 7 tests, no fix rounds
- [x] **Task 13** — UpscalePipeline, the sole public entry point — 8 tests, **1 fix round**
      (scratch directory made injectable: the cancellation test asserted on the shared
      temp dir while Swift Testing ran tests in parallel; this also closed a spec gap,
      since scratch belongs in Caches). Public surface narrowed: 35 declarations
      internalised, leaving only the pipeline and its vocabulary public.
- [x] **Task 14** — Golden image regression tests — 3 cases, **1 fix round**
      (reference files were HEIC named .png; ImageIO sniffs content so the assertion
      passed and hid it). References inspected visually before committing.

## Phase 6 — App data layer
- [x] **Task 15** — App target, SwiftData record, library store — 9 tests, no fix rounds
      Extended past the plan to retain the input image, per the design: the record
      carries input and output dimensions and byte counts, and the store keeps a copy
      of the source so press-and-hold compares against the real original. Batch delete
      added for the multi-select history the design specifies.

## Phase 7 — User interface
All six built against `docs/design/2026-09-20-flow-board.md`, both themes.
Import and Configure are verified on real hardware. Processing, Result, History and
Settings compile and are unit-tested but have NOT been exercised on screen yet.
- [x] **Task 16** — Import screen and scale configuration — 12 model tests, **3 fix rounds**
      1. Wordmark crushed to "S..." inside an iOS 26 toolbar glass capsule; moved into
         the content as a real header.
      2. **Device-only blanking bug.** Resetting the picker's `selection` to nil
         re-fired onChange with a nil item; the second pass assigned nil into `pending`,
         wiping the photo one frame after Configure appeared. Root-caused from the device
         console after two other hypotheses were tested and refuted. Now guarded, with
         `PendingImage.resolve` making the invariant explicit and testable.
      3. Selected scale segment rendered as an empty pill - the default button style
         repaints the label with its own tint, so `.buttonStyle(.plain)` is required.
      Confirmed working on device 2026-09-20: photo loads and Configure renders.
- [x] **Task 17** — Processing screen — **1 fix round** (weak self captured inside the
      @Sendable progress closure; the type is @MainActor and so already Sendable)
- [x] **Task 18** — Press-and-hold comparison with pinch zoom — design replaced the
      draggable divider, which also removed the divider-vs-pan gesture conflict
- [x] **Task 19** — Save to Photos and library persistence
- [x] **Task 20** — History with multi-select, batch share and delete, confirm dialogs
- [x] **Task 21** — Settings with appearance, storage, and the Licenses screen the
      design omits but BSD-3-Clause requires

## Phase 8 — Device validation
- [ ] **Task 22** — Device matrix and performance verification
## Notes

**Needs Dylan before the relevant task:**
- Minimum deployment target — provisionally iOS 18.0, unconfirmed. Blocks Task 15.
- Whether history stores a "before" copy. Blocks Task 20. Do not ship an image
  compared to itself.
- App display name and icon — "Scally" is only the directory name.
- Golden-image fixtures for Task 14 must be Dylan's own photographs.

**Risks:**
- Task 2 is the project's single point of failure. If `load_state_dict` complains,
  fix the architecture; never pass `strict=False` to silence it.
- Task 12's flat-grey sanity check failing means the conversion is wrong, not that
  the threshold is tight. Go back to Task 3.
- The memory clamp (Task 11) only truly executes under real pressure, so Task 22
  must observe it firing on an old device at least once.
- Real-ESRGAN training-data reach-through is assumed a non-issue, not verified.

## Review

Task 1 complete. Scaffolding verified end to end on 2026-09-20: `swift test` in ScallyKit
runs 2 tests green, `xcodebuild build` and `xcodebuild test` both succeed against
iPhone 17 Pro / iOS 26.5, with 1 test executed in the app target.

~~**Known limitation:** simulator only.~~ Resolved 2026-09-20: `DEVELOPMENT_TEAM`
is `UQRXPYHMJ9` (read from the installed provisioning profiles, same team as Listn)
and signing is enabled. Built, signed and installed to Dylan's iPhone 17 Pro
(`3F380110-D711-5C7B-9725-2656FCB16BD6`) with automatic provisioning.

**Device build:**
`xcodebuild -project Scally.xcodeproj -scheme Scally -destination 'platform=iOS,id=<device-id>' -allowProvisioningUpdates build`
then `xcrun devicectl device install app --device <device-id> <path-to-Scally.app>`

**Build commands:**
- Package tests: `cd ScallyKit && swift test`
- Regenerate project: `xcodegen generate`
- App tests: `xcodebuild test -project Scally.xcodeproj -scheme Scally -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'`

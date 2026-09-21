# Scally — Task Status

Live progress for `docs/superpowers/plans/2026-09-20-scally-upscaler.md`. Branch: `master`.

**Legend:** `[x]` complete & reviewed · `[~]` in progress · `[ ]` not started

## Phase 0 — Foundation
- [x] **Task 1** — ScallyKit package skeleton and typed errors
      `3492bd0..HEAD` · 2 tests pass (Swift Testing) · project scaffolded with XcodeGen,
      app builds and its test target runs on iPhone 17 Pro / iOS 26.5

## Phase 1 — Model conversion (highest risk, built first)
- [x] **Task 2** — PyTorch to Core ML conversion script — **model swapped 2026-09-20**
      Originally `realesr-general-x4v3` (SRVGGNetCompact, 1.2M params, 2.4 MB), converted
      first try. Replaced with `RealESRGAN_x4plus` (RRDBNet, 16.70M params, 33 MB) after
      device testing showed the small model was within 3.6/255 of a bicubic stretch on a
      clean photo. RRDBNet also loaded with `strict=True` first try. convert.py now takes
      a model argument and supports both.
- [x] **Task 3** — Numerical parity gate — **1 fix round**
      First run failed at 0.0286 vs 0.00784. Root-caused to FP16 accumulation, not
      architecture: an FP32 conversion of the same graph matches PyTorch to 2.1e-5.
      Gate rebuilt as three tests (structural FP32 / photographic FP16 / PSNR floor).
      Thresholds are now per-architecture: the 120-layer RRDBNet legitimately accumulates
      more error than the 33-layer SRVGGNet, and the recorded measurements for both sit
      in the file. All 3 pass for x4plus.

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
- [x] **Task 14** — Golden image regression tests — 3 cases, **3 fix rounds**
      1. Reference files were HEIC named .png; ImageIO sniffs content so the assertion
         passed and hid it.
      2. The gate correctly caught the x4plus swap (31.1 dB vs a 35 dB bound) and the
         references were regenerated.
      3. **The fixtures were not deterministic.** They were seeded from
         `name.hashValue`, which Swift randomises per process, so the texture case failed
         against its own freshly recorded reference. Now seeded by FNV-1a over the name's
         bytes; verified stable over three consecutive runs. Compute units are also pinned
         to CPU so the gate cannot drift with Core ML scheduling.

## Phase 6 — App data layer
- [x] **Task 15** — App target, SwiftData record, library store — 9 tests, no fix rounds
      Extended past the plan to retain the input image, per the design: the record
      carries input and output dimensions and byte counts, and the store keeps a copy
      of the source so press-and-hold compares against the real original. Batch delete
      added for the multi-select history the design specifies.

## Phase 7 — User interface
All six built against `docs/design/2026-09-20-flow-board.md`, both themes.
**All six screens verified on screen 2026-09-20.** Import and Configure on real
hardware; Processing, Result, History and Settings walked in the simulator via a
launch-argument harness with seeded data. Three bugs found and fixed by looking:
ASCII `x`/`->` where the design specifies `×`/`→`; a zoom hint that said "tap 100%
for real pixels" while already at 226% of real pixels; and a dead vertical gap on
Processing.
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
- [~] **Task 22** — Device matrix and performance verification
      Measured on iPhone 17 Pro (Release): 143 ms/tile on the Neural Engine with
      x4plus, 683 ms GPU, 1026 ms CPU. `os_proc_available_memory` reports 6434 MB
      with the increased-memory entitlement, 3429 MB without.
      **Still outstanding:** a genuinely old device. The memory clamp has never
      fired on real hardware - a 17 Pro grants 4x on everything - so that path
      remains unverified outside tests.
## Phase 9 — Identity and design conformance (2026-09-21)
The design's §5 had never been built at all: there was no asset catalog in the
repo, so the app wore the default white iOS icon, and `UILaunchScreen_Generation`
gave it a blank launch screen.
- [x] **Task 23** — App icon
      `tools/make_icon.py` draws the mark the design specifies - a viewfinder of
      four three-square brackets closing on one amber pixel - and bakes
      `Scally/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Checked at 180,
      120, 87, 58 and 29 px: the smallest element still reads at 29.
      `ASSETCATALOG_COMPILER_APPICON_NAME` added to project.yml; verified in the
      built bundle's `CFBundleIcons`.
- [x] **Task 24** — Launch animation
      `LaunchView.swift`, on the design's score: brackets 50% open, closed by
      0.70 s with the amber pixel landing, hold, then opening past the screen
      edge by 2.20 s. The exit spread is solved from the screen size rather than
      hardcoded, so the brackets clear a small phone as well as a large one.
      `AppReadiness` is a reference type on purpose - a `let` copied into the
      running task would never see the flag flip. Import is not in the view
      hierarchy until the mark has left.
- [x] **Task 25** — Four screens brought back to the flow board — **1 fix round**
      1. Settings was a stock grouped `List`, bringing its own background,
         separators and type. Rebuilt on the app's own cards and tokens.
      2. History showed a bare `09:38` where the design specifies the date group
         `TODAY 09:38` / `TUE 18:02` / `12 SEP`.
      3. Import's trust panel said `NEURAL ENGINE`; the design names the
         silicon. `DeviceChip` reads it from the hardware and falls back to the
         plain claim rather than guessing.
      4. Processing rendered `ELAPSED 3.4 S` as one run of caption text, losing
         the label/value type distinction and uppercasing the unit.
      **Fix round:** the long date form truncated to `YESTER…` and wrapped the
      dimension summary onto two lines. Found by looking at the screen, not by
      a test. `YESTERDAY` dropped (the design has no such label and the weekday
      form already covers it) and the date column pinned with `.fixedSize()` so
      the filename gives way instead.

**Verified on screen 2026-09-21** in the iPhone 17 Pro simulator with seeded
data: launch mark plays and hands over to Import, Settings, History. Built,
signed and installed to Dylan's iPhone 17 Pro. The icon on the home screen and
the `NEURAL · A19 PRO` chip label are device-only and unverified by me.

## Phase 10 — Rebuilt against the imported design (2026-09-21)
**Root cause of the repeated "not the same as the design" reports.** Every screen
had been built from `docs/design/2026-09-20-flow-board.md`, a *prose extract* of
the design. Nobody had seen the design itself. The extract was lossy in ways
that changed structure, not just polish.

- [x] **Task 26** — Import the design into the repository
      Pulled through the design MCP from claude.ai project
      `2438fdc0-e5a2-435e-ae04-3cdaa09beebf` into
      `docs/design/flow-board/`. 28 designed phone frames - 13 screens in both
      themes, plus the launch animation - rendered to PNG from the source and
      used as the comparison target. **This is now the source of truth; the
      prose extract is not.**
- [x] **Task 27** — Tokens re-derived from the source
      The extract had the **light theme's background and surface swapped**
      (#FFFFFF is the background, #F6F6F7 the surface, not the reverse), gave
      one border value where the design uses 6/7/8/14/16/22/24% per context,
      and omitted the iOS label bases the design actually uses -
      `235,235,245` dark and `60,60,67` light - at a dozen distinct alphas.
- [x] **Task 28** — Icon and launch mark redrawn
      The mark is **four thin corner rules**, not four groups of solid squares.
      "Built from squares" in the extract described the geometry, not the
      drawing. The arithmetic matters: 24% inset + 14% content + 3% border puts
      the bracket's inner corner at 41%, exactly where the pixel starts, so the
      viewfinder touches what it closes on. Verified against the design's own
      render at 0.79/255 mean pixel difference.
      The animation is **scale-based** (1.5 -> 1 -> 9 for the brackets,
      0.4 -> 1 -> 4 for the pixel), not translation-based, on the source's own
      keyframe times, and the app fades in *under* the clearing splash.
- [x] **Task 29** — Every screen rebuilt
      Structural corrections, not restyling:
      1. **History is a two-column thumbnail grid**, captioned per tile. The
         extract said it was a list, and §6 of it claimed the design had
         *changed* the spec's grid to a list. The opposite is true.
      2. **Choose a photo is a surface row with a ringed plus**, not a filled
         button. The filled slab is reserved for Upscale and Save.
      3. **Processing** has a 2 pt amber progress bar under the panel; the
         photo stays visible at 50% behind a 42% scrim.
      4. **Confirm dialogs are the design's own bottom sheets**, not
         `confirmationDialog`.
      5. **Result's `100%` badge lives in the top bar**, not floating on the
         photo, which needed the zoom state lifted out of `HoldToCompare`.
      6. Top bars are drawn, not `navigationBar` - iOS 26 glass capsules crush
         a filename to an ellipsis.
      7. `ELAPSED 3.4 s` is one run of mono text. An earlier "fix" that split
         it into a caption and a value was wrong against the design.

**Verified by side-by-side comparison with the design render:** Import (light),
History (dark), Settings (dark). **Not yet compared:** Configure, Processing,
Result, S3/S4/S5 edge cases, History selecting and its confirm sheet, the light
theme on every screen but Import, and the launch animation with the new mark.

**Deliberate deviations from the design, both in Settings:**
- A `Licenses` row. Both model licences oblige reproducing their notice with
  the binary. Kept in a *third* card so the design's two cards stay exact.
- `Sharpening` and `Compare models`, features the design predates, in that
  same third card.

## Engine

**One model: `ScallyDiffusion.mlpackage`, 334 MB.** One-step ResShift (RSD),
118.6M parameters, FP16. Real-ESRGAN was removed on Dylan's instruction.

The VQ encoder, the single denoising step and the VQ decoder are fused into one
Core ML graph together with the prior sample and the `_scale_input`
normalisation. Only the 4x resample stays in Swift, because coremltools has no
`upsample_bicubic2d`.

FP16 throughout, justified by measurement rather than assumed: the fused model
sits 5.19% of range from the PyTorch reference, while the model's own
stochasticity moves the output by 67.64% - roughly 25x more. Chasing FP32
determinism would be measuring noise.

**Non-commercial licence.** ResShift is S-Lab 1.0, RSD is CC BY-NC-SA 4.0. The
Licenses screen reproduces both. Scally is free permanently.

**The model is gitignored** (334 MB). `tools/convert_fused.py` regenerates it.
Shipping needs on-demand resources or a first-launch download.

## Notes

**Needs Dylan before the relevant task:**
- Minimum deployment target — provisionally iOS 18.0, unconfirmed.
- ~~Per-tile time constant needs device calibration.~~ Done 2026-09-20: measured
  143 ms/tile on an iPhone 17 Pro; `ConfigureModel.secondsPerTile` is now 0.16.
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

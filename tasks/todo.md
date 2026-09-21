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

## Phase 11 — One model, and face awareness (2026-09-21)
- [x] **Task 30** — RealPLKSR replaces all four models
      `4xNomosWebPhoto_RealPLKSR`, CC BY 4.0. 7.4M parameters, 14 MB package,
      Release app **17 MB down from 404 MB**. Architecture derived from the
      checkpoint and then checked against the author's own ONNX export:
      6.3e-6 worst pixel once the export's [0,1] clamp was matched. Core ML
      FP16 sits 1.12% of range from the FP32 PyTorch reference on photographic
      input; flat-grey sanity check holds.
- [x] **Task 31** — Golden-image gate re-enabled
      It had been disabled while the engine was stochastic. RealPLKSR is
      deterministic, references recorded fresh, verified stable over two
      separate processes.
- [x] **Task 32** — Face-aware sharpening — **1 fix round**
      Vision detects faces on the *input* (normalised rects, so they describe
      every later buffer at a sixteenth of the cost) and the sharpener keeps
      only 25% of its intensity inside a feathered ellipse over each face.
      Chosen over CodeFormer/GFPGAN on licensing: those are non-commercial and
      would have re-encumbered an app that just became commercially free.
      **Fix round:** the mask was drawn into a `CGContext`, whose origin is
      bottom-left, using top-left rectangles - so the damping landed on the
      mirror image of the face. The unit test could not catch it because the
      test rectangle was centred and therefore its own reflection. Found by an
      end-to-end run on a real photograph; the test now uses an asymmetric
      rectangle checked against its mirrored band. Verified end to end:
      **29.5x** more change inside the detected face than outside it.

## Phase 12 — All 13 designed screens verified (2026-09-21)
- [x] **Task 33** — The last four compared — **2 divergences found and fixed**
      S1b (selecting), S2b (confirm clear), S5 (save failed) and screen 1
      (Import, empty) put side by side with the design render.
      1. **S5 carries no INPUT/OUTPUT rows.** The design replaces the metrics
         with the banner; the build stacked both.
      2. **The save-failed banner is destructive-tinted, not neutral** - border
         and fill drawn from the destructive colour at different strengths per
         theme (45%/12% dark, 35%/7% light), with a destructive ring rather
         than the amber one the clamp notice uses.
      Also corrected while checking: the clamp notice's own panel colour
      (#121215 dark / #F8F6F3 light, a shade off `surface`), its 11 pt radius,
      and the disabled segment's per-theme alpha.
      `DesignHarness` gained `selecting`, `confirm-clear` and `save-failed`;
      Import-empty was captured against a fresh container.

**All 13 designed screens now verified against `docs/design/flow-board/`.**
Two knowingly unverifiable on this machine: S3's copy says "2x is available"
only when it is, and the simulator's memory budget leaves neither scale
available; and Import's ENGINE row reads `NEURAL ENGINE` rather than
`NEURAL - A19 PRO`, because the simulator reports no recognisable chip. Both
are data, not layout, and both are correct behaviour.

## Phase 13 — What the Neural Engine will actually run (2026-09-21)
Dylan reported RealPLKSR looked worse than the ESRGAN it replaced, and asked
whether a stronger model exists. Measured rather than argued.

- [x] **Task 34** — Transformers evaluated and rejected
      `4xRealWebPhoto_v4_dat2` (DAT, 11.2M) and `4xNomos2_hq_drct-l`
      (DRCT-L, 27.6M) both converted, via `tools/convert_transformer.py`, and
      both are **rejected by the Neural Engine compiler** - `ANECCompile()
      FAILED`. Per 256x256 tile: DRCT-L 2208 ms, DAT2 1110 ms and it will not
      run at all under the default compute units. Packages 118 MB and 101 MB.
      A 12 MP photo would take 8-9 minutes against roughly 30 seconds today.
      Ruled out on speed before quality was ever a question.
- [x] **Task 35** — `4xNomosWebPhoto_esrgan` restored as the shipping model
      **Parameter count is not what decides ANE speed.** Per tile:
      ESRGAN 16.7M is 145 ms on ANE and 380 ms on CPU+GPU; PLKSR 7.4M is
      186 ms on ANE and 101 ms off it; MoSR 4.3M is 102 ms on and 72 ms off.
      The largest model is the fastest on the Neural Engine and the two
      smaller ones are *slower* on it than without it - RRDBNet is 3x3
      convolutions throughout, which is what the ANE is built for, while
      PLKSR's 17x17 partial large kernel is not. The 145 ms also matches the
      143 ms/tile measured on Dylan's 17 Pro.
      All three convolutional models ship so they can be compared on device;
      golden references re-recorded for the new shipping model.

**Still unanswered:** no valid *quality* comparison has ever been run. The one
attempt used a photo with a Laplacian variance of 6.7. Speed ruled the
transformers out regardless, but ESRGAN vs PLKSR vs MoSR remains a judgement
call awaiting a sharp photograph.

## Phase 14 — The loss function, not the architecture (2026-09-21)
Dylan compared all three bundled models and rejected all of them: "they look
sharper but too digitalised... it looks modified". The cause was not capacity,
and a bigger model would have made it worse.

- [x] **Task 36** — Root cause: adversarial training
      Every model bundled to that point was GAN-trained. Adversarial loss
      rewards output that *looks* like a sharp photograph, which in practice
      means inventing high-frequency texture. Verified visually against ground
      truth at 1:1: the GAN models manufacture hair strands and foliage that
      were never resolved; Real-ESRNet, the same RRDBNet trained with L1
      alone, sharpens the in-focus subject without inventing anything.
      **This also resolves a contradiction in the product.** The Configure
      screen promises "Detail is reconstructed, not invented." The GAN models
      broke that promise.
- [x] **Task 37** — Real-ESRNet ships; sharpening defaults off
      Same architecture and the same 16.7M weights as the model it replaces,
      so identical on the ANE at ~145 ms/tile. BSD-3-Clause, notice recovered
      from commit 3b9b6c2. The unsharp mask now defaults to 0: it manufactures
      edge contrast, which is exactly the quality being designed out. The
      slider stays.
      **Method note:** PSNR against ground truth was misleading here and
      nearly sent this the wrong way - it ranked plain Lanczos above every
      model, because the reference crop has genuinely shallow depth of field
      and "do nothing" scores well against soft truth. The 1:1 visual decided
      it. Numbers alone would have been wrong.

**Rejected on measurement, recorded so it is not revisited:** window-attention
models are refused by the ANE compiler (DAT2 1110 ms/tile, DRCT-L 2208 ms/tile
against 145 ms), and going larger would have worsened the actual complaint
rather than fixing it, since the large models available are also GAN-trained.

## Phase 15 — A benchmark, instead of trying models one at a time (2026-09-21)
Dylan: "before yet again just trying out a model, i want you to benchmark it.
make sure to use models that are big and small." Fair - the previous four
swaps were decided on impression.

- [x] **Task 38** — `tools/benchmark_models.py`
      Scores every bundled package against real photographs. A 1024x1024 crop
      is chosen by detail (a benchmark run on flat sky measures nothing),
      downsampled 4x, and each model asked to put it back. Reports ANE and
      CPU+GPU ms/tile, PSNR, SSIM, and a **detail ratio** - mean absolute
      Laplacian of output over truth - which is the metric that captures
      "digitalised": 1.00 is what the camera resolved, above 1.00 is invented.
      Two degradations are run, clean and realistic, because a Lanczos
      downsample is nearly the inverse of a Lanczos upsample and flatters
      plain resampling.
      **Two flaws found and fixed in my own method:** the low-resolution input
      was being padded into a 256x256 tile with black, putting a hard edge
      inside every model's receptive field and producing grid artefacts; and
      centre crops landed on out-of-focus background. Both were skewing the
      first run's numbers.
- [x] **Task 39** — Results, on realistic input
      | model | ANE | PSNR | SSIM | detail |
      |---|---|---|---|---|
      | RealESRNet | 172 ms | **32.28** | **0.8973** | 0.16x |
      | Lanczos | - | 31.72 | 0.8904 | 0.16x |
      | MoSR_mssim | 110 ms | 31.36 | 0.8814 | 0.23x |
      | DRCT-L mssim | 1180 ms | 30.39 | 0.8736 | 0.27x |
      | SPAN_mssim | 16 ms | 29.79 | 0.8710 | 0.31x |
      | NomosPLKSR | 170 ms | 29.92 | 0.8455 | **1.33x** |
      | NomosWebPhoto | 160 ms | 29.08 | 0.8443 | **1.26x** |
      **Every GAN model sits above 1.00 on detail** - Dylan's complaint,
      measured. **Size buys nothing:** DRCT-L at 27.6M scores below MoSR at
      4.3M while being eleven times slower. **DAT2's conversion is broken,**
      not merely slow: PSNR 5.75, SSIM 0.002, output is garbage.
      Bundle is now RealESRNet (shipping), MoSR_mssim and SPAN_mssim. The
      GAN models are gone. App 90 MB -> 44 MB.

## Phase 16 — 2x by default (2026-09-21)
- [x] **Task 40** — `defaultScale` is 2x wherever the budget allows
      Measured on four photographs against the original, shipping model:

      | scale | PSNR | SSIM | detail |
      |---|---|---|---|
      | 4x | 32.28 | 0.8973 | 0.16x |
      | **2x** | **36.34** | **0.9341** | **0.25x** |

      Four decibels and half again as much of the detail the camera recorded.
      At 4x, fifteen of every sixteen output pixels were never photographed,
      so a faithful model has nothing to work from and an unfaithful one
      invents - which is the whole complaint. At 2x there is enough signal to
      genuinely resolve.
      **Deliberate divergence from the design**, whose Configure screen shows
      4x selected. 4x is still one tap away.

**Why not a large generative model** (asked, answered, recorded so it is not
relitigated): a hosted image model does not enhance a photograph, it generates
a new one that resembles it - faces come back subtly different, text becomes
gibberish. It is the "too digitalised" failure taken to its limit. It also
contradicts four claims the app currently makes on screen (`NETWORK - NOT
USED`, "never connects to the internet", "Nothing is uploaded. No account. No
internet.", "Detail is reconstructed, not invented"), costs roughly $0.02-0.19
per image in an app with no purchases, and ends offline use. Viable only as a
different product with different promises.

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
(device id redacted) with automatic provisioning.

**Device build:**
`xcodebuild -project Scally.xcodeproj -scheme Scally -destination 'platform=iOS,id=<device-id>' -allowProvisioningUpdates build`
then `xcrun devicectl device install app --device <device-id> <path-to-Scally.app>`

**Build commands:**
- Package tests: `cd ScallyKit && swift test`
- Regenerate project: `xcodegen generate`
- App tests: `xcodebuild test -project Scally.xcodeproj -scheme Scally -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'`

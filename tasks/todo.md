# Scally — Task Status

Live progress for `docs/superpowers/plans/2026-09-20-scally-upscaler.md`. Branch: `master`.

**Legend:** `[x]` complete & reviewed · `[~]` in progress · `[ ]` not started

## Phase 0 — Foundation
- [ ] **Task 1** — ScallyKit package skeleton and typed errors

## Phase 1 — Model conversion (highest risk, built first)
- [ ] **Task 2** — PyTorch to Core ML conversion script
- [ ] **Task 3** — Numerical parity gate (max 2/255, mean 0.5/255)

## Phase 2 — Geometry and composition (no ML)
- [ ] **Task 4** — Tile geometry
- [ ] **Task 5** — Memory-mapped pixel buffer
- [ ] **Task 6** — Ramp-blended tile composer
- [ ] **Task 7** — Upscaler/FaceRestorer protocols + reconstruction proof

## Phase 3 — Image input and output
- [ ] **Task 8** — Loading, EXIF orientation, sRGB conversion
- [ ] **Task 9** — Alpha channel preservation
- [ ] **Task 10** — Output encoding (HEIC/PNG)

## Phase 4 — Memory budget
- [ ] **Task 11** — Budget calculation and scale clamping

## Phase 5 — Model integration
- [ ] **Task 12** — Core ML upscaler with reflect padding
- [ ] **Task 13** — UpscalePipeline, the sole public entry point
- [ ] **Task 14** — Golden image regression tests

## Phase 6 — App data layer
- [ ] **Task 15** — App target, SwiftData record, library store

## Phase 7 — User interface
- [ ] **Task 16** — Import screen and scale configuration
- [ ] **Task 17** — Processing screen
- [ ] **Task 18** — Before/after comparison with zoom
- [ ] **Task 19** — Save to Photos and library persistence
- [ ] **Task 20** — History
- [ ] **Task 21** — Settings and licenses
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

Not started. No code written as of 2026-09-20.

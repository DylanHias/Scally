# Scally — Flow Board (design reference)

Extracted 2026-09-20 from the claude.ai design project `2438fdc0-e5a2-435e-ae04-3cdaa09beebf`
("Scally", owner Dylan Hias). **This document supersedes spec §8 wherever they disagree.**
Divergences are listed in §6 below.

## 1. Design tokens

| Token | Dark | Light |
|---|---|---|
| Background | `#0B0B0C` | `#F6F6F7` |
| Surface | `#141417`, `#17171A` | `#FFFFFF` |
| Surface raised | `#1C1C1F` | `#FBFBFA` |
| Border | `#2A2A2F` | `#EFEFF1`, `#EEEEF1`, `#F2F2F4` |
| Primary text | `#F5F5F7` | `#1A1A1A` |
| Accent (amber) | `#E2A45E` | `#A8641F` |
| Destructive | `#D4675C` | `#B3392C` |

Type: system sans for body and controls, `ui-monospace` for all numbers, dimensions,
sizes and small-caps metadata labels. Uppercase mono labels with wide tracking for
field captions (`INPUT`, `OUTPUT`, `ESTIMATE`, `ENGINE`, `NETWORK`, `RECENT`).
Radii in use: 8-14px for cards and controls, 18-24px for sheets, 46-56px for the phone frame.

Both themes are designed. Appearance is user-selectable in Settings, defaulting to System.

## 2. The linear path (five screens)

**1 - Import, empty.** Title `Scally` with subtitle `ON-DEVICE UPSCALER`, Settings at
top right. Primary action `Choose a photo`, plus secondary `Paste` and `Files`.
A `RECENT` section reading `No files yet.` Bottom trust panel, two columns:
`ENGINE / NEURAL · A17 PRO` and `NETWORK / NOT USED`.

**2 - Import, with history.** Same, but `RECENT` carries an `All 14` affordance and a
list of rows: filename, `240×240 → 960×960`, a scale badge (`4×`), and a relative
timestamp (`09:38`, `TUE`, `12 SEP`). Footer: `STORED LOCALLY · 48.2 MB`.

**3 - Configure, inline on the photo.** Not a sheet. `Back` and the filename in the bar.
A `2× / 4×` segmented control over the photo. Three mono rows:
`INPUT 240 × 240 px · 38 KB`, `OUTPUT 960 × 960 px · ~1.1 MB`, `ESTIMATE 6 s · on device`.
Primary button `Upscale`. Footnote, verbatim and load-bearing:
**"Detail is reconstructed, not invented. Faces stay as they are."**

**4 - Processing.** `UPSCALING · 4×`, a large `58%`, then `ELAPSED 3.4 s` and
`REMAINING ~2.6 s` as separate readouts, plus `OUTPUT 960 × 960 px`. `Cancel` button.
Footnote: `Screen stays awake until it finishes`.

**5 - Result, press and hold.** `Discard` top left, `IMG_4471 · 4×` as title, a `100%`
badge. The photo fills the screen. Instruction: **`HOLD TO SEE ORIGINAL`** - a
press-and-hold reveal, *not* a draggable divider. Mono rows `INPUT 240 × 240 · 38 KB`
and `OUTPUT 960 × 960 · 1.1 MB`. Actions `Save to Photos` and `Share`.

## 3. Shared screens

**S1 History.** `Back`, `Select`, title `History`. A list of results, each with a scale
badge and a date group (`TODAY 09:38`, `TUE 18:02`, `12 SEP`). Footer:
`14 RESULTS · 48.2 MB ON THIS IPHONE`.

**S1b History, selecting.** `Select All` / `Cancel`, title becomes `3 selected`.
Bottom bar: `Share`, `3 ITEMS · 9.1 MB`, `Delete`.

**S1c Confirm delete.** `These 3 results will be removed from Scally.` /
`The originals in your Photos library are untouched.` Buttons `Delete 3 Results`, `Cancel`.

**S2 Settings.** `Storage used 48.2 MB`, `Results kept 14`, `Clear history`,
`Appearance System`, `Save location Photos`, footer `VERSION 1.0 · BUILD 118`.

**S2b Confirm clear.** `All 14 results and their 48.2 MB will be removed from Scally.` /
`The originals in your Photos library are untouched.` Buttons `Clear All 14 Results`, `Cancel`.

## 4. Edge cases (all three designed)

**S3 - 4× unavailable.** Configure screen with 4× disabled and an inline explanation:
`4× would need 1.9 GB of memory — more than this iPhone can give a single app. 2× is available.`
Button becomes `Upscale 2×`. Note the design states the actual requirement in GB.

**S4 - Library access denied.** `No access to your library` /
`Scally can only see photos you give it. Nothing is read in the background and nothing is
uploaded either way.` Actions `Open Settings`, `Choose specific photos`, hint
`SETTINGS → PRIVACY → PHOTOS → SCALLY`. Footer: `Runs entirely on this iPhone.` /
`Nothing is uploaded. No account. No internet.`

**S5 - Save failed.** Result screen with an inline banner: `Couldn't save to Photos` /
`Your iPhone storage is full. The result is still here — free up space and try again.`
Actions `Try again`, `Share`.

## 5. Identity

**Icon** - a viewfinder closing on one pixel, built from squares so it survives at 29px.
Amber pixel, same accent as the progress bar. One fixed appearance on light and dark.

**Launch animation** - 2.2 s, plays once during actual cold start and is cut short the
moment the UI is ready. It is not a loading spinner. Beats: `0.00s` black, brackets 50%
open; `0.70s` brackets close to resting size, amber pixel lands; `1.20s` hold;
`1.70s` brackets keep opening past the screen edge. The splash clears before the app is
shown - Import never appears behind the mark.

## 6. Divergences from the spec and plan

| # | Design | Spec/plan said | Impact |
|---|---|---|---|
| 1 | Result uses **press-and-hold to reveal the original** | Draggable divider plus pinch-zoom | Task 18 rewritten. Removes the divider-vs-pan gesture conflict. `100%` badge retained. |
| 2 | Configure is **inline on the photo** | A bottom sheet over Import | Task 16 restructured |
| 3 | Import offers **Paste** and **Files** | Photo picker only | New scope in Task 16 |
| 4 | Import carries an **ENGINE / NETWORK trust panel** | Not designed | New scope in Task 16 |
| 5 | History is a **list with multi-select**, batch Share/Delete, confirm dialogs | Thumbnail grid, swipe-to-delete | Task 20 materially larger |
| 6 | Settings adds **Appearance** and **Save location**; both themes designed | Storage and Licenses only | Task 21 larger |
| 7 | **The original is retained** - result and history both show INPUT alongside OUTPUT | Left open; history had no "before" | **Resolves open question 2.** Store a copy of the input. |
| 8 | Edge cases **S4 and S5** are designed | Only the memory clamp was planned | New scope |

## 7. Conflict requiring a decision

**The design has no Licenses row in Settings.** Real-ESRGAN's BSD-3-Clause obliges
reproducing its copyright notice and disclaimer in materials distributed with the binary
(spec §2), so this cannot simply be dropped. Proposal: add a `Licenses` row beneath
`Save location`, styled as the existing rows. Flagged for Dylan; implementing it that way
unless told otherwise.


## 8. Measured device figures (added 2026-09-20)

iPhone 17 Pro, Release build, `RealESRGAN_x4plus` on the Neural Engine:

| Compute unit | ms per 256x256 tile |
|---|---|
| ANE (`.all`) | **143** |
| CPU + GPU | 683 |
| CPU only | 1026 |

End-to-end 512x384 -> 2048x1536 in 1.12 s. A 12MP photo is 221 tiles, so about
32 s; a 3249x2262 photo is 140 tiles, about 20 s.

The design's own `ESTIMATE` values are illustrative - `240x240 -> 6 s` and
`3024x4032 -> 22 s` imply per-tile rates roughly 60x apart. The app computes the
estimate from the real tile count at 0.16 s/tile instead.

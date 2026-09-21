"""Generate the Scally app icon.

The design (docs/design/2026-09-20-flow-board.md §5) calls for "a viewfinder
closing on one pixel, built from squares so it survives at 29px. Amber pixel,
same accent as the progress bar. One fixed appearance on light and dark."

So: four corner brackets, each an L of three squares, closing on a single amber
square. No strokes, no gradients, no thin features - at 29pt the smallest
element here is still ~3px across.

The same geometry is drawn in Swift by Scally/Views/LaunchView.swift. The two
are deliberately separate: this one bakes a PNG, that one animates. Change the
proportions in both or the mark will not match itself.
"""

from PIL import Image, ImageDraw

SIZE = 1024
BACKGROUND = (11, 11, 12)      # #0B0B0C, the dark theme background
BRACKET = (245, 245, 247)      # #F5F5F7, primary text
PIXEL = (226, 164, 94)         # #E2A45E, the accent - same amber as the progress bar

# Proportions, as fractions of the canvas, so the mark scales cleanly.
INSET = 0.176                  # outer edge of the corner brackets
BLOCK = 0.107                  # side of one square
GAP = 0.025                    # space between the squares of one bracket
PIXEL_SIDE = 0.127             # the single amber square
RADIUS = 0.010                 # a hair off square, so it does not look like a glyph


def draw_mark(draw, size, spread=1.0):
    """Draw the mark. `spread` moves the brackets out from the centre; 1.0 is
    the resting position the icon uses."""
    inset = INSET * size
    block = BLOCK * size
    gap = GAP * size
    radius = RADIUS * size
    centre = size / 2

    # The bracket corner at rest, then pushed out by `spread`.
    rest = inset
    offset = (rest - centre) * spread + centre

    arm = block + gap
    for sx in (1, -1):
        for sy in (1, -1):
            # Corner of this bracket, measured from the near edges.
            cx = offset if sx > 0 else size - offset - block
            cy = offset if sy > 0 else size - offset - block
            for dx, dy in ((0, 0), (arm, 0), (0, arm)):
                x = cx + dx * sx
                y = cy + dy * sy
                draw.rounded_rectangle([x, y, x + block, y + block],
                                       radius=radius, fill=BRACKET)

    side = PIXEL_SIDE * size
    draw.rounded_rectangle(
        [centre - side / 2, centre - side / 2, centre + side / 2, centre + side / 2],
        radius=radius, fill=PIXEL)


def render(size=SIZE):
    # Drawn at 4x and downsampled: PIL has no antialiasing of its own.
    scale = 4
    image = Image.new("RGB", (size * scale, size * scale), BACKGROUND)
    draw_mark(ImageDraw.Draw(image), size * scale)
    return image.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"
    render().save(out)
    print(f"wrote {out}")

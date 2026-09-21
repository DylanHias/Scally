"""Generate the Scally app icon.

Transcribed from the design, `docs/design/flow-board/Scally - Flow Board.dc.html`,
turn 3c. Every number below is that file's, expressed as a fraction of the
canvas exactly as the CSS expresses it as a percentage or an em:

    corner bracket   left/top 24%, 14% x 14% box, 0.03em borders,
                     outer radius 0.035em
    pixel            left/top 41%, 18% x 18%, radius 0.018em
    ground           #111113

The CSS has no `box-sizing` reset, so `width:14%` is the CONTENT box and each
0.03em border adds to it: an arm is 14% + 3% = 17% long and 3% thick. That
arithmetic is the whole composition - the bracket's inner corner lands at
24 + 17 = 41%, which is exactly where the pixel starts. The viewfinder touches
what it is closing on. Round the numbers and you lose that.

The same geometry is drawn in Swift by Scally/Views/LaunchView.swift at the
launch mark's own proportions.
"""

from PIL import Image, ImageChops, ImageDraw

SIZE = 1024
GROUND = (17, 17, 19)      # #111113
BRACKET = (245, 245, 247)  # #F5F5F7
PIXEL = (226, 164, 94)     # #E2A45E

INSET = 0.24        # left/top of the corner bracket
ARM_CONTENT = 0.14  # the CSS width, before the border is added
STROKE = 0.03       # 0.03em
OUTER_RADIUS = 0.035
PIXEL_INSET = 0.41
PIXEL_SIDE = 0.18
PIXEL_RADIUS = 0.018

ARM = ARM_CONTENT + STROKE  # 17%: content box plus the one border on that axis


def corner_mask(size):
    """The top-left bracket, as CSS resolves it.

    A border-left plus a border-top with a corner radius is the outer rounded
    box minus the inner one, and the inner radius is the outer radius less the
    border width. Here that is 3.5% - 3% = 0.5%, so the inner corner is very
    nearly square while the outer is visibly round. Drawing the L as two bars
    and rounding a corner afterwards gets this wrong in exactly the place the
    eye looks.
    """
    inset = INSET * size
    arm = ARM * size
    stroke = STROKE * size
    outer = OUTER_RADIUS * size

    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([inset, inset, inset + arm, inset + arm],
                           radius=outer, fill=255)
    draw.rounded_rectangle([inset + stroke, inset + stroke, inset + arm, inset + arm],
                           radius=max(0.0, outer - stroke), fill=0)
    return mask


def draw_mark(image, size):
    mask = corner_mask(size)
    mask = ImageChops.lighter(mask, mask.transpose(Image.FLIP_LEFT_RIGHT))
    mask = ImageChops.lighter(mask, mask.transpose(Image.FLIP_TOP_BOTTOM))
    image.paste(BRACKET, mask=mask)

    low = PIXEL_INSET * size
    high = (PIXEL_INSET + PIXEL_SIDE) * size
    pixel = Image.new("L", (size, size), 0)
    ImageDraw.Draw(pixel).rounded_rectangle([low, low, high, high],
                                            radius=PIXEL_RADIUS * size, fill=255)
    image.paste(PIXEL, mask=pixel)


def render(size=SIZE):
    scale = 4  # PIL has no antialiasing; draw large and resample
    image = Image.new("RGB", (size * scale, size * scale), GROUND)
    draw_mark(image, size * scale)
    return image.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"
    render().save(out)
    print(f"wrote {out}")

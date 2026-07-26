"""Draws Cairn's app icon: a stack of trail-marking stones.

Run with `python3 tool/make_icon.py`, then `dart run flutter_launcher_icons`.

Two files come out. `icon.png` is the full-bleed square used for iOS and as the
legacy Android icon. `icon_foreground.png` is transparent and keeps the stones
inside the middle 60% of the canvas, because Android's adaptive icons crop the
foreground to a shape the launcher chooses and anything near the edge is liable
to be cut off.
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SUPERSAMPLE = 4  # Draw large and shrink; PIL's ellipses have no antialiasing.

BACKGROUND = (47, 61, 51)  # deep green, a shade under the app's seed colour
STONE_LIGHT = (232, 227, 217)
STONE_DARK = (198, 191, 178)

# Each stone: width and height as a fraction of the stack's own box, plus a
# horizontal nudge. Real cairns are not stacked plumb, and a perfectly centred
# pile reads as a machine part rather than something hands piled up.
STONES = [
    (1.00, 0.185, 0.000),
    (0.80, 0.170, 0.035),
    (0.66, 0.155, -0.030),
    (0.48, 0.140, 0.025),
    (0.30, 0.120, -0.010),
]

# Barely a gap. Stones piled by hand rest on each other; spacing them out makes
# the icon read as a row of pebbles rather than a stack.
GAP = 0.008


def draw_stack(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float]) -> None:
    """Draws the cairn inside `box` given as (left, top, width, height)."""
    left, top, width, height = box

    total = sum(stone[1] for stone in STONES) + GAP * (len(STONES) - 1)
    scale = height / total

    y = top
    for index, (stone_width, stone_height, nudge) in enumerate(reversed(STONES)):
        # Reversed so the smallest is drawn first, at the top of the pile.
        w = stone_width * width
        h = stone_height * scale
        cx = left + width / 2 + nudge * width

        colour = STONE_LIGHT if index % 2 == 0 else STONE_DARK
        draw.ellipse([cx - w / 2, y, cx + w / 2, y + h], fill=colour)
        y += h + GAP * scale


def render(transparent: bool, inset: float) -> Image.Image:
    """`inset` is the fraction of the canvas left empty around the stack."""
    side = SIZE * SUPERSAMPLE
    background = (0, 0, 0, 0) if transparent else (*BACKGROUND, 255)
    image = Image.new("RGBA", (side, side), background)
    draw = ImageDraw.Draw(image)

    margin = side * inset
    draw_stack(draw, (margin, margin, side - 2 * margin, side - 2 * margin))

    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "assets" / "icon"
    out.mkdir(parents=True, exist_ok=True)

    render(transparent=False, inset=0.16).save(out / "icon.png")
    # Tighter stack, because the launcher crops the outer third away.
    render(transparent=True, inset=0.30).save(out / "icon_foreground.png")

    print(f"wrote {out / 'icon.png'} and {out / 'icon_foreground.png'}")


if __name__ == "__main__":
    main()

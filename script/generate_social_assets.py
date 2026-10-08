"""Generate the landing page's code-drawn social assets (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "assets"
OUT.mkdir(exist_ok=True)
GREEN = "#3a5a3f"
INK = "#15161a"
MUTED = "#6b7280"
PAPER = "#f6f6f4"
FONTS = Path("/System/Library/Fonts/Supplemental")


def font(size, serif=False, bold=False):
    filename = "Georgia.ttf" if serif else ("Arial Bold.ttf" if bold else "Arial.ttf")
    return ImageFont.truetype(str(FONTS / filename), size)


def mark(draw, x, y, size):
    draw.rounded_rectangle((x, y, x + size, y + size), radius=size * .23, fill=GREEN)
    points = [(x + size * a, y + size * b) for a, b in
              [(.26, .25), (.74, .25), (.74, .63), (.43, .63), (.26, .77)]]
    draw.polygon(points, fill="white")
    for fraction in [.39, .50]:
        draw.line((x + size * .38, y + size * fraction,
                   x + size * .62, y + size * fraction), fill=GREEN, width=max(1, int(size * .035)))


image = Image.new("RGB", (1200, 630), PAPER)
d = ImageDraw.Draw(image)
mark(d, 64, 54, 54)
d.text((135, 65), "rails-markup", font=font(27, bold=True), fill=INK)
d.text((64, 178), "Visual feedback", font=font(76, serif=True), fill=INK)
d.text((64, 268), "for Rails apps.", font=font(76, serif=True), fill=INK)
d.text((68, 390), "Point to it. Leave a note. Keep the context.", font=font(25), fill=MUTED)
d.text((68, 443), "Browser toolbar  /  Dashboard  /  MCP", font=font(21), fill=GREEN)
d.line((64, 536, 1136, 536), fill="#d6d4cd", width=1)
d.text((64, 560), "Open source · Built with love in Sydney", font=font(19), fill=MUTED)
d.text((916, 560), "nauman.one / Pavelabs", font=font(18), fill=GREEN)

# A small illustrative feedback card echoes the real toolbar's pin and context.
d.rounded_rectangle((855, 178, 1136, 457), radius=14, fill="white", outline="#e4e3de", width=2)
d.text((879, 202), "PAGE FEEDBACK", font=font(14, bold=True), fill=MUTED)
d.rounded_rectangle((879, 241, 1112, 323), radius=8, fill="#f1f0ec")
d.line((902, 264, 1063, 264), fill="#b8bcb3", width=7)
d.line((902, 286, 1013, 286), fill="#d6d4cd", width=7)
d.ellipse((1070, 278, 1098, 306), fill=GREEN)
d.text((1080, 282), "1", font=font(15, bold=True), fill="white")
d.text((879, 348), "Give this more", font=font(21), fill=INK)
d.text((879, 377), "breathing room.", font=font(21), fill=INK)
d.text((879, 422), "Pending  ·  /pricing", font=font(15), fill=GREEN)
image.save(OUT / "og-image.png", optimize=True)

icon = Image.new("RGBA", (512, 512))
mark(ImageDraw.Draw(icon), 0, 0, 512)
icon.resize((180, 180), Image.Resampling.LANCZOS).save(OUT / "apple-touch-icon.png")
icon.save(ROOT / "docs" / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
(ROOT / "docs" / "favicon.svg").write_text("""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="23" fill="#3a5a3f"/><path d="M26 25h48v38H43L26 77Z" fill="white"/><path d="M38 39h24M38 50h24" stroke="#3a5a3f" stroke-width="3.5"/></svg>\n""")
print("Generated OG image, SVG/ICO favicon and Apple touch icon.")

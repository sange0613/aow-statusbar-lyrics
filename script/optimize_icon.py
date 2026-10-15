"""Optional asset maintenance: Pillow is needed only when regenerating the icon."""
from pathlib import Path
import subprocess
import tempfile
from PIL import Image

root = Path(__file__).resolve().parent.parent
source = Image.open(root / "Resources/AppIcon.png").convert("RGBA")
with tempfile.TemporaryDirectory() as temporary:
    iconset = Path(temporary) / "AppIcon.iconset"
    iconset.mkdir()
    # A 256pt @2x image covers large Finder icons; omit redundant 512pt/1024px payloads.
    for points in (16, 32, 128, 256):
        for scale in (1, 2):
            size = points * scale
            image = source.resize((size, size), Image.Resampling.LANCZOS)
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            image.save(iconset / name, optimize=True)
            assert image.convert("RGBA").getpixel((0, 0))[3] == 0
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o",
                    str(root / "Resources/AppIcon.icns")], check=True)
print("Optimized AppIcon.icns:", (root / "Resources/AppIcon.icns").stat().st_size, "bytes")

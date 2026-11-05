"""The codicons the site's pictures of the app draw (site/mocks/*.html,
`class="ci ci-<name>"`): their rules at the end of site/mocks/mock.css, and
site/mocks/codicon.woff2, assets/codicons/codicon.ttf cut down to them.
Run again after drawing an icon not drawn before:

    python3 -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools brotli
    /tmp/ft/bin/python tool/make_mock_icons.py

The names are lib/theme/codicons.dart's, as VS Code writes them
(layoutSidebarLeft is layout-sidebar-left)."""

import pathlib
import re
import sys

from fontTools import subset

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOCKS = ROOT / "site" / "mocks"
CSS = MOCKS / "mock.css"
MARK = "/* --- The icons drawn (tool/make_mock_icons.py) --- */"

points = {}
for camel, code in re.findall(r"static const IconData (\w+) = IconData\(\s*0x([0-9a-f]+)", (ROOT / "lib/theme/codicons.dart").read_text()):
    points.setdefault(re.sub(r"(?<=[a-z0-9])([A-Z])", r"-\1", camel).lower(), int(code, 16))

used = sorted({name for page in MOCKS.glob("*.html") for name in re.findall(r"\bci-([a-z0-9-]+)", page.read_text())})
missing = [name for name in used if name not in points]
if missing:
    sys.exit(f"Not codicons: {', '.join(missing)}")

rules = "\n".join(f'.ci-{name}::before {{ content: "\\{points[name]:x}"; }}' for name in used)
css = CSS.read_text().split(MARK)[0].rstrip()
CSS.write_text(f"{css}\n\n{MARK}\n{rules}\n")

options = subset.Options()
options.flavor = "woff2"
options.layout_features = []
options.name_IDs = []
font = subset.load_font(str(ROOT / "assets/codicons/codicon.ttf"), options)
subsetter = subset.Subsetter(options)
subsetter.populate(unicodes=[points[name] for name in used])
subsetter.subset(font)
subset.save_font(font, str(MOCKS / "codicon.woff2"), options)
print(f"{len(used)} icons, {(MOCKS / 'codicon.woff2').stat().st_size} bytes")

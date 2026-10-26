#!/usr/bin/env python3
"""把中文覆盖层脚本放进前端产物，并在 index.html 里挂上 script 标签。

构建会重新生成 web_dist 和 index.html，所以每次 apply.sh 构建完都要跑一次。
"""
import shutil
import sys
from pathlib import Path

REPO = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".hermes/hermes-agent"
HERE = Path(__file__).resolve().parent
DIST = REPO / "hermes_cli/web_dist"
SRC = HERE / "payload" / "zhOverlay.js"

if not SRC.exists():
    print("⚠ 找不到 payload/zhOverlay.js，跳过覆盖层")
    sys.exit(0)

assets = DIST / "assets"
assets.mkdir(parents=True, exist_ok=True)
shutil.copyfile(SRC, assets / "zh-overlay.js")

idx = DIST / "index.html"
html = idx.read_text(encoding="utf-8")
TAG = '<script src="/assets/zh-overlay.js" defer></script>'
if "zh-overlay.js" in html:
    print("· 覆盖层已挂载")
else:
    if "</head>" in html:
        html = html.replace("</head>", "  " + TAG + "\n  </head>", 1)
        idx.write_text(html, encoding="utf-8")
        print("✓ 覆盖层已挂载")
    else:
        print("⚠ index.html 没有 </head>，未挂载")

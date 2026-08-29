#!/usr/bin/env python3
"""为捐赠凭证 PDF 重建 CJK 子集字体。

背景：src/lib/generateDonationReceipt.ts 为 zh-Hant/ko/ja 凭证嵌入
Noto Sans CJK 子集字体（public/fonts/NotoSansCJK-Receipt.ttf）。
字体按当前 messages 全部文案字符精确子集化（~315KB）。

何时需要重建：
  - src/messages/*.json 新增了 CJK 字符（新文案/新语言）
  - 日期格式化输出字符集变化（月份/曜日等）
  重新运行本脚本即可（需 python3 + fonttools，联网下载一次源字体）。

产物：public/fonts/NotoSansCJK-Receipt.ttf
源字体：notofonts/noto-cjk NotoSansCJKsc-VF.ttf（可变字体，实例化 wght=400）

用法（在仓库根目录）：
  python3 scripts/build-receipt-font.py [--vf <已下载的VF字体路径>]

校验：脚本内置 100% 覆盖检查，缺字形直接退出非零码。
"""

import json
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]
MESSAGES_DIR = REPO / "src" / "messages"
OUT_FONT = REPO / "public" / "fonts" / "NotoSansCJK-Receipt.ttf"
VF_URL = (
    "https://raw.githubusercontent.com/notofonts/noto-cjk/main/"
    "Sans/Variable/TTF/NotoSansCJKsc-VF.ttf"
)
WORK_DIR = REPO / ".font-build"

# 日期/时间格式化输出字符（next-intl 内置 locale 数据不在 messages 里）
EXTRA_CHARS = (
    "0123456789"                     # 数字
    "一二三四五六七八九十零"           # 中日月份/日序
    "年月日時分秒曜"                   # zh-Hant / ja 日期单位
    "月火水木金土"                     # 曜日（ja/ko 周名）
    "요일년월일"                       # ko 日期单位
    "午前午後"                         # ja AM/PM
    "AMPMampm"                        # 通用 AM/PM
    "UTCGMT"                          # 时区缩写
    "．，、。「」『』（）！？：；－"     # 全角/CJK 标点
    "％‰·—"                           # 符号
    " +"
)


def collect_chars() -> set[str]:
    chars: set[str] = set()
    for f in MESSAGES_DIR.glob("*.json"):
        data = json.loads(f.read_text(encoding="utf-8"))

        def walk(node):
            if isinstance(node, dict):
                for v in node.values():
                    walk(v)
            elif isinstance(node, list):
                for v in node:
                    walk(v)
            elif isinstance(node, str):
                chars.update(node)

        walk(data)
    chars.update(EXTRA_CHARS)
    chars.update(chr(c) for c in range(0x20, 0x7F))  # ASCII 可打印区
    return chars


def main() -> None:
    WORK_DIR.mkdir(exist_ok=True)
    OUT_FONT.parent.mkdir(parents=True, exist_ok=True)

    # 1. 源字体（--vf 指定本地文件，否则下载）
    vf_arg = None
    if "--vf" in sys.argv:
        vf_arg = pathlib.Path(sys.argv[sys.argv.index("--vf") + 1])
    else:
        vf_arg = WORK_DIR / "NotoSansCJKsc-VF.ttf"
        if not vf_arg.exists():
            print(f"downloading {VF_URL} ...")
            subprocess.run(
                ["curl", "-sL", "--max-time", "300", "-o", str(vf_arg), VF_URL],
                check=True,
            )
    print(f"source VF: {vf_arg} ({vf_arg.stat().st_size / 1024 / 1024:.1f} MB)")

    # 2. 收集字符
    chars = collect_chars()
    char_file = WORK_DIR / "receipt-chars.txt"
    char_file.write_text("".join(sorted(chars)), encoding="utf-8")
    print(f"unique chars: {len(chars)}")

    # 3. 实例化 wght=400（静态化）
    static_font = WORK_DIR / "NotoSansCJK-static-400.ttf"
    subprocess.run(
        [sys.executable, "-m", "fontTools.varLib.instancer",
         str(vf_arg), "wght=400", "-o", str(static_font)],
        check=True, capture_output=True,
    )

    # 4. 子集化
    subprocess.run(
        [sys.executable, "-m", "fontTools.subset",
         str(static_font),
         f"--text-file={char_file}",
         f"--output-file={OUT_FONT}",
         "--no-hinting",
         "--layout-features=",
         "--no-layout-closure",
         "--drop-tables+=GSUB,GPOS",
         ],
        check=True, capture_output=True,
    )
    print(f"subset font: {OUT_FONT} ({OUT_FONT.stat().st_size / 1024:.1f} KB)")

    # 5. 覆盖校验（astral emoji 与 U+2190-2BFF 装饰符号按设计排除）
    from fontTools.ttLib import TTFont

    cmap = TTFont(str(OUT_FONT)).getBestCmap()
    missing = [c for c in chars
               if 0x20 < ord(c) <= 0xFFFF
               and not (0x2190 <= ord(c) <= 0x2BFF)
               and ord(c) not in cmap]
    if missing:
        print("MISSING glyphs for:", "".join(missing[:80]))
        sys.exit(1)
    print("coverage: 100% of text chars — OK")


if __name__ == "__main__":
    main()

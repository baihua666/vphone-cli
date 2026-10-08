"""Read the shared literal feature macros before touching firmware files."""

from pathlib import Path
import re


FEATURE_HEADER = Path(__file__).resolve().parents[1] / "vphone_custom_features.h"


def read_feature_macros(path=None):
    required = {"TB_VPHONE_CUSTOMIZATIONS", "TB_VPHONE_HIDE_MOBILEGESTALT_VM"}
    values = {}
    for line in Path(path or FEATURE_HEADER).read_text().splitlines():
        if not re.match(r"\s*#\s*define\s+TB_VPHONE_", line):
            continue
        match = re.fullmatch(r"\s*#\s*define\s+(TB_VPHONE_\w+)\s+([01])\s*", line)
        if not match or match[1] not in required or match[1] in values:
            raise ValueError(f"Invalid or duplicate feature macro: {line}")
        values[match[1]] = match[2] == "1"
    if set(values) != required:
        raise ValueError(f"Missing feature macros: {sorted(required - values.keys())}")
    return values


def hide_mobilegestalt_vm():
    values = read_feature_macros()
    return values["TB_VPHONE_CUSTOMIZATIONS"] and values["TB_VPHONE_HIDE_MOBILEGESTALT_VM"]

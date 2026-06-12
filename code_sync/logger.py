#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
统一日志和脱敏工具 — 所有模块共用。
"""

import re
import sys

_COLORS = {
    "green":  "\033[0;32m",
    "yellow": "\033[1;33m",
    "red":    "\033[0;31m",
    "cyan":   "\033[0;36m",
}
_RESET = "\033[0m"


def log(text: str, color: str = "default", end: str = "\n"):
    prefix = _COLORS.get(color, "")
    try:
        print(f"{prefix}{text}{_RESET}", end=end, flush=True)
    except UnicodeEncodeError:
        safe_text = text.encode("gbk", errors="replace").decode("gbk")
        print(f"{prefix}{safe_text}{_RESET}", end=end, flush=True)


def desensitize(text: str) -> str:
    return re.sub(r"(://[^:@]+:)[^@]+@", r"\1***@", text)

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Git 命令行工具函数 — 纯 git 操作，无 HTTP API 调用。
"""

import subprocess
import urllib.parse
from pathlib import Path
from typing import List, Optional, Tuple

from logger import desensitize, log


def run(
    args: List[str],
    *,
    cwd: Optional[Path] = None,
    show: bool = True,
) -> Tuple[int, str, str]:
    if show:
        log(f"    $ {desensitize('git ' + ' '.join(args))}")
    try:
        r = subprocess.run(
            ["git"] + args,
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return -1, "", str(e)


def branch_exists(repo: Path, remote: str, branch: str) -> bool:
    ret, out, _ = run(
        ["ls-remote", "--heads", remote, branch.removeprefix("refs/heads/")],
        cwd=repo,
        show=False,
    )
    return ret == 0 and bool(out.strip())


def get_commit(repo: Path, ref: str) -> Tuple[str, str, str]:
    ret, commit_id, _ = run(["rev-parse", ref], cwd=repo, show=False)

    if not commit_id and ref.startswith("dest/"):
        _, out, _ = run(["ls-remote", "dest", ref[5:]], cwd=repo, show=False)
        commit_id = out.strip().split()[0] if out else None

    if not commit_id:
        return "unknown", "unknown", "unknown"

    _, short_id, _ = run(["rev-parse", "--short", commit_id], cwd=repo, show=False)
    short_id = short_id or commit_id[:7]

    if ref.startswith("dest/") and run(["rev-parse", ref], cwd=repo, show=False)[0] != 0:
        msg = "(远程存在)"
    else:
        ret, msg, _ = run(["log", "-1", "--pretty=%s", commit_id], cwd=repo, show=False)
        msg = msg or "(未知)"

    return commit_id, short_id, msg


def insert_auth(raw_url: str, user: str, pwd: str) -> str:
    if not user or not pwd:
        return raw_url
    if raw_url.startswith("http://"):
        prefix, rest = "http://", raw_url[7:]
    elif raw_url.startswith("https://"):
        prefix, rest = "https://", raw_url[8:]
    else:
        return raw_url
    return f"{prefix}{user}:{urllib.parse.quote(pwd, safe='')}@{rest}"


def repo_name(url: str) -> str:
    name = Path(url).stem
    return name.removesuffix(".git") if name.endswith(".git") else name

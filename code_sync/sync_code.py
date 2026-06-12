#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
代码同步 — GitLab<->Gitee 单向/反向同步指定分支。
运行后显示交互菜单，无需命令行参数。
"""

import re
import sys
from pathlib import Path

from api_ops import GitLabAPI, GiteeAPI
from config import (
    DST_PASSWORD, DST_USER, REPOS, SRC_PASSWORD, SRC_USER, WORKSPACE,
)
from git_utils import branch_exists, get_commit, insert_auth, log, repo_name, run


def _prepare_config(cfg: dict, reverse: bool = False) -> tuple:
    """解析源/目标 URL、分支、认证信息，支持正向/反向同步。"""
    if reverse:
        return (
            cfg["destination"],                              # Gitee → 拉取源
            cfg["source"],                                   # GitLab → 推送目标
            cfg.get("dest_branch") or cfg["source_branch"],  # 从 Gitee 拉取的分支
            cfg["source_branch"],                            # 推送到 GitLab 的分支
            DST_USER, DST_PASSWORD,                          # Gitee 认证
            SRC_USER, SRC_PASSWORD,                          # GitLab 认证
        )
    else:
        return (
            cfg["source"], cfg["destination"],
            cfg["source_branch"], cfg.get("dest_branch") or cfg["source_branch"],
            SRC_USER, SRC_PASSWORD, DST_USER, DST_PASSWORD,
        )


def sync(cfg: dict, reverse: bool = False) -> bool:
    (src_url, dst_url, src_branch, dst_branch,
     src_user, src_pass, dst_user, dst_pass) = _prepare_config(cfg, reverse)
    name      = repo_name(src_url)
    auth_src  = insert_auth(src_url, src_user, src_pass)
    auth_dst  = insert_auth(dst_url, dst_user, dst_pass)
    repo_dir  = Path(WORKSPACE) / name

    # ── clone 或 fetch ──────────────────────────────
    if (repo_dir / ".git").exists():
        log("   ⏩ Pull 更新...", "cyan")
        # 每次刷新 origin URL，避免本地残留过期 token
        run(["remote", "set-url", "origin", auth_src], cwd=repo_dir, show=False)
        ret, _, err = run(["fetch", "origin"], cwd=repo_dir)
        if ret != 0:
            log(f"   ❌ Fetch: {err}", "red");  return False
    else:
        log("   ⬇️ Clone...", "cyan")
        ret, _, err = run(["clone", auth_src, str(repo_dir)])
        if ret != 0:
            log(f"   ❌ Clone: {err}", "red");  return False

    # ── checkout 源分支 & pull 最新 ─────────────────
    if not branch_exists(repo_dir, "origin", src_branch):
        log(f"   ❌ 源分支 '{src_branch}' 不存在", "red");  return False

    ret, _, err = run(["checkout", src_branch], cwd=repo_dir)
    if ret != 0:
        ret, _, err = run(["checkout", "-b", src_branch, f"origin/{src_branch}"],
                          cwd=repo_dir)
        if ret != 0:
            log(f"   ❌ checkout: {err}", "red");  return False

    run(["pull", "origin", src_branch], cwd=repo_dir)

    # ── 配置 dest 远端 & fetch ──────────────────────
    run(["remote", "remove", "dest"], cwd=repo_dir, show=False)
    run(["remote", "add", "dest", auth_dst], cwd=repo_dir)
    ret, _, err = run(["fetch", "dest"], cwd=repo_dir)
    if ret != 0:
        log(f"   ❌ 目标仓库不可达: {err}", "red");  return False

    # ── 提交对比 ────────────────────────────────────
    local_id, short_id, local_msg = get_commit(repo_dir, src_branch)

    if branch_exists(repo_dir, "dest", dst_branch):
        remote_id, remote_short_id, remote_msg = get_commit(
            repo_dir, f"dest/{dst_branch}")
    else:
        remote_id, remote_short_id, remote_msg = "unknown", "(不存在)", "(将创建)"

    log(f"   📊 {short_id} ← {local_msg}")
    log(f"      {remote_short_id} ← {remote_msg}")

    if local_id == remote_id and local_id != "unknown":
        log("   ✅ 已同步", "green");  return True

    # ── 推送 ────────────────────────────────────────
    push_args = ["push", "dest", f"{src_branch}:{dst_branch}"]
    log("   📤 推送...", "default")

    ret, _, err = run(push_args, cwd=repo_dir)
    if ret == 0:
        log("   ✅ 完成", "green");  return True

    if "non-fast-forward" in err or "rejected" in err:
        log("   ❌ 被拒绝: 远端有独立提交，不允许强制推送", "red")
    else:
        log(f"   ❌ {err}", "red")
    return False


def sync_dry_run(cfg: dict, src_api: GitLabAPI, dst_api: GiteeAPI) -> bool:
    """纯 API 对比两端分支 commit，无需 clone。"""
    from api_ops import APIError

    src_url = cfg["source"]
    dst_url = cfg["destination"]
    src_branch = cfg["source_branch"]
    dst_branch = cfg.get("dest_branch") or src_branch
    name = repo_name(src_url)

    src_info = src_api.get_branch_commit(src_url, src_branch)
    if not src_info:
        log(f"   ❌ 源分支 '{src_branch}' 不存在或无法访问", "red")
        return False

    try:
        dst_info = dst_api.get_branch_commit(dst_url, dst_branch)
    except APIError as e:
        log(f"   📊 {src_info['sha']} ← {src_info['message']}")
        log(f"      ❌ 目标仓库不可达: {e.message}", "red")
        return False
    except Exception as e:
        log(f"   📊 {src_info['sha']} ← {src_info['message']}")
        log(f"      ❌ 目标仓库不可达: {e}", "red")
        return False

    if dst_info:
        log(f"   📊 {src_info['sha']} ← {src_info['message']}")
        log(f"      {dst_info['sha']} ← {dst_info['message']}")

        if src_info["sha"] == dst_info["sha"]:
            log("   ✅ 已同步", "green");  return True

        # 额外诊断：检查是否只是 SHA 不同但内容相同
        if src_info["message"] == dst_info["message"]:
            log(f"   ⚠️  Message 相同但 SHA 不同（可能是 rebase/cherry-pick 导致）", "yellow")
        else:
            log(f"   ⚠️  Message 也不同，远端可能指向错误提交", "red")

        log("   ⚠️  需要推送", "yellow")
    else:
        log(f"   📊 {src_info['sha']} ← {src_info['message']}")
        log(f"      (不存在) ← (将创建)")
        log("   ⚠️  需要推送创建远程分支", "yellow")

    return True  # dry-run 不视为失败


def select_repo() -> dict:
    """交互式选择仓库，返回用户选中的配置。"""
    log("\n📋 可用的仓库:", "cyan")
    print("-" * 40)
    for i, cfg in enumerate(REPOS, 1):
        name = repo_name(cfg["source"])
        src_branch = cfg["source_branch"]
        dst_branch = cfg.get("dest_branch") or src_branch
        log(f"  [{i}] {name}")
        print(f"      GitLab  : {cfg['source']}  ({src_branch})")
        print(f"      Gitee   : {cfg['destination']}  ({dst_branch})")
    print("-" * 40)

    while True:
        try:
            choice = input(f"\n请选择仓库 [1-{len(REPOS)}] (Ctrl+C 取消): ").strip()
            if not choice:
                continue
            idx = int(choice) - 1
            if 0 <= idx < len(REPOS):
                return REPOS[idx]
            log(f"   ⚠️  无效选择，请输入 1-{len(REPOS)}", "yellow")
        except ValueError:
            log(f"   ⚠️  请输入数字 (1-{len(REPOS)})", "yellow")
        except (EOFError, KeyboardInterrupt):
            log("\n\n👋 已取消", "yellow")
            sys.exit(0)


def main_menu() -> str:
    """显示主菜单，返回用户选择。"""
    menu = """
+------------------------------------------+
|       代码同步工具 - GitLab <-> Gitee     |
+------------------------------------------+
|  [1] 正常同步 (GitLab -> Gitee)          |
|  [2] 反向同步 (Gitee -> GitLab, 选择仓库)|
|  [3] 仅对比   (API 对比, 不推送)         |
|  [0] 退出                                |
+------------------------------------------+
"""
    print(menu)
    while True:
        try:
            choice = input("请选择 [0-3]: ").strip()
            if choice in ("0", "1", "2", "3"):
                return choice
            log(f"  ⚠️  无效选择, 请输入 0-3", "yellow")
        except (EOFError, KeyboardInterrupt):
            log("\n\n👋 已退出", "yellow")
            sys.exit(0)


def main():
    if not SRC_PASSWORD or not DST_PASSWORD:
        log("❌ 请创建 .env 文件或设置环境变量: GIT_SRC_PASS, GIT_DST_PASS", "red")
        return 1

    choice = main_menu()

    # ── 退出 ────────────────────────────────────────
    if choice == "0":
        log("👋 已退出", "yellow")
        return 0

    # ── 仅对比 (dry-run) ────────────────────────────
    if choice == "3":
        total = len(REPOS)
        log(f"🚀 对比 {total} 个仓库 [dry-run]", "green")
        print("-" * 40)
        for i, cfg in enumerate(REPOS, 1):
            log(f"\n[{i}/{total}]", "default")
            name = repo_name(cfg["source"])
            src_base = re.match(r"(https?://[^/]+)", cfg["source"]).group(1)
            dst_base = re.match(r"(https?://[^/]+)", cfg["destination"]).group(1)
            src_api = GitLabAPI(src_base, SRC_PASSWORD)
            dst_api = GiteeAPI(dst_base, DST_PASSWORD)
            ok = sync_dry_run(cfg, src_api, dst_api)
            if not ok:
                log(f"\n❌ {name} 失败，停止", "red")
                return 1
        log(f"\n{'=' * 40}\n🎉 对比完成!", "green")
        return 0

    # ── 反向同步 (Gitee -> GitLab) ──────────────────
    if choice == "2":
        cfg = select_repo()
        name = repo_name(cfg["source"])
        src_branch = cfg["source_branch"]
        dst_branch = cfg.get("dest_branch") or src_branch
        log(f"\n🔄 反向同步 {name}: Gitee -> GitLab", "yellow")
        log(f"   拉取: {cfg['destination']} ({dst_branch})")
        log(f"   推送: {cfg['source']} ({src_branch})")
        print("-" * 40)
        ok = sync(cfg, reverse=True)
        if not ok:
            log(f"\n❌ {name} 反向同步失败", "red")
            return 1
        log(f"\n{'=' * 40}\n🎉 反向同步完成!", "green")
        return 0

    # ── 正常同步 (GitLab -> Gitee) ──────────────────
    # 子菜单：全部 or 单个
    sub = ""
    while sub not in ("a", "s"):
        try:
            sub = input("\n同步范围: [A]全部仓库  [S]单个仓库: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            log("\n\n👋 已退出", "yellow")
            sys.exit(0)

    repos_to_sync = REPOS
    if sub == "s":
        repos_to_sync = [select_repo()]

    total = len(repos_to_sync)
    log(f"\n🚀 同步 {total} 个仓库", "green")
    print("-" * 40)
    for i, cfg in enumerate(repos_to_sync, 1):
        log(f"\n[{i}/{total}]", "default")
        name = repo_name(cfg["source"])
        ok = sync(cfg)
        if not ok:
            log(f"\n❌ {name} 失败，停止", "red")
            return 1
    log(f"\n{'=' * 40}\n🎉 全部完成!", "green")
    return 0


if __name__ == "__main__":
    sys.exit(main())

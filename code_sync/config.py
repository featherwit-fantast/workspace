#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
全局配置 — 仓库列表、认证信息、默认分支等。

密码从 .env 文件或环境变量读取，不要直接写在这里。
用法：
    echo 'GIT_SRC_PASS=你的token' > .env   # 首次运行
    python sync_code.py
"""

import os
from pathlib import Path

# ── 从 .env 文件加载环境变量 ──────────────────────────
_env_path = Path(__file__).parent / ".env"
if _env_path.is_file():
    for line in _env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, val = line.split("=", 1)
            os.environ.setdefault(key.strip(), val.strip())

# ── 认证信息（环境变量优先） ──────────────────────────
SRC_USER = os.getenv("GIT_SRC_USER", "lisong")
SRC_PASSWORD = os.getenv("GIT_SRC_PASS", "D@tasu2e")

DST_USER = os.getenv("GIT_DST_USER", "yingzhengshi")
DST_PASSWORD = os.getenv("GIT_DST_PASS", "K9#mP2$vL8@xQ5")

# ── 工作目录（环境变量优先，每个人根据自己存储代码的实际位置调整）──────────────────────────
WORKSPACE = os.getenv("GIT_SYNC_WORKSPACE", "data")

# ── 常用分支常量 ────────────────────────────────────
BRANCH_GLMS_FEATURE_142 = "glms/feature/1.4.2"
BRANCH_GLMS_142 = "glms/1.4.2"
BRANCH_GLMS = "glms"
BRANCH_EQD_GLMS_FEATURE_142 = "eqd/glms/feature/1.4.2"

# ── 仓库列表 ─────────────────────────────────────────
# 字段说明:
#   source       : 源仓库 URL (GitLab)
#   destination  : 目标仓库 URL (Gitee)
#   source_branch: 源分支
#   dest_branch  : 目标分支 (留空则与 source_branch 同名)
# ──────────────────────────────────────────────────────
REPOS = [
    # ┌─ repo ───────────────┐
    {
        "source"      : "http://git.yiliantech.com/gitlab/otc-dev/bond-calc.git",
        "destination" : "https://gitee.glmszq.com/gsty/onederiv/bond-calc.git",
        "source_branch": BRANCH_GLMS_142,
       # "force"        : True,       # 强制覆盖远程
    },
    {
        "source"      : "http://git.yiliantech.com/gitlab/otc-dev/zszq-trs.git",
        "destination" : "https://gitee.glmszq.com/gsty/onederiv/trs.git",
        "source_branch": BRANCH_GLMS_FEATURE_142,
    },
    {
        "source"      : "http://git.yiliantech.com/gitlab/otc-dev/zszq-bond-oms.git",
        "destination" : "https://gitee.glmszq.com/gsty/onederiv/oms-bond-oms.git",
        "source_branch": BRANCH_GLMS_FEATURE_142,
    },
    {
        "source"      : "http://git.yiliantech.com/gitlab/otc-dev/bond-sync.git",
        "destination" : "https://gitee.glmszq.com/gsty/onederiv/bond-sync.git",
        "source_branch": BRANCH_GLMS,
    },
    {
        "source"      : "http://git.yiliantech.com/gitlab/otc-dev/otc.git",
        "destination" : "https://gitee.glmszq.com/gsty/onederiv/yield-certificate.git",
        "source_branch": BRANCH_EQD_GLMS_FEATURE_142,
        "dest_branch" : BRANCH_GLMS_FEATURE_142,        # 目标分支名称与源不同
    },
    {
        "source"      : "http://git.yiliantech.com/gitlab/otc-dev/otc-marketdata.git",
        "destination" : "https://gitee.glmszq.com/gsty/onederiv/market-app.git",
        "source_branch": BRANCH_GLMS_142,
    },
    {
        "source"      : "http://git.yiliantech.com/gitlab/otc-dev/bond-oms-ui.git",
        "destination" : "https://gitee.glmszq.com/gsty/onederiv/bond-oms-ui.git",
        "source_branch": BRANCH_GLMS_FEATURE_142,
     #   "force"        : True,       # Gitee 指向错误 commit，需要强制覆盖
    },
    {
        "source"      : "http://git.yiliantech.com/gitlab/otc-dev/otcdms-ui.git",
        "destination" : "https://gitee.glmszq.com/gsty/onederiv/otcdms-ui.git",
        "source_branch": BRANCH_GLMS_FEATURE_142,
    },
    # └─────────────────────────┘
    # 新增仓库照此格式复制粘贴 ↑
]

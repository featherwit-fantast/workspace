#!/bin/bash
#author:lisong
# nginx_html_rollback.sh
# =========================================
# 1️⃣ 初始化回滚环境（只输入备份目录）
# =========================================
init_rollback_env() {
  read -p "请输入回滚备份目录：" BACKUP_DIR

  [ -d "$BACKUP_DIR" ] || {
    echo "❌ 备份目录不存在：$BACKUP_DIR"
    exit 1
  }

  echo "✅ 使用回滚备份目录：$BACKUP_DIR"
}

# =========================================
# 2️⃣ 自动生成回滚组件列表 + 用户确认
# =========================================
generate_and_confirm_rollback_list() {
  ROLLBACK_LIST=()

  for dir in "$BACKUP_DIR"/*; do
    [ -d "$dir" ] || continue
    base=$(basename "$dir")

    for comp in "${!COMPONENTS[@]}"; do
      if [ "$base" = "$(basename "${COMPONENTS[$comp]}")" ]; then
        ROLLBACK_LIST+=("$comp")
      fi
    done
  done

  [ ${#ROLLBACK_LIST[@]} -eq 0 ] && {
    echo "ℹ️ 未发现可回滚的组件"
    exit 0
  }

  echo "本次需要回滚的组件： ${ROLLBACK_LIST[*]}"

  read -p "是否继续回滚？(y/N)：" CONFIRM
  CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
  [ "$CONFIRM" = "y" ] || {
    echo "❌ 用户取消回滚"
    exit 0
  }
}

# =========================================
# 3️⃣ 回滚单个组件（最简、安全）
# =========================================
rollback_component() {
  local comp=$1
  local DEST="${COMPONENTS[$comp]}"
  local SRC="$BACKUP_DIR/$(basename "$DEST")"

  echo "=============================="
  echo "回滚组件：$comp"
  echo "备份来源：$SRC"
  echo "目标目录：$DEST"

  [ -d "$SRC" ] || {
    echo "❌ 备份目录不存在：$SRC"
    exit 1
  }

  echo "🔹 开始回滚组件：$comp ..."
  rsync -av "$SRC"/ "$DEST"/ || {
    echo "❌ 回滚失败：$comp"
    exit 1
  }

  echo "✅ 组件 $comp 回滚完成"

}

# =========================================
# 4️⃣ 主流程
# =========================================

# 定义组件映射
declare -A COMPONENTS=(
  ["otcdms-ui"]="/etc/nginx/html/otcdms-ui"
  ["reg-ui"]="/etc/nginx/html/reg-ui"
  ["trader-ui"]="/etc/nginx/html/bond-oms-ui/trader"
  ["client-ui"]="/etc/nginx/html/bond-oms-ui/client"
)
# 初始化
init_rollback_env

# 自动生成回滚列表 + 确认
generate_and_confirm_rollback_list

# 执行回滚
for comp in "${ROLLBACK_LIST[@]}"; do
  rollback_component "$comp"
done

echo "🔁 重启 nginx"
systemctl restart nginx

echo "✅ 所有组件回滚完成。"

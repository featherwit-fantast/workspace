#!/bin/bash
#author:lisong
#nginx_html_update.sh
# =========================================
# 1️⃣ 初始化更新环境
# =========================================
init_update_env() {
  # 命令检查
  command -v rsync >/dev/null 2>&1 || { echo "❌ 未检测到 rsync"; exit 1; }
  command -v unzip >/dev/null 2>&1 || { echo "❌ 未检测到 unzip"; exit 1; }

  # 读取更新目录
  read -p "请输入更新目录：" UPDATE_DIR
  [ -d "$UPDATE_DIR" ] || { echo "❌ 目录不存在：$UPDATE_DIR"; exit 1; }

  # 解压 zip
  found_zip=0
  for zip in "$UPDATE_DIR"/*.zip; do
    [ -e "$zip" ] || continue
    found_zip=1
    echo "👉 解压：$zip"
    unzip -oq "$zip" -d "$UPDATE_DIR" || { echo "❌ 解压失败：$zip"; exit 1; }
  done
  [ "$found_zip" -eq 1 ] && rm -f "$UPDATE_DIR"/*.zip
  echo "✅ 初始化完成，更新目录：$UPDATE_DIR"
}

# =========================================
# 2️⃣ 生成更新组件列表 + 用户确认
# =========================================
generate_and_confirm_update_list() {
  UPDATE_LIST=()
  for dir in "$UPDATE_DIR"/*; do
    [ -d "$dir" ] || continue
    base=$(basename "$dir")
    [ -n "${COMPONENTS[$base]}" ] && UPDATE_LIST+=("$base")
  done

  [ ${#UPDATE_LIST[@]} -eq 0 ] && { echo "ℹ️ 未发现需要更新的组件，退出。"; exit 0; }

  echo "本次需要更新的组件： ${UPDATE_LIST[*]}"

  read -p "是否继续更新？(y/N)：" CONFIRM
  CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
  [ "$CONFIRM" = "y" ] || { echo "❌ 用户取消更新"; exit 0; }
}

# =========================================
# 3️⃣ 备份和更新单个组件
# =========================================
backup_and_update() {
  local comp=$1
  local SRC="$UPDATE_DIR/$comp"
  local DEST="${COMPONENTS[$comp]}"
  local BACKUP_DIR=/home/zszq/backup/$(date +%Y%m%d)
  mkdir -p "$BACKUP_DIR"

  echo "=============================="
  echo "处理组件：$comp"
  echo "备份目录：$BACKUP_DIR"

  # ---------- 备份 ----------
  echo "🔹 开始备份组件：$comp ..."
  rsync -av  "$DEST" "$BACKUP_DIR/" || {
    echo "❌ 备份失败：$comp"
    exit 1
  }
  echo "✅ 组件 $comp 备份完成"

  # ---------- 更新 ----------
  echo "🔹 开始更新组件：$comp ..."
  rsync -av "$SRC"/ "$DEST"/ || {
    echo "❌ 更新失败：$comp"
    exit 1
  }
  echo "✅ 组件 $comp 更新完成"

  # ---------- 校验 ----------
  echo "🔹 开始校验组件：$comp ..."
  DIFF=$(rsync -rcn --itemize-changes "$SRC"/ "$DEST"/)
  if [ -n "$DIFF" ]; then
    echo "❌ 校验失败，以下文件未同步或有差异："
    echo "$DIFF"
    exit 1
  fi
  echo "✅ 组件 $comp 校验通过"


  echo "组件 $comp 全部操作完成。"
}

# 初始化环境
init_update_env

# 定义组件映射
declare -A COMPONENTS=(
  ["otcdms-ui"]="/etc/nginx/html/otcdms-ui"
  ["reg-ui"]="/etc/nginx/html/reg-ui"
  ["trader-ui"]="/etc/nginx/html/bond-oms-ui/trader"
  ["client-ui"]="/etc/nginx/html/bond-oms-ui/client"
)

# 生成更新列表 + 用户确认
generate_and_confirm_update_list

# 遍历更新组件
for comp in "${UPDATE_LIST[@]}"; do
  backup_and_update "$comp"
done

echo "🔁 重启 nginx"
systemctl restart nginx

echo "✅ 所有组件更新完成。"
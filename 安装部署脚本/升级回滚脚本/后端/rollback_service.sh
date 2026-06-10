#!/bin/bash
# author: lisong
# backend_service_rollback.sh

# =========================================
# 全局变量
# =========================================
NOT_STARTED_COMPONENTS=()   # 记录未启动的组件

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
# 3️⃣ 回滚单个组件（安全版）
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

  # 停止服务
  [ -f "$DEST/stop.sh" ] && (cd "$DEST" && sh stop.sh)

  # ---------- 回滚 ----------
  echo "🔹 开始回滚组件：$comp ..."
  rsync -av "$SRC"/ "$DEST"/ || {
    echo "❌ 回滚失败：$comp"
    exit 1
  }
  echo "✅ 组件 $comp 回滚完成"

  # ---------- 启动前 JAR 校验 ----------
  echo "🔹 启动前检查 JAR 数量：$comp ..."
  JAR_COUNT=$(ls "$DEST"/*.jar 2>/dev/null | wc -l)

  if [ "$JAR_COUNT" -le 1 ]; then
    echo "✅ JAR 数量正常（$JAR_COUNT 个），启动服务"
    [ -f "$DEST/start.sh" ] && (cd "$DEST" && sh start.sh)
  else
    echo "⚠️ 发现多个 JAR（$JAR_COUNT 个），跳过启动：$comp"
    NOT_STARTED_COMPONENTS+=("$comp")
  fi

  echo "组件 $comp 回滚流程完成。"
}

# =========================================
# 4️⃣ 主流程
# =========================================

# 组件映射（与更新脚本保持一致）
declare -A COMPONENTS=(
  ["calc"]="/home/zszq/bond-calc"
  ["sync"]="/home/zszq/bond-sync"
  ["comstar"]="/home/zszq/comstar-api"
  ["market-app"]="/home/zszq/market-app"
  ["client-app"]="/home/zszq/oms-app/client-app"
  ["hedge-app"]="/home/zszq/oms-app/hedge-app"
  ["RealTimeCalcPositionService"]="/home/zszq/RealTimeCalcPositionService"
  ["reg-app"]="/home/zszq/reg-app"
  ["reg-upstream"]="/home/zszq/reg-upstream"
  ["xxljob"]="/home/zszq/xxl-job"
  ["otc"]="/home/zszq/YLErpWeb"
)

# 初始化
init_rollback_env

# 自动生成回滚列表 + 确认
generate_and_confirm_rollback_list

# 执行回滚
for comp in "${ROLLBACK_LIST[@]}"; do
  rollback_component "$comp"
done


# ---------- 启动汇总 ----------
if [ ${#NOT_STARTED_COMPONENTS[@]} -gt 0 ]; then
  echo "⚠️ 以下组件未自动启动："
  for comp in "${NOT_STARTED_COMPONENTS[@]}"; do
    echo " - $comp （原因：目录下存在多个 JAR，请手动确认并启动）"
  done
else
  echo "✅ 所有组件均已正常启动。"
fi

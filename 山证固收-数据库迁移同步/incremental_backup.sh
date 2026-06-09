#!/bin/bash
#===============================================================================
# 数据库增量备份脚本
# 基于表的时间字段进行增量备份，支持两个数据库: yltrs_ylcms 和 bond_oms
#
# 参考: shell/示例.sql (生产验证)
# 表定义: shell/增量表.txt
#===============================================================================

set -euo pipefail

# ==================== 配置区域 (按需修改) ====================

# ---- 数据库 yltrs_ylcms 连接信息 ----
DB1_HOST="10.6.4.195"
DB1_PORT="3306"
DB1_USER="ficc"
DB1_PASS="Gongxifacai@2023"
DB1_NAME="yltrs_ylcms"

# ---- 数据库 bond_oms 连接信息 ----
DB2_HOST="10.6.4.195"
DB2_PORT="3306"
DB2_USER="ficc"
DB2_PASS="Gongxifacai@2023"
DB2_NAME="bond_oms"

# ---- 备份输出目录 ----
BACKUP_DIR="/backup"

# ---- mysqldump 参数 (生产验证) ----
DUMP_OPTS="--skip-add-drop-table --no-create-info --skip-triggers --compact"

# ==================== 配置结束 ====================

#===============================================================================
# 用法
#===============================================================================
usage() {
    echo ""
    echo "用法: bash incremental_backup.sh <日期> [时间]"
    echo ""
    echo "  日期格式: YYYYMMDD             (必须)"
    echo "  时间格式: HHMMSS               (可选，默认 000000)"
    echo ""
    echo "  示例:"
    echo "    bash incremental_backup.sh 20260605              → 2026-06-05 00:00:00 之后"
    echo "    bash incremental_backup.sh 20260605 123121       → 2026-06-05 12:31:21 之后"
    echo "    bash incremental_backup.sh 20260605 090000       → 2026-06-05 09:00:00 之后"
    echo ""
    exit 1
}

# 解析命令行参数
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "错误: 参数数量不正确"
    usage
fi

SYNC_DATE="$1"
SYNC_TIME="${2:-000000}"   # 第二个参数可选，默认 000000

# 校验日期: 必须是8位数字
if ! [[ "$SYNC_DATE" =~ ^[0-9]{8}$ ]]; then
    echo "错误: 日期格式不正确，必须是8位数字 (YYYYMMDD)"
    usage
fi

# 校验时间: 必须是6位数字
if ! [[ "$SYNC_TIME" =~ ^[0-9]{6}$ ]]; then
    echo "错误: 时间格式不正确，必须是6位数字 (HHMMSS)"
    usage
fi

# ---- 日期格式化 ----
# YYYYMMDD HHMMSS → YYYY-MM-DD HH:MM:SS
SYNC_DATETIME="${SYNC_DATE:0:4}-${SYNC_DATE:4:2}-${SYNC_DATE:6:2} ${SYNC_TIME:0:2}:${SYNC_TIME:2:2}:${SYNC_TIME:4:2}"
SYNC_DAY="${SYNC_DATE:0:4}-${SYNC_DATE:4:2}-${SYNC_DATE:6:2}"

# 输出文件 (有时间则带上时间)
if [ "${SYNC_TIME}" = "000000" ]; then
    OUTPUT_FILE="${BACKUP_DIR}/increment-${SYNC_DATE}.sql"
else
    OUTPUT_FILE="${BACKUP_DIR}/increment-${SYNC_DATE}-${SYNC_TIME}.sql"
fi

# 统计
TOTAL=0
SUCCESS=0
FAIL=0

#===============================================================================
# 函数定义
#===============================================================================

# 替换占位符
#   {上次同步时间}  → 完整日期时间  'YYYY-MM-DD HH:MM:SS'  (用于 OptDate/OptTime/create_time/update_time 等 datetime 字段)
#   {交易日}       → 仅日期        'YYYY-MM-DD'           (用于 ValueDate/HappenDate/EventDate 等 date 字段)
replace_placeholders() {
    local condition="$1"
    condition="${condition//\{上次同步时间\}/${SYNC_DATETIME}}"
    condition="${condition//\{交易日\}/${SYNC_DAY}}"
    echo "$condition"
}

# 执行增量备份 (每表一次 mysqldump，追加到输出文件)
do_backup() {
    local host=$1
    local port=$2
    local user=$3
    local pass=$4
    local db=$5
    local table=$6
    local where_raw=$7

    TOTAL=$((TOTAL + 1))

    local where_cond=""
    if [ -n "$where_raw" ]; then
        where_cond=$(replace_placeholders "$where_raw")
        echo "[$(date '+%H:%M:%S')] 备份 ${db}.${table}  条件: ${where_cond}"
    else
        echo "[$(date '+%H:%M:%S')] 备份 ${db}.${table}  方式: 全量"
    fi

    if [ -z "$where_cond" ]; then
        # 全量: 不带 --where
        mysqldump -h"${host}" -P"${port}" -u"${user}" -p"${pass}" \
            ${DUMP_OPTS} \
            --databases "${db}" \
            --tables "${table}" \
            >> "${OUTPUT_FILE}" 2>/dev/null
    else
        mysqldump -h"${host}" -P"${port}" -u"${user}" -p"${pass}" \
            ${DUMP_OPTS} \
            --databases "${db}" \
            --tables "${table}" \
            --where="${where_cond}" \
            >> "${OUTPUT_FILE}" 2>/dev/null
    fi

    if [ $? -eq 0 ]; then
        echo "    ✓ 成功"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "    ✗ 失败"
        FAIL=$((FAIL + 1))
    fi
}

#===============================================================================
# 主流程
#===============================================================================

echo ""
echo "============================================================"
echo "  数据库增量备份"
echo "  同步日期: ${SYNC_DAY}"
echo "  同步时间: ${SYNC_DATETIME}"
echo "  输出文件: ${OUTPUT_FILE}"
echo "============================================================"
echo ""

# 确保备份目录存在
mkdir -p "${BACKUP_DIR}"

# 清空/创建输出文件
> "${OUTPUT_FILE}"

echo "开始备份..."
echo ""

# ===========================
# 数据库: yltrs_ylcms (17张表)
# ===========================
echo "--- yltrs_ylcms ---"

do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "trade"                      "OptDate >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "trade_cash"                 "ValueDate = '{交易日}' OR OptDate >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "trade_extend"               "update_time >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "trade_span"                 "OptDate >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "trade_contract_r"           "OptDate >= '{上次同步时间}'"

do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "swap_position"              "OptTime >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "swap_flow"                  "OptTime >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "swap_flow_deal"             "OptTime >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "swap_flow_event"            "EventDate = '{交易日}' OR OptTime >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "swap_event"                 "ValueDate = '{交易日}' OR OptTime >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "swap_rate"                  "opt_time >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "swap_float_rate"            "opt_time >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "swap_rate_log"              "opt_time >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "swap_fund_account"          ""   # 全量
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "dma_margin_record"          "OptTime >= '{上次同步时间}'"

do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "trade_contract_document"    "ValueDate = '{交易日}' OR OptDate >= '{上次同步时间}'"
do_backup "${DB1_HOST}" "${DB1_PORT}" "${DB1_USER}" "${DB1_PASS}" "${DB1_NAME}" "clientcashincashout"        "HappenDate = '{交易日}' OR CreateDate >= '{上次同步时间}'"

# ===========================
# 数据库: bond_oms (9张表)
# ===========================
echo ""
echo "--- bond_oms ---"

do_backup "${DB2_HOST}" "${DB2_PORT}" "${DB2_USER}" "${DB2_PASS}" "${DB2_NAME}" "client_order"               "create_time >= '{上次同步时间}'"
do_backup "${DB2_HOST}" "${DB2_PORT}" "${DB2_USER}" "${DB2_PASS}" "${DB2_NAME}" "client_deal"                "create_time >= '{上次同步时间}'"
do_backup "${DB2_HOST}" "${DB2_PORT}" "${DB2_USER}" "${DB2_PASS}" "${DB2_NAME}" "hedge_order"                "create_time >= '{上次同步时间}'"
do_backup "${DB2_HOST}" "${DB2_PORT}" "${DB2_USER}" "${DB2_PASS}" "${DB2_NAME}" "hedge_deal"                 "create_time >= '{上次同步时间}'"
do_backup "${DB2_HOST}" "${DB2_PORT}" "${DB2_USER}" "${DB2_PASS}" "${DB2_NAME}" "qt_order_info"              "create_time >= '{上次同步时间}'"
do_backup "${DB2_HOST}" "${DB2_PORT}" "${DB2_USER}" "${DB2_PASS}" "${DB2_NAME}" "order_operate_log"          "create_time >= '{上次同步时间}'"
do_backup "${DB2_HOST}" "${DB2_PORT}" "${DB2_USER}" "${DB2_PASS}" "${DB2_NAME}" "order_record_unwind_detail" "update_time >= '{上次同步时间}'"
do_backup "${DB2_HOST}" "${DB2_PORT}" "${DB2_USER}" "${DB2_PASS}" "${DB2_NAME}" "client_swap_confirm_log"    "opt_time >= '{上次同步时间}'"
do_backup "${DB2_HOST}" "${DB2_PORT}" "${DB2_USER}" "${DB2_PASS}" "${DB2_NAME}" "client_order_swap_record"   "create_time >= '{上次同步时间}'"

#===============================================================================
# 汇总
#===============================================================================
echo ""
echo "============================================================"
echo "  备份完成"
echo "============================================================"
echo "  总表数: ${TOTAL}"
echo "  成功:   ${SUCCESS}"
echo "  失败:   ${FAIL}"
echo "  文件:   ${OUTPUT_FILE}"
echo "  大小:   $(du -h "${OUTPUT_FILE}" | cut -f1)"
echo "============================================================"

if [ ${FAIL} -gt 0 ]; then
    exit 1
fi
exit 0

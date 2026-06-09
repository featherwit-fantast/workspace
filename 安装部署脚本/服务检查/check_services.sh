#!/bin/bash

# 日志文件路径
LOG_FILE="./service_check.log"

# 定义颜色
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"   # 无颜色

# 要检查的服务及端口（空表示不检查端口）
declare -A SERVICES=(
    ["YLErpWeb"]="8888"
    ["client-app"]="8886"
    ["hedge-app"]="8887"
    ["reg-app"]="8889"
    ["xxl-job"]="8884"
    ["bond-sync"]="8879"
    ["bond-calc"]=""
    ["RealTimeCalcPositionService"]=""
)

# 获取当前时间
NOW=$(date "+%Y-%m-%d %H:%M:%S")
echo -e "\n========= 服务检查 [$NOW] =========" | tee -a "$LOG_FILE"

# 异常计数器
ERROR_COUNT=0

for SERVICE in "${!SERVICES[@]}"; do
    PORT=${SERVICES[$SERVICE]}
    STATUS_MSG=""

    # 检查进程
    if pgrep -f "$SERVICE" > /dev/null; then
        STATUS_MSG+="进程:${GREEN}正常${NC} "
    else
        STATUS_MSG+="进程:${RED}未启动${NC} "
        ((ERROR_COUNT++))
    fi

    # 检查端口（如果配置了端口）
    if [[ -n "$PORT" ]]; then
        if netstat -tuln 2>/dev/null | grep -q ":$PORT"; then
            STATUS_MSG+="端口(${PORT}):${GREEN}正常${NC}"
        else
            STATUS_MSG+="端口(${PORT}):${RED}未监听${NC}"
            ((ERROR_COUNT++))
        fi
    fi

    # 每条结果加上时间
    TIME_NOW=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[$TIME_NOW] ▶ $SERVICE : $STATUS_MSG" | tee -a "$LOG_FILE"
done

# 输出统计结果
if [[ $ERROR_COUNT -eq 0 ]]; then
    echo -e "[$NOW] 检查结果: ${GREEN}全部正常${NC}" | tee -a "$LOG_FILE"
else
    echo -e "[$NOW] 检查结果: ${YELLOW}异常数量 ${ERROR_COUNT}${NC}" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
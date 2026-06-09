#!/bin/bash
# 文件名：service_watcher.sh

# ===== 配置区域 =====
declare -A services=(
    ["YLErpWeb"]="8888"
    ["client-app"]="8886"     
    ["hedge-app"]="8887"
    ["reg-app"]="8889"	             
    ["RealTimeCalcPositionService"]=""
	["mock-commodity"]=""
	["xxl-job"]="8884"
	["calc"]="8080"
	["bond-sync"]="8879"
    ["mysql"]="3306"
	["nginx"]="80"
	["zookeeper"]="2181"
	["redis"]="6379"
	["kafka"]="9092"
)

# 日志文件配置
LOG_DIR="/home/service_watcher"  # 日志目录
LOG_FILE="$LOG_DIR/service_monitor.log"  # 日志文件
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 最大日志大小10MB
LOG_RETENTION=30                    # 日志保留天数

#接收报警的邮箱
RECIPIENT="13522127643@163.com"
#邮件标题
SUBJECT="TRS服务告警"

# 检查mailx命令是否存在
if ! command -v mailx >/dev/null 2>&1; then
    if ! rpm -ivh mailx-12.5-19.el7.x86_64.rpm  >/dev/null 2>&1; then
        echo "错误：mailx安装失败！请手动安装" >&2
        exit 1
    fi
    echo "mailx安装完成"
fi

# ===== 初始化日志系统 =====
init_logging() {
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    # 设置日志文件权限
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log "===== 服务监控守护进程启动 ====="
    log "进程PID: $$"
    log "日志文件: $LOG_FILE"
    log "最大日志大小: $((MAX_LOG_SIZE/1024/1024))MB"
    log "日志保留天数: $LOG_RETENTION"
    log "==============================="
}

# ===== 日志记录函数 =====
log() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # 检查日志轮转
    if [ -f "$LOG_FILE" ] && [ $(stat -c %s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        rotate_log
    fi
    
    # 写入日志文件
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# ===== 日志轮转 =====
rotate_log() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local rotated_log="$LOG_DIR/service_monitor_$timestamp.log"
    
    # 轮转当前日志
    mv "$LOG_FILE" "$rotated_log"
    
    # 创建新日志文件
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # 清理旧日志
    find "$LOG_DIR" -name "service_monitor_*.log" -mtime +$LOG_RETENTION -delete
    
    log "日志轮转完成: $rotated_log"
}

# ===== 检查端口是否监听 =====
check_port_listening() {
    local port=$1   
    #使用 netstat
	if netstat -tuln | grep -q ":$port"; then
        return 0
    else
        return 1
    fi
}

# ===== 服务健康检查 =====
check_service_health() {
    local service_name=$1
    local port=$2
    
    log "检查服务: ${service_name}"
    
    # 状态跟踪变量
    local port_ok=0
    local process_ok=0
    
    # ===== 1. 端口检查（如果配置了端口） =====
    if [[ -n "$port" ]]; then
        log "  ├─ 端口检测: ${port}"
        if check_port_listening "$port"; then
            log "  │  [成功] 端口监听正常"
            port_ok=1
        else
            log "  │  [严重] 端口未监听!"
        fi
    else
        log "  ├─ 跳过端口检测（未配置）"
        port_ok=1  # 无端口要求视为通过
    fi
    
    # ===== 2. 进程检查 =====
    log "  └─ 进程检测"
    # 简化进程检测
    if pgrep -f "$service_name" >/dev/null; then
        log "     [成功] 进程运行中"
        process_ok=1
    else
        log "     [严重] 进程不存在!"
    fi
    
    # ===== 结果判断 =====
    if [[ $port_ok -eq 1 && $process_ok -eq 1 ]]; then
        return 0  # 完全健康
    elif [[ -n "$port" && $port_ok -eq 0 ]]; then
        return 1  # 端口问题
    elif [[ $process_ok -eq 0 ]]; then
        return 2  # 进程问题
    else
        return 3  # 未知状态
    fi
}

# ===== 主函数 =====
main() {
    # 初始化日志系统
    init_logging
    
    # 主监控循环
    while true; do
        log "============================================"
        log "服务健康检查 - $(date +"%Y-%m-%d %H:%M:%S")"
        log "============================================"
        
        for service_name in "${!services[@]}"; do
            port="${services[$service_name]}"
            
            check_service_health "$service_name" "$port"
            status=$?
            
            # 根据状态码处理问题
            case $status in
                0) 
                    log ">> 服务状态: 健康"
                    ;;
                1) 
                    log ">> 警告: 端口异常 - ${service_name}"
					echo "警告：$service_name服务的$port端口异常,时间：$(date +"%Y-%m-%d %H:%M:%S")" | mailx -s "$SUBJECT" $RECIPIENT
                    # 自动恢复示例:
                    # log ">> 尝试重启服务..."
                    # systemctl restart ${service_name}
                    ;;
                2) 
                    log ">> 警告: 进程丢失 - ${service_name}"
					echo "警告：$service_name服务进程丢失,时间：$(date +"%Y-%m-%d %H:%M:%S")" | mailx -s "$SUBJECT" $RECIPIENT
                    # 自动恢复示例:
                    # log ">> 尝试启动服务..."
                    # systemctl start ${service_name}
                    ;;
                *) 
                    log ">> 未知状态: ${service_name} (代码: $status)"
					echo "警告：$service_name服务未知状态,请检查,时间：$(date +"%Y-%m-%d %H:%M:%S")" | mailx -s "$SUBJECT" $RECIPIENT
                    ;;
            esac
            
            log "--------------------------------------------"
        done
        
        # 下次检查间隔（秒）
        sleep 60
    done
}

# 启动主函数
main
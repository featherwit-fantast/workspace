#!/bin/bash
set -euo pipefail

WORK_DIR=$(cd "$(dirname "$0")" && pwd)   # 脚本所在目录
DOTNET_BIN="/usr/local/dotnet/dotnet"      # dotnet 可执行文件路径
ASPNETCORE_ENVIRONMENT="dev"               # 运行环境: dev / test / production
PORT=8888                                  # Web 服务监听端口
LOG_ENABLED=true                           # 是否输出日志: true / false
PID_FILE="$WORK_DIR/1.pid"                 # PID 文件路径
LOG_FILE="$WORK_DIR/service.log"           # 日志文件路径

# ===== 限定识别的服务文件 =====
VALID_DLLS=(
    "YieldChain.CalcPlatform.Web.dll"
    "YLErpWeb.dll"
    "YLWebAPI.dll"
    "YLManageAPI.dll"
    "SmartTradingWeb.dll"
    "RealTimeCalcPositionService.dll"
)

EXEC_FILE=""
for dll in "${VALID_DLLS[@]}"; do
    if [ -f "$WORK_DIR/$dll" ]; then
        EXEC_FILE="$WORK_DIR/$dll"
        SERVICE_NAME="$dll"
        break
    fi
done

if [ -z "$EXEC_FILE" ]; then
    echo "❌ 当前目录未检测到可识别的服务文件"
    echo "可识别的文件包括:"
    for d in "${VALID_DLLS[@]}"; do
        echo "  - $d"
    done
    exit 1
fi

clean_files() {
    [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
}

clean_log() {
    if [ "$LOG_ENABLED" = "true" ]; then
        : > "$LOG_FILE"
    fi
}

is_web_service() {
    [ "$SERVICE_NAME" != "RealTimeCalcPositionService.dll" ]
}

start() {
    clean_log

    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "⚠️ 服务已在运行 (PID=$(cat $PID_FILE))"
        exit 1
    fi

    [ ! -x "$DOTNET_BIN" ] && { echo "❌ dotnet 不存在"; exit 1; }

    if [ "$LOG_ENABLED" = "true" ]; then
        LOG_OUT="$LOG_FILE"
    else
        LOG_OUT="/dev/null"
    fi

    export ASPNETCORE_ENVIRONMENT="$ASPNETCORE_ENVIRONMENT"

    if is_web_service; then
        echo "▶️ 启动 Web 服务: $SERVICE_NAME (端口: $PORT)"
        nohup "$DOTNET_BIN" "$EXEC_FILE" --urls="http://*:$PORT" >"$LOG_OUT" 2>&1 &
    else
        echo "▶️ 启动后台服务: $SERVICE_NAME"
        nohup "$DOTNET_BIN" "$EXEC_FILE" >"$LOG_OUT" 2>&1 &
    fi

    echo $! > "$PID_FILE"
    sleep 1
    if kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "✅ 启动成功 (PID=$(cat $PID_FILE))"
        if [ "$LOG_ENABLED" = "true" ]; then
            echo "日志文件: $LOG_FILE"
        fi
    else
        echo "❌ 启动失败，进程已退出"
        rm -f "$PID_FILE"
        exit 1
    fi
}

stop() {
    clean_log

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 $PID 2>/dev/null; then
            echo "⏹️ 停止服务: $SERVICE_NAME (PID=$PID)"
            kill $PID 2>/dev/null || true
            sleep 1
            if kill -0 $PID 2>/dev/null; then
                echo "⚠️ 进程未响应 SIGTERM，强制终止..."
                kill -9 $PID 2>/dev/null || true
                sleep 1
            fi
        else
            echo "⚠️ PID 文件存在但进程已结束"
        fi
    else
        echo "⚠️ 服务未在运行"
    fi
    clean_files
    echo "✅ 已停止"
}

restart() {
    stop
    sleep 1
    start
}
usage() {
    echo "用法:"
    echo "  $0 start     启动服务"
    echo "  $0 stop      停止服务"
    echo "  $0 restart   重启服务"
    echo
    echo "说明:"
    echo "  自动检测目录下的目标服务:"
    for d in "${VALID_DLLS[@]}"; do
        echo "    - $d"
    done
    echo "  端口: $PORT"
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    *) usage ;;
esac

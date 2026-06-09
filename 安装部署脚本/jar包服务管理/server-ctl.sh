#!/bin/bash
set -euo pipefail

WORK_DIR=$(cd "$(dirname "$0")" && pwd)   # 脚本所在目录
LOG_ENABLED=true                           # 是否输出日志: true / false
PID_FILE="$WORK_DIR/1.pid"                 # PID 文件路径
LOG_FILE="$WORK_DIR/service.log"           # 日志文件路径

# ===== Java 配置 =====
JAVA_HOME="/usr/local/jdk/bin/java"        # Java 可执行文件路径
JAVA_OPTS="-Xms1024m -Xmx2048m"           # JVM 启动参数

# ===== .NET 配置 =====
DOTNET_BIN="/usr/local/dotnet/dotnet"      # dotnet 可执行文件路径
ASPNETCORE_ENVIRONMENT="dev"               # 运行环境: dev / test / production
PORT=8888                                  # Web 服务监听端口
NON_WEB_DLL="RealTimeCalcPositionService.dll"  # 不需要 --urls 的后台服务

# ===== 扫描服务文件（有且仅有一个） =====
shopt -s nullglob
JAR_FILES=("$WORK_DIR"/*.jar)
DLL_FILES=("$WORK_DIR"/*.dll)
shopt -u nullglob

JAR_COUNT=${#JAR_FILES[@]}
DLL_COUNT=${#DLL_FILES[@]}
TOTAL=$((JAR_COUNT + DLL_COUNT))

if [ "$TOTAL" -eq 0 ]; then
    echo "❌ 当前目录未检测到服务文件 (.jar / .dll)"
    exit 1
elif [ "$TOTAL" -gt 1 ]; then
    echo "❌ 当前目录存在多个服务文件："
    for f in "${JAR_FILES[@]}" "${DLL_FILES[@]}"; do
        echo "  - $(basename "$f")"
    done
    exit 1
fi

# 确定服务类型和文件
if [ "$JAR_COUNT" -eq 1 ]; then
    SERVICE_TYPE="java"
    EXEC_FILE="${JAR_FILES[0]}"
    SERVICE_NAME=$(basename "$EXEC_FILE")
elif [ "$DLL_COUNT" -eq 1 ]; then
    SERVICE_TYPE="dotnet"
    EXEC_FILE="${DLL_FILES[0]}"
    SERVICE_NAME=$(basename "$EXEC_FILE")
fi

# ===== 通用函数 =====
clean_files() {
    [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
}

clean_log() {
    if [ "$LOG_ENABLED" = "true" ]; then
        : > "$LOG_FILE"
    fi
}

is_web_service() {
    [ "$SERVICE_NAME" != "$NON_WEB_DLL" ]
}

# ===== 启动 =====
start() {
    clean_log

    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "⚠️ 服务已在运行 (PID=$(cat $PID_FILE))"
        exit 1
    fi

    if [ "$LOG_ENABLED" = "true" ]; then
        LOG_OUT="$LOG_FILE"
    else
        LOG_OUT="/dev/null"
    fi

    if [ "$SERVICE_TYPE" = "java" ]; then
        [ ! -x "$JAVA_HOME" ] && { echo "❌ JAVA_HOME 错误: $JAVA_HOME"; exit 1; }
        echo "▶️ 启动 Java 服务: $SERVICE_NAME"
        nohup $JAVA_HOME $JAVA_OPTS \
            -Dloader.path="$WORK_DIR/lib/" \
            -jar "$EXEC_FILE" \
            --spring.config.location="$WORK_DIR/config/" \
            >"$LOG_OUT" 2>&1 &

    elif [ "$SERVICE_TYPE" = "dotnet" ]; then
        [ ! -x "$DOTNET_BIN" ] && { echo "❌ dotnet 不存在: $DOTNET_BIN"; exit 1; }
        export ASPNETCORE_ENVIRONMENT="$ASPNETCORE_ENVIRONMENT"
        if is_web_service; then
            echo "▶️ 启动 Web 服务: $SERVICE_NAME (端口: $PORT)"
            nohup "$DOTNET_BIN" "$EXEC_FILE" --urls="http://*:$PORT" >"$LOG_OUT" 2>&1 &
        else
            echo "▶️ 启动后台服务: $SERVICE_NAME"
            nohup "$DOTNET_BIN" "$EXEC_FILE" >"$LOG_OUT" 2>&1 &
        fi
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

# ===== 停止 =====
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

# ===== 重启 =====
restart() {
    stop
    sleep 1
    start
}

# ===== 帮助 =====
usage() {
    echo "用法: $0 {start|stop|restart}"
    echo "服务: $SERVICE_NAME ($SERVICE_TYPE)"
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    *) usage ;;
esac

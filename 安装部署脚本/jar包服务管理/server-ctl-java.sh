#!/bin/bash
set -euo pipefail

WORK_DIR=$(cd "$(dirname "$0")" && pwd)   # 脚本所在目录
JAVA_HOME="/usr/local/jdk/bin/java"        # Java 可执行文件路径
JAVA_OPTS="-Xms1024m -Xmx2048m"           # JVM 启动参数
LOG_ENABLED=true                           # 是否输出日志: true / false
PID_FILE="$WORK_DIR/1.pid"                 # PID 文件路径
LOG_FILE="$WORK_DIR/service.log"           # 日志文件路径

# ==== 自动识别 jar ====
JAR_COUNT=$(ls "$WORK_DIR"/*.jar 2>/dev/null | wc -l)

if [ "$JAR_COUNT" -eq 1 ]; then
    EXEC_FILE=$(ls "$WORK_DIR"/*.jar)
else
    echo "❌ 未检测到 JAR 文件，或存在多个 JAR"
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

start() {
    clean_log

    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "⚠️ Java 服务已运行 (PID=$(cat $PID_FILE))"
        exit 1
    fi

    [ ! -x "$JAVA_HOME" ] && { echo "❌ JAVA_HOME 错误"; exit 1; }

    if [ "$LOG_ENABLED" = "true" ]; then
        LOG_OUT="$LOG_FILE"
    else
        LOG_OUT="/dev/null"
    fi

    echo "▶️ 启动 Java 服务: $EXEC_FILE"
    nohup $JAVA_HOME $JAVA_OPTS -Dloader.path="$WORK_DIR/lib/" -jar "$EXEC_FILE" --spring.config.location="$WORK_DIR/config/" >"$LOG_OUT" 2>&1 &

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
            echo "⏹️ 停止 Java 服务 (PID=$PID)"
            kill $PID 2>/dev/null || true
            sleep 1
            if kill -0 $PID 2>/dev/null; then
                echo "⚠️ 进程未响应 SIGTERM，强制终止..."
                kill -9 $PID 2>/dev/null || true
                sleep 1
            fi
        else
            echo "⚠️ PID 文件存在但进程已不存在"
        fi
    else
        echo "⚠️ Java 服务未运行"
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
    echo "用法: $0 {start|stop|restart}"
    echo "执行文件: $EXEC_FILE"
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    *) usage ;;
esac

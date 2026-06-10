#!/bin/bash

# ================================================================
# 系统回滚脚本 (System Rollback Script)
#
# 功能：自动化执行系统回滚流程，包括停止服务、还原上一版本和启动服务
# Function: Automate the system rollback process, including stopping services,
#           restoring previous version and starting services
# ================================================================

# 设置环境变量 (Set environment variables)
BACKUP_DIR="/home/backup"
APP_HOME="/home"
NGINX_HOME="/usr/local/nginx"
DB_HOST="localhost"
DB_PORT="3306"
DB_NAME="root"
DB_PASSWD="D@tasu2e"
LOG_FILE="/var/log/ubs/rollback_$(date +%Y%m%d_%H%M%S).log"

# 创建日志目录 (Create log directory)
mkdir -p $(dirname $LOG_FILE)

# 日志函数 (Logging function)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# 检查命令执行状态 (Check command execution status)
check_status() {
    if [ $? -eq 0 ]; then
        log "SUCCESS: $1"
    else
        log "ERROR: $1"
        log "回滚失败，请查看日志获取详细信息。(Rollback failed, please check logs for details.)"
        exit 1
    fi
}

# 获取最近的备份目录 (Get the most recent backup directory)
get_latest_backup() {
    latest_backup=$(ls -td $BACKUP_DIR/*/ | head -1)
    if [ -z "$latest_backup" ]; then
        log "ERROR: 未找到可用的备份 (No available backup found)"
        exit 1
    fi
    echo $latest_backup
}

# 1. 停止服务 (Stop services)
stop_services() {

    log "停止管理端服务... (Stopping frontend services...)"
    systemctl stop otc
    check_status "停止管理端服务 (Stop otc service)"

    log "停止客户端服务... (Stopping frontend services...)"
    systemctl stop client
    check_status "停止客户端服务 (Stop client service)"

    log "所有服务已停止 (All services stopped)"
}

# 2. 检查服务是否已全部停止 (Check if all services are stopped)
check_services_stopped() {
    log "检查服务是否已全部停止... (Checking if all services are stopped...)"

    services=("otc" "client")

    for restart.sh in "${services[@]}"; do
        status=$(systemctl is-active $service)
        if [ "$status" == "active" ]; then
            log "ERROR: $service 服务仍在运行，尝试强制停止... ($service service is still running, trying to force stop...)"
            systemctl kill -s SIGKILL $service
            sleep 2

            status=$(systemctl is-active $service)
            if [ "$status" == "active" ]; then
                log "ERROR: 无法停止 $service 服务，回滚中止 (Cannot stop $service service, rollback aborted)"
                exit 1
            fi
        fi
    done

    log "所有服务已确认停止 (All services confirmed stopped)"
}

# 3. 还原上一个版本 (Restore previous version)
restore_previous_version() {
    log "开始还原上一个版本... (Starting to restore previous version...)"

         unalias cp

    # 获取最近的备份目录 (Get the most recent backup directory)
    latest_backup=$(get_latest_backup)
    log "使用备份: $latest_backup (Using backup: $latest_backup)"

    # 还原管理端 (Restore application binaries)
    log "还原管理端... (Restoring application binaries...)"
    cp -rf $latest_backup/YLErpWeb/* $APP_HOME/YLErpWeb/
    check_status "还原管理端 (Restore application binaries)"

    # 还原客户端 (Restore application binaries)
    log "还原客户端... (Restoring application binaries...)"
    cp -rf $latest_backup/client-app/* $APP_HOME/client-app/
    check_status "还原客户端 (Restore application binaries)"

    # 更新前端html文件 (Update configuration files)
    log "更新前端html文件... (Updating configuration files...)"
    cp -rf $latest_backup/nginx/html/*  $NGINX_HOME/html/
    check_status "更新前端html文件 (Update configuration files)"

    # 更新前端配置文件 (Update configuration files)
    log "更新前端配置文件... (Updating configuration files...)"
    cp -rf $latest_backup/nginx/conf/*  $NGINX_HOME/conf/
    check_status "更新前端配置文件 (Update configuration files)"

    log "上一个版本还原完成 (Previous version restoration completed)"
}

# 4. 执行数据库回滚脚本 (Execute database rollback scripts)
rollback_database() {
    log "开始执行数据库回滚脚本... (Starting to execute database rollback scripts...)"

    # 获取最近的备份目录 (Get the most recent backup directory)
    latest_backup=$(get_latest_backup)
    datetime=$(date +%Y%m%d_%H%M%S)
    # 1. 备份当前数据库的数据 (Backup incremental data in current database)
    log "备份当前数据库的数据... (Backing up incremental data in current database...)"
    mysqldump -h $DB_HOST -P $DB_PORT -u$DB_NAME -p$DB_PASSWD --single-transaction --set-gtid-purged=OFF --routines --triggers --events yltrs_ylcms variety > $BACKUP_DIR/database_rollback-$datetime.sql
    # 2. 还原数据库 (Restore database)
    log "还原数据库... (Restoring database...)"
    mysql -h $DB_HOST -P $DB_PORT -u$DB_NAME -p$DB_PASSWD yltrs_ylcms  < $latest_backup/db/database_backup.sql
    check_status "还原数据库 (Restore database)"

    log "数据库回滚完成 (Database rollback completed)"
}

# 5. 启动服务 (Start services)
start_services() {
    log "开始启动服务... (Starting to start services...)"

    systemctl start otc
    check_status "启动管理端服务 (Start trade service)"

    systemctl start client
    check_status "启动客户端服务 (Start client service)"

    log "启动前端服务... (Starting frontend services...)"
    systemctl restart nginx
    check_status "启动Nginx服务 (Start Nginx service)"

    log "所有服务已启动 (All services started)"
}

# 6. 检查服务是否正常运行 (Check if services are running normally)
check_services_running() {
    log "检查服务是否正常运行... (Checking if services are running normally...)"

    services=("nginx" "otc" "client" "mysqld" "kafka" "keepalived")

    for restart.sh in "${services[@]}"; do
        status=$(systemctl is-active $service)
        if [ "$status" != "active" ]; then
            log "ERROR: $service 服务未正常运行，回滚可能不完整 ($service service is not running normally, rollback may be incomplete)"
            exit 1
        fi
    done

    log "所有服务运行正常 (All services are running normally)"
}

# 主函数 (Main function)
main() {
    log "========== 开始系统回滚流程 (Starting system rollback process) =========="

    # 执行回滚步骤 (Execute rollback steps)
    stop_services
    check_services_stopped
    restore_previous_version
   # rollback_database
    start_services
    check_services_running

    log "========== 系统回滚成功完成 (System rollback successfully completed) =========="
}

# 执行主函数 (Execute main function)
main

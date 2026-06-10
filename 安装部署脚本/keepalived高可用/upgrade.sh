#!/bin/bash

# ================================================================
# 系统升级脚本 (System Upgrade Script)
#
# 功能：自动化执行系统升级流程，包括停止服务、备份、部署新版本和启动服务
# Function: Automate the system upgrade process, including stopping services,
#           backup, deploying new version and starting services
# ================================================================

# 设置环境变量 (Set environment variables)
APP_HOME="/home"
NGINX_HOME="/usr/local/nginx"
BACKUP_DIR="/home/backup/$(date +%Y%m%d_%H%M%S)"
NEW_VERSION_DIR="/home/update"
LOG_FILE="/home/update/upgrade_$(date +%Y%m%d_%H%M%S).log"
DB_HOST="localhost"
DB_PORT="3306"
DB_NAME="root"
DB_PASSWD="D@tasu2e"


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
        log "升级失败，请查看日志获取详细信息。(Upgrade failed, please check logs for details.)"
        exit 1
    fi
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
    log "检查服务是否已停止... (Checking if all services are stopped...)"
        services=("otc" "client")
        for restart.sh in "${services[@]}"; do
        status=$(systemctl is-active $service)
        if [ "$status" == "active" ]; then
            log "ERROR: $service 服务仍在运行，尝试强制停止... ($service service is still running, trying to force stop...)"
            systemctl kill -s SIGKILL $service
            sleep 2

            status=$(systemctl is-active $service)
            if [ "$status" == "active" ]; then
                log "ERROR: 无法停止 $service 服务，升级中止 (Cannot stop $service service, upgrade aborted)"
                exit 1
            fi
        fi
    done
    log "所有服务已确认停止 (All services confirmed stopped)"
}

# 3. 备份当前版本 (Backup current version)
backup_current_version() {
    log "开始备份当前版本... (Starting to backup current version...)"

    # 创建备份目录 (Create backup directory)
    mkdir -p $BACKUP_DIR/{nginx,db}
    check_status "创建备份目录 (Create backup directory)"

    # 备份管理端 (Backup configuration files)
    log "备份管理端... (Backing up configuration files...)"
    cp -rf $APP_HOME/YLErpWeb  $BACKUP_DIR/
    check_status "备份管理端 (Backup configuration files)"

    # 备份客户端 (Backup configuration files)
    log "备份客户端... (Backing up configuration files...)"
    cp -rf $APP_HOME/client-app  $BACKUP_DIR/
    check_status "备份客户端 (Backup configuration files)"

        # 备份前端html文件 (Backup configuration files)
    log "备份前端html文件... (Backing up configuration files...)"
    cp -rf $NGINX_HOME/html  $BACKUP_DIR/nginx/
    check_status "备份前端html文件 (Backup configuration files)"

        # 备份前端配置文件 (Backup configuration files)
    log "备份前端配置文件... (Backing up configuration files...)"
    cp -rf $NGINX_HOME/conf  $BACKUP_DIR/nginx/
    check_status "备份前端html (Backup configuration files)"

    # 备份数据库 (Backup database)
   # log "备份数据库... (Backing up database...)"
   # mysqldump -h $DB_HOST -P $DB_PORT -u$DB_NAME -p$DB_PASSWD --single-transaction --set-gtid-purged=OFF --routines --triggers --events yltrs_ylcms variety > $BACKUP_DIR/db/database_backup.sql
   # check_status "备份数据库 (Backup database)"
    log "备份完成 (Backup completed)"
}

# 4. 部署新版本 (Deploy new version)
deploy_new_version() {
    log "开始部署新版本... (Starting to deploy new version...)"

    unalias cp

    # 复制新版本管理端 (Copy new version binaries)
    log "部署新版本管理端... (Deploying new version binaries...)"
    cp -rf $NEW_VERSION_DIR/YLErpWeb/* $APP_HOME/YLErpWeb/
    check_status "部署新版本管理端 (Deploy new version binaries)"

    # 复制新版本客户端 (Copy new version binaries)
    log "部署新版本客户端... (Deploying new version binaries...)"
    cp -rf $NEW_VERSION_DIR/client-app/* $APP_HOME/client-app/
    check_status "部署新版本管理端 (Deploy new version binaries)"

    # 更新前端html文件 (Update configuration files)
    log "更新前端html文件... (Updating configuration files...)"
    cp -rf $NEW_VERSION_DIR/nginx/html/*  $NGINX_HOME/html/
    check_status "更新前端html文件 (Update configuration files)"

    # 更新前端配置文件 (Update configuration files)
    log "更新前端配置文件... (Updating configuration files...)"
    cp -rf $NEW_VERSION_DIR/nginx/conf/*  $NGINX_HOME/conf/
    check_status "更新前端配置文件 (Update configuration files)"

    log "新版本部署完成 (New version deployment completed)"
}

# 5. 执行数据库升级脚本 (Execute database upgrade scripts)
upgrade_database() {
    log "开始执行数据库升级脚本... (Starting to execute database upgrade scripts...)"

    # 执行SQL升级脚本 (Execute SQL upgrade scripts)
    log "执行SQL升级脚本... (Executing SQL upgrade scripts...)"
    mysql -h $DB_HOST -P $DB_PORT -u$DB_NAME -p$DB_PASSWD yltrs_ylcms < $NEW_VERSION_DIR/db/database_backup.sql 2>&1
    check_status "执行SQL升级脚本 (Execute SQL upgrade scripts)"

    log "数据库升级完成 (Database upgrade completed)"


}

# 6. 启动服务 (Start services)
start_services() {
    log "开始启动服务... (Starting to start services...)"

    systemctl start otc
    check_status "启动管理端服务 (Start trade service)"

    systemctl start client
    check_status "启动客户端服务 (Start trade service)"


    log "启动前端服务... (Starting frontend services...)"
    systemctl restart nginx
    check_status "启动Nginx服务 (Start Nginx service)"

    log "所有服务已启动 (All services started)"
}

# 7. 检查服务是否正常运行 (Check if services are running normally)
check_services_running() {
    log "检查服务是否正常运行... (Checking if services are running normally...)"

    services=("nginx" "otc" "client" "mysqld" "kafka" "keepalived")

    for restart.sh in "${services[@]}"; do
        status=$(systemctl is-active $service)
        if [ "$status" != "active" ]; then
            log "ERROR: $service 服务未正常运行，升级可能不完整 ($service service is not running normally, upgrade may be incomplete)"
            exit 1
        fi
    done


    log "所有服务运行正常 (All services are running normally)"
}

move_update_file(){
# 更简化的版本（直接保留脚本文件）
datetime="$NEW_VERSION_DIR/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$datetime" || exit 1

# 移动所有内容到备份目录（脚本除外）
find "$NEW_VERSION_DIR" -maxdepth 1 -mindepth 1 \
     ! -name "$(basename "$datetime")" \
     ! -name 'rollback.sh' \
     ! -name 'upgrade.sh' \
     -exec mv -t "$datetime" {} +
     echo  "更新文件已全部移动到:$datetime"
}

# 主函数 (Main function)
main() {
    log "========== 开始系统升级流程 (Starting system upgrade process) =========="

    # 执行升级步骤 (Execute upgrade steps)
    stop_services
    check_services_stopped
    backup_current_version
    deploy_new_version
   # upgrade_database
    start_services
    check_services_running
    log "========== 系统升级成功完成 (System upgrade successfully completed) =========="
    move_update_file
}

# 执行主函数 (Execute main function)
main
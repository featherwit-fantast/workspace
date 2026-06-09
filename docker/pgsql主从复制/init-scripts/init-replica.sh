#!/bin/bash
set -e

DATA_DIR="/var/lib/postgresql/data"
PGPASS="/var/lib/postgresql/.pgpass"

# 创建 .pgpass 避免 pg_basebackup 输入密码
echo "pg-primary:5432:replication:replica_user:123456" > "$PGPASS"
chmod 600 "$PGPASS"
export PGPASSFILE="$PGPASS"

# 如果 standby.signal 不存在，则初始化从库
if [ ! -f "$DATA_DIR/standby.signal" ]; then
    echo "初始化从库数据..."
    rm -rf "$DATA_DIR"/*
    until pg_basebackup -h pg-primary -U replica_user -D "$DATA_DIR" -v -P --wal-method=stream; do
        echo "等待主库可用进行同步..."
        sleep 2
    done
    touch "$DATA_DIR/standby.signal"
    echo "primary_conninfo='host=pg-primary port=5432 user=replica_user password=123456'" >> "$DATA_DIR/postgresql.auto.conf"

    # 允许所有 IP 外部连接
    echo "host all all 0.0.0.0/0 md5" >> "$DATA_DIR/pg_hba.conf"
fi

# 使用官方推荐用户启动 PostgreSQL
exec postgres -c listen_addresses='*' -c hot_standby=on
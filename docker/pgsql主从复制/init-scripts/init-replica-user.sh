#!/bin/bash
set -e

# 等待 PostgreSQL 启动
until pg_isready -U "$POSTGRES_USER"; do
  echo "等待 PostgreSQL 启动..."
  sleep 2
done

# 创建复制用户
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" <<-EOSQL
DO
\$do\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replica_user') THEN
      CREATE ROLE replica_user WITH REPLICATION LOGIN PASSWORD '123456';
   END IF;
END
\$do\$;
EOSQL

# 配置 pg_hba.conf 允许复制
PG_HBA="/var/lib/postgresql/data/pg_hba.conf"
if ! grep -q "replica_user" "$PG_HBA"; then
  echo "host replication replica_user 0.0.0.0/0 md5" >> "$PG_HBA"
fi
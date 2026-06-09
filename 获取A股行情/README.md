# A股实时行情采集

## 快速开始

```bash
# 安装依赖（仅首次）
pip install pymysql requests akshare

# 1. 同步代码列表（增量，已有不动）
python3.7 sync_codes.py

# 2. 更新行情（日常执行）
python3.7 tencent.py
```

## 脚本说明

| 脚本 | 用途 | 频率 |
|------|------|------|
| `sync_codes.py` | AkShare 拉取全量标的列表，与 DB 比对后增量新增 | 按需（新上市标的较多时跑一次） |
| `tencent.py` ★ | 腾讯接口批量查行情，10 秒全量更新 | 日常 |
| `sina.py` | 新浪接口，备选 | 腾讯不可用时 |

## 数据流程

```
sync_codes.py:
  AkShare API → 拉全量代码（A股 + ETF） → 比对 DB → 增量写入
         │
         ▼
  stock_quotes 表（代码列表）
         │
         ▼
tencent.py / sina.py:
  DB 读代码 → 批量查行情 → 写回 stock_quotes
```

## 数据覆盖

| 品种 | 代码段 | 数量 |
|------|--------|------|
| 沪市主板 | 60xxxx, 603xxx... | ~1,840 |
| 科创板 | 688xxx | ~610 |
| 深市主板 | 000xxx, 002xxx... | ~1,640 |
| 创业板 | 300xxx, 301xxx | ~1,440 |
| 沪市ETF | 51xxxx, 512xxx... | ~850 |
| 深市ETF | 15xxxx, 16xxxx... | ~640 |
| 北交所 | 4xxxxx, 8xxxxx | ~250 |
| **合计** | | **~7,500** |

## 数据库

三脚本共用 `stock_quotes` 表：

```sql
CREATE TABLE IF NOT EXISTS `stock_quotes` (
  `stock_code`   VARCHAR(10)   NOT NULL COMMENT '股票代码',
  `stock_name`   VARCHAR(50)   NOT NULL COMMENT '股票名称',
  `market`       VARCHAR(20)   NOT NULL DEFAULT '' COMMENT '所属市场',
  `latest_price` DECIMAL(12,4) NOT NULL COMMENT '最新价',
  `change_pct`   DECIMAL(10,4) NOT NULL COMMENT '涨跌幅%',
  `change_amt`   DECIMAL(12,4) NOT NULL COMMENT '涨跌额',
  `volume`       BIGINT        NOT NULL COMMENT '成交量(手)',
  `amount`       DECIMAL(20,4) NOT NULL COMMENT '成交额(元)',
  `amplitude`    DECIMAL(10,4) NOT NULL COMMENT '振幅%',
  `high`         DECIMAL(12,4) NOT NULL COMMENT '最高',
  `low`          DECIMAL(12,4) NOT NULL COMMENT '最低',
  `open`         DECIMAL(12,4) NOT NULL COMMENT '开盘',
  `prev_close`   DECIMAL(12,4) NOT NULL COMMENT '昨收',
  `update_time`  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`stock_code`),
  INDEX `idx_market` (`market`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## 配置

修改脚本开头的 `DB_CONFIG`：

```python
DB_CONFIG = {
    'host': '192.168.0.220',   # 数据库 IP
    'port': 13306,              # 端口
    'user': 'DBAdmin',          # 用户名
    'password': 'YourPassword', # 密码
    'database': 'market',       # 库名
}
```

## 常见问题

| 现象 | 处理 |
|------|------|
| 腾讯 403 | 改用 `sina.py`，腾讯接口对该 IP 做了限制 |
| 新浪 403 | 改用 `tencent.py`，互备 |
| 数据库连接超时 | 检查服务器到 DB 网络 |
| 北交所行情拉不到 | 腾讯 `bj` 前缀不全，换 `sina.py` 试试 |
| AkShare 报错 | `pip install --upgrade akshare` 升级到最新版 |

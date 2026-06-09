#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
实时A股行情采集脚本（新浪数据源）
- 股票代码列表从数据库 stock_quotes 表直接读取
- 行情批量查询新浪接口，6~8 次请求覆盖全市场
- HTTP 明文，无需 token

注意：部分服务器 IP 可能被新浪限制（返回 403），此时请改用腾讯版。
"""

import requests
import pymysql
import time
import random
import logging
import sys
import re

# ======================== 配置区域 ========================
DB_CONFIG = {
    'host': '192.168.0.220',
    'port': 13306,
    'user': 'DBAdmin',
    'password': 'YieldChain$$2025',
    'database': 'market',
    'charset': 'utf8mb4',
    'autocommit': False
}

# 新浪行情接口
SINA_URL = "http://hq.sinajs.cn/list={codes}"

# 配置
SINA_BATCH = 800
REQUEST_TIMEOUT = 10
BATCH_SLEEP_MIN = 0.5
BATCH_SLEEP_MAX = 1.5
MAX_RETRIES = 3

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://finance.sina.com.cn/',
}

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# ======================== 数据清洗 ========================
def safe_float(value):
    if value is None or value == '' or value == '-':
        return 0.0
    try:
        return float(value)
    except (ValueError, TypeError):
        return 0.0

def safe_int(value):
    if value is None or value == '' or value == '-':
        return 0
    try:
        return int(float(value))
    except (ValueError, TypeError):
        return 0

def get_market_by_code(code):
    if not code:
        return u"未知"
    code = str(code)
    if code.startswith('6'):
        return u"科创板" if code.startswith('688') else u"沪市主板"
    if code.startswith('5'):
        return u"沪市ETF"
    if code.startswith(('0', '2', '3')):
        return u"创业板" if code.startswith(('300', '301')) else u"深市主板"
    if code.startswith('1'):
        return u"深市ETF"
    if code.startswith(('4', '8')):
        return u"北交所"
    return u"其他"

# ======================== 股票代码获取 ========================
def load_stock_codes_from_db(conn):
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT stock_code, stock_name FROM stock_quotes ORDER BY stock_code")
        rows = cursor.fetchall()
        if not rows:
            raise Exception(u"stock_quotes 表中无数据，请先跑一次 eastmoney.py 填充代码")
        codes = [(row[0], row[1]) for row in rows]
        logger.info(u"从数据库加载 %d 只股票代码" % len(codes))
        return codes
    finally:
        cursor.close()

# ======================== 新浪行情解析 ========================
def parse_sina_response(text):
    """
    新浪字段（逗号分隔）:
      0: 名称
      1: 今开
      2: 昨收
      3: 当前价
      4: 最高
      5: 最低
      8: 成交量(股)
      9: 成交额(元)
    """
    results = []
    pattern = re.compile(r'hq_str_(\w+)="(.*?)"')
    matches = pattern.findall(text)

    for symbol, data_str in matches:
        parts = data_str.split(',')
        if len(parts) < 33:
            continue

        code = symbol[2:]

        try:
            name = parts[0]
            open_price = safe_float(parts[1])
            prev_close = safe_float(parts[2])
            price = safe_float(parts[3])
            high = safe_float(parts[4])
            low = safe_float(parts[5])
            volume = safe_int(parts[8])
            amount = safe_float(parts[9])

            change_amt = round(price - prev_close, 4)
            change_pct = round(change_amt / prev_close * 100, 4) if prev_close > 0 else 0.0
            amplitude = round((high - low) / prev_close * 100, 4) if prev_close > 0 else 0.0

            volume_lot = volume // 100   # 股 → 手

            market = get_market_by_code(code)

            row = (code, name, market, price, change_pct, change_amt,
                   volume_lot, amount, amplitude, high, low, open_price, prev_close)
            results.append(row)

        except Exception as e:
            logger.warning(u"解析 %s 异常: %s" % (symbol, e))
            continue

    return results

def fetch_sina_prices(codes):
    all_rows = []
    total_batches = (len(codes) + SINA_BATCH - 1) // SINA_BATCH
    logger.info(u"共 %d 只股票，分 %d 批查询" % (len(codes), total_batches))

    for i in range(0, len(codes), SINA_BATCH):
        batch = codes[i:i + SINA_BATCH]
        batch_num = i // SINA_BATCH + 1

        symbols = []
        for code, name in batch:
            if code.startswith(('5', '6')):
                symbols.append('sh' + code)
            elif code.startswith(('4', '8')):
                symbols.append('bj' + code)
            else:
                symbols.append('sz' + code)

        url = SINA_URL.format(codes=','.join(symbols))

        success = False
        for retry in range(MAX_RETRIES):
            try:
                if retry > 0:
                    time.sleep(2 ** retry)
                resp = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
                resp.encoding = 'gb2312'
                if resp.status_code != 200:
                    raise Exception("HTTP %d" % resp.status_code)
                rows = parse_sina_response(resp.text)
                all_rows.extend(rows)
                logger.info(u"批次 %d/%d 完成，获取 %d 条" % (batch_num, total_batches, len(rows)))
                success = True
                break
            except Exception as e:
                logger.warning(u"批次 %d/%d 第 %d 次失败: %s" %
                               (batch_num, total_batches, retry + 1, e))

        if not success:
            logger.error(u"批次 %d/%d 重试 %d 次后仍失败，跳过" %
                         (batch_num, total_batches, MAX_RETRIES))

        if i + SINA_BATCH < len(codes):
            time.sleep(random.uniform(BATCH_SLEEP_MIN, BATCH_SLEEP_MAX))

    return all_rows

# ======================== 数据库操作 ========================
def get_db_connection():
    try:
        conn = pymysql.connect(**DB_CONFIG)
        return conn
    except Exception as e:
        logger.error(u"数据库连接失败: %s" % e)
        raise

def upsert_stocks(conn, data):
    if not data:
        logger.warning(u"无数据需要写入")
        return

    sql = """
        INSERT INTO stock_quotes
        (stock_code, stock_name, market, latest_price, change_pct, change_amt,
         volume, amount, amplitude, high, low, open, prev_close)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
        stock_name = VALUES(stock_name),
        market = VALUES(market),
        latest_price = VALUES(latest_price),
        change_pct = VALUES(change_pct),
        change_amt = VALUES(change_amt),
        volume = VALUES(volume),
        amount = VALUES(amount),
        amplitude = VALUES(amplitude),
        high = VALUES(high),
        low = VALUES(low),
        open = VALUES(open),
        prev_close = VALUES(prev_close),
        update_time = CURRENT_TIMESTAMP
    """
    cursor = conn.cursor()
    try:
        cursor.executemany(sql, data)
        conn.commit()
        logger.info(u"成功更新/插入 %d 条记录" % len(data))
    except Exception as e:
        conn.rollback()
        logger.error(u"数据库写入失败: %s" % e)
        raise
    finally:
        cursor.close()

def init_table(conn):
    create_sql = """
        CREATE TABLE IF NOT EXISTS `stock_quotes` (
          `stock_code`   VARCHAR(10)   NOT NULL COMMENT '股票代码',
          `stock_name`   VARCHAR(50)   NOT NULL COMMENT '股票名称',
          `market`       VARCHAR(20)   NOT NULL DEFAULT '' COMMENT '所属市场',
          `latest_price` DECIMAL(12,4) NOT NULL COMMENT '最新价',
          `change_pct`   DECIMAL(10,4) NOT NULL COMMENT '涨跌幅%%',
          `change_amt`   DECIMAL(12,4) NOT NULL COMMENT '涨跌额',
          `volume`       BIGINT        NOT NULL COMMENT '成交量(手)',
          `amount`       DECIMAL(20,4) NOT NULL COMMENT '成交额(元)',
          `amplitude`    DECIMAL(10,4) NOT NULL COMMENT '振幅%%',
          `high`         DECIMAL(12,4) NOT NULL COMMENT '最高',
          `low`          DECIMAL(12,4) NOT NULL COMMENT '最低',
          `open`         DECIMAL(12,4) NOT NULL COMMENT '开盘',
          `prev_close`   DECIMAL(12,4) NOT NULL COMMENT '昨收',
          `update_time`  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`stock_code`),
          INDEX `idx_market` (`market`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='A股实时行情表';
    """
    cursor = conn.cursor()
    try:
        cursor.execute(create_sql)
        conn.commit()
        logger.info(u"数据表 stock_quotes 检查/创建完成")
    except Exception as e:
        logger.error(u"创建表失败: %s" % e)
        raise
    finally:
        cursor.close()

# ======================== 主流程 ========================
def job():
    logger.info(u"========== 开始新一轮数据采集（新浪数据源）==========")
    start_time = time.time()

    conn = None
    try:
        conn = get_db_connection()
        init_table(conn)
        codes = load_stock_codes_from_db(conn)
        rows = fetch_sina_prices(codes)
        if not rows:
            logger.warning(u"本次未获取到任何行情数据，跳过写入")
            return

        market_counts = {}
        for row in rows:
            m = row[2]
            market_counts[m] = market_counts.get(m, 0) + 1
        for mkt, cnt in sorted(market_counts.items()):
            logger.info(u"  %s: %d 只" % (mkt, cnt))

        upsert_stocks(conn, rows)
    except Exception as e:
        logger.error(u"执行失败: %s" % e)
    finally:
        if conn:
            conn.close()

    elapsed = time.time() - start_time
    logger.info(u"本轮采集完成，耗时 %.2f 秒\n" % elapsed)

def main():
    logger.info(u"实时股票行情采集脚本启动（新浪数据源，批量查询）")
    logger.info(u"数据库目标: %s:%d/%s" % (DB_CONFIG['host'], DB_CONFIG['port'], DB_CONFIG['database']))
    job()

if __name__ == "__main__":
    main()

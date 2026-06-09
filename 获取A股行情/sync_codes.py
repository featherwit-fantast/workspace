#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
股票代码同步脚本（AkShare + 数据库比对）
- 从 AkShare 拉取沪深京全A股 + ETF 代码
- 与数据库 stock_quotes 表比对
- 已有数据不动，仅新增缺失标的
- 新增标的行情字段填 0，后续由 tencent.py 更新
"""

import pymysql
import logging
import sys

# ======================== 配置 ========================
DB_CONFIG = {
    'host': '192.168.0.220',
    'port': 13306,
    'user': 'DBAdmin',
    'password': 'YieldChain$$2025',
    'database': 'market',
    'charset': 'utf8mb4',
    'autocommit': False
}

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)


def get_db_connection():
    return pymysql.connect(**DB_CONFIG)


def get_existing_codes(conn):
    """读取数据库已有代码"""
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT stock_code FROM stock_quotes")
        codes = set(row[0] for row in cursor.fetchall())
        logger.info(u"数据库现有 %d 只标的" % len(codes))
        return codes
    finally:
        cursor.close()


def fetch_all_from_akshare():
    """AkShare 拉全量：A股 + 北交所 + ETF"""
    import akshare as ak

    all_stocks = []

    # 1. 沪深京全部 A 股（含北交所）
    try:
        df_a = ak.stock_info_a_code_name()
        for _, row in df_a.iterrows():
            code = str(row['code']).strip()
            name = str(row['name']).strip()
            all_stocks.append((code, name))
        logger.info(u"AkShare A股列表: %d 只" % len(df_a))
    except Exception as e:
        logger.error(u"A股列表获取失败: %s" % e)

    # 2. 沪深 ETF 基金
    try:
        df_etf = ak.fund_etf_spot_em()
        for _, row in df_etf.iterrows():
            code = str(row['代码']).strip()
            name = str(row['名称']).strip()
            if code and name:
                all_stocks.append((code, name))
        logger.info(u"AkShare ETF列表: %d 只" % len(df_etf))
    except Exception as e:
        logger.error(u"ETF列表获取失败: %s" % e)

    # 去重（同代码取第一个名）
    seen = set()
    unique = []
    for code, name in all_stocks:
        if code not in seen:
            seen.add(code)
            unique.append((code, name))
    logger.info(u"去重后合计: %d 只" % len(unique))
    return unique


def insert_new_codes(conn, codes, existing):
    """仅插入数据库中不存在的标的，行情填0"""
    new_codes = [(c, n) for c, n in codes if c not in existing]
    if not new_codes:
        logger.info(u"没有需要新增的标的")
        return 0

    sql = """
        INSERT INTO stock_quotes
        (stock_code, stock_name, market, latest_price, change_pct, change_amt,
         volume, amount, amplitude, high, low, open, prev_close)
        VALUES (%s, %s, %s, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    """
    cursor = conn.cursor()
    try:
        rows = []
        for code, name in new_codes:
            # 市场判断
            market = get_market(code)
            rows.append((code, name, market))

        cursor.executemany(sql, rows)
        conn.commit()
        logger.info(u"新增 %d 只标的（行情待更新）" % len(rows))
        return len(rows)
    except Exception as e:
        conn.rollback()
        logger.error(u"插入失败: %s" % e)
        raise
    finally:
        cursor.close()


def get_market(code):
    """代码 → 市场"""
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


def main():
    logger.info(u"========== 代码同步开始 ==========")

    # 拉全量
    codes = fetch_all_from_akshare()
    if not codes:
        logger.error(u"未获取到任何代码，退出")
        return

    # 比对
    conn = get_db_connection()
    try:
        existing = get_existing_codes(conn)
        added = insert_new_codes(conn, codes, existing)
        logger.info(u"========== 同步完成，新增 %d 只 ==========\n" % added)
        logger.info(u"下一步: python3.7 tencent.py 更新行情")
    finally:
        conn.close()


if __name__ == "__main__":
    main()

-- =====================================================
-- 导出增量备份涉及的全部 35 张表结构
-- 执行方式: mysql -h10.6.4.195 -P3306 -uficc -p < 导出表结构.sql > 表结构.txt
-- =====================================================

-- ====================
-- 库: yltrs_ylcms (25张)
-- ====================

USE yltrs_ylcms;
SHOW CREATE TABLE trade\G
SHOW CREATE TABLE trade_cash\G
SHOW CREATE TABLE trade_extend\G
SHOW CREATE TABLE trade_span\G
SHOW CREATE TABLE trade_contract_r\G

SHOW CREATE TABLE swap_position\G
SHOW CREATE TABLE swap_flow\G
SHOW CREATE TABLE swap_flow_deal\G
SHOW CREATE TABLE swap_flow_event\G
SHOW CREATE TABLE swap_event\G
SHOW CREATE TABLE swap_rate\G
SHOW CREATE TABLE swap_float_rate\G
SHOW CREATE TABLE swap_rate_log\G
SHOW CREATE TABLE swap_fund_account\G
SHOW CREATE TABLE swap_asset\G
SHOW CREATE TABLE dma_margin_record\G

SHOW CREATE TABLE hedge_deal\G
SHOW CREATE TABLE hedge_order\G
SHOW CREATE TABLE client_deal\G
SHOW CREATE TABLE client_order\G

SHOW CREATE TABLE trade_contract_document\G
SHOW CREATE TABLE trade_contract_document_file\G

SHOW CREATE TABLE clientcashincashout\G
SHOW CREATE TABLE client_cash_log\G
SHOW CREATE TABLE client_position\G

-- ====================
-- 库: bond_oms (10张)
-- ====================

USE bond_oms;
SHOW CREATE TABLE client_order\G
SHOW CREATE TABLE client_deal\G
SHOW CREATE TABLE hedge_order\G
SHOW CREATE TABLE hedge_deal\G
SHOW CREATE TABLE qt_order_info\G
SHOW CREATE TABLE order_operate_log\G
SHOW CREATE TABLE order_record_unwind_detail\G
SHOW CREATE TABLE client_swap_confirm_log\G
SHOW CREATE TABLE client_order_swap_record\G
SHOW CREATE TABLE trade_risk_check_log\G

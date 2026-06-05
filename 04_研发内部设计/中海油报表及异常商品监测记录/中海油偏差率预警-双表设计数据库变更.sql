-- =====================================================
-- 中海油偏差率预警 - 双表设计数据库变更脚本
-- 变更日期: 2026-04-23
-- 说明: 将审核日志拆为主表（最新记录）和过程表（历史记录）
--       新增 tenant_id 字段支持多租户数据隔离
-- =====================================================

-- 1. 备份现有数据（执行前务必备份）
CREATE TABLE IF NOT EXISTS t_reasonable_price_audit_log_backup AS 
SELECT * FROM t_reasonable_price_audit_log;

-- 2. 为主表添加 tenant_id 字段
ALTER TABLE t_reasonable_price_audit_log 
ADD COLUMN tenant_id VARCHAR(64) COMMENT '租户ID' AFTER goods_id;

-- 3. 为已有数据填充 tenant_id（中海油租户）
UPDATE t_reasonable_price_audit_log 
SET tenant_id = '1711947796057141249' 
WHERE tenant_id IS NULL;

-- 4. 为主表添加 tenant_id 索引
ALTER TABLE t_reasonable_price_audit_log 
ADD INDEX idx_tenant_id (tenant_id);

-- 5. 创建过程表（存储完整历史记录，包含 tenant_id）
DROP TABLE IF EXISTS `t_reasonable_price_audit_log_process`;
CREATE TABLE `t_reasonable_price_audit_log_process` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `msg_id` VARCHAR(64) DEFAULT NULL COMMENT '消息ID',
  `task_id` VARCHAR(64) DEFAULT NULL COMMENT '任务ID',
  `tenant_id` VARCHAR(64) DEFAULT NULL COMMENT '租户ID',
  `goods_id` VARCHAR(64) NOT NULL COMMENT '商品ID',
  `catalog_ids` TEXT COMMENT '品目ID列表（JSON格式）',
  `catalog_names` TEXT COMMENT '品目名称列表（JSON格式）',
  `goods_price` DECIMAL(18,2) DEFAULT NULL COMMENT '商品价格',
  `reasonable_price` DECIMAL(18,2) DEFAULT NULL COMMENT '合理价',
  `price_deviation_rate` DECIMAL(10,4) DEFAULT NULL COMMENT '价格偏离百分比',
  `audit_result_type` VARCHAR(10) DEFAULT NULL COMMENT '审核结果类型编码',
  `audit_remark` VARCHAR(500) DEFAULT NULL COMMENT '审核说明',
  `audit_time` DATETIME DEFAULT NULL COMMENT '审核时间',
  `create_time` DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_tenant_id` (`tenant_id`),
  KEY `idx_goods_id` (`goods_id`),
  KEY `idx_create_time` (`create_time`),
  KEY `idx_task_id` (`task_id`),
  KEY `idx_audit_result_type` (`audit_result_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='合理价审核日志过程表（历史记录）';

-- 6. 迁移现有数据到过程表（如果是首次执行）
INSERT INTO t_reasonable_price_audit_log_process 
(msg_id, task_id, tenant_id, goods_id, catalog_ids, catalog_names, 
 goods_price, reasonable_price, price_deviation_rate, 
 audit_result_type, audit_remark, audit_time, create_time)
SELECT msg_id, task_id, tenant_id, goods_id, catalog_ids, catalog_names, 
       goods_price, reasonable_price, price_deviation_rate, 
       audit_result_type, audit_remark, audit_time, create_time
FROM t_reasonable_price_audit_log;

-- 7. 清理主表重复数据（仅针对05类型偏差率预警规则）
-- 说明：01-04类型规则需要保留历史记录，不能添加唯一索引
-- 注意：如果表中已有05类型的重复数据，需要先执行此步骤
DELETE t1 FROM t_reasonable_price_audit_log t1
INNER JOIN t_reasonable_price_audit_log t2
WHERE t1.goods_id = t2.goods_id 
  AND t1.tenant_id = t2.tenant_id
  AND t1.audit_result_type = '05'
  AND t2.audit_result_type = '05'
  AND t1.create_time < t2.create_time;

-- =====================================================
-- 验证脚本（可选）
-- =====================================================

-- 验证主表是否有05类型规则的重复数据（按租户+商品）
SELECT tenant_id, goods_id, audit_result_type, COUNT(*) as cnt 
FROM t_reasonable_price_audit_log 
WHERE audit_result_type = '05'
GROUP BY tenant_id, goods_id, audit_result_type 
HAVING cnt > 1;
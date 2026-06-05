-- 标准商品治理核验失败类型分类 - 数据库变更脚本
-- 执行时间：业务低峰期
-- 影响表：t_stand_goods_govern

-- 1. 新增失败类型字段
ALTER TABLE t_stand_goods_govern 
ADD COLUMN failure_type VARCHAR(50) COMMENT '失败类型编码，参考FailureTypeEnum' AFTER audit_desc;

-- 2. 添加索引以支持按失败类型查询（可选，根据实际查询需求决定是否执行）
-- CREATE INDEX idx_failure_type ON t_stand_goods_govern(failure_type);

-- 说明：
-- 1. failure_type字段允许NULL，历史数据保持NULL
-- 2. 不设默认值，避免误导
-- 3. 字段存储FailureTypeEnum的code值

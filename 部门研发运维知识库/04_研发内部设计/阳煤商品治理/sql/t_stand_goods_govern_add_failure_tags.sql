-- ============================================
-- 标准商品治理表新增失败标签字段
-- 执行时间：2026-05-19
-- 说明：用于存储所有涉及的失败大类，支持多标签筛选
-- ============================================

-- 在 t_stand_goods_govern 表中新增 failure_tags 字段
ALTER TABLE t_stand_goods_govern 
ADD COLUMN failure_tags VARCHAR(200) COMMENT '失败标签，多个用逗号分隔，如：CATALOG,BRAND' AFTER failure_type;

-- 可选：为 failure_tags 字段添加索引（如果需要按标签查询）
-- CREATE INDEX idx_failure_tags ON t_stand_goods_govern(failure_tags);

-- 验证字段是否添加成功
-- DESCRIBE t_stand_goods_govern;

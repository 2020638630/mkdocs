# Phoenix QueryServer Namespace Mapping 异常排查报告

:material-file-document-edit: **文档类型**: 故障排查 |
:material-alert-circle: **优先级**: 🔴 高 |
:material-account-clock: **发生时间**: 2026-06-05 |
:material-account: **处理人**: 研发团队 |
:material-tag: **标签**: Phoenix, HBase, PQS, namespace-mapping, ERROR-726

---

## 一、问题现象

:red_circle: **问题描述**

Spark 任务通过 MyBatis 薄客户端连接 Phoenix QueryServer 时，报错：

```
ERROR 726 (43M10): Inconsistent namespace mapping properties.
Cannot initiate connection as SYSTEM:CATALOG is found but
client does not have phoenix.schema.isNamespaceMappingEnabled enabled
```

> **报错路径**：`GoodsInfoViewMapper.listForPriceStat` → MyBatis → Avatica 薄客户端 → PQS → Phoenix 厚客户端

**影响范围**：`tbprod` 环境的 Spark 价格统计任务（连接 `172.16.0.7:18765` 即 `hbase-0004` 上的 PQS）

---

## 二、排查过程

### 2.1 确认 HBase 集群状态

```bash
# 检查 SYSTEM 命名空间下的表
echo "list_namespace_tables 'SYSTEM'" | hbase shell -n
# 结果：SYSTEM 命名空间下有 CATALOG 等 8 张系统表 → namespace mapping 已启用

# 检查旧格式是否存在
echo "exists 'SYSTEM.CATALOG'" | hbase shell -n
# 结果：false → 旧的点号格式不存在
```

:material-check-circle: **确认**：HBase 集群启用了 namespace mapping，系统表以 `SYSTEM:CATALOG` 格式存储。

### 2.2 检查 PQS 服务端 hbase-site.xml

```bash
cat /data/hbase-2.4.9/conf/hbase-site.xml | grep namespaceMapping
```

:material-check-circle: **确认**：HBase 的 `hbase-site.xml` 中 `phoenix.schema.isNamespaceMappingEnabled=true` 配置正确。

### 2.3 检查 PQS 进程 classpath

```bash
ps aux | grep queryserver
# 关键信息：
# -cp /etc/hbase/conf:/etc/hadoop/conf:...
```

:material-alert-circle: **发现**：PQS classpath 写死了从 `/etc/hbase/conf/` 加载配置。

### 2.4 检查 `/etc/hbase/conf/` 目录

```bash
ls -la /etc/hbase/conf/
# 结果：/etc/hbase/conf/: No such file or directory
```

:material-close-circle: **关键发现**：`/etc/hbase/conf/` 目录不存在，PQS 无法加载 `hbase-site.xml`，使用默认配置（namespace mapping = false）。

### 2.5 排查配置丢失原因

查看 PQS 历史启动命令：

```bash
# 历史记录显示 2025-04-29 首次部署时：
./queryserver.py start -Dphoenix.schema.isNamespaceMappingEnabled=true
# ↑ 通过 JVM 参数传递了 namespace mapping 配置

# 2026-06-04 处理 OOM 时用 start.sh 重启：
/data/phoenix-queryserver-6.0.0/start.sh
# ↑ start.sh 中未包含 -D 参数，JVM 参数丢失
```

:material-alert-circle: **发现**：PQS 重启时丢失了 `-Dphoenix.schema.isNamespaceMappingEnabled=true` JVM 参数。

### 2.6 确认 PQS classpath 查找逻辑

`queryserver.py` 中配置目录的查找优先级：

| 优先级 | 条件 | 路径 |
|:---:|------|------|
| 1 | 设置 `$HBASE_CONF_DIR` | 环境变量指定路径 |
| 2 | 设置 `$HBASE_HOME` | `$HBASE_HOME/conf` |
| 3 | **默认（当前环境）** | **`/etc/hbase/conf`** |

当前环境 `$HBASE_CONF_DIR` 和 `$HBASE_HOME` 均未设置，因此使用硬编码默认路径 `/etc/hbase/conf`。

---

## 三、根本原因

```mermaid
flowchart TD
    A[部署时 /etc/hbase/conf/ 不存在<br>但通过 -D JVM 参数传配置] --> B[2026-06-04 PQS OOM<br>修改 start.sh 重启]
    B --> C[start.sh 未包含 -D 参数<br>JVM 参数丢失]
    C --> D[/etc/hbase/conf/ 目录不存在<br>hbase-site.xml 无法加载]
    D --> E[PQS 使用默认配置<br>namespace mapping = false]
    E --> F[2026-06-05 首次触发检查路径]
    F --> G[HBase 中 SYSTEM:CATALOG 存在<br>与客户端配置矛盾]
    G --> H[ERROR 726]
```

**三条线索交叉验证**：

1. `/etc/hbase/conf/` 目录在部署时就未创建 —— `rpm -qf` 显示不属于任何 RPM 包
2. 历史上 PQS 靠 `-D` JVM 参数绕过该问题
3. 2026-06-04 处理 OOM 时用 `start.sh` 重启，`start.sh` 中未写入 `-D` 参数 → JVM 参数丢失

---

## 四、解决方案

### 4.1 核心修复（hbase-0004，即 172.16.0.7）

```bash
# 1. 创建 /etc/hbase/conf/ 目录
mkdir -p /etc/hbase/conf

# 2. 将正确的 hbase-site.xml 复制过去
cp /data/hbase-2.4.9/conf/hbase-site.xml /etc/hbase/conf/hbase-site.xml

# 3. 确认配置
cat /etc/hbase/conf/hbase-site.xml | grep namespaceMapping
# 应输出：
#     <name>phoenix.schema.isNamespaceMappingEnabled</name>
#     <value>true</value>

# 4. 重启 PQS 使配置生效
kill -9 <PQS_PID>
/data/phoenix-queryserver-6.0.0/bin/queryserver.py start
```

:material-check-circle: **验证**：重启后 Spark 任务恢复正常，不再报 ERROR 726。

### 4.2 项目代码配置（可选恢复）

??? note "yml 配置建议恢复原样"
    之前在 5 个 yml 文件的 thin/phoenix URL 上加的 `;phoenix.schema.isNamespaceMappingEnabled=true` 参数实际未生效（thin URL 参数作为 Avatica 协议参数传递，服务端不加载时仍无效），建议恢复为：
    
    ```yaml
    # thin URL（MyBatis 用）
    url: jdbc:phoenix:thin:url=http://172.16.0.7:18765;serialization=PROTOBUF
    
    # 厚 URL（Spark readJdbc 用）
    url: jdbc:phoenix:172.16.0.201:2181
    ```

---

## 五、预防措施

### 5.1 检查所有 PQS 节点

:material-alert-circle: **必须检查**：所有 PQS 节点的 `/etc/hbase/conf/hbase-site.xml` 是否存在且包含 namespace mapping 配置。

```bash
# 批量检查所有 HBase 节点
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
  echo "=== $host ==="
  ssh $host "cat /etc/hbase/conf/hbase-site.xml 2>/dev/null | grep namespaceMapping || echo 'MISSING'"
done
```

### 5.2 加固 start.sh 脚本

在 `start.sh` 中增加 `-D` 参数，形成双重保障：

```bash
export PHOENIX_QUERYSERVER_OPTS="\
  -Dphoenix.schema.isNamespaceMappingEnabled=true \
  -Dphoenix.schema.mapSystemTablesToNamespace=true \
  -Dqueryserver.executor.corePoolSize=64 \
  -Dqueryserver.executor.maxPoolSize=256 \
  -Dqueryserver.executor.queueSize=2000 \
  -Dqueryserver.executor.keepAliveTime=120"
```

### 5.3 后续操作

1. **硬盘挂载恢复**：执行 `mount -a` 后 `df -h`，确保硬盘挂载正常
2. **PQS 重启规范**：以后重启 PQS 时，优先确保 `/etc/hbase/conf/hbase-site.xml` 存在，或显式传递 `-D` 参数
3. **监控告警**：考虑对 PQS 的 namespace mapping 异常增加监控

---

## 六、完整时间线

| 时间 | 事件 | 说明 |
|------|------|------|
| 2025-04-29 | 首次部署 PQS | 带 `-D` JVM 参数启动，绕过了 `/etc/hbase/conf/` 缺失问题 |
| 2026-06-04 20:28 | PQS OOM 排查 | 修改 `start.sh`，降低 `-Xmx` 从 15G 到 10G |
| 2026-06-04 | 用 `start.sh` 重启 PQS | `-D` 参数丢失，但因未触发检查路径，未暴露 |
| **2026-06-05 16:25** | **首次报错 ERROR 726** | 触发 namespace mapping 检查路径，矛盾暴露 |
| 2026-06-05 16:37 | 尝试重启 PQS（无 -D） | 不止一次重启，均未包含 `-D` 参数 |
| 2026-06-05 17:00 | 部署新 jar（含 yml URL 参数） | yml 中 thin URL 添加了 namespace 参数，但无效 |
| **2026-06-05 17:30** | **创建 `/etc/hbase/conf/hbase-site.xml`** | 核心修复，配置持久化到文件 |
| 2026-06-05 17:31 | 重启 PQS | 配置生效，问题解决 |

---

## 七、相关文件

| 文件 | 路径 | 说明 |
|------|------|------|
| PQS 启动脚本 | `/data/phoenix-queryserver-6.0.0/bin/queryserver.py` | classpath 中硬编码了 `/etc/hbase/conf` |
| PQS 配置工具 | `/data/phoenix-queryserver-6.0.0/bin/phoenix_queryserver_utils.py` | 定义了 `hbase_conf_dir` 查找逻辑 |
| HBase 配置源 | `/data/hbase-2.4.9/conf/hbase-site.xml` | 正确的 namespace mapping 配置所在处 |
| PQS 配置目标 | `/etc/hbase/conf/hbase-site.xml` | 需要创建的配置文件，本次修复已创建 |
| PQS 启动脚本 | `/data/phoenix-queryserver-6.0.0/start.sh` | 缺少 `-D` 参数的启动方式 |

---

**:material-check-all: 报告结束**

# :material-database-alert: Elasticsearch 集群写入拒绝排查与优化报告

---

## :material-information: 基本信息

| 项目 | 内容 |
|------|------|
| 集群节点 | es-0001（172.16.0.242）、es-0002（172.16.0.156）、es-0003（172.16.0.15） |
| ES 版本 | Elasticsearch 7.x |
| 服务器配置 | 3 节点，每节点 32GB 物理内存 |
| 涉及索引 | `goods-price-stat`、`crawl-data`、`goods-info`、`show-price` |
| 排查日期 | 2026-06-04 |

---

## :material-alert-circle: 一、问题现象

Spark 离线任务写入 ES 时大量报错：

```
es_rejected_execution_exception: rejected execution of processing
on EsThreadPoolExecutor[name = write, queue capacity = 200, ...]
```

!!! bug "影响"
    写入线程池队列满，ES 拒绝新的写入请求，导致 Spark Job 失败。

---

## :material-server: 二、系统环境检查

### 2.1 节点资源概览

```bash
# 查看各节点状态（Kibana DevTools 或 curl）
GET _cat/nodes?v&h=name,ip,heap.current,heap.percent,ram.percent,cpu,load_1m,node.role,master
```

| 节点 | IP | Heap | Heap% | RAM% | CPU | Load |
|------|----|------|-------|------|-----|------|
| es-0001 | 172.16.0.242 | 18GB | ~50% | 99% | ~20% | ~3 |
| es-0002 | 172.16.0.156 | 18GB | ~58% | 99% | ~40% | ~8 |
| es-0003 | 172.16.0.15 | 18GB | ~87% | 99% | ~30% | ~5 |

!!! warning "注意"
    ⚠️ 所有节点 RAM 使用率达 99%，但 Linux 中 `buff/cache` 也被计入 used，实际可用内存需看 `free -h` 中的 available。

---

### 2.2 系统内存详情

```bash
free -h
```

| 节点 | Total | Used | Free | Available |
|------|-------|------|------|-----------|
| es-0001 | 31G | ~20G | ~0.5G | ~10G |
| es-0002 | 31G | ~20G | ~0.5G | ~10G |
| es-0003 | 31G | ~20G | ~0.5G | ~10G |

!!! danger "核心问题"
    ⚠️ **JVM Heap 占用 18GB × 3 = 54GB**，留给 OS Cache 的内存仅约 14GB，而集群总 shard 数据量高达 58GB，**OS Cache 严重不足导致大量磁盘 IO**。

---

### 2.3 写入线程池状态

```bash
GET _cat/thread_pool/write?v&h=node_name,active,queue,rejected,completed
```

| 节点 | Active | Queue | Rejected | Completed |
|------|--------|-------|----------|-----------|
| es-0001 | 0-2 | 0 | 少量 | ~3600万 |
| es-0002 | 0-4 | 0-200 | **大量** | **~1.56亿** |
| es-0003 | 0-2 | 0 | 少量 | ~3600万 |

!!! bug "严重问题"
    ⚠️ **0002 节点写入量是其他节点的 4 倍以上**，存在严重的写入倾斜。

---

## :material-magnify: 三、根因分析

### 3.1 Shard 分布不均

```bash
GET _cat/shards?v&h=index,shard,prirep,node,store
```

关键索引均为 **3 个主分片 + 0 副本**，`total_shards_per_node=2`：

| 索引 | 分片分布 | 问题 |
|------|---------|------|
| `crawl-data` | 0001:1, 0002:2, 0003:0 | 0002 多一个主分片 |
| `goods-info` | 0001:1, 0002:2, 0003:0 | 0002 多一个主分片 |
| `show-price` | 0001:1, 0002:2, 0003:0 | 0002 多一个主分片 |
| `goods-price-stat` | 0001:1, 0002:1, 0003:1 | 均匀 ✅ |

!!! failure "根本原因"
    **ES 写入只走主分片**，0002 节点承载了多数索引的 2 个主分片，导致写入压力集中在 0002，写入线程池频繁打满（queue=200），触发 reject。

---

### 3.2 JVM Heap 设置过大

JVM Heap 设置为 18GB（`-Xms18g -Xmx18g`），32GB 物理内存扣除 18GB Heap 后，留给 OS Cache 的内存仅约 14GB。而集群总 shard 数据量约 58GB，OS Cache 无法容纳全部数据，导致大量磁盘读取，进一步影响写入性能。

```
物理内存 32GB
├── JVM Heap: 18GB
├── 其他进程/系统: ~4GB
└── OS Cache: ~10GB  ← 58GB 数据无法全部缓存
```

---

### 3.3 问题链路总结

```
JVM Heap 18GB (过大)
  → OS Cache 仅 14GB，无法覆盖 58GB shard 数据
    → 大量磁盘 IO，写入变慢
      → 0002 主分片集中，写入压力 4x
        → write thread pool queue=200 打满
          → es_rejected_execution_exception
            → Spark Job 失败
```

---

### 3.4 代码层面因素（未修复）

| 问题 | 说明 |
|------|------|
| **批量大小过小** | `EsGoodsPriceStatService.save2ES()` 每批仅 10 条 |
| **无重试机制** | `ErrorEsResponse.java` 直接抛 RuntimeException，失败即中断 |
| **并发度过高** | Spark 并行度 100，大量并发写入压垮 ES |
| **Phoenix/ES 耦合** | `flushGoodsPriceStatBatch()` 中 Phoenix 和 ES 写入在同一事务 |

---

## :material-wrench: 四、解决方案

### 4.1 调整 JVM Heap（已执行）

将所有 3 个节点的 JVM Heap 从 18GB 降至 12GB：

```bash
# 编辑 jvm.options
vim /etc/elasticsearch/jvm.options

# 修改前
-Xms18g
-Xmx18g

# 修改后
-Xms12g
-Xmx12g
```

同时优化 G1GC 参数，清理旧的 CMS GC 配置：

```bash
# 新增/确认的 G1GC 配置
-XX:+UseG1GC
-XX:G1HeapRegionSize=4m
-XX:InitiatingHeapOccupancyPercent=65
-XX:G1ReservePercent=15
-XX:+ParallelRefProcEnabled
```

**优化效果：**

| 指标 | 优化前 | 优化后 |
|------|--------|--------|
| JVM Heap | 18GB | 12GB |
| OS Available Memory | ~10GB | ~17GB |
| 0003 heap.percent | 87% | 60% |
| 0002 heap.percent | 58% | 50% |
| OS Cache | ~14GB | ~20GB |

!!! success "效果"
    释放 6GB × 3 = 18GB 给 OS Cache，大幅减少磁盘 IO。

---

### 4.2 滚动重启 ES 集群（已执行）

按顺序执行滚动重启，确保集群持续可用：

```bash
# 1. 暂停 Spark 写入任务

# 2. 重启节点（以 es 用户执行）
su - es
kill -SIGTERM <PID>           # 先停掉旧进程
cd /data/elasticsearch
./bin/elasticsearch -d -p pid # 后台启动
tail -f logs/elasticsearch.log # 观察启动日志

# 3. 等待集群恢复 green
GET _cluster/health

# 4. 依次重启 0001 → 0003 → 0002
```

!!! tip "重启顺序"
    **先重启主分片较少的节点 0001，再 0003，最后重启压力最大的 0002。**

**最终状态：**
- 集群状态：green ✅
- 活跃分片：319 / 319 (100%)
- 未分配分片：0

---

## :material-alert-decagram: 五、重启过程问题与处理

### 5.1 内存不足导致 12GB Heap 无法启动

!!! bug "现象"
    **现象：** 旧进程（18GB Heap）仍占用内存，新进程申请 12GB 时内存不够。

!!! check "解决"
    ```bash
    # 查找旧进程 PID
    ps aux | grep [e]lasticsearch

    # 优雅终止（SIGTERM，等待资源释放）
    kill -SIGTERM <PID>

    # 确认内存可用
    free -h
    ```

---

### 5.2 root 用户启动报错

!!! bug "现象"
    `can not run elasticsearch as root`

!!! check "解决"
    ```bash
    su - es
    cd /data/elasticsearch
    ./bin/elasticsearch -d -p pid
    ```

---

### 5.3 集群变红恢复等待

滚动重启期间集群短暂变 red（最多 42 个未分配分片），属正常现象。等待分片恢复完成即可，无需干预。

```
yellow → red (短暂) → yellow → green
        ↑ 0003 重启期间  ↑ 恢复完成
```

---

### 5.4 RAM% 99% 的误解

`_cat/nodes` 中的 `ram.percent=99%` 是 Linux 的 total used%，包含了 `buff/cache`。实际可用内存通过 `free -h` 查看 available 列，优化后可用内存从 ~10GB 提升至 ~17GB。

---

## :material-lightbulb: 六、待优化的代码改进建议

| 优化项 | 现状 | 建议 | 优先级 |
|--------|------|------|--------|
| 批量写入大小 | 每批 10 条 | 提升至 50-100 条 | :red_circle: 高 |
| 写入重试机制 | 无重试，直接抛异常 | 添加指数退避重试（参考 `EsGoodsInfoService.executeEsWriteWithRetry`） | :red_circle: 高 |
| Spark 并发度 | 100 并行写入 | 降至 20-30，避免压垮 ES | :orange_circle: 中 |
| Phoenix/ES 解耦 | 同事务写入 | 先写 Phoenix，ES 异步写入 + 失败补偿 | :orange_circle: 中 |
| Shard 均衡 | 0002 主分片集中 | 考虑添加 `index.routing.allocation.total_shards_per_node` 约束 | :green_circle: 低 |

---

### 参考代码：已有成熟重试机制

`EsGoodsInfoService.executeEsWriteWithRetry()` 已实现指数退避重试，可直接复用：

```java
// 参考文件：
// pricemonitor-bigdata/.../service/EsGoodsInfoService.java
private void executeEsWriteWithRetry(BulkRequest bulkRequest) {
    int maxRetries = 3;
    long baseDelayMs = 1000;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
            BulkResponse response = esClient.bulk(bulkRequest, RequestOptions.DEFAULT);
            if (!response.hasFailures()) return;
        } catch (Exception e) {
            if (attempt == maxRetries - 1) throw e;
            Thread.sleep(baseDelayMs * (1L << attempt)); // 指数退避
        }
    }
}
```

---

## :material-speedometer: 七、命令速查表

### ES 集群状态

| 场景 | 命令 |
|------|------|
| 集群健康 | `GET _cluster/health` |
| 节点状态 | `GET _cat/nodes?v&h=name,ip,heap*,ram*,cpu,load*` |
| 分片分布 | `GET _cat/shards?v&h=index,shard,prirep,node,store` |
| 写入线程池 | `GET _cat/thread_pool/write?v&h=node_name,active,queue,rejected,completed` |
| 索引设置 | `GET <index>/_settings` |

---

### ES 运维

| 场景 | 命令 |
|------|------|
| 查看 JVM 配置 | `cat /etc/elasticsearch/jvm.options` |
| 查找 ES 进程 | `ps aux \| grep [e]lasticsearch` |
| 优雅停止 ES | `kill -SIGTERM <PID>` |
| 后台启动 ES（es 用户） | `./bin/elasticsearch -d -p pid` |
| 查看 ES 日志 | `tail -f logs/elasticsearch.log` |

---

### 系统命令

| 场景 | 命令 |
|------|------|
| 查看内存 | `free -h` |
| 查看磁盘 | `df -h` |
| 查看 OOM | `dmesg \| grep -i "oom\|killed"` |

---

## :material-clipboard-text: 八、总结

| 环节 | 结论 |
|------|------|
| 直接原因 | 0002 节点主分片集中（4x 写入），write thread pool 队列打满触发 reject |
| 深层原因 | JVM Heap 18GB 过大，OS Cache 不足（仅 14GB），磁盘 IO 过高导致写入变慢 |
| 紧急修复 | JVM Heap 18GB → 12GB，3 节点滚动重启完成 |
| 修复效果 | OS 可用内存 10GB → 17GB，heap 压力下降，集群恢复 green |
| 长期建议 | 代码增加重试 + 增大批次 + 降低并发 + 解耦 Phoenix/ES 写入 |

---

> :calendar: 编写日期：2026-06-04

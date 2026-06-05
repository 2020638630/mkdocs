# :material-alert-octagon: RabbitMQ 宕机与 Redis 内存溢出排查报告

:material-file-document-edit: **文档类型**: 故障排查 |
:material-alert-circle: **优先级**: 🔴 高 |
:material-account-clock: **发生时间**: 2026-05-25 |
:material-account: **处理人**: 研发团队 |
:material-tag: **标签**: RabbitMQ, Redis, Docker, 内存溢出, OOM, logstach

---

## :material-information: 基本信息

| 项目 | 内容 |
|------|------|
| 服务器 | logstach |
| 排查日期 | 2026-05-25 |
| 涉及服务 | RabbitMQ、Redis（Docker） |
| 问题现象 | RabbitMQ 节点宕机，消费者不可用 |

---

## :material-alert: 一、问题现象

执行 `rabbitmqctl list_consumers` 时报错：

```
Error: unable to perform an operation on node 'rabbit@logstach'
epmd reports: node 'rabbit' not running at all
```

RabbitMQ 节点完全未运行，所有消息队列消费者不可用。

---

## :material-server: 二、系统环境检查

### 2.1 内存状态

```bash
free -h
```

结果：

| 项目 | 数值 |
|------|------|
| 总内存 | 31GB |
| 已用 | 27GB |
| 空闲 | 229MB |
| **Swap** | **0GB（未配置！）** |

> :warning: **警告**：系统内存几乎耗尽，且未配置任何 Swap 空间。

---

### 2.2 OOM Killer 日志

```bash
dmesg | grep -i "oom\|killed" | tail -20
```

发现 OOM Killer 被多次触发，redis-server 进程被反复杀死：

| 被杀进程 | 内存占用 | 次数 |
|----------|---------|------|
| redis-server (PID 8828) | ~14.3GB | 4次+ |

> :warning: **警告**：Redis 每次被杀死后 Docker 自动重启，然后再次占用大量内存，陷入"OOM 杀死→重启→再次OOM"的恶性循环。

---

### 2.3 Redis 进程状态

```bash
ps aux | grep redis
```

```
polkitd  18809  1.9 45.7 16434456 14981064 ?  Ssl  2025 9935:24 redis-server *:6379
```

**Redis 占用 45.7% 内存（约 14.5GB）**，是内存消耗最大的进程。

---

### 2.4 Redis 内存详情

```bash
redis-cli -p 16379 -a <password> INFO memory
```

关键指标：

| 项目 | 数值 |
|------|------|
| used_memory_human | **13.48G** |
| maxmemory_human | **25.00G** ← 上限过高！ |
| maxmemory_policy | allkeys-lru |
| total_system_memory | 31.26G |

> :warning: **警告**：Redis `maxmemory` 设置为 **25GB**，而系统总内存只有 31GB。Redis 占用 13.48GB 时系统已几乎无空闲内存。

---

## :material-magnify: 三、根因分析

```
系统内存 31GB
├── Redis:       14.5GB  (maxmemory=25GB 未限制)
├── 其他进程:    ~14GB
├── 空闲:        0.2GB   ← 几乎耗尽
└── Swap:        0GB     ← 无缓冲
```

**结果链路：**
```
Redis 内存持续增长 → 系统内存耗尽 → OOM Killer 触发
→ 杀死 redis-server 进程 → Docker 自动重启 Redis
→ RabbitMQ 因内存压力崩溃 → 所有消费者掉线
```

**根本原因：**

1. **Redis `maxmemory` 设置过大**（25GB），未对内存使用进行有效约束
2. **系统未配置 Swap**，内存耗尽时无缓冲，直接触发 OOM Killer
3. 虽然 `maxmemory-policy` 已配置 `allkeys-lru`，但上限 25GB 远超系统承受能力

**额外发现：**
- Redis 数据存储在 `db2`，约 2700 万条 key，**几乎每条都有 TTL**（平均 1.6 天过期）
- 数据属于缓存性质，并非持久化数据
- 动态调整 `maxmemory` 不会影响业务数据安全

---

## :material-wrench: 四、解决方案

### 4.1 添加 Swap 空间（紧急措施）

```bash
# 创建 8GB Swap 文件
dd if=/dev/zero of=/swapfile bs=1M count=8192
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# 设置开机自动挂载
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

# 验证
free -h
```

执行结果：

```
Swap: 8.0G  0B  8.0G  ✅
```

---

### 4.2 降低 Redis 内存上限

```bash
# 1. 连接 Redis（端口 16379，需认证）
redis-cli -p 16379
> AUTH <password>

# 2. 动态设置 maxmemory 为 12GB（立即生效）
CONFIG SET maxmemory 12884901888

# 3. 验证配置
CONFIG GET maxmemory
```

由于 CONFIG REWRITE 在容器内权限不足，需修改挂载的配置文件：

```bash
# 查看挂载信息
docker inspect redis6 | grep -A 20 "Mounts"

# 备份配置
cp /etc/conf/redis/redis.conf /etc/conf/redis/redis.conf.bak

# 修改 maxmemory
sed -i 's/^maxmemory.*/maxmemory 12gb/' /etc/conf/redis/redis.conf

# 重启容器使配置持久化
docker restart redis6
```

---

### 4.3 重启 RabbitMQ

```bash
cd /data/rabbitmq
./rabbitmqStart.sh
rabbitmqctl list_consumers
```

---

## :material-check-circle: 五、结果验证

### 5.1 Redis 内存变化

| 指标 | 处理前 | 处理后 |
|------|--------|--------|
| maxmemory | 25GB | **12GB** ✅ |
| used_memory | 13.48GB | **12.00GB** ✅ |
| DBSIZE (db2) | 26,951,407 | **23,850,193** |
| 淘汰 key 数量 | - | ~310万（自动淘汰） |

`allkeys-lru` 策略自动淘汰了约 310 万条最久未访问的 key，内存成功降到 12GB 以下。

---

### 5.2 RabbitMQ 消费者

```
queue.transfer.recommend.outside        ✅
queue.transfer.datatype.inside          ✅
enterprise_acquisition.aiTask.delayed   ✅
queue.privatization.data.sync           ✅ (5个消费者)
bigdata.goodscode.queue                 ✅ (7个消费者)
```

所有队列消费者正常运行。

---

### 5.3 Swap 状态

```
Swap: 8.0G  0B  8.0G  ✅
```

---

## :material-lightbulb: 六、可选优化（建议执行）

修复 Redis 日志中的 WARNING：

```bash
# Memory overcommit 警告
echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
sysctl vm.overcommit_memory=1
```

---

## :material-database-search: 七、Redis DB2 内存深度排查

> 降低 maxmemory 后仍需从根源解决内存占用问题。以下为对 DB2 中一个额外 Redis 实例（11.91G/12G）的深度排查记录。

### 7.1 确认 Redis 架构

```bash
# 查看 Redis 端口监听情况
netstat -tlnp | grep 6379
ss -tlnp | grep 6379

# 查看 Docker 容器
docker ps -a | grep redis50
```

**结论：** 只有一个 Redis 实例运行在 Docker 容器 `redis6`（redis:6.2.13）中，端口映射 `0.0.0.0:16379 -> 6379`。`ps aux` 中看到的 `redis-server *:6379` 就是 Docker 进程。

---

### 7.2 扫描大键（bigkeys）

```bash
# 进入 Docker 容器执行扫描（指定 DB2，采样间隔 0.1 秒）
docker exec -it redis6 redis-cli -p 6379 -a '<password>' -n 2 --bigkeys -i 0.1
```

扫描结果：

| 指标 | 数值 |
|------|------|
| 总键数 | 22,978,429 |
| String 类型键 | 22,978,236（99.99%） |
| 最大 String 键 | `APP:TENANT:CATALOGSMAP:1560527901820547074`（643KB） |
| 最大 Hash 键 | `SOURCE_CRAWL_REQUEST_STAT:2026-05-24:PRICE:REPEAT_COUNT`（1,048,767 字段，**128MB**） |

---

### 7.3 检查键的 TTL

```bash
# 连接 Redis
redis-cli -p 16379 -a '<password>' -n 2

# 检查 CATALOGSMAP TTL（永不过期！）
TTL APP:TENANT:CATALOGSMAP:1560527901820547074
# 结果: -1（永不过期）

# 检查 SOURCE_CRAWL_REQUEST_STAT TTL
TTL "SOURCE_CRAWL_REQUEST_STAT:2026-05-24:PRICE:REPEAT_COUNT"
# 结果: ~25505（约 7 小时）

# 检查 GOODSCRAWL 缓存 TTL
redis-cli -p 16379 -a '<password>' -n 2 --scan --pattern "GOODSCRAWL::S::*" | head -5 | \
  while read key; do echo -n "$key => "; redis-cli -p 16379 -a '<password>' -n 2 TTL "$key"; done
# 结果: TTL 约 2.2 天（195384 秒）

# 统计无 TTL 的键数量
redis-cli -p 16379 -a '<password>' -n 2 --scan --pattern "APP:TENANT:CATALOGSMAP:*" | \
  while read key; do TTL=$(redis-cli -p 16379 -a '<password>' -n 2 TTL "$key"); \
  echo "$TTL"; done | sort | uniq -c
# 结果: 全部 TTL=-1（永不过期）
```

---

### 7.4 精确统计键数量

```bash
# 查看 DB2 总键数
redis-cli -p 16379 -a '<password>' -n 2 DBSIZE
# 结果: 22,667,393

# 统计 GOODSCRAWL::S::* 键数量
redis-cli -p 16379 -a '<password>' -n 2 --scan --pattern "GOODSCRAWL::S::*" | wc -l
# 结果: 22,654,088（占 99.94%）

# 抽样验证键分布
redis-cli -p 16379 -a '<password>' -n 2 --scan --pattern "*" | head -50000 | \
  awk -F'::' '{print $1}' | sort | uniq -c | sort -rn
# 结果: 49996/50000 为 GOODSCRAWL::S::*
```

---

### 7.5 内存占用估算

```bash
# 查看单个 GOODSCRAWL 键的大小（抽样）
redis-cli -p 16379 -a '<password>' -n 2 --scan --pattern "GOODSCRAWL::S::*" | head -100 | \
  while read key; do redis-cli -p 16379 -a '<password>' -n 2 MEMORY USAGE "$key"; done | \
  awk '{sum+=$1; count++} END {print "平均:", sum/count, "总量估算:", sum/count*22654088/1024/1024/1024, "GB"}'
# 估算: 单个键平均 ~320B，总占用约 8-9GB（含元数据开销约 71B/键）

# 查看大 Hash 精确内存
redis-cli -p 16379 -a '<password>' -n 2 MEMORY USAGE "SOURCE_CRAWL_REQUEST_STAT:2026-05-24:PRICE:REPEAT_COUNT"
# 结果: 134,239,320 bytes ≈ 128MB
```

---

### 7.6 内存占比总结

| 项目 | 大小 |
|------|------|
| GOODSCRAWL::S::* 值总大小 | ~6.78GB |
| GOODSCRAWL::S::* 总占用（含元数据 71B/键） | ~8-9GB |
| SOURCE_CRAWL_REQUEST_STAT Hash | ~128MB |
| Redis 总内存 | 11.91GB |

---

## :material-code-braces: 八、代码层面根因分析

### 8.1 缓存 TTL 过长

**文件：** `goods-crawl/.../service/common/CacheConfig.java`

```java
TASK_REQUEST_CONTEXT = createCache("taskRequestContext", ..., Duration.ofDays(3));  // 3 天
ZHENG_CAI_CRAWL_CONTEXT = createCache("zhengCaiCrawlContext", ..., Duration.ofDays(4));  // 4 天
ZHENG_CAI_SEARCH_CRAWL_CONTEXT = createCache("zhengCaiSearchCrawlContext", ..., Duration.ofDays(4));  // 4 天
```

**问题：** TTL 3-4 天过长，在大量并发的爬取任务下，缓存键持续堆积。

---

### 8.2 CATALOGSMAP 未设置 TTL

**文件：** `TenantCatalogsServiceImpl.java` 第 105 行

```java
redisTemplate.opsForValue().set(CacheKey.TENANT_CATALOGSMAP + tenantId, tenantCatalogMap);
// ❌ 缺少过期时间参数，导致键永不过期
```

---

### 8.3 SOURCE_CRAWL_REQUEST_STAT 旧数据堆积

每日统计 Hash 字段过多（单日可达 104 万字段），历史数据未自动清理。

---

## :material-format-list-checks: 九、待处理的优化建议

| 优化项 | 现状 | 建议 | 优先级 |
|--------|------|------|--------|
| 缩短 GOODSCRAWL TTL | 3-4 天 | 改为 1 天 | :red_circle: 高 |
| CATALOGSMAP 加 TTL | 永不过期 | 设置为 1 天 | :red_circle: 高 |
| SOURCE_CRAWL_REQUEST_STAT 清理 | 单日 128MB | 加入定期清理逻辑 | :orange_circle: 中 |
| 可安全删除旧 STAT 数据 | 不影响业务 | `DEL` 老旧日期的 STAT 键 | :green_circle: 低 |

---

## :material-speedometer: 十、命令速查表

### Redis 排查命令

| 场景 | 命令 |
|------|------|
| 查看系统内存 | `free -h` |
| 查看 OOM 日志 | `dmesg \| grep -i "oom\|killed" \| tail -20` |
| 查看 Redis 进程 | `ps aux \| grep redis` |
| 查看端口监听 | `netstat -tlnp \| grep 6379` |
| 查看 Docker Redis 容器 | `docker ps \| grep redis` |
| 连接 Docker Redis | `docker exec -it redis6 redis-cli -p 6379 -a '<password>' -n 2` |
| 宿主机连接 Redis | `redis-cli -p 16379 -a '<password>' -n 2` |
| 查看 Redis 内存配置 | `INFO memory` |
| 动态设置 Redis 内存 | `CONFIG SET maxmemory 12884901888` |
| 查看 Redis 配置挂载 | `docker inspect redis6 \| grep -A 20 "Mounts"` |
| 修改 Redis 配置文件 | `sed -i 's/^maxmemory.*/maxmemory 12gb/' /etc/conf/redis/redis.conf` |
| 重启 Redis 容器 | `docker restart redis6` |
| 查看 Redis 容器日志 | `docker logs redis6 --tail 50` |
| 扫描大键 | `docker exec -it redis6 redis-cli -p 6379 -a '<pwd>' -n 2 --bigkeys -i 0.1` |
| 查看键总数 | `DBSIZE` |
| 统计前缀键数量 | `--scan --pattern "PREFIX*" \| wc -l` |
| 查看键 TTL | `TTL <key>` |
| 查看键内存占用 | `MEMORY USAGE <key>` |
| 抽样键分布 | `--scan --pattern "*" \| head -N` |
| 删除键 | `DEL <key>` |

---

### RabbitMQ 命令

| 场景 | 命令 |
|------|------|
| 启动 RabbitMQ | `./rabbitmqStart.sh` |
| 查看 RabbitMQ 消费者 | `rabbitmqctl list_consumers` |
| 查看 RabbitMQ 状态 | `rabbitmqctl status` |
| 查看 RabbitMQ 日志 | `tail -500 /data/rabbitmq/rabbitmq_server/var/log/rabbitmq/rabbit@logstach.log` |

---

## :material-clipboard-text: 十一、总结

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| RabbitMQ 宕机 | 系统内存耗尽，Erlang VM 崩溃 | 添加 Swap + 重启服务 |
| 系统内存耗尽 | Redis maxmemory=25GB 过高 | 降低至 12GB |
| 进程被杀死 | 无 Swap 空间，OOM Killer 触发 | 添加 8GB Swap |
| 配置不持久 | Docker 容器权限不足 | 修改宿主机挂载配置文件 |
| DB2 内存占用 11.91G | GOODSCRAWL 缓存 TTL 3-4 天，2200 万键 | 缩短 TTL 至 1 天（待改代码） |
| CATALOGSMAP 永不过期 | 代码未设 TTL | 添加 expire 参数（待改代码） |

---

> :calendar: 编写日期：2026-05-25

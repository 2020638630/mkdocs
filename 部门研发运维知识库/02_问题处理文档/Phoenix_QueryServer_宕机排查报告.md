# :material-server-off: Phoenix QueryServer 频繁宕机排查报告

---

## :material-information: 基本信息

| 项目 | 内容 |
|------|------|
| 服务器 | hbase-0001 |
| 服务 | Phoenix QueryServer 6.0.0 |
| 服务端口 | 8765 |
| 安装路径 | `/data/phoenix-queryserver-6.0.0/` |
| 日志路径 | `/tmp/phoenix/` |
| 排查日期 | 2026-06-04 |

---

## :material-alert: 问题现象

运维人员发现 Phoenix QueryServer 服务频繁宕机，无法持续稳定运行。

---

## :material-magnify: 排查过程

### 1. 确认服务状态

```bash
ps aux | grep -i queryserver
```

执行后发现 **服务未启动**，没有任何 queryserver 相关进程。

---

### 2. 启动服务

查看启动脚本：

```bash
cat /data/phoenix-queryserver-6.0.0/start.sh
```

启动脚本内的 JVM 参数：

```
-Xmx15G -Xms15G
-XX:MaxMetaspaceSize=1G -XX:MetaspaceSize=512M
-XX:ReservedCodeCacheSize=256M
```

通过 `queryserver.py start` 启动服务，观察日志确认服务成功监听 8765 端口。

---

### 3. 检查日志中的告警

日志中出现两个 WARN 信息，经分析均不影响正常运行：

| 告警 | 原因 | 影响 |
|------|------|------|
| `NativeCodeLoader: Unable to load native-hadoop library` | 缺少 Hadoop 本地库 | 仅影响性能，不影响功能 |
| `MetricsConfig: Cannot locate configuration` | 缺少 Metrics 配置文件 | 不影响运行，使用默认配置 |

---

### 4. 排查历史宕机原因

#### 4.1 分析日志文件

查看 `/tmp/phoenix/` 下的历史日志文件：

```
phoenix-root-queryserver.log.2026-06-03
phoenix-root-queryserver.log.2026-06-02
phoenix-root-queryserver.log.2026-06-01
...
```

**关键发现：** 多天日志均在 **凌晨 02:00 ~ 02:03** 左右结束，末尾没有任何 ERROR 或异常堆栈信息，说明进程是被外部强制终止，而非自身崩溃。

#### 4.2 检查系统日志

```bash
dmesg | grep "killed\|oom"
```

**关键证据 — OOM Killer 记录：**

```
Killed process 28452 (java), anon-rss: 17054640kB (~16.3GB)
Killed process 14254 (java), anon-rss: 16906756kB (~16.1GB)
Killed process 25869 (java), anon-rss: 12163388kB (~11.6GB)
```

---

## :material-root: 根因分析

### OOM Killer 机制

Linux 内核的 OOM Killer（Out of Memory Killer）在系统物理内存耗尽时，会根据进程内存占用等评分，自动杀掉得分最高的进程以释放内存。

### 问题根因

| 项目 | 数值 |
|------|------|
| 服务器物理内存 | **~14.7GB**（14720MB） |
| JVM 堆设置 (-Xmx) | **15GB** |
| 元空间上限 | 1GB |
| 代码缓存 | 256MB |
| 进程实际 RSS 占用 | **11.6 ~ 16.3GB** |

**根本原因：JVM 最大堆 `-Xmx15G` 设置过大，超出了服务器物理内存（~14.7GB）。**

Java 进程实际内存占用 = 堆内存 + 元空间 + 代码缓存 + 线程栈 + Off-Heap 内存，当总占用超过物理内存时，系统内存不足，触发 OOM Killer 杀掉 Java 进程。

### 触发场景推测

凌晨 02:00 左右可能是定时任务执行高峰期，Phoenix QueryServer 在该时段处理大量查询请求，内存占用攀升至临界值，最终触发 OOM Killer。

---

## :material-wrench: 解决方案

### 方案一：调整 JVM 参数（推荐立即执行）

修改 `/data/phoenix-queryserver-6.0.0/start.sh`：

```bash
# 修改前
-Xmx15G -Xms15G

# 修改后
-Xmx10G -Xms10G
```

将堆内存从 15G 降至 10G，为操作系统和其他进程预留足够内存。

修改后重启服务：

```bash
/data/phoenix-queryserver-6.0.0/start.sh
```

---

### 方案二：增加物理内存（长期方案）

将服务器内存扩容至 **32GB** 或更高，从根本上解决资源不足问题。

---

### 方案三：创建 Swap 作为应急缓冲

```bash
# 创建 8GB swap 文件
dd if=/dev/zero of=/swapfile bs=1M count=8192
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# 持久化配置
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

> **注意：** Swap 只能作为临时缓冲，会严重影响性能，不应作为长期方案。

---

## :material-check-circle: 验证方法

调整 JVM 参数后，持续观察以下指标：

```bash
# 1. 监控进程内存占用
watch -n 1 'ps aux | grep java | grep queryserver'

# 2. 检查 OOM 事件
dmesg -T | grep -i "killed\|oom"

# 3. 观察日志末尾（连续多天凌晨时段）
tail -f /tmp/phoenix/phoenix-root-queryserver.log
```

---

## :material-summary: 总结

| 环节 | 结论 |
|------|------|
| 宕机原因 | JVM `-Xmx15G` 超出物理内存（14.7GB），凌晨高负载时触发 OOM Killer |
| 直接证据 | `dmesg` 中多次记录 `Killed process (java)`，RSS 11.6~16.3GB |
| 紧急修复 | 将 `-Xmx` 调整为 10G，重启服务 |
| 长期建议 | 扩容物理内存至 32GB |

---

> :calendar: 编写日期：2026-06-04

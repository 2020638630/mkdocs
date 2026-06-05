# :material-server-network: HBase / Spark 集群排查与运维命令手册

:material-file-document-edit: **文档类型**: 工具手册 |
:material-account-clock: **更新时间**: 2026-06-04 |
:material-account: **维护人**: 研发团队 |
:material-tag: **标签**: HBase, Spark, 集群运维, 命令手册, 磁盘排查

> **适用集群**: 5 节点 HBase 2.4.9 + Spark 3.0.3 Standalone 集群  
> **节点**: hbase-0001 ~ hbase-0005

---

## :material-harddisk: 磁盘空间排查

### 查看各节点整体磁盘使用率

```bash
df -h
```

### 查看根目录下一级目录占用大小

```bash
du -sh /* 2>/dev/null | sort -rh
```

### 查看指定目录下各子目录大小

```bash
# 例如排查 /data 目录
du -sh /data/* | sort -rh

# 递归查两层
du -d 2 -h /data/ | sort -rh | head -30
```

### 查找大于 1G 的文件

```bash
find /data -type f -size +1G -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh
```

### 统计某目录下文件数量和总大小

```bash
# 文件数量
find /data/spark-3.0.3-bin-hadoop3.2/work -type f | wc -l

# 总大小
du -sh /data/spark-3.0.3-bin-hadoop3.2/work
```

---

## :material-database: HDFS 操作

### 查看 HDFS 根目录下各目录大小

```bash
hdfs dfs -du -h /
```

### 查看 HBase 数据占用

```bash
hdfs dfs -du -h /hbase | sort -rh
```

### 查看 DataNode 数据目录大小

```bash
du -sh /data/hadoop-3.2.2/data/*
du -sh /data/hadoop-3.2.2/data/current/BP-*
```

### 分开统计 hadoop 数据和日志

```bash
du -sh /data/hadoop-3.2.2/data /data/hadoop-3.2.2/logs
```

---

## :material-fire: HBase 运维

### 查看 HBase RegionServer 状态

```bash
# 查看 RS 进程
ps aux | grep HRegionServer | grep -v grep

# 统计 RS 数量
ps aux | grep HRegionServer | grep -v grep | wc -l
```

### HBase 启动命令

```bash
cd /data/hbase-2.4.9/bin
./start-hbase.sh
```

### 单独启动某节点 RegionServer

```bash
# 在目标节点执行
hbase-daemon.sh start regionserver

# 或
cd /data/hbase-2.4.9/bin
./hbase-daemon.sh start regionserver
```

### 查看 RegionServer 启动日志/错误

```bash
# 查看 .out 文件（启动错误通常在这里）
cat /data/hbase-2.4.9/logs/hbase-root-regionserver-$(hostname).out

# 实时跟踪
tail -f /data/hbase-2.4.9/logs/hbase-root-regionserver-$(hostname).log

# 查看 ERROR/WARN
grep -E "ERROR|WARN|FATAL" /data/hbase-2.4.9/logs/hbase-root-regionserver-$(hostname).log | tail -50
```

### 查看 Phoenix Query Server (PQS)

```bash
# 查看 PQS 进程
ps aux | grep queryserver | grep -v grep

# 查看 PQS 端口（默认 8765）
netstat -tulnp | grep 8765
```

---

## :material-flash: Spark 运维

### 查看 Spark 进程

```bash
# Master 进程
ps aux | grep org.apache.spark.deploy.master.Master | grep -v grep

# Worker 进程
ps aux | grep org.apache.spark.deploy.worker.Worker | grep -v grep

# 查看所有 Spark 相关进程
ps aux | grep spark | grep -v grep
```

### 查看 Spark 各 Worker 节点进程状态

```bash
# 在所有节点执行统计 Worker 数量
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo "=== $host ==="
    ssh $host "ps aux | grep 'org.apache.spark.deploy.worker.Worker' | grep -v grep | wc -l"
done
```

### 查看各节点 Spark work 目录占用大小

```bash
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo "=== $host ==="
    ssh $host "du -sh /data/spark-3.0.3-bin-hadoop3.2/work 2>/dev/null || echo 'dir not found'"
done
```

### 查看 work 目录下的应用列表

```bash
ls -la /data/spark-3.0.3-bin-hadoop3.2/work/
```

### 查看 7 天前的旧 Spark 应用目录

```bash
find /data/spark-3.0.3-bin-hadoop3.2/work -maxdepth 1 -name "app-*" -mtime +7 -exec ls -ld {} \;
```

### 清理 Spark work 目录

!!! warning "重要提示"
    `work/` 目录存储的是 Spark 作业运行时临时文件（JAR 包分发 + stderr/stdout 日志），不是计算结果。清理不会影响 HBase/HDFS 数据，但正在运行的作业会受影响。

=== "单节点清理"
    ```bash
    # 1. 先查看哪些是 7 天前的（预览，确认无误）
    find /data/spark-3.0.3-bin-hadoop3.2/work -maxdepth 1 -name "app-*" -mtime +7

    # 2. 确认当前无活跃任务（关键！）
    ps aux | grep spark | grep -v grep

    # 3. 删除 7 天前的应用目录
    find /data/spark-3.0.3-bin-hadoop3.2/work -maxdepth 1 -name "app-*" -mtime +7 -exec rm -rf {} \;

    # 4. 验证释放空间
    df -h
    ```

=== "集群批量清理"
    ```bash
    for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
        echo "=== Cleaning $host ==="
        ssh $host "echo '7 day old dirs:'; find /data/spark-3.0.3-bin-hadoop3.2/work -maxdepth 1 -name 'app-*' -mtime +7 | wc -l; find /data/spark-3.0.3-bin-hadoop3.2/work -maxdepth 1 -name 'app-*' -mtime +7 -exec rm -rf {} \; 2>/dev/null; echo 'Done'"
    done

    # 5. 清理后验证各节点磁盘
    for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
        echo "=== $host ==="
        ssh $host "df -h / | tail -1"
    done
    ```

---

### 清理实操完整流程

!!! example "实际清理操作记录"
    本流程为实际清理操作记录，单节点 + 批量合并执行。

```bash
# ====== 第一步：确认有无活跃 Spark 任务（关键！） ======
ps aux | grep spark | grep -v grep

# ====== 第二步：查看清理前 work 目录大小 ======
du -sh /data/spark-3.0.3-bin-hadoop3.2/work

# ====== 第三步：预览将要删除的 7 天前目录 ======
find /data/spark-3.0.3-bin-hadoop3.2/work -maxdepth 1 -name "app-*" -mtime +7

# ====== 第四步：执行清理 ======
find /data/spark-3.0.3-bin-hadoop3.2/work -maxdepth 1 -name "app-*" -mtime +7 -exec rm -rf {} \;

# ====== 第五步：查看清理后大小（对比释放空间） ======
du -sh /data/spark-3.0.3-bin-hadoop3.2/work

# ====== 示例输出（hbase-0005 实际清理结果） ======
# 清理前: 160G    /data/spark-3.0.3-bin-hadoop3.2/work
# 清理后: 6.3G    /data/spark-3.0.3-bin-hadoop3.2/work
# 释放约 154G 空间
```

```bash
# ====== 集群批量清理（含清理前后大小对比） ======
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo "=== $host ==="
    ssh $host "echo '清理前:'; du -sh /data/spark-3.0.3-bin-hadoop3.2/work 2>/dev/null; echo '删除7天前目录...'; find /data/spark-3.0.3-bin-hadoop3.2/work -maxdepth 1 -name 'app-*' -mtime +7 -exec rm -rf {} \; 2>/dev/null; echo '清理后:'; du -sh /data/spark-3.0.3-bin-hadoop3.2/work 2>/dev/null; echo '---'"
done
```

```bash
# ====== 第六步：清理后验证所有节点 /data 磁盘使用率 ======
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo "=== $host ==="
    ssh $host "df -h /data | tail -1"
done

# ====== 示例输出 ======
# === hbase-0001 ===
# /dev/vdb  1008G  792G  165G  83% /data
# === hbase-0002 ===
# /dev/vdb  1008G  697G  260G  73% /data
# === hbase-0003 ===
# /dev/vdb  1008G  803G  155G  84% /data
# === hbase-0004 ===
# /dev/vdb  1008G  610G  347G  64% /data
# === hbase-0005 ===
# /dev/vdb  1008G  730G  228G  77% /data
```

---

### Spark 自动清理配置

在 `/data/spark-3.0.3-bin-hadoop3.2/conf/spark-defaults.conf` 中添加：

```properties
# 开启 Worker 自动清理
spark.worker.cleanup.enabled=true
# 应用数据保留时间（秒），604800 = 7天
spark.worker.cleanup.appDataTtl=604800
# 清理检查间隔（秒），1800 = 30分钟
spark.worker.cleanup.interval=1800
```

!!! tip "批量添加配置到所有节点"
    ```bash
    for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
        echo "=== $host ==="
        ssh $host "echo -e '\n# 开启 Worker 自动清理\nspark.worker.cleanup.enabled=true\nspark.worker.cleanup.appDataTtl=604800\nspark.worker.cleanup.interval=1800' >> /data/spark-3.0.3-bin-hadoop3.2/conf/spark-defaults.conf"
    done
    ```

!!! warning "注意"
    配置后需重启 Spark Worker 生效。

=== "批量重启所有 Spark Worker"
    ```bash
    for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
        echo "=== Restarting Worker on $host ==="
        ssh $host "cd /data/spark-3.0.3-bin-hadoop3.2/sbin && ./stop-worker.sh"
        ssh $host "cd /data/spark-3.0.3-bin-hadoop3.2/sbin && ./start-worker.sh spark://hbase-0001:7077"
    done
    ```

---

## :material-text-box: 日志清理

### Nginx 日志清理

```bash
# 查看日志目录大小
du -sh /data/nginx/logs/

# 查看日志文件列表
ls -lh /data/nginx/logs/

# 按日期删除 3 天前的日志文件
find /data/nginx/logs/ -type f -mtime +3 -delete

# 删除后验证
du -sh /data/nginx/logs/

# 清空当前正在写入的日志文件（保留文件避免权限问题）
: > /data/nginx/logs/access.log
: > /data/nginx/logs/error.log

# 验证当前日志文件已清空为 0
ls -lh /data/nginx/logs/access.log /data/nginx/logs/error.log
```

### Nginx 日志轮转配置

创建 `/etc/logrotate.d/nginx-hbase`：

```bash
/data/nginx/logs/*.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        [ -f /data/nginx/logs/nginx.pid ] && kill -USR1 `cat /data/nginx/logs/nginx.pid`
    endscript
}
```

### 通用日志清理

```bash
# 清空日志文件（保留文件不删除）
> /path/to/logfile.log

# 只保留最新 100000 行
tail -n 100000 /path/to/logfile.log > /tmp/logfile.tmp && mv /tmp/logfile.tmp /path/to/logfile.log

# 删除 7 天前的 .log 文件
find /path/to/logs -name "*.log" -mtime +7 -delete

# 压缩 3 天前的日志
find /path/to/logs -name "*.log" -mtime +3 -exec gzip {} \;
```

---

## :material-bug: JVM / 配置文件特殊字符排查

### 检查文件中是否含有不可见/特殊字符

```bash
# cat -A 显示所有隐藏字符（$ 表示行尾，^M 表示 \r，^I 表示 Tab）
cat -A /data/hbase-2.4.9/conf/hbase-env.sh | head -160

# 只查看关键行
sed -n '140,150p' /data/hbase-2.4.9/conf/hbase-env.sh | cat -A

# 搜索可能包含特殊字符的行（非 ASCII 字符）
grep -n '[^\x00-\x7F]' /data/hbase-2.4.9/conf/hbase-env.sh

# 查看文件编码
file /data/hbase-2.4.9/conf/hbase-env.sh
```

### 常见特殊字符问题

| 字符 | cat -A 显示 | 说明 |
| :--- | :--- | :--- |
| 正常连字符 `-` | `-` | 代码中应使用的 |
| 短破折号 `–` | `M-bM-^@M-^S` | :warning: 不可用于 JVM 参数 |
| 长破折号 `—` | `M-bM-^@M-^T` | :warning: 不可用于 JVM 参数 |
| 中文引号 `"` | 显示为多字节 | :warning: 不可用于 shell |

### 排查 JVM 启动失败

```bash
# 查看进程的完整启动命令
cat /proc/<pid>/cmdline | tr '\0' ' '

# 查看 .out 文件中的启动错误
cat /data/hbase-2.4.9/logs/hbase-root-regionserver-$(hostname).out

# 常见错误："Error: Could not find or load main class –Xmx20g"
# → 说明 JVM 参数中有特殊字符，参数被当成主类名
```

---

## :material-alert-octagon: OOM / 进程异常退出排查

### 查看系统杀进程记录

```bash
# 查看 OOM Killer 记录
dmesg | grep -i "out of memory"
dmesg | grep -i "killed process"

# 查看最近 OOM 事件（带时间戳）
dmesg -T | grep -i "out of memory"

# 查看被 killed 的进程列表
dmesg | grep -i "Killed" | tail -20
```

### 查看系统日志

```bash
# 查看系统日志中的 OOM 相关信息
grep -i "out of memory" /var/log/messages
grep -i "invoked oom-killer" /var/log/messages

# 或
journalctl | grep -i "oom"
```

### JVM 进程 OOM 排查

```bash
# 查看 JVM 堆配置
ps aux | grep java | grep -oP '\-Xm[sx]\S+'

# 查看直接内存配置
ps aux | grep java | grep -oP '\-XX:MaxDirectMemorySize=\S+'

# 查看是否生成 heap dump
ls -lh /data/hbase-2.4.9/*.hprof 2>/dev/null
ls -lh /data/spark-3.0.3-bin-hadoop3.2/work/**/*.hprof 2>/dev/null
```

---

## :material-server: 批量多节点操作

### 对集群所有节点执行相同命令

```bash
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo "=== $host ==="
    ssh $host "<要执行的命令>"
done
```

### 实用示例：批量检查磁盘

```bash
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo "=== $host ==="
    ssh $host "df -h / /data 2>/dev/null"
done
```

### 实用示例：批量检查关键目录

```bash
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo "=== $host ==="
    ssh $host "du -sh /data/spark-3.0.3-bin-hadoop3.2/work /data/hbase-2.4.9 /data/hadoop-3.2.2/data 2>/dev/null"
done
```

### 实用示例：批量检查磁盘使用率是否 > 90%

```bash
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo -n "$host: "
    ssh $host "df -h / | tail -1 | awk '{print \$5}'"
done
```

---

## :material-map-marker-path: 集群关键路径速查

| 组件 | 路径 |
| :--- | :--- |
| HBase 安装目录 | `/data/hbase-2.4.9/` |
| HBase 配置文件 | `/data/hbase-2.4.9/conf/hbase-env.sh` |
| HBase 日志目录 | `/data/hbase-2.4.9/logs/` |
| HBase RS .out 日志 | `/data/hbase-2.4.9/logs/hbase-root-regionserver-<hostname>.out` |
| Spark 安装目录 | `/data/spark-3.0.3-bin-hadoop3.2/` |
| Spark work 目录 | `/data/spark-3.0.3-bin-hadoop3.2/work/` |
| Spark 配置文件 | `/data/spark-3.0.3-bin-hadoop3.2/conf/spark-defaults.conf` |
| Hadoop DataNode 数据 | `/data/hadoop-3.2.2/data/` |
| HDFS HBase 数据 | `/hbase` (HDFS 路径) |
| Nginx 日志 | `/data/nginx/logs/` |
| Phoenix Query Server | 端口 8765 (hbase-0004) |

---

## :warning: 重要阈值参考

| 指标 | 阈值 | 说明 |
| :--- | :--- | :--- |
| 磁盘使用率 | < 85% | 超过 90% HBase RS 可能无法启动或进入只读模式 |
| RS 堆内存 | -Xmx20g | 当前集群配置 |
| RS 直接内存 | -XX:MaxDirectMemorySize=20g | 当前集群配置 |
| Spark work 自动清理 TTL | 604800s (7天) | 推荐配置 |
| nginx 日志保留 | 7 天 | 推荐通过 logrotate 管理 |

---

## :material-alert-circle: 常见问题速查

### 问题 1：RegionServer 启动失败，报 "Could not find or load main class"

!!! bug "排查步骤"
    ```bash
    # 1. 查看 .out 文件
    cat /data/hbase-2.4.9/logs/hbase-root-regionserver-$(hostname).out

    # 2. 检查 hbase-env.sh 是否有特殊字符
    sed -n '145,150p' /data/hbase-2.4.9/conf/hbase-env.sh | cat -A

    # 3. 检查磁盘是否满了
    df -h

    # 4. 修复后重启
    cd /data/hbase-2.4.9/bin && ./hbase-daemon.sh start regionserver
    ```

---

### 问题 2：磁盘空间快速被占满

!!! bug "排查步骤"
    ```bash
    # 1. 先找到磁盘大户
    df -h
    du -sh /data/* 2>/dev/null | sort -rh | head -10

    # 2. 常见的"嫌疑犯"：
    #    - Nginx 日志: /data/nginx/logs/
    #    - Spark work:  /data/spark-3.0.3-bin-hadoop3.2/work/
    #    - Hadoop data: /data/hadoop-3.2.2/data/  (⚠️ 此目录不能删)
    #    - 业务日志:    /data/<服务名>/logs/

    # 3. 针对性清理
    ```

---

### 问题 3：Phoenix 查询卡住不响应

!!! bug "排查步骤"
    ```bash
    # 1. 检查 PQS 进程是否存在
    ps aux | grep queryserver | grep -v grep

    # 2. 检查 PQS 端口是否监听
    netstat -tulnp | grep 8765

    # 3. 检查集群磁盘空间（RS 可能因磁盘满进入只读）
    for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
        echo -n "$host: "
        ssh $host "df -h / | tail -1 | awk '{print \$5}'"
    done

    # 4. 检查 RS 日志是否有 OOM 或磁盘满相关报错
    grep -E "OutOfMemory|low disk|disk full" /data/hbase-2.4.9/logs/hbase-root-regionserver-*.log
    ```

---

**最后更新**: 2026-06-02  
**记录集群**: hbase-0001 ~ hbase-0005 (HBase 2.4.9 + Spark 3.0.3 Standalone)

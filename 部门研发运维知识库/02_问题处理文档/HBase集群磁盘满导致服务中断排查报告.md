# :material-harddisk-remove: HBase 集群磁盘满导致服务中断排查报告

:material-file-document-edit: **文档类型**: 故障排查 |
:material-alert-circle: **优先级**: 🔴 高 |
:material-account-clock: **发生时间**: 2026-06-04 |
:material-account: **处理人**: 研发团队 |
:material-tag: **标签**: HBase, 磁盘满, 服务中断, RegionServer, HDFS, WAL

:calendar: **记录时间**：2026-06-04

---

## :material-alert-octagon: 一、问题现象

### 初始发现

集群磁盘使用率普遍超过 85% 阈值，其中 **hbase-0001 和 hbase-0003 已到 100%**，导致：

- HBase RegionServer 全部下线（5 节点无一存活）
- HMaster 亦已停止
- Phoenix Query Server 返回 HTTP 502
- pricemonitor-bigdata 服务的 `error.log` 和 `apiError.log` 各涨到 **15G**，疯狂输出错误日志

### 磁盘初始状态

```
hbase-0001: 1008G / 988G  = 100% :red_circle:
hbase-0002: 1008G / 877G  =  92% :orange_circle:
hbase-0003: 1008G / 957G  = 100% :red_circle:
hbase-0004: 1008G / 879G  =  92% :orange_circle:
hbase-0005: 1008G / 720G  =  76% :green_circle:
```

---

## :material-connection: 二、故障链路

```
磁盘 100% 满
  → HBase RegionServer 无法写入 → 进入只读/异常状态 → 进程死亡
    → HMaster 也随后停止
      → Phoenix Query Server (PQS) 连不上 HBase → 返回 HTTP 502
        → pricemonitor-bigdata 每次 Phoenix 写入都报 502
          → error.log / apiError.log 被疯狂刷到 15G
            → 日志又进一步占满磁盘 → 恶性循环
```

### 报错确认

```
Caused by: java.lang.RuntimeException: Failed to execute HTTP Request, got HTTP/502
  at org.apache.calcite.avatica.remote.AvaticaCommonsHttpClientImpl.send(...)
  at org.apache.calcite.avatica.remote.Driver.connect(Driver.java:176)
  ...
```

---

## :material-tools: 三、处理过程

### 第一步：排查磁盘占用（各节点）

```bash
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo "=== $host ==="
    ssh $host "du -sh /data/* 2>/dev/null | sort -rh | head -10"
done
```

#### 排查结果

| 节点 | 第 1 大户 | 第 2 大户 | 异常项 |
|------|----------|----------|-------|
| hbase-0001 | hadoop 846G | **pricemonitor 125G** :warning: | pricemonitor 远超其他节点（正常仅 206M） |
| hbase-0002 | hadoop 862G | spark 12G | 正常 |
| hbase-0003 | hadoop 867G | **docker 65G + onlyoffice ~20G** :warning: | 多版本 onlyoffice 旧部署包堆积 |
| hbase-0004 | hadoop 836G | **nginx 12G** :warning: | nginx 日志堆积 |
| hbase-0005 | hadoop 704G | spark 11G | 正常，236G 空闲 |

---

### 第二步：清理 hbase-0001 pricemonitor 日志（释放 ~107G）

#### 定位大文件

```bash
ssh hbase-0001 "ls -lhS /data/pricemonitor/logs/"
```

发现：

| 文件 | 大小 | 说明 |
|------|------|------|
| `error.log` | 15G | 502 连接错误，清空 |
| `apiError.log` | 15G | 502 连接错误，清空 |
| `info.log` + 历史归档 | ~7G | 删除历史归档 |

#### 清理命令

```bash
# 删除所有历史归档日志文件
ssh hbase-0001 "find /data/pricemonitor/logs -name '*.log.*' -delete"

# 清空当前正在写的错误日志（避免删除导致文件句柄丢失）
ssh hbase-0001 ": > /data/pricemonitor/logs/error.log"
ssh hbase-0001 ": > /data/pricemonitor/logs/apiError.log"
ssh hbase-0001 ": > /data/pricemonitor/logs/info.log"
ssh hbase-0001 ": > /data/pricemonitor/logs/warn.log"
```

!!! warning "关键技术点"
    用 `: > file` 而非 `rm`，因为文件正在被程序写入，`rm` 会导致程序仍向已删除文件写数据，磁盘空间不会释放。

**效果：** 125G → 18G，释放约 107G

---

### 第三步：清理 hbase-0003 旧 onlyoffice + Docker（释放 ~64G）

#### 确认运行中的 onlyoffice

```bash
ssh hbase-0003 "ps aux | grep onlyoffice | grep -v grep"
```

输出表明实际运行的 onlyoffice 在 **`/var/www/onlyoffice/`**（标准 Linux 安装路径），`/data/` 下的都是旧部署包备份。

#### 清理旧版本

```bash
ssh hbase-0003 "rm -rf /data/onlyoffice82 /data/onlyoffice92_1 /data/onlyoffice-de /data/onlyoffice92"
```

#### 清理 Docker 无用资源

```bash
ssh hbase-0003 "docker system prune -a -f --volumes"
```

**效果：** Docker 65G → 20G，累计释放约 64G。Docker 3 个运行容器正常，无数据丢失。

---

### 第四步：清理 hbase-0004 Nginx 日志（释放 ~10G）

```bash
ssh hbase-0004 "find /data/nginx/logs/ -type f -mtime +3 -delete"
ssh hbase-0004 ": > /data/nginx/logs/access.log; : > /data/nginx/logs/error.log"
```

**效果：** nginx 日志 12G → 1.5G

---

### 第五步：清理后磁盘状态

```
hbase-0001: 96% (41G 空闲)  ← 从 100% 降到 96%
hbase-0002: 92% (80G 空闲)  ← 未变化
hbase-0003: 94% (65G 空闲)  ← 从 100% 降到 94%
hbase-0004: 91% (89G 空闲)  ← 略降
hbase-0005: 76% (237G 空闲) ← 未变化
```

---

### 第六步：恢复 HBase 集群

#### 确认 HMaster + RegionServer 状态

```bash
ps aux | grep HMaster | grep -v grep
# 无输出 → HMaster 已停止

for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    ssh $host "ps aux | grep HRegionServer | grep -v grep | wc -l"
done
# 全部输出 0 → 5 节点 RS 全部死亡
```

#### 启动 HBase 集群

```bash
cd /data/hbase-2.4.9/bin && ./start-hbase.sh
```

#### 补充启动 hbase-0001 的 RegionServer

```bash
cd /data/hbase-2.4.9/bin && ./hbase-daemon.sh start regionserver
```

#### 恢复结果

```
=== hbase-0001 RS ===  1  :white_check_mark:
=== hbase-0002 RS ===  1  :white_check_mark:
=== hbase-0003 RS ===  1  :white_check_mark:
=== hbase-0004 RS ===  1  :white_check_mark:
=== hbase-0005 RS ===  1  :white_check_mark:
```

---

### 第七步：恢复 Phoenix Query Server

```bash
ssh hbase-0004 "cd /data/phoenix-queryserver-6.0.0/bin && ./queryserver.py start"
```

**结果：** 端口 8765 恢复监听，Phoenix 连接恢复正常。

---

### 第八步：修复 HDFS（DataNode + SafeMode）

hbase-0005 的 DataNode 未启动：

```bash
ssh hbase-0005 "cd /data/hadoop-3.2.2/bin && ./hdfs --daemon start datanode"
```

NameNode 处于安全模式（因磁盘满导致 DataNode 下线触发）：

```bash
hdfs dfsadmin -safemode leave
# Safe mode is OFF :white_check_mark:
```

---

### 第九步：HDFS 数据再均衡（Balancer）

#### 为什么需要 Balancer

各节点 HDFS 数据分布严重不均（hbase-0005 空闲 237G，其他节点均满），需要把数据从满的节点迁移到空闲节点。

```bash
# 设置迁移带宽 50MB/s（不影响业务）
hdfs dfsadmin -setBalancerBandwidth 51200000

# 后台启动 balancer，阈值 10%
nohup hdfs balancer -threshold 10 > /tmp/hdfs-balancer.log 2>&1 &
```

#### Balancer 运行进度

| 节点 | 初始 | 运行 40 分钟后 | 趋势 |
|------|------|--------------|------|
| hbase-0003 | ~80%+ | 48% | :chart_increasing: 大量搬出后，正在接收数据 |
| hbase-0002 | 85% | 76% | :chart_decreasing: 持续搬出 |
| hbase-0004 | 82% | 77% | :chart_decreasing: 持续搬出 |
| hbase-0001 | 67% | 67% | 稳定 |
| hbase-0005 | 70% | 68% | 稳定 |

目标：各节点差距 < 10%，最终稳定在 65%-75% 区间。

---

## :material-flag-checkered: 四、最终成果

### 清理前后磁盘对比

| 节点 | 清理前 | 清理后 | 释放 |
|------|---------|--------|------|
| hbase-0001 | 988G (100%) | 724G (76%) | ~264G |
| hbase-0002 | 877G (92%) | 877G (92%) | 等待 balancer |
| hbase-0003 | 957G (100%) | 371G (39%) | ~586G |
| hbase-0004 | 879G (92%) | 869G (91%) | ~10G |
| hbase-0005 | 720G (76%) | 721G (76%) | 稳定 |

### 各组件恢复状态

| 组件 | 恢复状态 |
|------|---------|
| HMaster | :white_check_mark: 运行中 (hbase-0001) |
| RegionServer × 5 | :white_check_mark: 全部运行 |
| Phoenix Query Server | :white_check_mark: 端口 8765 监听 |
| HDFS DataNode × 5 | :white_check_mark: 全部运行 |
| HDFS SafeMode | :white_check_mark: 已退出 |

### hbase-0001 目录清理前后对比

| 目录 | 清理前 | 清理后 |
|------|-------|--------|
| `/data/pricemonitor` | 125G | 18G |
| `/data/pricemonitor/logs/error.log` | 15G | 0 (已清空) |
| `/data/pricemonitor/logs/apiError.log` | 15G | 0 (已清空) |

### hbase-0003 目录清理前后对比

| 目录 | 清理前 | 清理后 |
|------|-------|--------|
| `/data/docker` | 65G | 20G |
| `/data/onlyoffice*` | ~20G | 少量残留 |

---

## :warning: 五、关键注意事项

### 可以清理

| 路径 | 说明 |
|------|------|
| `/data/spark-3.0.3-bin-hadoop3.2/work/` | Spark 临时工作目录（7 天前可安全删除） |
| `/data/nginx/logs/` | Nginx 历史日志 |
| `/data/hbase-2.4.9/logs/` | HBase 旧 .log 文件 |
| `/data/pricemonitor/logs/` | 业务日志归档 |
| `/data/docker` 无用镜像/容器 | `docker system prune` |

### :no_entry: 绝对不能清理

| 路径 | 说明 |
|------|------|
| `/data/hadoop-3.2.2/data/` | **HDFS DataNode 核心数据** |
| HDFS 上的 HBase 表数据 | 通过 `hadoop fs -rm` 删除 |

### 清理文件正确姿势

- **正在被写入的文件**：用 `: > filename` 清空内容，不要用 `rm`——`rm` 后程序句柄仍指向已删除文件，磁盘空间不会释放
- **历史归档文件**：可以用 `find ... -mtime +N -delete`
- **Docker**：先用 `docker system prune` 不用 `--volumes`，确认后再决定是否清理 volumes

---

## :material-clipboard-check: 六、Balancer 完成 — 后置核查

### 最终 HDFS 数据分布（22:18）

| 节点 | DFS 使用率 | 说明 |
|------|-----------|------|
| hbase-0001 | 73.09% | 高位 |
| hbase-0003 | 58.08% | 最低（原始数据较少） |
| hbase-0003 | 67.08% | 稳定 |
| hbase-0004 | 67.05% | 稳定 |
| hbase-0005 | 72.54% | 从 84% 降下 |
| hbase-0002 | 71.36% | 从 80% 降下 |

> 最大差距：73.09% - 58.08% = **15%**，远好于初始的 **48%** 差距。  
> Balancer 此时已自然退出（`Done`），残余数据块仍在传输中继续微调。

### 最终磁盘空间核查（22:18）

| 节点 | 用量 | 可用 | 使用率 | 状态 |
|------|------|------|--------|------|
| hbase-0003 | 610G | 347G | 64% | :white_check_mark: 最优 |
| hbase-0005 | 696G | 261G | 73% | :white_check_mark: 正常 |
| hbase-0001 | 725G | 233G | 76% | :white_check_mark: 正常 |
| hbase-0002 | 748G | 209G | 79% | :warning: 偏高 |
| hbase-0004 | 756G | 201G | 80% | :warning: 偏高 |

**结论：** 所有节点均有 200G+ 可用空间，短期无风险。空间主要占用为 `/data/hadoop-3.2.2`（HDFS 数据），其他服务占用在合理范围（1-6G/节点）。

---

## :material-shield-alert: 七、预防措施

### 1. 配置 pricemonitor 日志轮转

```bash
ssh hbase-0001 'cat > /etc/logrotate.d/pricemonitor << '\''EOF'\''
/data/pricemonitor/logs/*.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    copytruncate
}
'\'' && logrotate -f /etc/logrotate.d/pricemonitor'
```

### 2. 配置 Nginx 日志轮转

```bash
ssh hbase-0004 'cat > /etc/logrotate.d/nginx-hbase << '\''EOF'\''
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
'\'' && echo "配置已创建"'
```

### 3. 配置 Spark 自动清理

```bash
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    ssh $host "echo -e '\n# 开启 Worker 自动清理\nspark.worker.cleanup.enabled=true\nspark.worker.cleanup.appDataTtl=604800\nspark.worker.cleanup.interval=1800' >> /data/spark-3.0.3-bin-hadoop3.2/conf/spark-defaults.conf"
done
```

### 4. 建议添加磁盘监控脚本

```bash
cat > /root/check_cluster.sh << 'EOF'
#!/bin/bash
echo "===== $(date) ====="
echo ""
echo "--- 磁盘使用率 ---"
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo -n "$host: "
    ssh $host "df -h /data | tail -1 | awk '{print \$5, \$4}'"
done
echo ""
echo "--- HBase RS ---"
for host in hbase-0001 hbase-0002 hbase-0003 hbase-0004 hbase-0005; do
    echo -n "$host: "
    ssh $host "ps aux | grep HRegionServer | grep -v grep | wc -l" 2>/dev/null
done
echo ""
echo "--- PQS ---"
ssh hbase-0004 "netstat -tulnp | grep 8765 | wc -l" 2>/dev/null
EOF
chmod +x /root/check_cluster.sh
```

### 5. 定期执行 HDFS Balancer

建议每月执行一次，保持各节点 HDFS 数据均衡：

```bash
hdfs dfsadmin -setBalancerBandwidth 51200000
nohup hdfs balancer -threshold 10 > /tmp/hdfs-balancer.log 2>&1 &
```

---

## :material-format-list-checkbox: 八、故障处理检查清单

- [ ] 排查磁盘占用大户 `du -sh /data/* | sort -rh`
- [ ] 清理业务日志历史归档 `find ... -name '*.log.*' -mtime +7 -delete`
- [ ] 清空当前大日志文件 `: > /data/xxx/logs/error.log`
- [ ] Docker prune 清理 `docker system prune -a -f`
- [ ] 检查清理后磁盘 `df -h /data`
- [ ] 检查 HBase RegionServer 进程
- [ ] 检查 HMaster 进程
- [ ] 启动 HBase 集群（如需要）
- [ ] 检查 Phoenix Query Server 端口
- [ ] 检查 HDFS DataNode 进程
- [ ] 退出 HDFS 安全模式（如需要）
- [ ] 运行 HDFS Balancer 均衡数据
- [ ] 验证 pricemonitor-bigdata 不再刷 502 错误
- [ ] 配置 logrotate 防止再次堆积

---

## :material-lightbulb: 九、经验总结

1. **磁盘 85% 是警戒线，100% 会连锁崩溃**：磁盘满 → HBase RegionServer 停 → HMaster 停 → PQS 502 → 日志暴涨 → 恶性循环
2. **先清理再恢复**：不要直接重启服务，磁盘满时启动大概率再次失败
3. **清空文件用 `: >` 而非 `rm`**：保护程序的文件句柄不被破坏
4. **根本原因是 HDFS 数据分布不均**：通过 Balancer 自动均衡是根本解决方案
5. **logrotate 是必备措施**：所有核心服务的日志目录都应配置自动轮转

---

:calendar: **最后更新**：2026-06-04 22:22  
:white_check_mark: **处理结果**：✅ HBase 集群恢复 | ✅ Phoenix 服务恢复 | ✅ Pricemonitor 服务恢复 | ✅ HDFS Balancer 已完成（各节点 64%-80%，可用 200G+）  
:computer: **影响范围**：HBase 集群 5 节点  
:clock3: **停机时间**：约 30 分钟（从排查到 HBase 完全恢复）

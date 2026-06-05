# :material-kubernetes: Kubernetes 运维常用命令手册

---

## :material-clipboard-list: Pod 相关命令

### 查看 Pod

```bash
# 查看命名空间中所有 pod
kubectl get pods -n pricemonitor

# 查看详细信息（包含 IP、节点等）
kubectl get pods -n pricemonitor -o wide

# 实时监控 pod 状态
kubectl get pods -n pricemonitor -w

# 查看特定 pod 的详细信息
kubectl describe pod <pod-name> -n pricemonitor

# 查看所有资源
kubectl get all -n pricemonitor

# 查看 pod 详细信息和事件
kubectl -n pricemonitor describe pod <pod-name>
```

---

### 删除/重启 Pod

```bash
# 删除单个 pod（自动重建）
kubectl delete pod <pod-name> -n pricemonitor

# 批量删除 pod（通过 label 筛选）
kubectl delete pods -l app=<label-name> -n pricemonitor

# 优雅重启 deployment
kubectl rollout restart deployment/<deployment-name> -n pricemonitor

# 强制删除卡住的 pod
kubectl delete pod <pod-name> -n pricemonitor --grace-period=0 --force
```

---

## :material-text-box: 日志查看命令

### kubectl logs（容器标准输出日志）

```bash
# 查看 pod 日志
kubectl logs <pod-name> -n pricemonitor

# 实时追踪日志
kubectl logs <pod-name> -n pricemonitor -f

# 查看最近 N 行
kubectl logs <pod-name> -n pricemonitor --tail=100

# 查看最近时间的日志（如 1 小时）
kubectl logs <pod-name> -n pricemonitor --since=1h

# 带 grep 过滤
kubectl logs <pod-name> -n pricemonitor -f | grep "deleteGoods"

# 查看上一个实例的日志（重启后）
kubectl logs <pod-name> -n pricemonitor --previous
```

---

### 文件日志查看

!!! info "日志路径"
    `/boss/softlog/pricemonitor/`

```bash
# 查看日志目录
ls -lh /boss/softlog/pricemonitor/<service-name>/

# 实时追踪日志文件
tail -f /boss/softlog/pricemonitor/<service-name>/*.log

# 搜索关键字
grep "deleteGoods" /boss/softlog/pricemonitor/<service-name>/*.log

# 查看最新 100 行
tail -n 100 /boss/softlog/pricemonitor/<service-name>/*.log

# 按时间过滤（今天）
cat /boss/softlog/pricemonitor/<service-name>/$(date +%Y-%m-%d).log
```

---

## :material-gear: Deployment/Service 相关

```bash
# 查看 deployment
kubectl get deployment -n pricemonitor

# 查看 deployment 详情
kubectl describe deployment <deployment-name> -n pricemonitor

# 查看 service
kubectl get svc -n pricemonitor

# 查看 replicaSet
kubectl get rs -n pricemonitor
```

---

## :material-chart-bar: 资源管理

```bash
# 查看节点状态
kubectl get nodes

# 查看节点详情
kubectl describe node <node-name>

# 查看资源使用情况
kubectl top pods -n pricemonitor
kubectl top nodes
```

---

## :material-key: 配置和 Secret

```bash
# 查看 ConfigMap
kubectl get configmap -n pricemonitor

# 查看 Secret
kubectl get secret -n pricemonitor

# 编辑配置
kubectl edit configmap <configmap-name> -n pricemonitor
```

---

## :material-rocket-launch: 快速排查组合命令

```bash
# 一键查看 pod 状态和日志
kubectl get pod <pod-name> -n pricemonitor && kubectl logs <pod-name> -n pricemonitor --tail=50

# 查找包含错误信息的日志
kubectl logs <pod-name> -n pricemonitor --since=1h | grep -i "error\|exception"

# 查看 pod 重启次数
kubectl get pods -n pricemonitor -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount

# 监控 pod 从创建到运行的全过程
kubectl get events -n pricemonitor --sort-by='.lastTimestamp' -w
```

---

## :material-lightbulb: 实用小技巧

### 设置默认 namespace

```bash
kubectl config set-context --current --namespace=pricemonitor
```

### 使用别名简化命令

```bash
alias kgp='kubectl get pods -n pricemonitor'
alias kgl='kubectl logs -n pricemonitor'
alias kgd='kubectl delete pod -n pricemonitor'
alias kgs='kubectl get svc -n pricemonitor'
alias kgdpl='kubectl describe pod -n pricemonitor'
```

### 快速切换上下文

```bash
kubectl config use-context <context-name>
```

---

## :material-crosshairs: 常用场景速查

### 场景 1：服务异常，需要重启

=== "方法 1：删除 pod"
    ```bash
    kubectl delete pod <pod-name> -n pricemonitor
    ```

=== "方法 2：重启 deployment"
    ```bash
    kubectl rollout restart deployment/<deployment-name> -n pricemonitor
    ```

---

### 场景 2：查看服务是否正常运行

```bash
kubectl get pods -n pricemonitor -o wide
```

---

### 场景 3：实时追踪日志排查问题

```bash
kubectl logs -n pricemonitor -l app=<app-name> -f | grep "关键词"
```

---

### 场景 4：排查 CPU/内存问题

```bash
kubectl top pods -n pricemonitor
```

---

## :material-map-marker: 项目特定信息

| 项目 | 值 |
| :--- | :--- |
| **Namespace** | `pricemonitor` |
| **日志路径** | `/boss/softlog/pricemonitor/<service-name>/` |
| **环境配置** | `--spring.profiles.active=test` |
| **服务端口** | `3002` |

---

**最后更新**: 2026-04-24

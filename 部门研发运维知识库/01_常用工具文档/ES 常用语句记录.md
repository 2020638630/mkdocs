# :material-magnify: Elasticsearch 常用语句记录

> 本文档记录了价格监控项目中常用的 Elasticsearch 查询语句。

---

## :material-format-list-bulleted: 目录

!!! tip "📖 本文档导航"
    本文档目录已自动生成在页面右侧，点击即可跳转对应章节。
    
    如需在内容区显示目录，可点击右上角的目录图标 :material-table-of-contents: 查看。

---

## :material-database-search: 基础查询

### 查询所有文档

查询索引中的所有文档。

```http
GET goods-price-stat/_search
{
  "query": {
    "match_all": {}
  }
}
```

!!! info "说明"
    - `goods-price-stat`：商品价格统计索引
    - `match_all`：匹配所有文档

---

## :material-filter: 条件查询

### 根据商品编码查询

通过商品编码查询商品价格统计信息。

```http
GET goods-price-stat/_search
{
    "query": {
        "match": {
            "goodsCode": "009648_0011019_18501_02424"
        }
    }
}
```

!!! info "说明"
    - `goodsCode`：商品编码字段
    - `match`：全文检索查询

---

### 多条件组合查询

查询指定商品编码、站外来源类型和任务 ID，且排除供应商商品的文档。

```http
GET goods-price-stat/_search
{
  "from": 0,
  "size": 100,
  "query": {
    "bool": {
      "filter": [
        { "term": { "goodsCode": "250610_0012112_103_00004" } },
        { "term": { "outsideSourceType": "2" } },
        { "term": { "taskId": "2043525257120526337" } },
        {
          "bool": {
            "should": [
              {
                "bool": {
                  "must_not": { "exists": { "field": "supplierGoodsAsOutside" } }
                }
              },
              { "term": { "supplierGoodsAsOutside": false } }
            ],
            "minimum_should_match": 1
          }
        }
      ]
    }
  }
}
```

!!! info "说明"
    - `filter`：过滤条件，不计算相关性评分，性能更优
    - `outsideSourceType`：站外来源类型字段
    - `taskId`：任务 ID 字段，用于数据隔离
    - `supplierGoodsAsOutside`：供应商商品标识字段
    - `minimum_should_match`: 至少满足一个 should 条件
    - **用途**：查询非供应商的站外商品数据

---

### 根据批次 ID 查询

通过批次 ID 查询商品信息。

```http
GET goods-info/_search
{
    "query": {
        "match": {
            "batchId": "1483162982188228608"
        }
    }
}
```

!!! info "说明"
    - `goods-info`：商品信息索引
    - `batchId`：批次 ID 字段

---

### 查询可用的外部商品信息

通过商品 ID、来源 ID、数据状态和价格范围查询可用的外部商品信息。

```http
GET goods-info/_search
{
  "size": 2000,
  "query": {
    "bool": {
      "filter": [
        { "term": { "goodsId": "100174928545?01688699899?01688598144" } },
        { "terms": { "sourceId": ["4ea10fd9-53e5-44d1-9a87-518496b3ff85"] } },
        { "term": { "dataState": 1 } },
        { "range": { "price": { "gt": 0 } } }
      ]
    }
  }
}
```

!!! info "说明"
    - `size`：返回结果数量限制
    - `filter`：过滤条件数组，所有条件必须同时满足
    - `goodsId`：商品 ID（精确匹配）
    - `sourceId`：来源 ID（支持多值查询）
    - `dataState`：数据状态（1 表示可用）
    - `price.gt`：价格大于 0
    - **用途**：查询指定来源下可用的、有价格的外部商品信息

---

## :material-chart-bar: 统计查询

### 统计符合条件的文档数（排除某字段）

统计指定批次和来源下，缺少 `goodsCode` 字段的文档数量。

```http
GET /goods-info/_count
{
  "query": {
    "bool": {
      "must": [
        { "term": { "batchId": "1483162982188228608" } },
        { "term": { "sourceId": "fjcoal" } }
      ],
      "must_not": [
        { "exists": { "field": "goodsCode" } }
      ]
    }
  }
}
```

!!! info "说明"
    - `_count`：返回符合条件的文档总数
    - `must`：必须满足的条件
    - `must_not`：必须不满足的条件
    - `exists`：字段存在性检查
    - **用途**：统计缺失商品编码的数据量

---

### 统计符合条件的文档数（包含某字段）

统计指定批次和来源下，包含 `goodsCode` 字段的文档数量。

```http
GET /goods-info/_count
{
  "query": {
    "bool": {
      "must": [
        { "term": { "batchId": "1483162982188228608" } },
        { "term": { "sourceId": "fjcoal" } },
        { "exists": { "field": "goodsCode" } }
      ]
    }
  }
}
```

!!! info "用途"
    统计已匹配商品编码的数据量

---

## :material-logic: 布尔查询

### 查询缺失某字段的文档

查询指定批次和来源下，缺少 `goodsCode` 字段的文档详情。

```http
GET /goods-info/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "batchId": "1483162982188228608" } },
        { "term": { "sourceId": "fjcoal" } }
      ],
      "must_not": [
        { "exists": { "field": "goodsCode" } }
      ]
    }
  },
  "size": 1000,
  "_source": ["goodsId"]
}
```

!!! info "说明"
    - `size`: 返回结果数量限制（默认 10，最大 10000）
    - `_source`：指定返回的字段列表
    - **用途**：获取缺失商品编码的商品 ID 列表，用于数据治理

---

## :material-database-edit: 数据更新

### 手动更新商品编码

为指定商品添加或更新小博码。

```http
POST /goods-info/_doc/ITEM202605080000010_yqmy/_update
{
  "doc": {
    "goodsCode": "009447_0000003_001_01396"
  }
}
```

!!! info "说明"
    - `goods-info`：商品信息索引
    - `ITEM202605080000010_yqmy`：文档 ID（格式：`goodsId_sourceId`）
    - `goodsCode`：小博码字段（keyword 类型）
    - **用途**：手动为商品添加或更新小博码，用于商品核验/打码

!!! warning "注意事项"
    - 索引映射设置为 `dynamic: "strict"`，不允许动态添加未定义字段
    - 必须使用已有的字段名 `goodsCode`（驼峰命名），不能使用 `goodscode`
    - 更新后建议执行刷新操作使数据立即可搜索

---

### 刷新索引

手动刷新索引，使更新的数据立即可以被搜索到。

```bash
POST /goods-info/_refresh
```

!!! info "说明"
    - Elasticsearch 默认有 1 秒的刷新延迟
    - 执行刷新后，刚更新的数据可以立即被搜索到
    - 也可在更新请求中添加 `?refresh=true` 参数实现自动刷新

??? tip "替代方式"
    ```http
    POST /goods-info/_doc/ITEM202605080000010_yqmy/_update?refresh=true
    {
      "doc": {
        "goodsCode": "009447_0000003_001_01396"
      }
    }
    ```

---

### 批量更新商品编码

使用 Bulk API 批量为多个商品添加小博码。

```http
POST /_bulk
{"update":{"_index":"goods-info","_id":"ITEM202605080000010_yqmy"}}
{"doc":{"goodsCode":"009447_0000003_001_01396"}}
{"update":{"_index":"goods-info","_id":"ITEM202605080000011_yqmy"}}
{"doc":{"goodsCode":"009447_0003841_001_00007"}}
```

!!! info "说明"
    - 适用于需要为多个商品同时添加或更新 `goodsCode` 的场景
    - 每个操作由两行 JSON 组成：操作行 + 数据行
    - 性能优于逐个更新

---

## :material-briefcase: 业务查询

### 根据批次 ID 查询商品信息

查询指定批次的所有商品。

```http
GET /goods-info/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "batchId": "1502334362804592640" } }
      ]
    }
  }
}
```

!!! info "用途"
    查看某个批次下采集的所有商品数据

---

### 查询批次中未核验的商品

查询指定批次和来源下，缺少 `goodsCode` 字段的文档详情。

```http
GET /goods-info/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "sourceId": "yqmy" } },
        { "term": { "batchId": "1502334362804592640" } }
      ],
      "must_not": [
        { "exists": { "field": "goodsCode" } }
      ]
    }
  },
  "_source": ["goodsId", "name", "goodsCode"]
}
```

!!! info "用途"
    查找批次中还未完成核验/打码的商品，用于数据治理

---

## :material-table: 查询类型说明

| 查询类型 | 说明 | 使用场景 |
| :--- | :--- | :--- |
| `match_all` | 匹配所有文档 | 全量查询 |
| `match` | 全文检索查询 | 文本字段查询 |
| `term` | 精确值查询 | 数值、日期、keyword 类型字段 |
| `terms` | 多值精确查询 | IN 条件查询 |
| `bool` | 布尔组合查询 | 复杂条件组合 |
| `exists` | 字段存在性检查 | 判断字段是否存在 |
| `range` | 范围查询 | 数值或日期范围 |

---

## :material-logic-gate: 布尔查询操作符

| 操作符 | 说明 | SQL 对应 |
| :--- | :--- | :--- |
| `must` | 必须满足 | `AND` |
| `must_not` | 必须不满足 | `NOT` |
| `should` | 应该满足（可选） | `OR` |
| `filter` | 过滤条件（不计分） | `WHERE` |

---

## :material-database-settings: 常用索引说明

| 索引名称 | 用途 | 主要字段 |
| :--- | :--- | :--- |
| `goods-price-stat` | 商品价格统计 | `goodsCode`, `price`, `sourceId`, `outsideSourceType`, `taskId` 等 |
| `goods-info` | 商品基础信息 | `batchId`, `goodsId`, `goodsCode`, `sourceId`, `catalogCode`, `name`(ik分词) 等 |

---

## :material-cog: 索引管理

### 创建索引

使用 curl 命令创建索引（需要认证）：

```bash
curl -X PUT "http://localhost:9200/goods-info" \
  -H "Content-Type: application/json" \
  -u elastic:密码 \
  -d '{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  },
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "ik_max_word"
      },
      "goodsCode": {
        "type": "keyword"
      }
    }
  }
}'
```

!!! info "说明"
    - `number_of_shards`：主分片数（建议单节点设为 1）
    - `number_of_replicas`：副本数（单节点建议设为 0，避免 yellow 状态）
    - `dynamic`: `strict`：严格模式，不允许动态添加未定义的字段
    - `ik_max_word`：IK 中文分词器（细粒度分词）
    - 需要先安装 IK 分词器插件才能使用

---

### 查看索引列表

```bash
# 查看所有索引及其状态
curl -X GET "http://localhost:9200/_cat/indices?v" -u elastic:密码

# 查看指定索引
curl -X GET "http://localhost:9200/goods-info" -u elastic:密码
```

??? example "输出示例"
    ```
    health status index             uuid                   pri rep docs.count docs.deleted store.size pri.store.size
    green  open   goods-info        vdBvH9xqS3Wq1lVxcBXm8w   1   0          0            0       230b           230b
    green  open   goods-price-stat  QUxwPbmURPmUnIL0whiC3A   1   0          0            0       283b           283b
    ```

---

### 检查索引是否存在

```bash
# 方法一：查看详细信息（存在返回配置，不存在返回 404）
curl -X GET "http://localhost:9200/goods-info" -u elastic:密码

# 方法二：只检查状态码（推荐）
curl -I "http://localhost:9200/goods-info" -u elastic:密码

# 返回 200 OK 表示存在，404 Not Found 表示不存在
```

---

### 删除索引

```bash
curl -X DELETE "http://localhost:9200/goods-info" -u elastic:密码
```

!!! danger "警告"
    删除操作不可恢复，请谨慎执行！

---

### 修改索引设置

```bash
# 修改副本数为 0（解决 yellow 状态）
curl -X PUT "http://localhost:9200/tenantoperate.log/_settings" \
  -u elastic:密码 \
  -H "Content-Type: application/json" \
  -d '{
  "index": {
    "number_of_replicas": 0
  }
}'
```

---

## :material-server-network: 集群运维

### 查看集群健康状态

```bash
# 查看整体集群健康状态
curl -X GET "http://localhost:9200/_cluster/health?pretty" -u elastic:密码

# 查看指定索引的健康状态
curl -X GET "http://localhost:9200/_cluster/health/goods-info?pretty" -u elastic:密码
```

??? info "健康状态说明"
    - **green（绿色）**：所有主分片和副本分片都正常分配
    - **yellow（黄色）**：主分片正常，但部分或全部副本分片未分配（单节点常见）
    - **red（红色）**：部分主分片不可用，数据可能丢失

!!! tip "yellow 状态处理"
    单节点集群中，副本分片无法分配到同一节点，导致 yellow 状态。解决方法是将副本数设为 0。

---

### 查看节点信息

```bash
# 查看所有节点
curl -X GET "http://localhost:9200/_cat/nodes?v" -u elastic:密码

# 查看节点详细信息
curl -X GET "http://localhost:9200/_nodes?pretty" -u elastic:密码
```

---

### 查看 ES 版本信息

```bash
curl -X GET "http://localhost:9200" -u elastic:密码
```

??? example "输出示例"
    ```json
    {
      "name" : "iZ0jl1wp0yifdg9vrmak76Z",
      "cluster_name" : "elasticsearch",
      "version" : {
        "number" : "7.3.2",
        "build_flavor" : "default",
        "build_type" : "rpm"
      }
    }
    ```

---

### 重启 Elasticsearch 服务

```bash
# 停止服务
systemctl stop elasticsearch

# 启动服务
systemctl start elasticsearch

# 重启服务
systemctl restart elasticsearch

# 查看服务状态
systemctl status elasticsearch

# 查看启动日志
tail -f /var/log/elasticsearch/elasticsearch.log
```

---

## :material-puzzle: 插件管理

### 查看已安装的插件

```bash
# 使用 curl 查看
curl -X GET "http://localhost:9200/_cat/plugins?v" -u elastic:密码

# 或在服务器上直接查看
ls -la /usr/share/elasticsearch/plugins/
```

??? example "输出示例"
    ```
    name                    component   version
    iZ0jl1wp0yifdg9vrmak76Z analysis-ik 7.3.2
    ```

---

### 安装 IK 分词器插件

=== "方式一：从本地文件安装（推荐）"
    ```bash
    # 1. 下载 IK 分词器到 /tmp 目录（在 Windows 上下载后上传）
    # 下载地址：https://github.com/medcl/elasticsearch-analysis-ik/releases
    # 选择与 ES 版本匹配的版本，如 v7.3.2、v7.10.2 等

    # 2. 从本地文件安装
    /usr/share/elasticsearch/bin/elasticsearch-plugin install \
      file:///tmp/elasticsearch-analysis-ik-7.3.2.zip

    # 3. 输入 y 确认安装

    # 4. 重启 Elasticsearch
    systemctl restart elasticsearch

    # 5. 验证安装
    curl -X GET "http://localhost:9200/_cat/plugins?v" -u elastic:密码
    ```

=== "方式二：在线安装（需要网络访问 GitHub）"
    ```bash
    /usr/share/elasticsearch/bin/elasticsearch-plugin install \
      https://github.com/medcl/elasticsearch-analysis-ik/releases/download/v7.10.2/elasticsearch-analysis-ik-7.10.2.zip
    ```

!!! warning "注意事项"
    - IK 分词器版本应与 Elasticsearch 版本兼容（7.x 系列通常可以互相兼容）
    - 如果 GitHub 下载失败，可使用国内镜像或手动下载后上传
    - 安装后必须重启 Elasticsearch 才能生效

---

### 测试 IK 分词器

```bash
# 测试 ik_max_word（细粒度分词）
curl -X POST "http://localhost:9200/_analyze" \
  -H "Content-Type: application/json" \
  -u elastic:密码 \
  -d '{
  "analyzer": "ik_max_word",
  "text": "商品价格监测"
}'

# 测试 ik_smart（粗粒度分词）
curl -X POST "http://localhost:9200/_analyze" \
  -H "Content-Type: application/json" \
  -u elastic:密码 \
  -d '{
  "analyzer": "ik_smart",
  "text": "华为Mate40 Pro手机"
}'
```

??? example "预期输出"
    ```json
    {
      "tokens": [
        {"token": "商品", "position": 0},
        {"token": "价格", "position": 1},
        {"token": "监测", "position": 2}
      ]
    }
    ```

---

### 卸载插件

```bash
# 卸载 IK 分词器
/usr/share/elasticsearch/bin/elasticsearch-plugin remove analysis-ik

# 重启 Elasticsearch
systemctl restart elasticsearch
```

---

## :material-lock: 安全认证

### 重置 elastic 用户密码

!!! info "说明"
    ES 7.3.2 版本没有 `elasticsearch-reset-password` 命令，可以使用以下方式：

=== "方式一：临时禁用安全认证（仅用于测试环境）"
    ```bash
    # 1. 编辑配置文件
    vi /etc/elasticsearch/elasticsearch.yml

    # 2. 添加或修改以下配置
    xpack.security.enabled: false

    # 3. 重启 Elasticsearch
    systemctl restart elasticsearch

    # 4. 此时访问不需要密码
    curl -X GET "http://localhost:9200"

    # ⚠️ 注意：操作完成后记得重新启用安全认证
    ```

=== "方式二：使用 elasticsearch-setup-passwords（如果可用）"
    ```bash
    /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto -u "http://localhost:9200"
    ```

---

### 使用密码访问

```bash
# 所有 curl 命令都需要添加认证参数
-u elastic:密码

# 示例
curl -X GET "http://localhost:9200/_cat/indices?v" \
  -u elastic:密码
```

---

## :material-alert: 常见问题

### 1. 认证失败（401 Unauthorized）

!!! bug "原因"
    密码错误或未提供认证信息

!!! check "解决"
    ```bash
    # 检查是否提供了认证参数
    curl -X GET "http://localhost:9200" -u elastic:正确密码

    # 如果忘记密码，参考上面的"重置密码"章节
    ```

---

### 2. IK 分词器未找到

!!! bug "原因"
    IK 分词器插件未安装

!!! check "解决"
    参考上面的"安装 IK 分词器插件"章节

---

### 3. 索引状态为 yellow

!!! bug "原因"
    单节点集群中副本分片无法分配

!!! check "解决"
    ```bash
    # 将副本数设置为 0
    curl -X PUT "http://localhost:9200/索引名/_settings" \
      -u elastic:密码 \
      -H "Content-Type: application/json" \
      -d '{
      "index": {
        "number_of_replicas": 0
      }
    }'
    ```

---

### 4. 连接拒绝（Connection refused）

!!! bug "原因"
    Elasticsearch 服务未启动

!!! check "解决"
    ```bash
    # 检查服务状态
    systemctl status elasticsearch

    # 启动服务
    systemctl start elasticsearch

    # 查看日志排查问题
    tail -f /var/log/elasticsearch/elasticsearch.log
    ```

---

### 5. 插件安装失败（404 Not Found）

!!! bug "原因"
    GitHub 上的旧版本已被迁移或删除

!!! check "解决"
    - 使用较新版本（如 7.10.2、7.17.0），7.x 系列通常兼容
    - 手动下载后从本地文件安装
    - 使用国内镜像源

---

## :material-update: 更新记录

| 日期 | 更新内容 |
| :--- | :--- |
| 2026-05-08 | 添加数据更新章节（手动更新商品编码、刷新索引、批量更新）和业务查询章节 |
| 2026-04-29 | 添加索引管理、集群运维、插件管理、安全认证等运维操作文档 |
| 2026-04-15 | 添加查询可用的外部商品信息示例 |
| 2026-03-25 | 初始版本，添加基础查询、统计查询、布尔查询示例 |

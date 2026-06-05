# 阳煤双租户ID支持改造说明

:material-file-document-edit: **文档类型**: 技术改造说明 |
:material-account-clock: **更新时间**: 2026年 |
:material-account: **维护人**: 研发团队

---

## 1. 文档概述

### 1.1 改造背景

:material-information: **背景说明**

阳煤项目存在两个正式环境租户ID，需要所有阳煤相关的业务逻辑同时支持两个租户ID的 **OR判断**（任意一个匹配即视为阳煤租户）。

| 常量引用名 | 租户ID | 说明 |
|-----------|--------|------|
| `YANGMEI_TENANT_ID` / `YM_TENANT` | `1810228209924907010` | 阳煤租户-1（原有） |
| `YANGMEI_TENANT_ID_2` / `YM_TENANT_2` | `2013903710105972737` | 阳煤租户-2（新增） |

### 1.2 改造目标

:material-target: **目标**

将所有原来仅判断单一租户ID `1810228209924907010` 的地方，改为对两个租户ID同时进行OR判断。

---

## 2. 改造内容

### 2.1 改动文件清单

| # | 模块 | 文件 | 改动说明 |
|---|------|------|---------|
| 1 | entpur | `PriceMonitorController.java` | 新增 `YANGMEI_TENANT_ID_2` 常量 + `isYangmeiTenant()` OR判断方法；4处未登录默认租户改为 `YANGMEI_TENANT_ID_2` |
| 2 | operate | `YangmeiDataSyncService.java` | 接口新增 `YANGMEI_TENANT_ID_2` 常量 + `default isYangmeiTenant()` OR判断方法 |
| 3 | interchange | `YangmeiDataSyncService.java` | 同上 |
| 4 | operate | `YangmeiDataSyncServiceImpl.java` | `saveBusData` 的 sourceTenantId 参数改为 `YANGMEI_TENANT_ID_2` |
| 5 | interchange | `YangmeiDataSyncServiceImpl.java` | `saveBatchBusData` 的 sourceTenantId 参数改为 `YANGMEI_TENANT_ID_2` |
| 6 | interchange | `SyncDataServiceImpl.java` | 数据同步路由判断改为 `YM_TENANT \|\| YM_TENANT_2` OR判断 |
| 7 | interchange | `InterchangeConstants.java` | 新增 `YM_TENANT_2` 常量 |

---

## 3. 详细改动说明

### 3.1 PriceMonitorController.java（entpur模块）

:material-file-code: **文件路径**: `entpur-backend/bssc-biz-entpur/src/main/java/com/bssc/cloud/contract/controller/PriceMonitorController.java`

**改造前：** 仅定义一个常量，4个接口未登录时默认使用该常量。

```java
private static final String YANGMEI_TENANT_ID = "1810228209924907010";
```

**改造后：** 定义两个常量 + OR判断方法。

```java
/**
 * 阳煤租户ID-1（本分支专用于阳煤，如租户ID变更修改此处即可）
 */
private static final String YANGMEI_TENANT_ID = "1810228209924907010";

/**
 * 阳煤租户ID-2
 */
private static final String YANGMEI_TENANT_ID_2 = "2013903710105972737";

/**
 * 判断是否为阳煤租户
 */
private boolean isYangmeiTenant(String tenantId) {
    return YANGMEI_TENANT_ID.equals(tenantId) || YANGMEI_TENANT_ID_2.equals(tenantId);
}
```

**未登录默认租户处理（4处）：** 均改为使用 `YANGMEI_TENANT_ID_2`

| 接口 | 行号 | 说明 |
|------|------|------|
| `/goods/detail` | 121 | 商品详情 |
| `/goods/monitor/priceHis` | 138 | 价格统计历史 |
| `/goods/monitor/price` | 156 | 价格统计 |
| `/goods/monitor/links` | 165 | 监测链接 |

```java
// 示例
String tenantId = tokenInfo != null ? tokenInfo.getTenantId() : YANGMEI_TENANT_ID_2;
```

---

### 3.2 YangmeiDataSyncService.java（接口层 - operate & interchange）

:material-file-code: **文件路径：**

- operate: `entpur-backend/bssc-biz-operate/src/main/java/com/bssc/maint/operate/service/YangmeiDataSyncService.java`
- interchange: `entpur-backend/bssc-biz-interchange/src/main/java/com/bssc/biz/interchange/service/YangmeiDataSyncService.java`

**改造前：** 接口仅定义一个常量。

```java
String YANGMEI_TENANT_ID = "1810228209924907010";
```

**改造后：** 双常量 + 接口默认方法 `isYangmeiTenant()`。

```java
String YANGMEI_TENANT_ID = "1810228209924907010";
String YANGMEI_TENANT_ID_2 = "2013903710105972737";

/**
 * 判断是否为阳煤租户（两个租户ID均匹配即可）
 */
default boolean isYangmeiTenant(String tenantId) {
    return YANGMEI_TENANT_ID.equals(tenantId) || YANGMEI_TENANT_ID_2.equals(tenantId);
}
```

!!! tip "使用说明"
    后续任何需要判断是否为阳煤租户的业务逻辑，可直接通过实现该接口的Service调用 `isYangmeiTenant(tenantId)` 方法，无需重复编写OR判断逻辑。

---

### 3.3 YangmeiDataSyncServiceImpl.java（实现层）

:material-file-code: **文件路径：**

- operate: `entpur-backend/bssc-biz-operate/src/main/java/com/bssc/maint/operate/service/impl/YangmeiDataSyncServiceImpl.java`
- interchange: `entpur-backend/bssc-biz-interchange/src/main/java/com/bssc/biz/interchange/service/impl/YangmeiDataSyncServiceImpl.java`

**改造内容：** 数据同步时 `sourceTenantId` 从 `YANGMEI_TENANT_ID` 改为 `YANGMEI_TENANT_ID_2`。

**operate模块：**

```java
taskDataSyncService.saveBusData(
        clazz, entity, operType,
        TaskSyncDataType.operate,
        "-1",
        YANGMEI_TENANT_ID_2   // 原来是 YANGMEI_TENANT_ID
);
```

**interchange模块：**

```java
taskDataSyncService.saveBatchBusData(
        clazz, entities,
        TaskSyncType.CONFIGS, operType,
        TaskSyncDataType.operate,
        "-1",
        YANGMEI_TENANT_ID_2   // 原来是 YANGMEI_TENANT_ID
);
```

---

### 3.4 SyncDataServiceImpl.java（数据同步路由）

:material-file-code: **文件路径**: `entpur-backend/bssc-biz-interchange/src/main/java/com/bssc/biz/interchange/service/impl/SyncDataServiceImpl.java`

**改造前：** 单一租户判断，走阳煤v1.1.0格式。

```java
// 本分支专用于阳煤租户，直接使用v1.1.0格式调用
return callApiWithYangmeiFormat(...);
```

**改造后：** 双租户OR判断，匹配阳煤租户走v1.1.0格式，否则走标准格式。

```java
// 阳煤租户使用v1.1.0格式调用（两个租户ID均匹配）
if (YM_TENANT.equals(tenantId) || YM_TENANT_2.equals(tenantId)) {
    log.info("[数据同步] 检测到阳煤租户={}, 使用v1.1.0格式调用", tenantId);
    return callApiWithYangmeiFormat(dataList, url, protocol, tenantId, transferType, urlType, requestMap);
}
log.info("[数据同步] 使用标准格式调用, tenantId={}", tenantId);
ResultBody result = callBackApi(url, requestMap, ApiExceptionEnum.HTTP_ERROR, protocol, urlType, header);
handleResult(result);
return result;
```

---

### 3.5 InterchangeConstants.java（常量定义）

:material-file-code: **文件路径**: `entpur-backend/bssc-biz-interchange/src/main/java/com/bssc/biz/interchange/constant/InterchangeConstants.java`

**改造内容：** 新增 `YM_TENANT_2` 常量。

```java
/**阳煤租户特殊处理 */
public final static String YM_TENANT = "1810228209924907010";

/**阳煤租户特殊处理 */
public final static String YM_TENANT_2 = "2013903710105972737";
```

---

## 4. OR判断逻辑汇总

:material-check-all: **以下4处均生效双租户OR判断：**

| 位置 | 判断方式 | 用途 |
|------|---------|------|
| `YangmeiDataSyncService.isYangmeiTenant()` | `ID \|\| ID_2` | 接口默认方法，供各Service实现类调用 |
| `PriceMonitorController.isYangmeiTenant()` | `ID \|\| ID_2` | Controller层阳煤租户判断 |
| `SyncDataServiceImpl.callApiSyncData()` | `YM_TENANT \|\| YM_TENANT_2` | 数据同步路由：阳煤走v1.1.0格式 |
| 未登录默认租户（PriceMonitorController） | 使用 `YANGMEI_TENANT_ID_2` | 4个接口未登录时默认使用新租户ID |

---

## 5. 后续扩展建议

:material-lightbulb-on: **如需继续新增阳煤租户ID：**

1. 在各常量定义处新增 `_3` 常量
2. 更新所有 `isYangmeiTenant()` 方法的OR判断
3. 更新 `SyncDataServiceImpl` 中的租户判断条件
4. :material-alert: **建议后续考虑将租户ID改为配置项或数据库配置，减少硬编码**

??? tip "配置化改造建议"
    ```yaml
    # 建议的配置文件格式
    yangmei:
      tenant:
        ids:
          - "1810228209924907010"
          - "2013903710105972737"
    ```
    
    这样后续新增租户ID只需修改配置文件，无需修改代码。

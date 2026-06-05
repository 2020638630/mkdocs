# :material-hammer-wrench: HBase/Phoenix + Kafka 禁用改造 - 问题处理记录

:calendar: **记录时间**：2026-04-23

---

## :material-target: 一、核心目标

将项目中的 **HBase/Phoenix 数据源**和 **Kafka 消息队列**改为**可选依赖**，使代码可以在不使用这些中间件的地区（如阳煤租户）部署。

### 涉及服务模块

阳煤租户仅使用以下四个服务：

- :white_check_mark: `bssc-biz-interchange` - 数据交换平台
- :white_check_mark: `bssc-biz-entpur` - 租户端业务管理
- :white_check_mark: `bssc-biz-operate` - 运营平台（唯一使用 Phoenix 和 Kafka 的服务）
- :white_check_mark: `bssc-sys-entpur` - 租户端系统管理

---

## :white_check_mark: 二、已完成的修改

### 一、Phoenix/HBase 改造

#### 1. 配置文件修改

**文件：** `bssc-biz-operate/src/main/resources/application-huayang.yml`

- 添加 `spring.datasource.phoenix.enabled: false`
- 保留原有 Phoenix 配置（方便切换）

---

#### 2. 新增 Mock 配置类

**文件：** `PhoenixMockConfig.java`（新建）

```java
@Configuration
@ConditionalOnProperty(name = "spring.datasource.phoenix.enabled", 
                       havingValue = "false", matchIfMissing = true)
public class PhoenixMockConfig {
    @Bean(name = "phoenixDataSource")
    public DataSource mockPhoenixDataSource() {
        // 返回匿名内部类实现的 DataSource
        // getConnection() 抛出 IllegalStateException 提示
    }
}
```

---

#### 3. 修改 PhoenixDataSourceConfig

**文件：** `PhoenixDataSourceConfig.java`

- 添加 `@ConditionalOnProperty(name = "spring.datasource.phoenix.enabled", havingValue = "true", matchIfMissing = false)`
- 修复事务管理器注入方式（从调用方法改为注入参数）

---

#### 4. 修改 SqlGeneratorConfig

**文件：** `SqlGeneratorConfig.java`

- 添加相同的条件注解
- 当 Phoenix 禁用时，不创建 `phoenixSqlGenerator` Bean

---

#### 5. 修改 Service 层依赖

**文件：** `SyncGoodsWithCatalogForEntpurServiceImpl.java`

- `phoenixDataSource` 改为 `@Autowired(required = false)`
- `sqlGenerator` 改为 `@Autowired(required = false)`
- 方法开头添加空指针检查：
  ```java
  if (phoenixDataSource == null || sqlGenerator == null) {
      log.warn("Phoenix 数据源未启用，跳过...");
      return;
  }
  ```
- 删除多余的外层 try-catch 块

---

### 二、Kafka 禁用改造

#### 1. 配置文件修改

**文件：** `bssc-biz-operate/src/main/resources/application-huayang.yml`

**排除自动配置：**
```yaml
spring:
  autoconfigure:
    exclude:
      - org.springframework.boot.autoconfigure.kafka.KafkaAutoConfiguration
```

**注释 Kafka 配置：**
- 第 81-124 行：所有 `spring.kafka.*` 配置已注释
- 包括：`bootstrap-servers`、`producer`、`consumer`、`listener`、`ssl` 等全部配置

---

#### 2. Kafka 组件条件加载

**文件：** `MessageProducer.java`

```java
@Component
@ConditionalOnProperty(name = "spring.kafka.bootstrap-servers")
public class MessageProducer {
    // Kafka 消息生产者
}
```

**文件：** `NewFlowResultConsumer.java`

```java
@Component
@ConditionalOnProperty(name = "spring.kafka.bootstrap-servers")
public class NewFlowResultConsumer {
    @KafkaListener(...)
    public void consume(...) {
        // Kafka 消息消费者
    }
}
```

**说明：**

- 两个 Kafka 组件都添加了 `@ConditionalOnProperty` 条件注解
- 当配置文件中不存在 `spring.kafka.bootstrap-servers`时，这些 Bean 不会加载
- 配合 `KafkaAutoConfiguration` 排除，确保 Kafka 完全禁用

---

#### 3. 其他服务检查结果

- :white_check_mark: `bssc-biz-interchange` - 无 Kafka 依赖
- :white_check_mark: `bssc-biz-entpur` - 无 Kafka 依赖
- :white_check_mark: `bssc-sys-entpur` - 无 Kafka 依赖

---

## :wrench: 三、技术要点

### Phoenix 改造技术要点

#### 条件注解机制

- `@ConditionalOnProperty` 根据配置项决定是否加载 Bean
- `matchIfMissing = false`：配置不存在时不加载（安全默认值）
- 两个配置类互斥：一个启用时另一个不加载

#### Mock DataSource 设计

- 使用**匿名内部类**而非动态代理（避免 NPE）
- 实现所有 DataSource 接口方法
- `getConnection()` 抛出清晰的异常提示

#### 防御性编程

- 可选注入：`@Autowired(required = false)`
- 使用前检查：`if (xxx == null) return;`
- 日志记录：warn 级别提示功能已跳过

---

### Kafka 禁用技术要点

#### 双重保障机制

1. **排除自动配置**：`spring.autoconfigure.exclude` 阻止 Spring Boot 自动配置 Kafka
2. **条件注解**：`@ConditionalOnProperty` 确保 Kafka 组件在未配置时不加载

#### 为什么需要双重保障？

- 仅排除自动配置：如果代码中有 `@KafkaListener`，仍会尝试创建相关 Bean 导致启动失败
- 仅条件注解：如果忘记加条件注解的组件会报错
- 双重保障：确保万无一失

#### 依赖保留原因

- `pom.xml` 中仍保留 `spring-kafka` 依赖
- 原因：其他环境（test/online）需要使用 Kafka
- 影响：无负面影响，通过条件控制是否加载

---

## :warning: 四、待处理问题#

### 可能还需要修改的文件

项目中可能有其他 Service 也注入了 Phoenix 相关的 Mapper，如果遇到类似错误需要继续修改：

- 将 Mapper 注入改为 `@Autowired(required = false)`
- 在使用处添加空指针检查

---

## :chart-line: 五、改造效果#

### Phoenix 改造效果

| 场景 | 行为 |
|------|------|
| `phoenix.enabled = false` | 不加载 Phoenix 配置，使用 Mock DataSource，跳过 Phoenix 相关功能 |
| `phoenix.enabled = true` | 正常加载 Phoenix 配置，连接 HBase，执行完整功能 |
| 配置缺失 | 默认禁用（`matchIfMissing = false`） |

---

### Kafka 禁用效果

| 场景 | 行为 |
|------|------|
| 无 `spring.kafka.bootstrap-servers` 配置 | Kafka 自动配置被排除，Kafka 组件不加载 |
| 有 `spring.kafka.bootstrap-servers` 配置 | Kafka 正常启动，生产者和消费者正常工作 |
| 配置缺失 | 默认禁用（配合自动配置排除） |

---

## :light_bulb: 六、下一步建议#

### 测试验证

1. **测试启动**
   - 确认不再报 Phoenix 相关错误
   - 确认不再报 Kafka 相关错误
   - 验证 MySQL 连接成功后应用能正常启动

### 后续优化

2. **批量修改其他 Service**（如需要）
   - 搜索所有注入 Phoenix Mapper 的地方
   - 统一改为可选注入 + 空指针检查

3. **其他环境配置同步**
   - 为 test/local/online 等环境添加 `phoenix.enabled` 配置
   - 确保各环境 Kafka 配置正确

---

## :memo: 七、关键经验#

### Phoenix 改造经验

1. **不要直接删除配置类** → 会导致 Bean 注入失败
2. **使用条件注解** → 一套代码多环境适配
3. **Mock Bean 用匿名内部类** → 比动态代理更稳定
4. **前置检查优于异常捕获** → 逻辑更清晰

### Kafka 禁用经验

5. **双重保障更安全** → 自动配置排除 + 条件注解
6. **依赖可以保留** → 通过配置控制是否加载，无需修改 pom.xml
7. **检查所有 @KafkaListener** → 确保都有条件注解保护

---

## :page_facing_up: 八、相关文件清单#

### Phoenix 改造相关文件

#### 已修改文件

- `bssc-biz-operate/src/main/resources/application-huayang.yml` - 添加 phoenix.enabled 配置
- `bssc-biz-operate/src/main/java/com/bssc/maint/operate/config/PhoenixMockConfig.java` - 新建 Mock 配置类
- `bssc-biz-operate/src/main/java/com/bssc/maint/operate/config/PhoenixDataSourceConfig.java` - Phoenix 数据源配置
- `bssc-biz-operate/src/main/java/com/bssc/maint/operate/config/SqlGeneratorConfig.java` - SQL 生成器配置
- `bssc-biz-operate/src/main/java/com/bssc/maint/operate/service/impl/SyncGoodsWithCatalogForEntpurServiceImpl.java` - Service 实现类

#### 无需修改的文件

- `bssc-biz-interchange` - 无 Phoenix 依赖
- `bssc-biz-entpur` - 无 Phoenix 依赖
- `bssc-sys-entpur` - 无 Phoenix 依赖

---

### Kafka 禁用相关文件

#### 已配置文件

- `bssc-biz-operate/src/main/resources/application-huayang.yml` 
  - 排除 Kafka 自动配置
  - 注释所有 Kafka 相关配置

#### 已有条件注解的文件（无需修改）

- `bssc-biz-operate/src/main/java/com/bssc/maint/operate/kafka/MessageProducer.java` - 已有 `@ConditionalOnProperty`
- `bssc-biz-operate/src/main/java/com/bssc/maint/operate/kafka/NewFlowResultConsumer.java` - 已有 `@ConditionalOnProperty`

#### 无需处理的文件

- `bssc-biz-interchange` - 无 Kafka 依赖
- `bssc-biz-entpur` - 无 Kafka 依赖
- `bssc-sys-entpur` - 无 Kafka 依赖

---

## :mag: 九、排查思路#

### Phoenix 相关报错排查

1. 检查错误是否与 Phoenix 相关
2. 如果是 Phoenix 相关，确认是否已正确添加条件注解
3. 检查 `phoenix.enabled` 配置是否正确
4. 查看具体哪个 Bean 注入失败，定位到对应的 Service

### Kafka 相关报错排查

1. 检查是否有 `KafkaAutoConfiguration` 相关错误
2. 确认 `application-huayang.yml` 中已排除 Kafka 自动配置
3. 检查所有 `@KafkaListener` 是否都有 `@ConditionalOnProperty` 注解
4. 确认 `spring.kafka.bootstrap-servers` 配置已注释或删除

---

> :calendar: **最后更新**：2026-04-23  
> :white_check_mark: **状态**：✅ Phoenix 改造完成 | ✅ Kafka 禁用完成  
> :computer: **涉及服务**：bssc-biz-operate（唯一需要改造的服务）  
> :information_source: **其他服务**：bssc-biz-interchange、bssc-biz-entpur、bssc-sys-entpur（无需修改）

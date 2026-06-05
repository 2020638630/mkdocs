# AI 文档生成规则使用说明

:material-file-document-edit: **文档类型**: 使用指南 |
:material-account-clock: **更新时间**: 2026-06-05 |
:material-account: **维护人**: 研发团队 |
:material-tag: **标签**: AI, 文档生成, 规则配置

---

## 一、规则文件说明

### 1.1 文件位置

:material-file: **规则源文件**（CodeBuddy Rules 引擎读取）: `D:\Program Files (x86)\pricemonitor\.codebuddy\rules\AI文档生成规则.mdc`

:material-link: **线上浏览版**（本文档所在知识库，可直接点击查看完整内容）: [**AI文档生成规则.md**](../99_文档模板/AI文档生成规则.md)

:material-information: **作用**

该规则文件用于指导AI在生成知识库文档时：
1. 自动归类到正确的文件夹
2. 添加标准化标签头部（文档类型、时间、维护人、**标签**）
3. 应用MkDocs Material美化规范
4. 确保文档格式统一、美观、可检索

### 1.2 规则内容概览

规则文件包含以下核心内容：

| 章节 | 内容 | 说明 |
|------|------|------|
| 一、知识库目录结构 | 定义文件夹结构和归类规则 | 帮助AI正确分类文档 |
| 二、文档美化规范 | MkDocs Material格式化规则 | 确保文档美观、专业 |
| 　2.1 标签化元数据 | 5种文档类型的标准化头部格式 | **所有文档必选标签字段** |
| 　2.2 标签命名规范 | 标签选取原则与格式规则 | 3~6个标签，英文逗号分隔 |
| 　2.3 图标使用规范 | 22个常用场景图标速查表 | 英文冒号，禁止中文冒号 |
| 三、文档生成流程 | AI生成文档的标准流程 | 含提取标签关键词步骤 |
| 四、示例模板 | 4种文档类型的完整模板 | 工具手册/故障排查/功能设计/部署指南 |
| 五、注意事项 | 安全红线、常见错误、存量文档规范调整 | **含密码安全红线 + 5.5存量文档批量规范化流程** |

---

## 二、使用方法

### 2.1 方式1：在对话中引用规则

:material-chat: **操作步骤**

在CodeBuddy对话中，直接引用规则文件：

```
请按照 D:\Program Files (x86)\pricemonitor\.codebuddy\rules\AI文档生成规则.mdc 
中的规则，帮我生成一份【文档标题】文档，并保存到【目录路径】
```

**示例**：

```
请按照 D:\Program Files (x86)\pricemonitor\.codebuddy\rules\AI文档生成规则.mdc 
中的规则，帮我生成一份"Redis缓存优化方案"文档，
并保存到 D:\Work\Dev-KB\部门研发运维知识库\04_研发内部设计\ 目录下
```

### 2.2 方式2：让AI记住规则

:material-brain: **操作步骤**

1. 打开CodeBuddy设置
2. 找到"自定义指令"或"系统提示词"配置
3. 粘贴规则文件内容
4. 保存配置

:material-check: **效果**

后续所有文档生成请求都会自动遵循规则，无需每次引用。

### 2.3 方式3：使用快捷指令

:material-lightning-bolt: **操作步骤**

在CodeBuddy中创建自定义快捷指令：

**指令名称**: `生成知识库文档`

**指令内容**:
```
请按照以下规则生成文档：
1. 读取规则文件：D:\Program Files (x86)\pricemonitor\.codebuddy\rules\AI文档生成规则.mdc
2. 根据文档内容归类到正确的知识库目录
3. 添加标准化标签头部（文档类型、时间、维护人、标签）
4. 应用MkDocs Material美化规范
5. 生成后保存到指定路径

文档需求：【在这里描述你要生成的文档内容】
```

---

## 三、规则详解

### 3.1 知识库目录结构

:material-folder: **目录说明**

```
部门研发运维知识库/
├── 00_说明/                    # 知识库使用说明、部署文档
├── 01_常用工具文档/             # ES、HBase、Spark、K8s等工具使用手册
├── 02_问题处理文档/             # 故障排查报告、问题处理记录
├── 03_项目技术架构文档/          # 项目流程、架构设计、接口说明
├── 04_研发内部设计/             # 功能设计文档、需求追踪
│   ├── 阳煤商品治理/
│   ├── 华能消费帮扶/
│   └── 中海油报表及异常商品监测记录/
├── 05_附件资源/                # 附件、资源文件
└── 99_文档模板/                # 文档模板
```

### 3.2 文档美化规范

:material-brush: **核心规范**

#### 3.2.1 文档头部信息（标签化元数据）

每个文档标题后必须添加标准化标签头部，所有字段用 `|` 分隔，**标签字段为必选**。

**通用格式**（部署指南、使用指南类）：

```markdown
# 文档标题

:material-file-document-edit: **文档类型**: 类型说明 |
:material-account-clock: **更新时间**: YYYY-MM-DD |
:material-account: **维护人**: 姓名 |
:material-tag: **标签**: 标签1, 标签2, 标签3
```

**故障排查类** — 额外包含优先级和发生时间：

```markdown
:material-file-document-edit: **文档类型**: 故障排查 |
:material-alert-circle: **优先级**: 🔴 高 |
:material-account-clock: **发生时间**: YYYY-MM-DD |
:material-account: **处理人**: 研发团队 |
:material-tag: **标签**: 故障组件, 故障现象, 涉及服务
```

**工具手册类**：

```markdown
:material-file-document-edit: **文档类型**: 工具手册 |
:material-account-clock: **更新时间**: YYYY-MM-DD |
:material-account: **维护人**: 研发团队 |
:material-tag: **标签**: 组件名, 功能分类, 环境
```

**功能设计类** — 可选增加涉及模块：

```markdown
:material-file-document-edit: **文档类型**: 功能设计 |
:material-api: **涉及模块**: 模块名 |
:material-account-clock: **更新时间**: YYYY-MM-DD |
:material-account: **维护人**: 研发团队 |
:material-tag: **标签**: 租户名, 功能分类, 技术方案
```

> :material-tag: **标签选取原则**：技术关键字优先 → 项目/租户名 → 功能/模块名 → 问题/场景标识，每文档 3~6 个标签，英文逗号分隔。

#### 3.2.2 图标使用

| 场景 | 图标语法 | 示例 |
|------|---------|------|
| 信息提示 | `:material-information:` | 背景说明 |
| 警告提示 | `:material-alert-circle:` | 注意事项 |
| 成功提示 | `:material-check-circle:` | 完成状态 |
| 代码块 | `:material-code-json:` | 代码示例 |

#### 3.2.3 提示框

```markdown
!!! info "信息标题"
    信息内容

!!! warning "警告"
    警告内容

!!! tip "提示"
    提示内容
```

#### 3.2.4 可折叠内容

```markdown
??? example "示例标题"
    折叠的内容

???+ abstract "默认展开"
    默认展开的内容
```

---

## 四、示例场景

### 4.1 场景1：生成工具使用手册

:material-clipboard-text: **用户需求**

```
请帮我生成一份"MySQL慢查询优化指南"，包含常用命令和排查方法
```

:material-robot: **AI执行流程**

1. 识别文档类型：工具使用手册
2. 归类目录：`01_常用工具文档/`
3. 应用美化规范：添加图标、提示框、代码块
4. 生成文件：`01_常用工具文档/MySQL慢查询优化指南.md`

### 4.2 场景2：生成故障排查报告

:material-clipboard-text: **用户需求**

```
请帮我整理一份"Redis内存溢出排查报告"，包含问题现象、排查过程、解决方案
```

:material-robot: **AI执行流程**

1. 识别文档类型：故障排查报告
2. 归类目录：`02_问题处理文档/`
3. 应用美化规范：使用 `:red_circle:` 标记优先级，添加Mermaid流程图
4. 生成文件：`02_问题处理文档/Redis内存溢出排查报告.md`

### 4.3 场景3：生成功能设计文档

:material-clipboard-text: **用户需求**

```
请帮我写一份"商品比价功能设计文档"，包含需求背景、技术方案、接口设计
```

:material-robot: **AI执行流程**

1. 识别文档类型：功能设计文档
2. 归类目录：`04_研发内部设计/`
3. 应用美化规范：添加表格、代码块、标签页
4. 生成文件：`04_研发内部设计/商品比价功能设计文档.md`

---

## 五、常见问题

### 5.0 生成文档的安全红线（必读）

:material-shield-alert: **最重要规则：禁止在任何文档中输出真实密码！**

AI 生成文档时必须遵守以下安全规则：

| 敏感类型 | 禁止行为 | 正确做法 |
| :--- | :--- | :--- |
| 数据库密码 | 在 JDBC URL 中写真实密码 | 使用 `your_password` 占位 |
| Redis 密码 | 在配置文件中写真实密码 | 使用 `your_redis_password` 占位 |
| API Token/Key | 在接口示例中暴露真实 Token | 使用 `your_api_token` 或 `sk-xxxx` 占位 |
| 生产环境 IP | 在排查报告中暴露真实 IP | 使用 `10.x.x.x` 或 `192.168.x.x` 脱敏 |
| 证书密钥 | 在文档中粘贴证书内容 | 仅说明证书类型，不粘贴内容 |

!!! danger "安全警告"
    知识库使用 GitHub Pages 公开托管，若密码被提交到仓库，将**永久记录**在 Git 历史中，即使后续删除也无法清除，存在严重安全隐患。

### 5.1 生成的文档有乱码怎么办？

:material-alert-circle: **原因**

图标语法使用了中文冒号导致渲染错误。

:material-check-circle: **解决方法**

检查规则文件中的图标语法：

- ❌ 错误：`:material-chart-flow：` （中文冒号）
- ✅ 正确：`:material-chart-flow:` （英文冒号）

### 5.2 目录跳转无效怎么办？

:material-alert-circle: **原因**

手动编写的目录锚点与标题生成的ID不匹配。

:material-check-circle: **解决方法**

不要手动编写目录，使用MkDocs Material自动生成的右侧目录。

### 5.3 如何修改规则文件？

:material-information: **修改方式**

1. 打开规则文件：[**AI文档生成规则.md**](../99_文档模板/AI文档生成规则.md) 或本地路径 `D:\Program Files (x86)\pricemonitor\.codebuddy\rules\AI文档生成规则.mdc`
2. 修改对应章节内容
3. 保存文件
4. 后续AI生成文档时会自动应用新规则

---

## 六、规则文件维护

### 6.1 更新记录

| 版本 | 日期 | 更新内容 | 更新人 |
|------|------|---------|---------|
| v1.1 | 2026-06-05 | 所有模板强制增加标签字段；新增标签命名规范(2.2)；新增部署指南模板(4.4)；完善图标速查表；新增存量文档规范调整说明(5.5)；统一图标命名 | AI Assistant |
| v1.0 | 2026-06-05 | 初始版本，定义文档生成规则 | AI Assistant |

### 6.2 维护建议

:material-lightbulb-on: **建议**

1. **定期审查** - 每月检查规则是否适用
2. **收集反馈** - 记录使用中的问题，优化规则
3. **版本管理** - 重大修改时更新版本号
4. **团队共享** - 将规则文件同步给团队成员

---

## 七、参考资料

### 7.1 MkDocs Material 文档

:material-link: **官方文档**

- [MkDocs Material 官网](https://squidfunk.github.io/mkdocs-material/)
- [Admonitions 提示框](https://squidfunk.github.io/mkdocs-material/reference/admonitions/)
- [Icons 图标](https://squidfunk.github.io/mkdocs-material/reference/icons-emojis/)
- [Code Blocks 代码块](https://squidfunk.github.io/mkdocs-material/reference/code-blocks/)

### 7.2 项目知识库

:material-folder-file: **本地路径**

`D:\Work\Dev-KB\部门研发运维知识库\`

:material-file-document: **参考文档**

- [**99_文档模板/AI文档生成规则.md**](../99_文档模板/AI文档生成规则.md) - **规则文件线上版（点击浏览完整规则）**
- `00_说明/个人知识库部署.md` - 知识库部署指南
- `02_问题处理文档/Phoenix_QueryServer_Namespace_Mapping_排查报告.md` - 标签化头部参考模板
- `01_常用工具文档/ES 常用语句记录.md` - 工具手册美化示例
- `02_问题处理文档/ES集群写入拒绝排查优化报告.md` - 故障排查报告美化示例

---

## 八、总结

:material-check-all: **核心要点**

1. :white_check_mark: 规则文件：[**99_文档模板/AI文档生成规则.md**](../99_文档模板/AI文档生成规则.md)（线上可浏览）
2. :white_check_mark: 使用方式：对话引用、自定义指令、快捷指令
3. :white_check_mark: 标签化头部：文档类型 + 时间 + 维护人 + **必选标签**（3~6个）
4. :white_check_mark: 美化规范：图标、提示框、可折叠内容、代码块
5. :white_check_mark: 目录归类：根据文档类型自动归类到对应文件夹

:material-lightbulb-on: **建议**

- 首次使用规则时，先生成测试文档验证效果
- 根据实际使用效果，持续优化规则文件
- 将规则文件分享给团队，统一文档生成标准

---

**:material-check-all: 文档结束**

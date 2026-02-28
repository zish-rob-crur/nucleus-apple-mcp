# Health 模块规范（v0.1）

本文档定义 Health 模块的实施手册：范围、同步架构、文件 schema、MCP 工具以及错误约定。

v0.1 在真实世界约束下收紧 v0 设计以保证正确性：

- iOS 后台执行是 **best-effort（尽力而为）**；上传可能延迟。([Apple Developer][6])
- 网络重试与并发运行可能导致 **写入竞态（write races）**；较旧的上传绝不能覆盖较新的数据。
- “一天”在跨时区/夏令时（DST）时必须无歧义；日边界必须显式声明。
- 缺失/未授权的数据必须显式表达；绝不能用 `0` 来编码“无数据”。

---

## 1. 范围与约束

- 模块名：**health**
- 数据采集运行时：**仅 iOS 伴生应用（Nucleus）**（v0.x 不直接在 macOS 上采集 HealthKit）。
- v0.x 对下游 agent **只读**（不回写 HealthKit）。
- v0.x **仅上传聚合指标**（按天聚合）。
- v1 可选上传 **原始样本**（JSONL），用于更适合 agent 的分析与特征衍生。
- 支持两种存储后端：
  - `icloud_drive`（应用 iCloud ubiquity container 下的 Documents 文件夹）
  - `s3_object_store`
- 同步模式：**基于文件的同步**（按天 + 增量更新）。
- 一致性模型：**最终一致性**（文件在上传完成后出现）。

v0.x 范围外：

- 心电（ECG）/临床记录
- 原始样本导出 API（v1 引入 raw JSONL 导出；v0.x 仍保持仅聚合）
- 服务端数据库/索引服务（v0.x 为“直接读文件”）
- 复杂的按需触发（推送通知）

---

## 2. 术语

- **Collector（采集端）**：iOS 应用（Nucleus）组件，读取 HealthKit 并上传每日健康数据文件。
- **Storage（存储）**：iCloud Drive（Documents）或用于落盘文件的 S3 bucket/prefix。
- **Day（天）**：一个带显式时区且边界为 `[start, end)` 的报告日。
- **Revision（修订版）**：不可变文件，表示某一天生成的一次快照。
- **Latest Pointer（最新指针）**：小文件，用于标记某天“已知最新”的 revision。

---

## 3. 本规范假设的平台代理事实

- HealthKit 授权是细粒度的；应用必须按类型请求读取权限。([Apple Developer][4])
- 后台投递基于 observer queries / background delivery，属于 best-effort。([Apple Developer][5])
- 后台任务调度属于 best-effort；不要假设精确的时机或频率。([Apple Developer][6])
- S3 对 PUT/GET/LIST 具备强的 read-after-write 一致性。([AWS][7])

---

## 4. 架构

### 4.1 高层流程

1. iOS Collector 读取 HealthKit（按天统计查询）。
2. Collector 为报告日构造 **Daily Revision** 的 JSON 负载。
3. Collector 将不可变的 revision 文件上传到该天目录下（仅追加）。
4. （可选）Collector 更新该天的 `latest.json` 指针。
5. MCP 工具直接读取这些文件以回答查询。

### 4.2 写入模型（规范性 / Normative）：仅追加的 Revisions

为防止写入竞态破坏“latest”数据，**不要覆盖每日数据文件**。

- 每次更新都在 `.../{YYYY}/{MM}/{DD}/revisions/` 下生成一个新的 revision 文件。
- Revision 文件名必须按时间顺序可排序（字典序 / lexicographic order）且全局唯一。
- Collector 可以更新 `latest.json` 作为优化，但 MCP 必须容忍它缺失或过期（stale）。

### 4.3 同步触发（Best-Effort）

- **主触发（HealthKit 更新）**：
  - 为跟踪的类型注册 `HKObserverQuery`。([Apple Developer][5])
  - 收到通知（Background Delivery）后，重新计算“今天”并上传新的 revision。
- **次触发（定时）**：
  - 使用 `BGAppRefreshTask` 周期性运行（例如每晚）。([Apple Developer][6])
  - 重新计算并上传一个 **追赶窗口（catch-up window）** 的 revisions（默认：最近 7 天），以吸收延迟到达的数据（睡眠、HRV 等）。

---

## 5. 存储布局（规范性 / Normative）

### 5.1 基础前缀

所有对象都位于：

`health/v0/`

### 5.2 天目录

`health/v0/data/{YYYY}/{MM}/{DD}/`

内容：

- `revisions/{REVISION_ID}.json`（不可变；1 个或多个文件）
- `latest.json`（可选；指向“已知最新”的 revision）

### 5.3 Revision ID 格式（规范性 / Normative）

`REVISION_ID` 必须（MUST）：

- 以 UTC 时间戳格式 `YYYYMMDDTHHMMSSZ`
- 后接 `-` 与随机后缀（6+ 位 base16 字符）

示例：

- `20260208T100000Z-7F3A2C`

### 5.4 latest.json 格式（可选 / Optional）

```json
{
  "date": "2026-02-08",
  "latest_generated_at": "2026-02-08T10:00:00Z",
  "revision_id": "20260208T100000Z-7F3A2C",
  "revision_relpath": "revisions/20260208T100000Z-7F3A2C.json"
}
```

语义：

- `revision_relpath` 相对于 `health/v0/data/{YYYY}/{MM}/{DD}/`。
- MCP 必须（MUST）验证被引用的 revision 存在且可解析；否则必须回退到扫描 `revisions/`。

### 5.5 对象存储映射（s3_object_store）

当使用 `s3_object_store` 后端时，Collector 会上传它在本地写入的同一批文件，并保持与本地相对路径一致的 object key：

- 本地根目录：`.../Documents/`
- Object key：`{prefix(可选)}/{documents 下的相对路径}`

示例：

- 本地：`Documents/health/v0/data/2026/02/21/revisions/20260221T115720Z-FF283A.json`
- Object key：`health/v0/data/2026/02/21/revisions/20260221T115720Z-FF283A.json`

备注：

- 只要支持 SigV4，S3 兼容对象存储也可以使用（例如 Cloudflare R2）。
- Cloudflare R2 通常使用 `auto` 作为 region，并需要自定义 endpoint。
- 不要在 App 内硬编码长期 Access Key；本地个人开发可放入 Keychain，正式使用建议短期凭证或 pre-signed URL。

---

## 6. Daily Revision 文件 schema（v0）

### 6.1 文件路径

`health/v0/data/{YYYY}/{MM}/{DD}/revisions/{REVISION_ID}.json`

### 6.2 JSON 内容

```json
{
  "schema_version": "health.v0",
  "date": "2026-02-08",
  "day": {
    "timezone": "America/Los_Angeles",
    "start": "2026-02-08T00:00:00-08:00",
    "end": "2026-02-09T00:00:00-08:00"
  },
  "generated_at": "2026-02-08T10:00:00Z",
  "collector": {
    "collector_id": "4E0A0B4E-2E08-4B63-9B50-8E3F6F8A1F1F",
    "device_id": "A1B2C3D4-E5F6-7890-ABCD-EF0123456789"
  },
  "metrics": {
    "steps": 1250,
    "active_energy_kcal": 450.5,
    "exercise_minutes": 30,
    "stand_hours": 4,
    "resting_hr_avg": null,
    "hrv_sdnn_avg": null,
    "sleep_asleep_minutes": null,
    "sleep_in_bed_minutes": null
  },
  "metric_status": {
    "steps": "ok",
    "active_energy_kcal": "ok",
    "exercise_minutes": "ok",
    "stand_hours": "ok",
    "resting_hr_avg": "no_data",
    "hrv_sdnn_avg": "unauthorized",
    "sleep_asleep_minutes": "no_data",
    "sleep_in_bed_minutes": "no_data"
  },
  "metric_units": {
    "steps": "count",
    "active_energy_kcal": "kcal",
    "exercise_minutes": "min",
    "stand_hours": "hr",
    "resting_hr_avg": "bpm",
    "hrv_sdnn_avg": "ms",
    "sleep_asleep_minutes": "min",
    "sleep_in_bed_minutes": "min"
  }
}
```

规则：

- `generated_at` 必须（MUST）是 ISO-8601 的 UTC datetime（后缀 `Z`）。
- `day.start`/`day.end` 必须（MUST）为带显式时区偏移的 ISO-8601；区间为 `[start, end)`。
- `metrics` 的值为 number 或 `null`（绝不使用 `0` 表示“无数据”）。
- 对于指标键 `k`：
  - 若 `metric_status[k] == "ok"`，则 `metrics[k]` 必须（MUST）为 number
  - 若 `metric_status[k] != "ok"`，则 `metrics[k]` 必须（MUST）为 `null`

### 6.3 metric_status 枚举

- `ok`：数据已计算且存在
- `no_data`：已授权，但该区间内 HealthKit 没有数据
- `unauthorized`：collector 没有读取该指标的权限
- `unsupported`：该设备/OS 配置不支持该指标

---

## 6.4 原始样本导出（v1, JSONL）（可选）

v1 增加一个可选的“原始样本导出流”，用于更适合 agent 的分析（特征工程、异常检测、纵向时间序列等）。它与 v0 的“每日聚合”互补：

- v0：快速稳定回答“今天发生了什么”。
- v1：保留样本级信息，便于下游重新计算任意派生指标。

### 6.4.1 文件路径

样本（samples）：

`health/v1/raw/data/{YYYY}/{MM}/{DD}/revisions/{REVISION_ID}.jsonl`

元信息（meta）：

`health/v1/raw/data/{YYYY}/{MM}/{DD}/revisions/{REVISION_ID}.meta.json`

### 6.4.2 格式（JSON Lines）

- 样本文件必须（MUST）为 UTF-8 文本的 JSONL（每行一个 JSON 对象）。
- 样本文件的每一行都是 **sample 记录**（`record = "sample"`）。
- meta 文件是单个 JSON 对象（不是 JSONL），描述该 revision 的整体信息。

### 6.4.3 Meta 文件（`*.meta.json`）

```json
{
  "record": "meta",
  "schema_version": "health.raw.v1",
  "date": "2026-02-21",
  "day": { "timezone": "Asia/Shanghai", "start": "2026-02-21T00:00:00+08:00", "end": "2026-02-22T00:00:00+08:00" },
  "generated_at": "2026-02-21T11:57:20Z",
  "collector": { "collector_id": "...", "device_id": "..." },
  "type_status": { "heart_rate": "ok", "sleep_analysis": "unauthorized" },
  "type_counts": { "heart_rate": 2450, "sleep_analysis": 0 }
}
```

规则：

- `type_status[k]` 必须（MUST）是：`ok | no_data | unauthorized | unsupported` 之一。
- 若 `type_status[k] != "ok"`，则 `type_counts[k]` 必须（MUST）为 `0`。

### 6.4.4 Sample 记录（JSONL 行）

每条 sample 记录对应一个 HealthKit 样本（quantity/category/workout）。

数量样本（quantity）示例：

```json
{
  "record": "sample",
  "kind": "quantity",
  "key": "heart_rate",
  "hk_identifier": "HKQuantityTypeIdentifierHeartRate",
  "uuid": "…",
  "start": "2026-02-21T10:12:00+08:00",
  "end": "2026-02-21T10:12:00+08:00",
  "value": 72.0,
  "unit": "bpm"
}
```

睡眠类别样本（category）示例：

```json
{
  "record": "sample",
  "kind": "category",
  "key": "sleep_analysis",
  "hk_identifier": "HKCategoryTypeIdentifierSleepAnalysis",
  "uuid": "…",
  "start": "2026-02-21T00:30:00+08:00",
  "end": "2026-02-21T07:10:00+08:00",
  "category_value": 0,
  "category_label": "in_bed"
}
```

备注：

- `start`/`end` 必须（MUST）为带显式时区偏移的 ISO-8601。
- 建议采用规范单位：`count | kcal | bpm | ms | m | sec`。
- raw 导出同样遵循仅追加的 revision 写入模型，并沿用 v0 的 `REVISION_ID` 生成规则。

---

## 7. Metric Keys（v0）

- `steps`
- `active_energy_kcal`
- `exercise_minutes`
- `stand_hours`
- `resting_hr_avg`
- `hrv_sdnn_avg`
- `sleep_asleep_minutes`
- `sleep_in_bed_minutes`

---

## 8. iOS Collector 行为（规范性 / Normative）

### 8.1 Collector 身份

- `collector_id` 必须（MUST）在多次启动间保持稳定，且理想情况下跨重装也稳定（例如：存储在 Keychain 中的 UUID）。
- `device_id` 应当（SHOULD）是应用选择的稳定 UUID；避免使用易变化的标识符。

### 8.2 需要重新计算的内容

每次运行（前台启动、observer 唤醒或定时任务）时：

- 始终重新计算 **今天**。
- 重新计算过去若干天的 **追赶窗口（catch-up window）**（默认：最近 7 天），用于处理延迟到达或被更正的数据。

### 8.3 上传流程（按天）

1. 计算日边界（`day.timezone`, `day.start`, `day.end`）以及该区间的聚合指标。
2. 使用当前 UTC 时间与随机后缀生成新的 `REVISION_ID`。
3. 先将 JSON 写入本地临时文件，再上传/移动到 `revisions/{REVISION_ID}.json`（不可变）。
4. （可选）更新 `latest.json` 指向新的 revision。

如果计算出的负载与当前最新 revision 在字节级完全一致，collector 可以（MAY）跳过写入新的 revision。

---

## 9. MCP 读取行为（规范性 / Normative）

### 9.1 解析某天的 “Latest”

给定 `date`：

1. 尝试读取 `health/v0/data/YYYY/MM/DD/latest.json`。
2. 若存在，尝试读取其引用的 revision 文件。
3. 若 `latest.json` 缺失、过期或无效，则列出 `health/v0/data/YYYY/MM/DD/revisions/` 并选择字典序最大的 `REVISION_ID`。

### 9.2 区间读取

区间读取必须（MUST）以日期为驱动（按日历日期），而不是通过列举任意前缀：

- 对 `[start_date, end_date]`（包含端点）内的每个日期，尝试解析 latest 并读取一个 revision。
- 缺失日期记录在 `missing_dates` 中，且不会导致工具失败。

---

## 10. 错误码（v0.x）

- `INVALID_ARGUMENTS`：参数无效/解析失败（日期格式错误、`start_date > end_date`、范围过大）。
- `NOT_AUTHORIZED`：MCP 缺少读取已配置存储所需的权限/凭据。
- `DATA_NOT_FOUND`：请求日期无数据（未找到任何 revisions）。
- `STORAGE_UNAVAILABLE`：存储后端暂不可用（网络、API 错误）。
- `INTERNAL`：未预期异常（序列化、缺陷）。

---

## 11. MCP 工具映射（Python / FastMCP）

必需工具：

- `health.read_daily_metrics`
- `health.read_range_metrics`

### 11.1 `health.read_daily_metrics`

输入：

- `date`（YYYY-MM-DD，必填）

返回：

- `date`（YYYY-MM-DD）
- `generated_at`（ISO-8601 UTC）
- `day`（时区 + 边界）
- `metrics`（object，值为 number|null）
- `metric_status`（object）
- `metric_units`（object）

### 11.2 `health.read_range_metrics`

输入：

- `start_date`（YYYY-MM-DD，必填）
- `end_date`（YYYY-MM-DD，必填；包含端点）

约束：

- `start_date <= end_date`，否则为 `INVALID_ARGUMENTS`
- 最大跨度：366 天（否则为 `INVALID_ARGUMENTS`）

返回：

- `start_date`
- `end_date`
- `data`：按天对象数组（按 `date` 升序排序）
- `missing_dates`：未找到 revision 的日期数组（YYYY-MM-DD）

---

## 12. 新鲜度策略（Freshness Policy）

- 数据新鲜度取决于该日期可用的最新 revision。
- MCP 始终返回 `generated_at`，以便调用方判断陈旧程度。

---

## 13. 安全与隐私

- Collector 仅写入用户私有存储（iCloud Drive / 私有 S3 prefix）。
- v0.x 仅导出按天聚合数据；v1 可选导出原始样本（JSONL），路径为 `health/v1/raw/...`。
- MCP 使用用户提供的凭据读取存储；不存在中间的 ingest server。

---

## 14. v0.x 验收标准

- iOS 应用按 `health/v0/...` 上传“仅追加”的每日 revisions。
- “Latest” 解析在重试/竞态下仍正确（旧 revision 不能覆盖新数据）。
- MCP 可读取单日与区间结果，并提供显式的缺失/未授权语义。

---

## 15. 产品命名与设计语言（非规范性 / Non-normative）

- iOS 伴生应用（Collector）产品名：**Nucleus**
- 设计语言建议：以 Apple Human Interface Guidelines（HIG）为基线（SwiftUI / SF Pro / Dynamic Type / Dark Mode / Accessibility），保持“中性、克制、可信”的气质，避免仅限 health 的视觉暗示；采用“中性底色 + 单一品牌强调色”的 token 体系；信息架构优先突出数据来源、生成时间（`generated_at`）与授权/缺失状态（`metric_status`），并让连接/同步状态在全局可见。

---

## 参考资料

[4]: https://developer.apple.com/documentation/healthkit/authorizing_access_to_health_data
[5]: https://developer.apple.com/documentation/healthkit/hkobserverquery
[6]: https://developer.apple.com/documentation/backgroundtasks
[7]: https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html

# Nucleus（iOS 伴生 App / Collector）

本目录是 **Nucleus** 的 iOS 伴生应用（Collector）工程骨架，用于按照 `docs/specs/health.md` 从 HealthKit 采集按天聚合指标，并以“仅追加 revisions”的方式写入应用私有本地存储，并可选上传到 S3 兼容对象存储。

发版策略说明：

- 出于 App Store 审核约束，Nucleus 不再提供“把健康数据同步到 iCloud”这条产品线。
- 原因是 Apple App Review Guideline 5.1.3(ii) 不允许将个人健康信息存储到 iCloud。

## 目标平台

- Xcode：26.x
- iOS Deployment Target：26.0+

## 打开与运行

1. 用 Xcode 打开 `apps/ios/Nucleus/Nucleus.xcodeproj`
2. 选择一个 iOS 26+ 模拟器或真机
3. 如需真机运行：在 Xcode 的 Signing & Capabilities 里设置 Team 与 Bundle ID

## 需要的能力（当前发版路径）

- HealthKit（读取权限 + `NSHealthShareUsageDescription`）
- Background Tasks（Observer Query / BGAppRefreshTask）
- App Groups（主 app / widget 共享最近同步状态）

# Nucleus（iOS 伴生 App / Collector）

本目录是 **Nucleus** 的 iOS 伴生应用（Collector）工程骨架，用于按照 `docs/specs/health.md` 从 HealthKit 采集按天聚合指标，并以“仅追加 revisions”的方式写入用户私有存储（iCloud Drive / S3）。

## 目标平台

- Xcode：26.x
- iOS Deployment Target：26.0+

## 打开与运行

1. 用 Xcode 打开 `apps/ios/Nucleus/Nucleus.xcodeproj`
2. 选择一个 iOS 26+ 模拟器或真机
3. 如需真机运行：在 Xcode 的 Signing & Capabilities 里设置 Team 与 Bundle ID

## 需要的能力（后续会逐步接入）

- HealthKit（读取权限 + `NSHealthShareUsageDescription`）
- Background Tasks（Observer Query / BGAppRefreshTask）
- iCloud（写入 ubiquity container 的 Documents）


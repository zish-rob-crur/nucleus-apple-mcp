# Nucleus（iOS 伴生 App / Collector）

本目录是 **Nucleus** 的 iOS 伴生应用（Collector）工程骨架，用于按照 `docs/specs/health.md` 从 HealthKit 采集按天聚合指标，并以“仅追加 revisions”的方式写入应用私有本地存储，并可选上传到 S3 兼容对象存储。

App Store 下载地址：
[Nucleus Context Hub](https://apps.apple.com/us/app/nucleus-context-hub/id6760659033)

发版策略说明：

- 出于 App Store 审核约束，Nucleus 不再提供“把健康数据同步到 iCloud”这条产品线。
- 原因是 Apple App Review Guideline 5.1.3(ii) 不允许将个人健康信息存储到 iCloud。

## 目标平台

- Xcode：26.x
- iOS Deployment Target：26.0+

## Codex / SwiftUI 工作流

本项目按 OpenAI Codex 原生 iOS 工作流沉淀了 project-local skills，文件位于 repo 根目录的 `.agents/skills/`：

- `swiftui-expert-skill`：SwiftUI 功能实现与常规最佳实践。
- `swiftui-pro`：现代 SwiftUI API、可维护性、可访问性、性能的综合 review。
- `swiftui-liquid-glass`：iOS 26+ Liquid Glass API 采用与评审。
- `swiftui-performance`：SwiftUI 更新路径、滚动、布局和 Instruments 方向的性能审查。
- `swift-concurrency-expert`：Swift 6 并发、actor isolation、Sendable 和 async/await 诊断。
- `swiftui-view-refactor`：拆分大型 SwiftUI view、稳定 view tree、统一依赖注入。
- `swiftui-patterns`：`@Observable`、`@Environment`、MV 架构和组件组合模式。

Liquid Glass 的项目入口集中在 `Nucleus/NucleusDesign.swift`：`NucleusGlassContainer` 负责分组，`NucleusGlassRoundedSurface` 与 `NucleusGlassCapsuleSurface` 负责共享玻璃表面。页面代码应继续优先使用 `NucleusCard`、`NucleusInset`、`StatusPill` 和 `NucleusButtonStyle`，不要在业务页面散落自定义 blur/material。

## 打开与运行

1. 用 Xcode 打开 `apps/ios/Nucleus/Nucleus.xcodeproj`
2. 选择一个 iOS 26+ 模拟器或真机
3. 如需真机运行：在 Xcode 的 Signing & Capabilities 里设置 Team 与 Bundle ID

CLI 验证：

```sh
xcodebuild -project apps/ios/Nucleus/Nucleus.xcodeproj -scheme Nucleus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## 需要的能力（当前发版路径）

- HealthKit（读取权限 + `NSHealthShareUsageDescription`）
- Background Tasks（Observer Query / BGAppRefreshTask）
- App Groups（主 app / widget 共享最近同步状态）

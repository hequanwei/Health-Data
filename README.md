# Health Data

本地生化数据枢纽 —— 把 Apple Health / Apple Watch 近 7 日数据导出为本地 JSON，并用规则引擎做恢复分与健康提醒。适合「量化自我」与 AI Weekly 复盘。

> **非医疗诊断**，仅供个人参考，不能替代医生诊断。

## 亮点

| 能力 | 说明 |
|------|------|
| **本地 JSON 导出** | 23+ 类 HealthKit 指标，按日归并，`schemaVersion: 4` |
| **恢复分 & 提醒** | 基于 HRV、静息心率、睡眠、训练负荷的本地规则 |
| **AI 分析 Prompt** | 一键复制，配合 JSON 交给 ChatGPT / Claude 做周报 |
| **隐私优先** | 数据只写本机 Documents，不上传云端 |
| **主屏幕 Widget** | 展示恢复分、HRV、提醒数 |
| **后台轻扫** | `BGAppRefresh` 静默更新提醒与 Widget |
| **导出历史** | 查看、分享、删除已导出的 JSON |

## 截图 / 使用场景

1. 打开 App → 授权 HealthKit → **扫描健康提醒** 看恢复分  
2. **导出近 7 日健康数据** → 在「文件 → 我的 iPhone → Health Data」拿到 JSON  
3. **复制 AI 分析 Prompt** + 附上 JSON → 做 Weekly 量化复盘  
4. 长按主屏幕添加 **「恢复分」** 小组件  

## 导出的指标（部分）

心率 / 静息心率 / **HRV (SDNN)** / 呼吸率 / 睡眠阶段 / 体能训练 / 步数 / VO2 Max / 心率恢复 / 步行心率 / 步行不对称与双支撑 / 睡眠手腕温度 / 血氧 / 日光时间 / 活动与基础能量 / 站立时间 / 步长 / 上下楼梯速度 / 环境音量 / 咖啡因  

JSON 额外包含：

- `dailySummaries`：日级摘要与 flags  
- `weeklyInsight`：恢复分、周级标记、`suggestedAnalysisPrompt`  

## 技术栈

- SwiftUI + HealthKit（async / await + TaskGroup）
- WidgetKit + App Group 共享恢复分快照
- BackgroundTasks（`BGAppRefresh`）
- UserNotifications（可选本地通知）
- 最低系统：**iOS 18.6+**
- Bundle ID：`com.personal.Health-Data`  
- Widget：`com.personal.Health-Data.widget`  
- App Group：`group.com.personal.Health-Data`

## 仓库结构

```
Health Data/
├── Health Data/                 # 主 App 源码
│   ├── HealthManager.swift      # HealthKit 读取与导出
│   ├── HealthInsightAnalyzer.swift
│   ├── ContentView.swift / SettingsView.swift / ExportHistoryView.swift
│   └── ...
├── Health Data Widget/          # 恢复分 Widget
├── Health Data.xcodeproj
├── Health-Data-Info.plist
└── README.md
```

## 本地构建

### 要求

- macOS + Xcode 16+（建议最新稳定版）
- Apple Developer 账号（真机）
- 真机 iOS ≥ 18.6，并已配对 Apple Watch（部分指标依赖手表）

### 步骤

1. Clone 本仓库并打开 `Health Data.xcodeproj`
2. 在 **Signing & Capabilities** 中为两个 Target 选择你的 Team  
   - `Health Data`  
   - `Health Data WidgetExtension`
3. 如需改 Bundle ID，请同步修改 App Group 标识符与 entitlements
4. **真机部署前务必配置 App Groups**（见下节）
5. 连接 iPhone → 选择真机 → Run（⌘R）

### App Groups（真机必配）

Widget 与主 App 通过 App Group 共享恢复分。请在 [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list) 中：

1. 为 `com.personal.Health-Data` 开启 **App Groups**，创建并勾选 `group.com.personal.Health-Data`
2. 为 `com.personal.Health-Data.widget` 勾选**同一个** App Group
3. Xcode 两个 Target 的 Signing 勾选 Automatically manage signing，确认 Capability 中已勾选该 Group

未配置时，真机构建可能报 *Provisioning profile doesn't include the App Groups capability*。

### 模拟器说明

模拟器可编译通过，但 **HealthKit 数据有限**，完整能力请在真机验证。

## 权限说明

| 权限 | 用途 |
|------|------|
| HealthKit 读取 | 导出与扫描所需指标 |
| 后台 App Refresh | 每日轻量扫描 |
| 本地通知（可选） | 注意 / 重要级别提醒，每日最多一条 |
| 文件共享 (`UIFileSharingEnabled`) | 在「文件」App 中访问导出的 JSON |

## 设置项

- 扫描后本地通知开关  
- 每日后台自动扫描开关  
- HRV / 静息心率 / 睡眠 / 训练负荷阈值（可恢复默认）

## 免责声明

本项目仅供个人量化自我与学习交流使用。输出结果**不是医疗建议**，不构成诊断或治疗依据。若身体不适，请及时就医。

## License

[MIT](./LICENSE)

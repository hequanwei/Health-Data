# Health Data

**把 Apple Watch 里的身体数据，变成你能带走、能复盘、能丢给 AI 的本地 JSON。**

如果你有 iPhone 和 Apple Watch，也盯着 HRV、睡眠、静息心率、训练负荷这些数字——却发现「健康」App 好看不好带走，商业恢复类 App 好看但不开放——这个项目就是假期里做出来的一款**本地生化数据枢纽**：读近 7 日 HealthKit，导出结构化 JSON，用本地规则算出恢复分与健康提醒，一键复制分析 Prompt，交给 ChatGPT / Claude 做 Weekly 量化复盘。

数据**不出手机、不上传云端**。非医疗诊断，仅供个人参考。

[功能](#功能) · [为什么做](#为什么做) · [快速开始](#快速开始) · [导出长什么样](#导出长什么样) · [构建说明](#构建说明) · [免责声明](#免责声明)

---

## 功能

| | |
|---|---|
| **开放导出** | 23+ 类 HealthKit 指标，按日归并，JSON `schemaVersion: 4`，可用「文件」App 直接打开 |
| **恢复分 & 提醒** | 本地规则：HRV 断崖 / 持续偏低、静息心率升高、睡眠不足、低恢复日硬练 |
| **AI 友好** | 内置 `suggestedAnalysisPrompt` + 一键复制，JSON 直接当附件做周报 |
| **隐私优先** | 仅写本机 Documents；无账号、无后端、无 iCloud 同步 |
| **主屏幕 Widget** | 恢复分、最新 HRV、提醒数，一眼看到状态 |
| **后台轻扫** | 系统调度的每日扫描，刷新提醒与 Widget（可选通知） |
| **导出历史** | 列表查看、系统分享、单条 / 全部删除 |

### 典型用法

1. 打开 App → 授权「健康」读取 → **扫描健康提醒**，看恢复分与告警  
2. **导出近 7 日健康数据** → `文件 → 我的 iPhone → Health Data`  
3. **复制 AI 分析 Prompt**，把 JSON 一并贴给大模型做 Weekly 复盘  
4. 长按主屏幕添加 **「恢复分」** 小组件  

---

## 为什么做

市面上 PeakWatch / Bevel / StressWatch 等产品体验成熟，但往往是**封闭分数 + 订阅墙**。本项目刻意站在另一侧：

- **数据归你**：原始与摘要都在本地 JSON 里，可归档、可 diff、可喂给任意 AI  
- **规则透明**：阈值可在设置里调，不是黑盒「恢复分」  
- **够用就好**：个人量化自我 + AI 周报，不为做 App Store 大而全产品  

适合：有 Apple Watch、关心自主神经与恢复、愿意自己读数 / 用 AI 复盘的人。

---

## 导出长什么样

覆盖指标（节选）：心率、静息心率、**HRV (SDNN)**、呼吸率、睡眠阶段、体能训练、步数、VO2 Max、心率恢复、步行心率、步行不对称 / 双支撑、睡眠手腕温度、血氧、日光、活动 / 基础能量、站立、步长、上下楼梯速度、环境音量、咖啡因等。

除按日明细 `dataByDate` 外，还包含：

| 字段 | 内容 |
|------|------|
| `dailySummaries` | 每日 HRV / 睡眠 / 训练摘要与 `flags` |
| `weeklyInsight` | 恢复分、周级标记、提醒列表、**AI 分析 Prompt** |
| `exportSummary` | 各类样本计数，方便快速核对权限与空数据 |

---

## 技术栈

SwiftUI · HealthKit（async/await + TaskGroup）· WidgetKit · App Groups · BackgroundTasks · UserNotifications  

- iOS **18.6+**（建议真机 + 已配对 Apple Watch）  
- Bundle：`com.personal.Health-Data`  
- Widget：`com.personal.Health-Data.widget`  
- App Group：`group.com.personal.Health-Data`

```
Health Data/
├── Health Data/              # 主 App（导出、规则引擎、设置、历史）
├── Health Data Widget/       # 恢复分小组件
├── Health Data.xcodeproj
└── README.md
```

---

## 快速开始

```bash
git clone https://github.com/hequanwei/Health-Data.git
cd Health-Data
open "Health Data.xcodeproj"
```

1. Xcode 中为 **Health Data** 与 **Health Data WidgetExtension** 选择你的 Team  
2. 配置 **App Groups**（真机必做，见下）  
3. 连上 iPhone → Run（⌘R）  
4. 首次在「健康」中授权读取；扫描一次后即可加 Widget  

模拟器可编译，但 HealthKit 数据不完整，**请以真机为准**。

### App Groups（真机必配）

Widget 与主 App 共享恢复分快照。在 [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list)：

1. `com.personal.Health-Data` → 启用 App Groups → 添加并勾选 `group.com.personal.Health-Data`  
2. `com.personal.Health-Data.widget` → 勾选**同一个** Group  
3. Xcode Signing 保持 Automatically manage signing，确认两个 Target 都勾了该 Group  

未配置时常见报错：*Provisioning profile doesn't include the App Groups capability*。

若你 fork 后改了 Bundle ID，请同步改 entitlements 里的 App Group 名。

---

## 权限与设置

| 权限 | 用途 |
|------|------|
| HealthKit 读取 | 导出与扫描 |
| 后台 App Refresh | 每日轻量扫描 |
| 本地通知（可选） | 「注意 / 重要」提醒，每日最多一条 |
| 文件共享 | 在「文件」中访问导出的 JSON |

设置页可调：通知、后台扫描、HRV / 静息心率 / 睡眠 / 训练负荷阈值（可一键恢复默认）。

---

## 免责声明

本项目用于个人量化自我与学习交流。输出**不是医疗建议**，不构成诊断或治疗依据。身体不适请及时就医。

---

## License

[MIT](./LICENSE) — 欢迎 fork、改造与提 Issue。请勿上传含真实健康数据的导出文件到公开 Issue。

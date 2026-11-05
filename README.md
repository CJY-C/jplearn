# 日语拾阶 · JPLearn

面向日语原版阅读的原生 iOS 训练应用。离线学习，逐项保存，使用系统日语朗读；最低系统为 iOS 15.5。

[GitHub 仓库](https://github.com/CJY-C/jplearn) · [版本与 IPA 下载](https://github.com/CJY-C/jplearn/releases) · [构建记录](https://github.com/CJY-C/jplearn/actions/workflows/build.yml)

当前交付是应用底座与 **12 个个人试用样章**：150 个词、20 个语法及表达、40 道结构练习、6 篇短文。N5–N2 的完整路线和制作目标已建模，剩余课程尚未编写，不能将当前样章视为完整 N2 课程。样章为原创试用内容，尚待独立日语审校。

## 已实现

- 今天／课程／资料三个入口；可调整每日学习时长。
- SE3 单屏词卡与句型题，底部操作区固定；长文仅在上方独立滚动。
- 实际学习计时、手动暂停、离开及锁屏停止；每日目标按累计时间显示。
- 汉字、注音、中文释义、可选罗马音；系统日语朗读和慢速播放。
- 词义与读音分别复习；假名输入、自主回忆、结构判断、新句迁移和短文理解。
- 固定版本 FSRS-6，目标回忆率 90%；使用提示的回答按未独立回忆处理。
- 逐项保存答案；暂停后继续；提交答案与更新位置之间退出也可恢复。
- 课程资料搜索、收藏、笔记；带完整性校验的备份与幂等合并。
- 用户授权的 iCloud Drive 文件夹交换；按事件合并，支持两机离线后汇合。
- GitHub Actions 的内容检查、Swift 单元测试、iOS 集成测试、设备归档和 IPA 打包。
- 新版本通过检查后自动发布 Release，直接提供 IPA 下载，保留旧版文件。

## 通过 GitHub 构建

1. 将项目放入自己的 GitHub 仓库，保留 `.github/workflows/build.yml`。
2. 在 **Actions → Validate and build iOS IPA** 中运行工作流；push 和 pull request 也会触发检查。
3. 工作流通过后，在 [Releases](https://github.com/CJY-C/jplearn/releases) 下载 `JPLearn.ipa`；Actions artifact 也会保留。
4. 在已经安装 TrollStore 的兼容设备上打开 IPA 并安装。应用固定 Bundle ID 为 `dev.jplearn.reader`，后续同 ID 更新可保留应用数据。

构建不需要 Apple 开发者证书、Team ID 或仓库签名 secrets。此产物用于 TrollStore；普通系统安装需要另外配置合法签名。

工作流明确使用 macOS 15、Xcode 16.4 和校验过 SHA-256 的 XcodeGen 2.46.0。XcodeGen 从 `project.yml` 生成 Xcode 工程及 Info.plist，SwiftPM 从根目录 `Package.swift` 加载核心模块。FSRS 依赖固定到提交 `4fbaf20184d62f82a9f44f343337c61a2c5483e9`。

应用版本和构建号统一在 `Version.xcconfig` 设置。发布新版本时修改此文件并补充 `CHANGELOG.md`，推送 main。全部测试通过后，工作流为对应提交创建 `v<版本号>` Release 并附上 IPA；重复构建同一版本不会覆盖已发布文件。pull request 只检查，不发布。

## 本地开发与检查

macOS 安装 Xcode 16.4 与 XcodeGen 2.46.0 后：

```sh
python3 scripts/build_content.py --check
python3 -m unittest discover -s Tests/ContentTests -v
swift test
xcodegen generate --spec project.yml
open JPLearn.xcodeproj
```

选择 JPLearn scheme，可在模拟器运行。设备支持目标设置为 iOS 15.5；自动测试使用 iOS 18.5 的 iPhone SE3 模拟器，覆盖单屏按钮、键盘、固定答题区与暂停，不代表旧版系统已经完成真机验收。

Linux 可运行所有 Python 内容检查。2026-11-05 已在 [GitHub macOS 工作流](https://github.com/CJY-C/jplearn/actions/runs/41981863480) 通过 12 项内容检查、22 项核心测试和 4 项 iOS 18.5 模拟器集成测试，完成设备归档并生成 IPA。iOS 15.5、16.6 真机安装、朗读和双机 iCloud Drive 同步尚待验收。

## 第一次使用

在“设置”选择学习时长。在系统“辅助功能 → 朗读内容 → 声音”准备日语语音，然后在应用内试播；开启飞行模式再试一次，确认设备已具备离线语音。语音选择只在本机保存。

“今天”从到期复习开始，每天默认引入至多 5 个新词和 1 个表达；读音与词义独立计分。遇到较大复习队列时减少新内容，仍保留一段阅读。“费力”只用于已经想起的答案，忘记时选“忘记”。

计时只在学习页可见、应用前台且未手动暂停时进行。离开学习页、锁屏、进入后台或本轮结束时停止；每 15 秒、提交答案及暂停时保存。做完一轮不会自动算作完成每日时间目标，可以继续下一轮。复习、词语查阅和长文阅读均计入当前学习时间。历史 0.1.0 记录不会补算时间，计时从更新后开始。

在“课程”可查看样章、先查阅讲解，再练习该单元；所有阶段可浏览。“资料”搜索的是已随应用提供的课程内容，不包含完整外部词典。

## iCloud Drive 与备份

1. 在“文件”里创建一个专用的 iCloud Drive 文件夹。
2. 在每台设备的“设置 → iCloud Drive 同步”选择同一个文件夹。
3. 两台设备分别完成练习，再点“现在同步”；等待系统上传下载后，另一台再同步。

本地 Core Data 数据库始终保留在应用容器内；同步文件是带 SHA-256 校验的不可变事件批次。重入前台、每完成 5 项练习以及结束安排时尝试交换。界面显示文件夹交换状态，不把本地写入成功等同于另一台已经收到。iCloud 下载延迟时可稍后再次同步。

此方案不使用应用专属 CloudKit 容器，也不使用 Aidoku 的容器或签名身份。TrollStore 下的目录授权、系统语音和跨设备 iCloud 传输仍需按 [真机验收清单](docs/DEVICE_TESTS.md) 验证。

0.2.0 的备份与同步文件升级为事件格式 2，兼容导入格式 1。新增学习时间记录随复习记录一同交换；跨设备重叠时段只累计一次。两台设备均须升级到 0.2.0 或以上，旧版无法读取新格式。

“导出学习备份”生成 `.jplearnbackup` 文件，含复习、课程进度、收藏与笔记；“合并备份”保留已有数据、去重相同事件。课程正文随 IPA 提供，备份记录课程版本。请保留独立备份；同步目录里的事件文件属于同步历史。

## 内容维护

[课程制作说明](docs/CONTENT.md) 包含稳定编号、资料核对、生成与发布流程。[架构说明](docs/ARCHITECTURE.md) 说明学习状态、同步协议及版本兼容规则。

本轮没有加入全文阅读器、OCR、任意文本自动解析或运行时联网 AI。应用无自建业务服务器和分析 SDK。

# GlobalRefresh-PiP 开发实现说明

简体中文 | [English](IMPLEMENTATION_EN.md)

本文以 `1.1.2` 源码为基准，记录默认 VideoCall + 仅 PiP 组合的行为。项目用途、方案对比、安装和版本日志见 [README](../README.md)。

## 1. PiP 内容更新与系统刷新率

**30 fps 是 PiP 内容更新目标，不是显示器刷新率上限。** 默认组合在关闭文字滚动后仍维持 PiP 内容更新。在满足隐藏、收起或锁屏等条件时，只暂停额外的后台刷新驱动，不主动停止 PiP 会话或内容更新。显示刷新率仍由系统独立调度。

帧率演示中的 120 Hz 开关仅控制本 App 的前台刷新请求，关闭时请求最高 80 Hz；它不参与后台 PiP 的内容更新或播放策略。验证系统级效果时，可在同一设备的系统设置页面对比 PiP 开启与关闭时的同一滑动操作。App 内动画和刷新请求值不等同于系统实测帧率。

- ~~用默认 VideoCall 的后台驱动固定请求 120Hz。~~ 当前默认组合保留内容更新，不在后台明确请求 120Hz。
- ~~用持续静音音频作为默认保活。~~ 当前默认仅 PiP；其他音频模式仍保留供选择。

删除线表示旧做法不再用于**当前默认组合**，不表示 Apple 废弃了对应 API。

## 2. 启动、并存与控件

1. **先启动悬浮窗。** iOS 15 的默认组合保留原生 VideoCall 启动，创建时不加入新版控件隐藏处理，也不为了共存预先强写内容类型。
2. **启动成功后才尝试并存。** 识别到支持的系统状态后，首次切换约延后 1 秒。同一会话可以有限检查和补试，不重启 PiP；关闭或替换会话时取消旧任务。
3. **分开维护控件隐藏。** iOS 16 及以上在创建时隐藏控件，启动、高度调整及并存状态写入后按需检查；并存写入后仍需向当前代理补交样式，不能只看外层属性值。私有接口不匹配时，优先保留原生控件和启动行为。
4. **区分挂起与停止。** 系统暂时挂起 PiP 时保留会话等待恢复；确认失活后才清理。

[AVKit 内容源](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class)是公开 API；并存和控件隐藏的内部适配不是。代码里的内容类型（常见为 `4 → 6`）是运行时内部状态，不能当成 Apple 的公开枚举使用。诊断中的「已安排」「实际写入」「本地读回」是三件事，**读回 `6` 不代表系统已确认与其他 PiP 共存**。

兼容备选 PlayerLayer 使用循环视频。生成任务在后台完成，只读取已写入完成的素材；切换方案、停止 PiP 或替换会话时，旧任务不能覆盖当前播放器。

## 3. 兼容与验证

| 检查项 | 怎么测 |
| --- | --- |
| iOS 15 启动 | 真机冷启动，分别验证普通开启和一键开启并隐藏。确认默认组合能启动，不以模拟器或本地回归代替。 |
| iOS 16+ 控件 | 分别测试首次开启、关闭后重开、调整高度，以及共存切换后关闭按钮是否重新出现。 |
| 并存与保活 | 保持当前 PiP 运行，再启动另一个 App 的 PiP。确认双方实际表现；挂起、停止、整进程退出分开记。 |
| 高刷和副作用 | 在同一设备、同一场景做 PiP 开关对照。另测自动熄屏、音视频和切回桌面；不要以 App 内动画或帧率请求代替系统实测。 |
| 覆盖升级 | 从正式 (1.1.1) 覆盖到 (1.1.2)，检查原有设置、最近日志和诊断是否保留，再测一次 PiP 启动。 |

项目最低部署目标为 iOS 15。硬件、系统版本、其他 App 和系统资源都会影响结果，不能把一个机型上的结果推广到所有设备。[iOS 不提供普通 App 永久后台权限](https://developer.apple.com/forums/thread/685525)。排查失活时，最后心跳只代表最后确认时间，不能单独判断是内存、进程终止还是 PiP 停止。

正式构建默认关闭调试模式，仍保留有限的轻量关键日志；开启调试才收集详细性能数据。覆盖升级保留现有退出记录与系统诊断。分享日志前请检查并遮盖个人信息。

## 4. 源码入口

| 文件 | 负责什么 |
| --- | --- |
| [ViewController.swift](../pip_swift/pip_swift/ViewController.swift) | PiP 创建、尺寸和内容更新、生命周期，以及 PlayerLayer 素材接入。 |
| [PiPCoexistenceExperiment.swift](../pip_swift/pip_swift/PiPCoexistenceExperiment.swift) | 默认刷新策略、并存切换、会话限定补试和控件样式维护。 |
| [MainTabBarController.swift](../pip_swift/pip_swift/MainTabBarController.swift) | App 前台刷新驱动及后台驱动切换。 |
| [AppDebugLogger.swift](../pip_swift/pip_swift/AppDebugLogger.swift) / [MetricKitLogger.swift](../pip_swift/pip_swift/MetricKitLogger.swift) | 轻量日志、详细归档与系统诊断。 |

从仓库根目录打开 `pip_swift/pip_swift.xcworkspace`，选择 `pip_swift` scheme。运行真机时使用自己的签名配置。可在装有 Xcode 和命令行工具的 Mac 上执行定向回归：

```bash
bash tests/test_ios15_native_content_refresh.sh
bash tests/test_controls_resubmission.sh
bash tests/test_bounded_coexistence_retry.sh
bash tests/test_page_refresh_isolation.sh
bash tests/test_recent_runtime_logs.sh
```

原始示例：[CaiWanFeng/PiP](https://github.com/CaiWanFeng/PiP)。后续开发与维护：[Yoroin](https://github.com/Yoroin/GlobalRefresh-PiP)。保留原作者与当前项目署名，见 [NOTICE](../NOTICE)。

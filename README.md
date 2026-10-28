# shiyi-translator（拾译）

Flutter 桌面翻译工具，目标平台为 Linux、Windows、macOS。当前版本 0.3.6，优先在 KDE Wayland 上验证。

## 名字的含义

**Shiyi** 是「拾译」的拼音。「拾」是拾起阅读时遇到的词句，「译」是通过翻译理解它们。选中文字、按下快捷键，就能在文字附近查看译文，让阅读自然地继续。

**拾起文字，读懂世界。**

应用及系统菜单显示名称为「拾译 / Shiyi Translator」。内部应用 ID 和数据目录沿用原有标识，更新后可继续使用已有服务配置、密钥和历史记录。

## 第一版功能

- 输入翻译，自动检测原文语言，选择目标语言，复制结果。
- 四种接口：Chat Completions 兼容协议、DeepL、LibreTranslate、百度通用翻译。
- 同一接口可以配置多个实例，多个服务并行返回，单个服务失败不影响其他服务。
- 拖拽服务卡片左侧手柄调整顺序，自动保存；主翻译页和独立弹窗按此顺序展示结果，返回速度不影响位置，编辑服务后也保留顺序。
- 服务管理卡片展示启用状态、接口类型与模型，服务地址仅在编辑表单中显示；编辑表单分组配置，测试与保存操作固定在底部，适配小窗口和深色模式。
- 兼容接口支持 SSE 流式译文，也可关闭流式输出。
- 取消、重试、45 秒超时、内存缓存；新请求不会被旧结果覆盖。
- 本机最近 100 条历史记录，可禁用保存或清空。
- 托盘、关闭后后台驻留、独立翻译弹窗、置顶、深色模式。
- 可选开机自启动，登录后静默驻留托盘，设置开关直接读取和管理系统启动项。
- 快捷键只显示翻译弹窗，主窗口的草稿、页面与窗口尺寸不受影响。
- 弹窗按原文、语言切换、各服务结果排列，支持复制、修改原文、折叠结果。
- 弹窗高度随实际内容调整，译文增长、折叠结果或修改原文后自动适配；超出屏幕可用高度时滚动显示。
- 弹窗关闭或按 Escape 后隐藏；未置顶时失去焦点会隐藏，主进程继续驻留。
- 快捷键翻译选区；读取不到选区时明确标识剪贴板回退。
- 单实例运行；`--selection` / `--clipboard` 可由系统快捷键调用。

这一版不包含 OCR、鼠标划词后自动弹按钮、无焦点弹窗、第三方插件市场或云同步。

## 环境

本项目开发环境：Flutter 3.47.7 / Dart 3.13.5。Dart 随 Flutter 安装。

Manjaro / Arch：

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf gtk3 libsecret libayatana-appindicator wl-clipboard
```

Ubuntu：

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libsecret-1-dev libayatana-appindicator3-dev
```

X11 下取词需要 `xclip`；Wayland 下取词需要 `wl-clipboard`。全局快捷键使用 XDG GlobalShortcuts Portal，发行版需提供相应后端。KDE 使用 `xdg-desktop-portal-kde`。

Windows 构建需要 Windows 和 Visual Studio 的「使用 C++ 的桌面开发」组件。macOS 构建需要 Mac、Xcode 和 Flutter 插件需要的包管理工具。辅助功能取词需要用户在 macOS「隐私与安全性 → 辅助功能」中授权。当前 macOS 版本作为桌面工具禁用了 App Sandbox，不是 Mac App Store 分发配置。

## 运行

```bash
flutter pub get
flutter run -d linux
```

在「翻译服务」中添加服务，填写服务地址、模型（兼容接口）和 API Key。没有预设密钥或自动向公共翻译站发送文本。

添加或编辑服务时，点击「测试连接」即可用当前填写的信息将 `Hello, world!` 从英文翻译为简体中文，显示译文、耗时或失败原因。测试无需保存配置，也不会写入历史；可取消测试，修改信息后旧结果会清除。测试不要求填写显示名称，保存时仍需填写。

在「翻译服务」中按住卡片左侧的拖拽手柄上下移动即可排序。调整后已有译文会同步重排，进行中的翻译继续运行；服务顺序会随配置保存在本机，重启后仍有效。

| 接口 | 服务地址示例 | 说明 |
| --- | --- | --- |
| Chat Completions 兼容 | `https://your-provider.example/v1` | 模型 ID 由服务商提供；自定义网关、提供兼容协议的本地模型服务均可 |
| DeepL Free | `https://api-free.deepl.com` | 需要 DeepL API Free Key |
| DeepL Pro | `https://api.deepl.com` | 需要对应的 Pro Key |
| LibreTranslate | `http://localhost:5000` | 连接自己的实例；按实例要求填写 Key |
| 百度翻译 | `https://fanyi-api.baidu.com` | 填写百度翻译开放平台的 APP ID 和密钥，需开通通用翻译 |

百度通过 POST 表单发送 APP ID、原文、随机 salt 和 MD5 签名。密钥保存在系统钥匙串中，不会作为明文字段发送到接口或进入弹窗通信。日语、韩语、法语、西班牙语会映射到百度语言代码；分段结果按原顺序合并。超过 6000 UTF-8 字节会提示分段，不会截断原文。支持认证、签名、限流和余额等错误提示。

参考：[百度通用翻译官方文档](https://fanyi-api.baidu.com/doc_bd/21)。

地址可以填写基础地址，也可以填写完整的 `/chat/completions`、`/v2/translate`、`/translate`、`/api/trans/vip/translate` 地址。不要在地址中放密钥或查询参数。端点支持由 Dart HttpClient 读取环境代理配置。

API Key 通过系统凭据存储保存：Linux 需要运行中的 Secret Service（例如提供该服务的 KWallet / GNOME Keyring）。保存失败会提示，不会回退到明文文件。没有密钥的本地服务可以留空。

## 开机自启动

在「偏好设置 → 启动与后台」中开启「开机自启动」。默认关闭，只管理当前用户的拾译启动项。开启后下次登录桌面时通过 `--autostart` 启动，主窗口保持隐藏，托盘和快捷翻译可用；托盘不可用时显示主窗口。已有实例运行时，自启动命令不会重复打开窗口或读取选区。

关闭开关会移除拾译的启动项，不影响当前程序运行。开关状态从系统配置读取，不另存一份容易失真的本地布尔值。

- Linux：使用 `$XDG_CONFIG_HOME/autostart/dev.justtranslator.just_translator.desktop`，默认位于 `~/.config/autostart/`，遵循 [XDG 自启动规范](https://specifications.freedesktop.org/autostart/latest/)。
- Windows：使用当前用户的 [Run 注册表项](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)，值名为 `ShiyiTranslator`。
- macOS：使用用户目录下的 [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，文件为 `~/Library/LaunchAgents/dev.justtranslator.justTranslator.autostart.plist`。

自启动测试在临时目录中创建并移除测试项，不会开启开发者机器的真实自启动。Windows、macOS 的原生桥接仍需在对应系统上编译和验证。

## 快捷取词

默认申请 `Ctrl + Alt + Space`（macOS 为 Control + Option + Space）。Linux 由桌面 Portal 绑定，可能出现系统授权/配置窗口，实际快捷键以系统设置为准。

1. 在其他应用中选中文字。
2. 按全局快捷键。
3. 应用先读取选区，再单独展示翻译弹窗。主窗口保持原来的状态。

Linux Wayland 读取 PRIMARY selection；X11 使用 xclip；Windows 使用 UI Automation；macOS 使用 Accessibility API。目标应用和桌面环境决定取词是否可用，没有任意应用都能取词的保证。失败时尝试剪贴板，并在原文底部标注来源；也可先手动复制再调用剪贴板翻译。

若 Portal 快捷键不可用，可以在 KDE 系统设置中添加自定义快捷键，命令为：

```bash
/absolute/path/to/just_translator --selection
/absolute/path/to/just_translator --clipboard
```

再次执行程序会把动作发送给已经运行的实例。内部 IPC 仅绑定本机随机端口并验证随机令牌，不提供公开翻译 API。

Wayland 下置顶、焦点激活由窗口管理器决定，不能保证和 X11 完全一致。翻译弹窗是独立窗口，不会将主界面缩小或带到前台。弹窗会优先在取词时的鼠标位置附近出现，空间不足时向左/向上翻转，并限制在该显示器的可用区域内。

## 构建与安装

```bash
flutter build linux --release
```

程序在 `build/linux/x64/release/bundle/just_translator`。分发时需要携带整个 `bundle` 目录。

可选安装到用户目录并创建应用菜单入口（不会改动系统目录）：

```bash
bash tools/install-linux.sh
```

菜单入口使用的 Desktop ID 与应用 ID 一致，便于桌面 Portal 识别。Windows 和 macOS 工程也已生成并补充了原生快捷键/取词桥接，需分别在对应系统编译验证。

## 数据

`settings.json` 保存在系统应用数据目录中（Linux 通常为 `$XDG_DATA_HOME/dev.justtranslator.just_translator/`，未设置时位于 `~/.local/share/` 下）。包含服务配置、偏好和可选翻译历史，不含 API Key。密钥在系统凭据存储中按服务 ID 分开保存。缓存仅在内存中。

## 验证

```bash
flutter analyze
flutter test
flutter build linux --release
flutter test integration_test/desktop_smoke_test.dart -d linux
```

单元测试使用本机临时 HTTP 服务验证真实请求、百度签名、表单编码、语言映射和流式解析，不使用付费 Key。集成测试使用测试配置和固定测试译文验证界面，截图保存到 `build/screenshots/`，不会调用真实翻译服务。

## 代码

- `lib/models.dart`：服务配置、结果和历史数据。
- `lib/services/translation_service.dart`：四种协议、百度签名、SSE、超时和取消。
- `lib/app_controller.dart`：并发翻译、缓存、历史与状态。
- `lib/services/selection_service.dart`：平台取词与剪贴板回退。
- `lib/services/shortcut_service.dart`：Linux Portal 和原生快捷键桥接。
- `lib/services/instance_service.dart`：单实例与本机命令转发。
- `lib/services/storage_service.dart`：配置原子写入与系统密钥存储。
- `lib/app.dart`、`lib/widgets/`：界面。
- `windows/runner/`、`macos/Runner/`：原生取词与全局快捷键。

## 独立弹窗

快捷键、托盘取词和 `--selection` / `--clipboard` 都只打开翻译弹窗。点击主窗口右上角弹窗按钮可把当前原文送到弹窗。首次冷启动取词时，主窗口也保持隐藏。弹窗右上角的设置按钮才会打开主窗口的翻译服务页面。

弹窗采用独立原生窗口，翻译请求、历史记录与凭据仍由主进程统一管理。通信使用经过令牌验证的本机 IPC；传输状态不包含 API Key 或历史记录。重复取词复用弹窗，退出程序时一并结束弹窗。

相关代码：`lib/popup.dart`（界面和窗口行为）、`lib/services/popup_service.dart`（状态和窗口生命周期）。

## 鼠标附近定位

快捷键触发时先保存鼠标位置和所在显示器的可用区域，再取词和展示弹窗。位置使用逻辑像素，支持负坐标显示器和屏幕边缘翻转。Windows、macOS、X11 使用屏幕插件；KDE Wayland 使用临时 KWin 脚本定位，仅匹配本应用弹窗进程，不会修改其他应用窗口或安装全局窗口规则。脚本在更新定位或退出时卸载，弹窗仍可手动拖动。其他 Wayland 桌面不保证支持程序指定位置，取不到有效位置时保留窗口管理器的默认位置。

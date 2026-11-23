import 'package:flutter/widgets.dart';

import 'models.dart';

// Put English first so systems without a supported language fall back to English.
const interfaceLocales = [Locale('en'), Locale('zh')];

Locale resolveInterfaceLocale(InterfaceLanguage language) =>
    language.locale ??
    basicLocaleListResolution(
      WidgetsBinding.instance.platformDispatcher.locales,
      interfaceLocales,
    );

extension InterfaceText on BuildContext {
  String tr(String text, [Object? value]) =>
      interfaceText(Localizations.localeOf(this), text, value);
}

String interfaceText(Locale locale, String text, [Object? value]) {
  if (locale.languageCode == 'en') text = _english[text] ?? text;
  return value == null ? text : text.replaceFirst('{value}', value.toString());
}

// Service errors arrive as text, including across the popup process boundary.
String localizeNotice(BuildContext context, String text) {
  if (Localizations.localeOf(context).languageCode != 'en') return text;
  final translation = _english[text];
  if (translation != null) return translation;
  final match = _errorCode.firstMatch(text);
  if (match == null) return text;
  final code = match.group(1)!;
  final template = text.replaceFirst(code, '{value}', match.start);
  return _english[template]?.replaceFirst('{value}', code) ?? text;
}

final _errorCode = RegExp(r'（(?:HTTP )?(\d+)）');

// Chinese copy is also used by the services so their messages remain readable in logs.
const _english = <String, String>{
  '翻译': 'Translate',
  '翻译服务': 'Services',
  '历史记录': 'History',
  '偏好设置': 'Settings',
  '关于': 'About',
  '界面语言': 'Interface language',
  '跟随系统': 'Follow system',
  '版本 {value}': 'Version {value}',
  '项目地址': 'Project repository',
  '拾译是一款桌面翻译工具。选中文字并按下快捷键，就能在附近查看译文。': 'Shiyi Translator is a desktop translation app. Select text and press a shortcut to see the translation nearby.',
  '拾起文字，读懂世界。': 'Pick up words. Understand the world.',
  '随选随译': 'Shortcuts',
  '正在连接桌面快捷键…': 'Connecting to desktop shortcuts…',
  '等待系统绑定快捷键…': 'Waiting for the system shortcut…',
  '未绑定 · 可在设置中重试': 'Shortcut unavailable. Retry in Settings.',
  '跨越语言，保持原意。': 'Translate without losing the meaning.',
  '连接你喜欢的服务，让译文多一个视角。': 'Connect your preferred translation services.',
  '让每一次理解，都有迹可循。': 'Review your previous translations.',
  '按你的习惯，调整每一个细节。': 'Customize the app to suit your workflow.',
  '取消置顶': 'Unpin',
  '窗口置顶': 'Pin window',
  '打开翻译弹窗': 'Open translation popup',
  '{value} 个服务已启用': 'Enabled services: {value}',
  '管理服务': 'Manage services',
  '交换语言': 'Swap languages',
  '先选择原文语言，再交换翻译方向。': 'Choose a source language before swapping.',
  '手动输入': 'Typed text',
  '输入文字，开始理解另一种语言…': 'Enter text to translate…',
  '粘贴文字': 'Paste text',
  '清空原文': 'Clear source text',
  '停止': 'Stop',
  '重新翻译': 'Restart',
  '让不同的语言，彼此靠近': 'Ready to translate',
  '添加一个翻译服务，就可以开始了。': 'Add a translation service to get started.',
  '译文将显示在这里。\n多个服务的结果会分别呈现。':
      'Translations appear here.\nEach service has its own result.',
  '添加翻译服务': 'Add translation service',
  '缓存': 'Cached',
  '复制译文': 'Copy translation',
  '正在翻译…': 'Translating…',
  '已停止': 'Stopped',
  '{value} 个服务': 'Services: {value}',
  '{value} 个启用': 'Enabled: {value}',
  '拖动卡片左侧手柄调整顺序，译文将按此排列。': 'Drag the handles on the left to reorder results.',
  '添加服务': 'Add service',
  '连接你的第一个服务': 'Connect your first service',
  '选择接口类型，填入自己的配置，即可开始翻译。':
      'Select an API type and enter its settings to start translating.',
  '兼容接口 · 自定义模型与流式译文': 'Compatible API · Custom models and streaming',
  '专业翻译 · 支持 Free / Pro': 'Translation API · Supports Free and Pro',
  '自由部署 · 连接自己的翻译实例': 'Self-hosted · Connect your own instance',
  '百度翻译 · APP ID 与密钥接入': 'Baidu Translation · Uses an APP ID and secret key',
  '每个接口可添加多个配置，密钥通过系统凭据存储保护。': 'Each API supports multiple configurations. Keys are stored in the system credential store.',
  '兼容接口': 'Compatible API',
  '已配置密钥': 'Key configured',
  '编辑服务': 'Edit service',
  '编辑': 'Edit',
  '删除服务': 'Delete service',
  '拖拽调整顺序': 'Drag to reorder',
  '调整{value}的顺序': 'Reorder {value}',
  '已启用 · 参与并行翻译': 'Enabled · Translates in parallel',
  '已暂停 · 保留当前配置': 'Paused · Configuration retained',
  '停用服务': 'Disable service',
  '启用服务': 'Enable service',
  '最近 {value} 条记录': 'Recent entries: {value}',
  '清空历史': 'Clear history',
  '还没有翻译记录。\n完成的翻译会保存在这里。':
      'No translation history yet.\nCompleted translations will appear here.',
  '外观与窗口': 'Appearance and window',
  '主题模式': 'Theme',
  '可随系统自动切换外观': 'Match your system appearance',
  '浅色': 'Light',
  '深色': 'Dark',
  '启动与后台': 'Startup and background',
  '开机自启动': 'Launch at login',
  '正在更新系统启动设置…': 'Updating system startup settings…',
  '登录后自动启动，默认静默驻留托盘': 'Start quietly in the tray when you sign in',
  '关闭窗口后留在托盘': 'Keep running in the tray after closing',
  '保持快捷翻译可用，可通过托盘菜单退出': 'Keep shortcuts available. Quit from the tray menu.',
  '翻译与记录': 'Translation and history',
  '保存翻译历史': 'Save translation history',
  '仅保存在本机，最多保留最近 100 条': 'Keep up to 100 recent entries on this device',
  '快捷翻译': 'Translation shortcuts',
  '全局快捷键': 'Global shortcut',
  '绑定中…': 'Binding…',
  '重新绑定': 'Bind again',
  '选中文字后按快捷键翻译。若应用无法提供选区，请先复制文字，再使用剪贴板翻译。': 'Select text and press the shortcut. If the selection is unavailable, copy the text and use clipboard translation.',
  '也可在系统设置中，为下面的命令分配快捷键：':
      'You can also assign a shortcut to this command in system settings.',
  '翻译选区': 'Translate selection',
  '翻译剪贴板': 'Translate clipboard',
  '退出应用': 'Quit app',
  '剪贴板': 'Clipboard',
  '剪贴板里还没有文字。': 'The clipboard is empty.',
  '暂时无法读取剪贴板。': 'Could not read the clipboard.',
  '译文已复制': 'Translation copied',
  '删除 {value}？': 'Delete {value}?',
  '将移除这个服务的配置和已保存的 API Key。':
      'This removes the service configuration and its saved API key.',
  '删除未完全完成，请重试或检查系统钥匙串。': 'Could not finish deleting the service. Try again or check your system keychain.',
  '清空历史记录？': 'Clear translation history?',
  '本机保存的翻译历史和内存缓存将被清空。':
      'This clears your local translation history and in-memory cache.',
  '取消': 'Cancel',
  '确定': 'Confirm',
  '置顶弹窗': 'Pin popup',
  '翻译服务设置': 'Translation service settings',
  '关闭弹窗': 'Close popup',
  '选取或输入需要翻译的文字…': 'Select or enter text to translate…',
  '复制原文': 'Copy source text',
  '粘贴原文': 'Paste source text',
  '停止翻译': 'Stop translation',
  '{value} 字符': 'Characters: {value}',
  '添加翻译服务后，即可在这里查看译文。': 'Add a translation service to see results here.',
  '选中文字后按快捷键，或直接输入文字翻译。':
      'Select text and press the shortcut, or type text to translate.',
  '已复制': 'Copied',
  'Chat Completions 兼容接口': 'Chat Completions-compatible API',
  '百度翻译': 'Baidu Translation',
  '自动检测': 'Auto-detect',
  '简体中文': 'Simplified Chinese',
  '英语': 'English',
  '日语': 'Japanese',
  '韩语': 'Korean',
  '法语': 'French',
  '德语': 'German',
  '西班牙语': 'Spanish',
  '俄语': 'Russian',
  '葡萄牙语': 'Portuguese',
  '朗读失败，请检查系统英文语音和音频输出。':
      'Read-aloud failed. Check your system English voice and audio output.',
  '停止朗读': 'Stop reading',
  '朗读英文': 'Read English aloud',
  '音标查询中…': 'Looking up pronunciation…',
  '音标来自在线词典': 'Pronunciation from the online dictionary',
  '音标暂不可用，重试': 'Retry lookup',
  '音标查询仅支持英文单词。': 'Pronunciation lookup supports English words only.',
  '未找到该单词的音标。': 'No pronunciation found for this word.',
  '该单词暂无音标。': 'No pronunciation is available for this word.',
  '音标查询超时，请重试。': 'Pronunciation lookup timed out. Try again.',
  '无法连接音标服务，请检查网络。':
      'Could not reach the pronunciation service. Check your network.',
  '请先安装 espeak-ng 并确认音频输出可用。':
      'Install espeak-ng and check that audio output is available.',
  '当前系统暂不支持朗读。': 'Read-aloud is unavailable on this system.',
  '无法读取已存密钥，请解锁系统钥匙串后重新打开。': 'Could not read the saved key. Unlock your system keychain and reopen the editor.',
  '编辑翻译服务': 'Edit translation service',
  '配置你的接口，让翻译更合心意': 'Set up your translation API',
  '关闭': 'Close',
  '基本信息': 'Basic information',
  '便于在多个服务之间辨认': 'Help identify this service',
  '显示名称': 'Display name',
  '例如：我的翻译助手': 'For example, My Translator',
  '请为这个服务取一个名字': 'Enter a name for this service',
  '接口类型': 'API type',
  '连接设置': 'Connection settings',
  '按服务商提供的信息填写': 'Use the details from your provider',
  '服务地址': 'Service URL',
  '请输入 HTTP(S) 地址，不包含密钥或查询参数':
      'Enter an HTTP(S) URL without credentials or query parameters',
  '百度翻译应用 ID': 'Baidu Translation app ID',
  '请填写百度翻译 APP ID': 'Enter your Baidu Translation APP ID',
  '模型名称': 'Model name',
  '填写模型 ID': 'Enter the model ID',
  '请填写模型名称': 'Enter a model name',
  '流式显示译文': 'Stream translation',
  '边生成边显示，不支持时可关闭': 'Show text as it arrives. Turn off if unsupported.',
  '可选': 'Optional',
  '密钥（Secret Key）': 'Secret Key',
  '正在读取密钥…': 'Reading key…',
  '填写服务密钥': 'Enter your secret key',
  '按服务要求填写': 'Enter a key if the service requires one',
  '显示密钥': 'Show key',
  '隐藏密钥': 'Hide key',
  '请填写百度翻译密钥': 'Enter your Baidu Translation secret key',
  'DeepL 需要 API Key': 'DeepL requires an API key',
  '密钥仅保存在本机': 'The key is stored on this device',
  '取消测试': 'Cancel test',
  '测试连接': 'Test connection',
  '正在保存…': 'Saving…',
  '保存服务': 'Save service',
  '正在测试…': 'Testing…',
  '测试成功': 'Test succeeded',
  '测试失败': 'Test failed',
  '连接验证': 'Connection test',
  '{value} 秒': '{value} s',
  '使用 Hello, world! 验证配置，无需先保存。':
      'Test your settings with “Hello, world!” before saving.',
  '测试未完成，请检查服务配置和网络后重试。': 'The test could not finish. Check your configuration and network, then try again.',
  '保存失败。请确认本地目录可写，并且系统钥匙串已解锁。': 'Could not save. Check that the local data folder is writable and the system keychain is unlocked.',
  '原配置文件无法读取，已备份并使用默认设置。': 'The previous settings file could not be read. It was backed up and defaults were loaded.',
  '没有读取到文字。请先选中文字；如果目标应用不支持取词，请复制后再翻译。': 'No text captured. Select text first, or copy it if the source app does not support selection capture.',
  '划词取词': 'Selected text',
  '剪贴板 · 未读取到选区': 'Clipboard · Selection unavailable',
  '打开拾译': 'Open Shiyi Translator',
  '翻译选中文字': 'Translate selected text',
  '退出拾译': 'Quit Shiyi Translator',
  '托盘暂不可用，已保留主窗口。可从偏好设置退出应用。':
      'The system tray is unavailable. You can quit the app from Settings.',
  '无法读取系统启动设置，可尝试重新切换开关':
      'Could not read system startup settings. Try toggling the switch again.',
  '设置失败，请检查系统权限后重试':
      'Could not update the setting. Check system permissions and try again.',
  '无法修改开机自启动设置，请检查系统权限后重试。': 'Could not change launch at login. Check system permissions and try again.',
  '取词失败，请尝试复制文字后使用剪贴板翻译。':
      'Could not capture text. Copy it and use clipboard translation.',
  '部分桌面功能初始化失败，仍可使用输入翻译。': 'Some desktop features could not start. You can still type text to translate.',
  '连接翻译服务失败，请重新打开弹窗。': 'Could not connect to the translation service. Reopen the popup and try again.',
  '无法保存语言设置，请重试。': 'Could not save the language settings. Try again.',
  '连接已断开，请重新打开弹窗。': 'Connection lost. Reopen the popup to reconnect.',
  '无法保存本地配置，请检查目录写入权限。': 'Could not save your settings. Check write permissions for the local data folder.',
  '先输入或选取一段需要翻译的文字。': 'Enter or select text to translate.',
  '单次最多翻译 15,000 个字符，请分段翻译。': 'Each translation supports up to 15,000 characters. Split longer text into smaller sections.',
  '请先添加并启用一个翻译服务。': 'Add and enable a translation service first.',
  '无法读取密钥，请解锁系统钥匙串后重试。':
      'Could not read your key. Unlock the system keychain and try again.',
  '翻译失败，请检查服务配置后重试。':
      'Translation failed. Check your service settings and try again.',
  '服务地址需要是有效的 HTTP(S) URL，不能包含密钥或查询参数。': 'The service URL must be a valid HTTP(S) address without credentials or query parameters.',
  '请在服务设置中填写模型名称。': 'Enter a model name in your service settings.',
  '请在服务设置中填写 DeepL API Key。': 'Enter your DeepL API key in service settings.',
  '请在服务设置中填写百度翻译 APP ID 和密钥。':
      'Enter your Baidu Translation APP ID and secret key in service settings.',
  '百度单次翻译最多支持 6000 字节，请缩短原文或分段翻译。': 'Baidu supports up to 6,000 bytes per request. Shorten the text or split it into smaller sections.',
  '认证失败，请检查 API Key 和服务权限。':
      'Authentication failed. Check the API key and service permissions.',
  '接口不存在，请检查服务地址和模型。': 'Endpoint not found. Check the service URL and model.',
  '请求过于频繁或额度不足，请稍后重试。':
      'Too many requests or insufficient quota. Try again later.',
  'DeepL 翻译额度已用完。': 'Your DeepL translation quota has been used up.',
  '服务暂时不可用（HTTP {value}）。':
      'The service is temporarily unavailable (HTTP {value}).',
  '翻译请求失败（HTTP {value}），请检查服务配置。':
      'Translation request failed (HTTP {value}). Check your service settings.',
  '请求超时，请检查网络或更换服务。':
      'The request timed out. Check your network or try another service.',
  '服务返回了空结果，请检查模型是否支持此接口。': 'The service returned an empty result. Check whether the model supports this API.',
  '无法连接服务，请检查网络、代理和服务地址。':
      'Could not reach the service. Check the network, proxy, and service URL.',
  '无法解析服务响应，请确认选择的接口类型正确。': 'Could not read the service response. Check that the API type is correct.',
  '百度翻译请求超时，请稍后重试。': 'Baidu Translation timed out. Try again later.',
  '百度翻译认证或签名失败，请检查 APP ID 和密钥。': 'Baidu Translation authentication failed. Check the APP ID and secret key.',
  '百度翻译调用频率受限，请稍后重试。': 'Baidu Translation rate limit reached. Try again later.',
  '百度翻译账户余额不足，请检查账户额度。':
      'Your Baidu Translation account balance is too low. Check your quota.',
  '百度长文本请求频率受限，请稍后重试。':
      'Baidu Translation rate limit for long text reached. Try again later.',
  '百度翻译暂不支持此语言方向。': 'Baidu Translation does not support this language pair.',
  '请在百度翻译开放平台开通通用翻译并完成认证。': 'Enable General Translation and complete verification on the Baidu Translation Open Platform.',
  '百度翻译返回错误（{value}），请检查服务配置。':
      'Baidu Translation returned error {value}. Check your service settings.',
  '服务在生成过程中返回错误，请检查模型和额度。': 'The service returned an error while generating the translation. Check the model and quota.',
  '请在系统设置 → 隐私与安全性 → 辅助功能中允许拾译（Shiyi Translator）取词。': 'Allow Shiyi Translator to capture selections in System Settings → Privacy & Security → Accessibility.',
  '无法启动拾译。\n请检查应用数据目录权限，或稍后重试。\n错误类型：{value}': 'Could not start Shiyi Translator.\nCheck permissions for the app data folder or try again later.\nError type: {value}',
  '拾译 · 翻译': 'Shiyi Translator · Translate',
};

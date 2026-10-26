import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'models.dart';
import 'services/desktop_service.dart';
import 'widgets/provider_dialog.dart';

const accent = Color(0xFF6655D9);

class TranslatorApp extends StatelessWidget {
  const TranslatorApp({super.key, required this.controller, this.desktop});
  final AppController controller;
  final DesktopService? desktop;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'Just Translator',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: controller.settings.darkMode
          ? ThemeMode.dark
          : ThemeMode.light,
      home: HomePage(controller: controller, desktop: desktop),
    ),
  );
  static ThemeData buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xFF17181F)
          : const Color(0xFFF6F7FB),
      fontFamilyFallback: const [
        'Noto Sans CJK SC',
        'Microsoft YaHei',
        'PingFang SC',
      ],
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: dark ? const Color(0xFFE7E8F2) : const Color(0xFF262735),
        displayColor: dark ? const Color(0xFFE7E8F2) : const Color(0xFF262735),
      ),
      dividerColor: dark ? const Color(0xFF353641) : const Color(0xFFECECF3),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF252630) : const Color(0xFFF7F8FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 450),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller, this.desktop});
  final AppController controller;
  final DesktopService? desktop;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextEditingController _input;
  AppController get app => widget.controller;
  static const _titles = ['翻译', '翻译服务', '历史记录', '偏好设置'];
  static const _icons = [
    Icons.translate_rounded,
    Icons.widgets_outlined,
    Icons.history_rounded,
    Icons.tune_rounded,
  ];
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: app.input);
    app.addListener(_syncInput);
    widget.desktop?.addListener(_desktopChanged);
  }

  void _syncInput() {
    if (_input.text != app.input) {
      _input.value = TextEditingValue(
        text: app.input,
        selection: TextSelection.collapsed(offset: app.input.length),
      );
    }
  }

  void _desktopChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    app.removeListener(_syncInput);
    widget.desktop?.removeListener(_desktopChanged);
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
          unawaited(app.translate()),
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
          unawaited(app.translate()),
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (app.busy) app.cancel();
      },
    },
    child: Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 900;
          return Row(
            children: [
              if (!narrow) _sidebar(),
              Expanded(
                child: Column(
                  children: [
                    _header(narrow),
                    if (narrow) _navigationBar(),
                    if (app.notice != null) _notice(),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          narrow ? 20 : 32,
                          8,
                          narrow ? 20 : 32,
                          24,
                        ),
                        child: switch (app.page) {
                          0 => _translator(),
                          1 => _providers(),
                          2 => _history(),
                          _ => _settings(),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _sidebar() => Container(
    width: 210,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            BrandMark(size: 38),
            SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Just\nTranslator',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 42),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: app.page == i
                  ? accent.withValues(alpha: .10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => app.goTo(i),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _icons[i],
                        size: 20,
                        color: app.page == i ? accent : Colors.grey,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _titles[i],
                        style: TextStyle(
                          color: app.page == i ? accent : null,
                          fontWeight: app.page == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.keyboard_command_key_rounded,
                    size: 15,
                    color: accent,
                  ),
                  SizedBox(width: 7),
                  Text(
                    '随选随译',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.desktop?.shortcutStatus ?? 'Ctrl + Alt + Space',
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '  少一点隔阂，多一点理解。',
          style: TextStyle(fontSize: 10, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        const Text(
          '  VERSION 0.3.1',
          style: TextStyle(fontSize: 9, color: Colors.grey, letterSpacing: 1.8),
        ),
      ],
    ),
  );

  Widget _header(bool narrow) => Padding(
    padding: EdgeInsets.fromLTRB(narrow ? 20 : 32, 26, narrow ? 20 : 32, 22),
    child: Row(
      children: [
        if (narrow) ...[const BrandMark(size: 32), const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _titles[app.page],
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  '跨越语言，保持原意。',
                  '连接你喜欢的服务，让译文多一个视角。',
                  '让每一次理解，都有迹可循。',
                  '按你的习惯，调整每一个细节。',
                ][app.page],
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        if (widget.desktop != null) ...[
          IconButton(
            tooltip: widget.desktop!.pinned ? '取消置顶' : '窗口置顶',
            onPressed: () => widget.desktop!.togglePinned(),
            icon: Icon(
              widget.desktop!.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 19,
              color: widget.desktop!.pinned ? accent : null,
            ),
          ),
          IconButton(
            tooltip: '打开翻译弹窗',
            onPressed: () => widget.desktop!.openPopup(),
            icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 20),
          ),
        ],
      ],
    ),
  );

  Widget _navigationBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Row(
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: TextButton.icon(
              onPressed: () => app.goTo(i),
              icon: Icon(_icons[i], size: 17),
              label: Text(_titles[i], style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: app.page == i ? accent : Colors.grey,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _notice() => Container(
    margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(app.notice!, style: const TextStyle(fontSize: 12)),
        ),
        IconButton(
          onPressed: app.clearMessage,
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );

  Widget _translator() => LayoutBuilder(
    builder: (context, constraints) {
      final vertical = constraints.maxWidth < 750;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: app.enabledProviders.isEmpty
                        ? Colors.grey
                        : const Color(0xFF37A584),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${app.enabledProviders.length} 个服务已启用',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () => app.goTo(1),
                  child: const Text('管理服务', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: vertical
                ? Column(
                    children: [
                      SizedBox(
                        height: constraints.maxHeight < 620 ? 225 : 280,
                        child: _sourceCard(true),
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: _resultPane()),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 10, child: _sourceCard(false)),
                      const SizedBox(width: 22),
                      Expanded(flex: 11, child: _resultPane()),
                    ],
                  ),
          ),
        ],
      );
    },
  );

  Widget _sourceCard(bool compact) => Surface(
    child: Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            compact ? 4 : 10,
            10,
            compact ? 4 : 10,
          ),
          child: Row(
            children: [
              Expanded(child: _languageDropdown(app.settings.source, true)),
              IconButton(
                tooltip: '交换语言',
                onPressed: () {
                  if (app.settings.source == 'auto') {
                    app.message('先选择原文语言，再交换翻译方向。');
                    return;
                  }
                  final previous = app.settings.source;
                  app.settings.source = app.settings.target;
                  app.settings.target = previous;
                  app.settingsChanged();
                  unawaited(app.persist());
                },
                icon: const Icon(
                  Icons.swap_horiz_rounded,
                  size: 20,
                  color: accent,
                ),
              ),
              Expanded(child: _languageDropdown(app.settings.target, false)),
            ],
          ),
        ),
        Divider(height: 1, color: Theme.of(context).dividerColor),
        Expanded(
          child: TextField(
            key: const Key('source-input'),
            controller: _input,
            onChanged: (value) => app.setInput(value, from: '手动输入'),
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(fontSize: compact ? 14 : 17, height: 1.85),
            decoration: InputDecoration(
              hintText: '输入文字，开始理解另一种语言…',
              hintStyle: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9B9CAE),
              ),
              fillColor: Colors.transparent,
              contentPadding: EdgeInsets.symmetric(
                horizontal: compact ? 18 : 22,
                vertical: compact ? 10 : 22,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 12, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: '粘贴文字',
                visualDensity: compact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                onPressed: _paste,
                icon: const Icon(
                  Icons.content_paste_rounded,
                  size: 18,
                  color: Colors.grey,
                ),
              ),
              IconButton(
                tooltip: '清空原文',
                visualDensity: compact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                onPressed: () {
                  app.cancel();
                  app.setInput('');
                },
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 19,
                  color: Colors.grey,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  app.captureLabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${app.input.length} / 15000',
                style: TextStyle(
                  fontSize: 10,
                  color: app.input.length > 15000 ? Colors.red : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(18, 2, 18, 12)
              : const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            children: [
              if (!compact)
                const Expanded(
                  child: Text(
                    '⌘ / Ctrl + Enter',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              if (app.busy)
                TextButton(onPressed: app.cancel, child: const Text('停止')),
              if (compact) const Spacer(),
              FilledButton.icon(
                key: const Key('translate-button'),
                style: compact
                    ? FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      )
                    : null,
                onPressed: () => app.translate(),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: Text(app.busy ? '重新翻译' : '翻译'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _languageDropdown(String value, bool source) =>
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: languages.entries
              .where((l) => source || l.key != 'auto')
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (language) {
            if (language == null) return;
            if (source) {
              app.settings.source = language;
            } else {
              app.settings.target = language;
            }
            app.settingsChanged();
            unawaited(app.persist());
          },
        ),
      );

  Widget _resultPane() {
    if (app.results.isEmpty) {
      return Surface(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    size: 34,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '让不同的语言，彼此靠近',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  app.enabledProviders.isEmpty
                      ? '添加一个翻译服务，就可以开始了。'
                      : '译文将显示在这里。\n多个服务的结果会分别呈现。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.8,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 22),
                if (app.enabledProviders.isEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _editProvider(),
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('添加翻译服务'),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: app.results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _resultCard(app.results[index]),
    );
  }

  Widget _resultCard(TranslationResult result) => Surface(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProviderIcon(kind: result.provider.kind, size: 32),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  result.provider.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (result.status == ResultStatus.loading)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (result.status == ResultStatus.complete)
                Text(
                  result.cached
                      ? '缓存'
                      : '${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '复制译文',
                onPressed: result.text.isEmpty
                    ? null
                    : () => _copy(result.text),
                icon: const Icon(Icons.copy_rounded, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (result.text.isNotEmpty)
            SelectableText(
              result.text,
              style: const TextStyle(fontSize: 16, height: 1.9),
            ),
          if (result.status == ResultStatus.loading && result.text.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Text(
                '正在翻译…',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          if (result.error != null)
            Text(
              result.error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
                height: 1.7,
              ),
            ),
          if (result.status == ResultStatus.cancelled)
            const Text(
              '已停止',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
    ),
  );

  Widget _providers() => ListView(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '${app.settings.providers.length} 个已连接的服务',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _editProvider(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加服务'),
          ),
        ],
      ),
      const SizedBox(height: 22),
      if (app.settings.providers.isEmpty)
        Surface(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择你的第一个翻译服务',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  '使用自己的接口，控制模型、费用和翻译风格。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                for (final kind in ProviderKind.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: ProviderIcon(kind: kind),
                      title: Text(
                        kind.label,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        switch (kind) {
                          ProviderKind.compatible => '自定义模型、API 地址，支持流式译文',
                          ProviderKind.deepl => '专业翻译接口，支持 Free / Pro 地址',
                          ProviderKind.libreTranslate =>
                            '连接自托管或其他 LibreTranslate 实例',
                          ProviderKind.baidu => '使用 APP ID 和密钥连接百度通用翻译',
                        },
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                      ),
                      onTap: () => _editProvider(kind: kind),
                    ),
                  ),
              ],
            ),
          ),
        ),
      for (final provider in app.settings.providers)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Surface(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ProviderIcon(kind: provider.kind),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${provider.kind.label}${provider.model.isEmpty ? '' : ' · ${provider.model}'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          provider.endpoint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: provider.enabled,
                    onChanged: (enabled) =>
                        app.toggleProvider(provider, enabled),
                  ),
                  IconButton(
                    tooltip: '编辑服务',
                    onPressed: () => _editProvider(provider: provider),
                    icon: const Icon(Icons.edit_outlined, size: 19),
                  ),
                  IconButton(
                    tooltip: '删除服务',
                    onPressed: () => _removeProvider(provider),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      const Text(
        '每个服务可以添加多个配置。API Key 存储在系统钥匙串中。',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
    ],
  );

  Widget _history() => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '最近 ${app.settings.history.length} 条记录',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          TextButton.icon(
            onPressed: app.settings.history.isEmpty ? null : _clearHistory,
            icon: const Icon(Icons.delete_outline, size: 17),
            label: const Text('清空历史'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Expanded(
        child: app.settings.history.isEmpty
            ? const Surface(
                child: Center(
                  child: Text(
                    '还没有翻译记录。\n完成的翻译会保存在这里。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, height: 2),
                  ),
                ),
              )
            : ListView.separated(
                itemCount: app.settings.history.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = app.settings.history[index];
                  return Surface(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => app.restoreHistory(entry),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${languages[entry.source]} → ${languages[entry.target]}',
                                  style: const TextStyle(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _date(entry.createdAt),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              entry.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, height: 1.6),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              entry.translations.values.first,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );

  Widget _settings() => ListView(
    children: [
      _section('外观与窗口', [
        SwitchListTile(
          title: const Text('深色模式', style: TextStyle(fontSize: 14)),
          subtitle: const Text('让夜间阅读更舒适', style: TextStyle(fontSize: 11)),
          value: app.settings.darkMode,
          onChanged: (value) {
            app.settings.darkMode = value;
            app.settingsChanged();
            unawaited(app.persist());
          },
        ),
        SwitchListTile(
          title: const Text('关闭窗口后留在托盘', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '保持快捷翻译可用，可通过托盘菜单退出',
            style: TextStyle(fontSize: 11),
          ),
          value: app.settings.closeToTray,
          onChanged: (value) {
            app.settings.closeToTray = value;
            app.settingsChanged();
            unawaited(app.persist());
          },
        ),
      ]),
      const SizedBox(height: 20),
      _section('翻译与记录', [
        SwitchListTile(
          title: const Text('保存翻译历史', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '仅保存在本机，最多保留最近 100 条',
            style: TextStyle(fontSize: 11),
          ),
          value: app.settings.saveHistory,
          onChanged: (value) {
            app.settings.saveHistory = value;
            app.settingsChanged();
            unawaited(app.persist());
          },
        ),
      ]),
      const SizedBox(height: 20),
      _section('快捷翻译', [
        ListTile(
          title: const Text('全局快捷键', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            widget.desktop?.shortcutStatus ?? 'Ctrl + Alt + Space',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: TextButton(
            onPressed: widget.desktop == null || widget.desktop!.registering
                ? null
                : widget.desktop!.registerShortcut,
            child: Text(widget.desktop?.registering == true ? '绑定中…' : '重新绑定'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Text(
            '选中文字后按快捷键翻译。若应用无法提供选区，请先复制文字，再使用剪贴板翻译。',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.8),
          ),
        ),
        if (Platform.isLinux)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '也可在系统设置中，为下面的命令分配快捷键：',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  '"${Platform.resolvedExecutable}" --selection',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 10,
          children: [
            TextButton.icon(
              onPressed: widget.desktop == null
                  ? null
                  : () => widget.desktop!.capture(),
              icon: const Icon(Icons.highlight_alt, size: 17),
              label: const Text('翻译选区'),
            ),
            TextButton.icon(
              onPressed: widget.desktop == null
                  ? null
                  : () => widget.desktop!.capture(clipboard: true),
              icon: const Icon(Icons.content_paste, size: 17),
              label: const Text('翻译剪贴板'),
            ),
          ],
        ),
      ]),
      const SizedBox(height: 24),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Just Translator 0.3.1 · 为理解而生',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          if (widget.desktop != null)
            TextButton(
              onPressed: widget.desktop!.quit,
              child: const Text('退出应用'),
            ),
        ],
      ),
    ],
  );

  Widget _section(String title, List<Widget> children) => Surface(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
  Future<void> _paste() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboard?.text?.isNotEmpty == true) {
        app.setInput(clipboard!.text!, from: '剪贴板');
      } else {
        app.message('剪贴板里还没有文字。');
      }
    } catch (_) {
      app.message('暂时无法读取剪贴板。');
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('译文已复制'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _editProvider({
    ProviderConfig? provider,
    ProviderKind? kind,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ProviderDialog(
        controller: app,
        provider: provider,
        initialKind: kind,
      ),
    );
  }

  Future<void> _removeProvider(ProviderConfig provider) async {
    if (await _confirm('删除 ${provider.name}？', '将移除这个服务的配置和已保存的 API Key。')) {
      try {
        await app.removeProvider(provider.id);
      } catch (_) {
        app.message('删除未完全完成，请重试或检查系统钥匙串。');
      }
    }
  }

  Future<void> _clearHistory() async {
    if (await _confirm('清空历史记录？', '本机保存的翻译历史和内存缓存将被清空。')) {
      await app.clearHistory();
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ) ??
      false;
  String _date(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class Surface extends StatelessWidget {
  const Surface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    clipBehavior: Clip.antiAlias,
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: Theme.of(context).dividerColor),
    ),
    child: child,
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .3),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF8A7BEA), Color(0xFF6655D9)],
      ),
    ),
    child: Icon(Icons.translate_rounded, color: Colors.white, size: size * .56),
  );
}

class ProviderIcon extends StatelessWidget {
  const ProviderIcon({super.key, required this.kind, this.size = 42});
  final ProviderKind kind;
  final double size;
  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      ProviderKind.compatible => accent,
      ProviderKind.deepl => const Color(0xFF257AAB),
      ProviderKind.libreTranslate => const Color(0xFF2B9D84),
      ProviderKind.baidu => const Color(0xFF3179E9),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Icon(
        switch (kind) {
          ProviderKind.compatible => Icons.auto_awesome_outlined,
          ProviderKind.deepl => Icons.translate_rounded,
          ProviderKind.libreTranslate => Icons.public_rounded,
          ProviderKind.baidu => Icons.g_translate_rounded,
        },
        size: size * .5,
        color: color,
      ),
    );
  }
}

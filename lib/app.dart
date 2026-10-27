import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'app_identity.dart';
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
      title: appTitle,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        fontSize: 21,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      appEnglishName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
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
          '  VERSION $appVersion',
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
    final results = app.orderedResults;
    if (results.isEmpty) {
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
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _resultCard(results[index]),
    );
  }

  Widget _resultCard(TranslationResult result) => Surface(
    key: ValueKey('translation-result-${result.provider.id}'),
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

  Widget _providers() {
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _serviceTag(
                        Icons.layers_outlined,
                        '${app.settings.providers.length} 个服务',
                      ),
                      _serviceTag(
                        Icons.check_circle_outline_rounded,
                        '${app.enabledProviders.length} 个启用',
                        highlighted: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '拖动卡片左侧手柄调整顺序，译文将按此排列。',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () => _editProvider(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('添加服务', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (app.settings.providers.isEmpty)
          Surface(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '连接你的第一个服务',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '选择接口类型，填入自己的配置，即可开始翻译。',
                    style: TextStyle(fontSize: 12, color: muted, height: 1.6),
                  ),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final kind in ProviderKind.values)
                          SizedBox(
                            width: constraints.maxWidth >= 620
                                ? (constraints.maxWidth - 12) / 2
                                : constraints.maxWidth,
                            child: Material(
                              color: colors.surfaceContainerLowest,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _editProvider(kind: kind),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ProviderIcon(kind: kind, size: 34),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              kind == ProviderKind.compatible
                                                  ? 'Chat Completions'
                                                  : kind.label,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              switch (kind) {
                                                ProviderKind.compatible =>
                                                  '兼容接口 · 自定义模型与流式译文',
                                                ProviderKind.deepl =>
                                                  '专业翻译 · 支持 Free / Pro',
                                                ProviderKind.libreTranslate =>
                                                  '自由部署 · 连接自己的翻译实例',
                                                ProviderKind.baidu =>
                                                  '百度翻译 · APP ID 与密钥接入',
                                              },
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: muted,
                                                height: 1.6,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_outward_rounded,
                                        size: 16,
                                        color: muted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    final footer = Column(
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 15, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '每个接口可添加多个配置，密钥通过系统凭据存储保护。',
                style: TextStyle(fontSize: 11, color: muted, height: 1.6),
              ),
            ),
          ],
        ),
      ],
    );
    return ReorderableListView.builder(
      key: const Key('provider-list'),
      header: header,
      footer: footer,
      buildDefaultDragHandles: false,
      itemCount: app.settings.providers.length,
      onReorderItem: (oldIndex, newIndex) =>
          unawaited(app.reorderProviders(oldIndex, newIndex)),
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        color: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
      itemBuilder: (context, index) {
        final provider = app.settings.providers[index];
        return Padding(
          key: ValueKey('provider-card-${provider.id}'),
          padding: const EdgeInsets.only(bottom: 16),
          child: _providerCard(provider, index),
        );
      },
    );
  }

  Widget _serviceTag(IconData icon, String text, {bool highlighted = false}) {
    final colors = Theme.of(context).colorScheme;
    final color = highlighted ? colors.primary : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: highlighted ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerCard(ProviderConfig provider, int index) {
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant;
    final metadata = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _serviceTag(
          Icons.hub_outlined,
          provider.kind == ProviderKind.compatible
              ? '兼容接口'
              : provider.kind.label,
        ),
        if (provider.model.isNotEmpty)
          _serviceTag(Icons.auto_awesome_outlined, provider.model),
        if (provider.hasApiKey)
          _serviceTag(Icons.lock_outline_rounded, '已配置密钥'),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: '编辑服务',
          child: OutlinedButton.icon(
            onPressed: () => _editProvider(provider: provider),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              side: BorderSide(color: Theme.of(context).dividerColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('编辑', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: '删除服务',
          onPressed: () => _removeProvider(provider),
          icon: Icon(Icons.delete_outline_rounded, size: 19, color: muted),
        ),
      ],
    );
    return Surface(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  key: ValueKey('provider-drag-${provider.id}'),
                  index: index,
                  child: Tooltip(
                    message: '拖拽调整顺序',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Semantics(
                        label: '调整${provider.name}的顺序',
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            size: 20,
                            color: muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ProviderIcon(kind: provider.kind, size: 40),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        provider.enabled ? '已启用 · 参与并行翻译' : '已暂停 · 保留当前配置',
                        style: TextStyle(
                          fontSize: 11,
                          color: provider.enabled ? colors.primary : muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: provider.enabled ? '停用服务' : '启用服务',
                  child: Switch(
                    value: provider.enabled,
                    onChanged: (enabled) =>
                        app.toggleProvider(provider, enabled),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 590
                  ? Row(
                      children: [
                        Expanded(child: metadata),
                        const SizedBox(width: 12),
                        actions,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        metadata,
                        const SizedBox(height: 12),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

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
              '$appName $appVersion · $appTagline',
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

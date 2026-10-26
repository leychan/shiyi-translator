import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'app_controller.dart';
import 'models.dart';
import 'popup_placement.dart';
import 'services/popup_service.dart';

class PopupWindow extends ChangeNotifier with WindowListener {
  bool pinned = false;
  bool _disposed = false;
  int _showGeneration = 0;

  Future<void> initialize() async {
    windowManager.addListener(this);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Just Translator · 翻译',
        size: Size(480, 700),
        minimumSize: Size(360, 380),
        center: false,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
        backgroundColor: Colors.transparent,
      ),
      () async {
        await windowManager.setAsFrameless();
        await windowManager.setPreventClose(true);
      },
    );
  }

  Future<void> show({
    PopupAnchor? anchor,
    Future<bool> Function()? preparePosition,
  }) async {
    final generation = ++_showGeneration;
    if (anchor != null) {
      final currentSize = await windowManager.getSize();
      final size = currentSize.width >= 360 && currentSize.height >= 380
          ? currentSize
          : const Size(480, 700);
      final target = popupBoundsNear(anchor, size);
      final compositor = await preparePosition?.call() ?? false;
      if (generation != _showGeneration || _disposed) return;
      if (!compositor) {
        if (target.size != currentSize) {
          await windowManager.setSize(target.size);
        }
        await windowManager.setPosition(target.topLeft);
      }
    }
    if (generation != _showGeneration || _disposed) return;
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> hide() => windowManager.hide();
  Future<void> togglePin() async {
    pinned = !pinned;
    await windowManager.setAlwaysOnTop(pinned);
    notifyListeners();
  }

  @override
  void onWindowClose() {
    unawaited(hide());
  }

  @override
  void onWindowBlur() {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 250), () async {
        if (!_disposed && !pinned && !await windowManager.isFocused()) {
          await hide();
        }
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    windowManager.removeListener(this);
    super.dispose();
  }
}

Future<void> runPopup() async {
  await windowManager.ensureInitialized();
  final remote = RemotePopupController(await PopupConnection.connect());
  final window = PopupWindow();
  remote.onPresent = () => window.show(
    anchor: remote.anchor,
    preparePosition: remote.preparePosition,
  );
  remote.onDisconnected = () async {
    remote.dispose();
    window.dispose();
    exit(0);
  };
  runApp(
    PopupApp(
      controller: remote,
      window: window,
      openSettings: () async {
        await remote.openServiceSettings();
        await window.hide();
      },
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(window.initialize().then((_) => remote.start()));
  });
}

class PopupApp extends StatelessWidget {
  const PopupApp({
    super.key,
    required this.controller,
    this.window,
    this.openSettings,
  });
  final AppController controller;
  final PopupWindow? window;
  final Future<void> Function()? openSettings;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'Just Translator · 翻译',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: TranslatorApp.buildTheme(Brightness.light),
      darkTheme: TranslatorApp.buildTheme(Brightness.dark),
      themeMode: controller.settings.darkMode
          ? ThemeMode.dark
          : ThemeMode.light,
      home: TranslationPopup(
        controller: controller,
        window: window,
        openSettings: openSettings,
      ),
    ),
  );
}

class TranslationPopup extends StatefulWidget {
  const TranslationPopup({
    super.key,
    required this.controller,
    this.window,
    this.openSettings,
  });
  final AppController controller;
  final PopupWindow? window;
  final Future<void> Function()? openSettings;
  @override
  State<TranslationPopup> createState() => _TranslationPopupState();
}

class _TranslationPopupState extends State<TranslationPopup> {
  AppController get app => widget.controller;
  late final TextEditingController _input;
  final _scroll = ScrollController();
  final _collapsed = <String>{};
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: app.input);
    app.addListener(_sync);
    widget.window?.addListener(_windowChanged);
  }

  void _windowChanged() {
    if (mounted) setState(() {});
  }

  void _sync() {
    if (_input.text != app.input) {
      _input.value = TextEditingValue(
        text: app.input,
        selection: TextSelection.collapsed(offset: app.input.length),
      );
    }
  }

  @override
  void dispose() {
    app.removeListener(_sync);
    widget.window?.removeListener(_windowChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Color get _card => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF292B33)
      : const Color(0xFFF0F1F4);
  Color get _bar => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF353741)
      : const Color(0xFFE3E5EA);

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
          unawaited(app.translate()),
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
          unawaited(app.translate()),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          widget.window?.hide(),
    },
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            DragToMoveArea(
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: widget.window?.pinned == true
                            ? '取消置顶'
                            : '置顶弹窗',
                        onPressed: widget.window?.togglePin,
                        icon: Icon(
                          widget.window?.pinned == true
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 18,
                          color: widget.window?.pinned == true
                              ? accent
                              : Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '翻译服务设置',
                        onPressed: widget.openSettings,
                        icon: const Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                      IconButton(
                        key: const Key('popup-close'),
                        tooltip: '关闭弹窗',
                        onPressed: widget.window?.hide,
                        icon: const Icon(
                          Icons.cancel_rounded,
                          size: 22,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                  children: [
                    _source(),
                    const SizedBox(height: 12),
                    _languageBar(),
                    if (app.notice != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                app.notice!,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: app.clearMessage,
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (app.results.isEmpty) _empty(),
                    for (final result in app.results)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _result(result),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _source() => Container(
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        TextField(
          key: const Key('popup-source'),
          controller: _input,
          minLines: 2,
          maxLines: 5,
          onChanged: (value) => app.setInput(value, from: '手动输入'),
          style: const TextStyle(fontSize: 18, height: 1.6),
          decoration: const InputDecoration(
            hintText: '选取或输入需要翻译的文字…',
            hintStyle: TextStyle(fontSize: 15, color: Colors.grey),
            filled: false,
            contentPadding: EdgeInsets.fromLTRB(16, 15, 16, 4),
            border: InputBorder.none,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 10, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: '复制原文',
                onPressed: app.input.isEmpty ? null : () => _copy(app.input),
                icon: const Icon(Icons.copy_outlined, size: 18),
              ),
              IconButton(
                tooltip: '粘贴原文',
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
              ),
              IconButton(
                tooltip: '清空原文',
                onPressed: () {
                  app.cancel();
                  app.setInput('');
                },
                icon: const Icon(Icons.backspace_outlined, size: 18),
              ),
              const Spacer(),
              if (app.busy)
                IconButton(
                  tooltip: '停止翻译',
                  onPressed: app.cancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 20),
                ),
              FilledButton.icon(
                key: const Key('popup-translate'),
                onPressed: () => app.translate(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3578E5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.translate_rounded, size: 16),
                label: Text(app.busy ? '重新翻译' : '翻译'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  app.captureLabel,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
              Text(
                '${app.input.length} 字符',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _languageBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    decoration: BoxDecoration(
      color: _bar,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Expanded(child: _language(true)),
        IconButton(
          tooltip: '交换语言',
          onPressed: () {
            if (app.settings.source == 'auto') {
              app.message('先选择原文语言，再交换翻译方向。');
              return;
            }
            final source = app.settings.source;
            app.settings.source = app.settings.target;
            app.settings.target = source;
            app.settingsChanged();
            unawaited(app.persist());
          },
          icon: const Icon(Icons.swap_horiz_rounded, size: 22),
        ),
        Expanded(child: _language(false)),
      ],
    ),
  );
  Widget _language(bool source) => DropdownButtonHideUnderline(
    child: DropdownButton<String>(
      value: source ? app.settings.source : app.settings.target,
      isExpanded: true,
      isDense: true,
      icon: const Icon(Icons.keyboard_arrow_down, size: 17),
      borderRadius: BorderRadius.circular(12),
      items: languages.entries
          .where((entry) => source || entry.key != 'auto')
          .map(
            (entry) => DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        if (source) {
          app.settings.source = value;
        } else {
          app.settings.target = value;
        }
        app.settingsChanged();
        unawaited(app.persist());
      },
    ),
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      children: [
        const Icon(Icons.translate_rounded, size: 30, color: Colors.grey),
        const SizedBox(height: 16),
        Text(
          app.enabledProviders.isEmpty
              ? '添加翻译服务后，即可在这里查看译文。'
              : '选中文字后按快捷键，或直接输入文字翻译。',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.8, color: Colors.grey),
        ),
        if (app.enabledProviders.isEmpty)
          TextButton(
            onPressed: widget.openSettings,
            child: const Text('添加翻译服务'),
          ),
      ],
    ),
  );

  Widget _result(TranslationResult result) {
    final collapsed = _collapsed.contains(result.provider.id);
    return Material(
      color: _card,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('popup-result-${result.provider.id}'),
            onTap: () => setState(() {
              if (collapsed) {
                _collapsed.remove(result.provider.id);
              } else {
                _collapsed.add(result.provider.id);
              }
            }),
            child: Container(
              color: _bar,
              padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
              child: Row(
                children: [
                  ProviderIcon(kind: result.provider.kind, size: 27),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      result.provider.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
                  const SizedBox(width: 8),
                  Icon(
                    collapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    size: 21,
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.text.isNotEmpty)
                    SelectableText(
                      result.text,
                      style: const TextStyle(fontSize: 18, height: 1.7),
                    ),
                  if (result.error != null)
                    Text(
                      result.error!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (result.status == ResultStatus.loading &&
                      result.text.isEmpty)
                    const Text(
                      '正在翻译…',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  if (result.status == ResultStatus.cancelled)
                    const Text(
                      '已停止',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: '复制译文',
                        onPressed: result.text.isEmpty
                            ? null
                            : () => _copy(result.text),
                        icon: const Icon(Icons.copy_outlined, size: 18),
                      ),
                      const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) app.setInput(data!.text!, from: '剪贴板');
    } catch (_) {
      app.message('暂时无法读取剪贴板。');
    }
  }
}

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../services/translation_service.dart';

class ProviderDialog extends StatefulWidget {
  const ProviderDialog({
    super.key,
    required this.controller,
    this.provider,
    this.initialKind,
  });
  final AppController controller;
  final ProviderConfig? provider;
  final ProviderKind? initialKind;
  @override
  State<ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends State<ProviderDialog> {
  final _form = GlobalKey<FormState>();
  final _formScroll = ScrollController();
  late ProviderKind _kind;
  late final TextEditingController _name;
  late final TextEditingController _endpoint;
  late final TextEditingController _model;
  late final TextEditingController _appId;
  final _apiKey = TextEditingController();
  bool _streaming = true;
  bool _saving = false;
  bool _loading = false;
  bool _keyUnavailable = false;
  bool _obscure = true;
  String? _error;
  CancellationToken? _testToken;
  String? _testTranslation;
  String? _testError;
  Duration? _testElapsed;
  bool _validatingTest = false;

  bool get _testing => _testToken != null;

  void _clearTest() {
    _testToken?.cancel();
    _testToken = null;
    _testTranslation = null;
    _testError = null;
    _testElapsed = null;
  }

  void _configurationChanged(String _) => setState(_clearTest);

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    _kind = provider?.kind ?? widget.initialKind ?? ProviderKind.compatible;
    _name = TextEditingController(text: provider?.name ?? '');
    _endpoint = TextEditingController(
      text: provider?.endpoint ?? _kind.defaultEndpoint,
    );
    _model = TextEditingController(text: provider?.model ?? '');
    _appId = TextEditingController(text: provider?.appId ?? '');
    _streaming = provider?.streaming ?? true;
    if (provider != null && provider.hasApiKey) _loadKey(provider.id);
  }

  Future<void> _loadKey(String id) async {
    _loading = true;
    try {
      final key = await widget.controller.store.readKey(id);
      if (mounted) _apiKey.text = key;
    } catch (_) {
      if (mounted) {
        _error = '无法读取已存密钥，请解锁系统钥匙串后重新打开。';
        _keyUnavailable = true;
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _testToken?.cancel();
    _formScroll.dispose();
    for (final controller in [_name, _endpoint, _model, _apiKey, _appId]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _ink => Theme.of(context).colorScheme.onSurface;
  Color get _muted => _dark ? const Color(0xFFA2A6B8) : const Color(0xFF737B91);
  Color get _line => _dark ? const Color(0xFF373B49) : const Color(0xFFE6E9F1);
  Color get _panel => _dark ? const Color(0xFF242731) : const Color(0xFFF7F8FC);

  IconData get _kindIcon => switch (_kind) {
    ProviderKind.compatible => Icons.auto_awesome_outlined,
    ProviderKind.deepl => Icons.translate_rounded,
    ProviderKind.libreTranslate => Icons.public_rounded,
    ProviderKind.baidu => Icons.language_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: _line),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _dark ? const Color(0xFF1D2029) : Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          hintStyle: TextStyle(
            fontSize: 13,
            color: _muted.withValues(alpha: 0.7),
          ),
          border: fieldBorder,
          enabledBorder: fieldBorder,
          disabledBorder: fieldBorder,
          focusedBorder: fieldBorder.copyWith(
            borderSide: BorderSide(color: primary, width: 1.5),
          ),
          errorBorder: fieldBorder.copyWith(
            borderSide: BorderSide(color: theme.colorScheme.error),
          ),
          focusedErrorBorder: fieldBorder.copyWith(
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5),
          ),
          errorMaxLines: 2,
        ),
      ),
      child: Dialog(
        backgroundColor: _dark ? const Color(0xFF1D2029) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: _line),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.sizeOf(context).height - 48,
          ),
          child: SizedBox(
            width: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 16, 20),
                  child: Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(_kindIcon, color: primary, size: 23),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.provider == null ? '添加翻译服务' : '编辑翻译服务',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '配置你的接口，让翻译更合心意',
                              style: TextStyle(fontSize: 12, color: _muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: _scrollableBody(
                    SingleChildScrollView(
                      controller: _formScroll,
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionHeading('基本信息', '便于在多个服务之间辨认'),
                            const SizedBox(height: 14),
                            _fieldRow(
                              _field(
                                '显示名称',
                                TextFormField(
                                  key: const Key('provider-name'),
                                  controller: _name,
                                  onChanged: _configurationChanged,
                                  enabled: !_saving,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                    hintText: '例如：我的翻译助手',
                                  ),
                                  validator: (value) =>
                                      !_validatingTest &&
                                          (value == null ||
                                              value.trim().isEmpty)
                                      ? '请为这个服务取一个名字'
                                      : null,
                                ),
                              ),
                              _field(
                                '接口类型',
                                DropdownButtonFormField<ProviderKind>(
                                  key: const Key('provider-kind'),
                                  initialValue: _kind,
                                  isExpanded: true,
                                  decoration: const InputDecoration(),
                                  icon: Icon(
                                    widget.provider == null
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.lock_outline_rounded,
                                    size: 17,
                                    color: _muted,
                                  ),
                                  style: TextStyle(fontSize: 13, color: _ink),
                                  items: ProviderKind.values
                                      .map(
                                        (kind) => DropdownMenuItem(
                                          value: kind,
                                          child: Text(
                                            kind.label,
                                            style: TextStyle(color: _ink),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _saving || widget.provider != null
                                      ? null
                                      : (kind) {
                                          if (kind == null) return;
                                          setState(() {
                                            _clearTest();
                                            _kind = kind;
                                            _endpoint.text =
                                                kind.defaultEndpoint;
                                          });
                                        },
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: _panel,
                                border: Border.all(color: _line),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _sectionHeading('连接设置', '按服务商提供的信息填写'),
                                  const SizedBox(height: 14),
                                  _field(
                                    '服务地址',
                                    TextFormField(
                                      key: const Key('provider-endpoint'),
                                      controller: _endpoint,
                                      onChanged: _configurationChanged,
                                      enabled: !_saving,
                                      style: const TextStyle(fontSize: 13),
                                      keyboardType: TextInputType.url,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      decoration: const InputDecoration(
                                        hintText: 'https://example.com/v1',
                                        prefixIcon: Icon(
                                          Icons.link_rounded,
                                          size: 18,
                                        ),
                                      ),
                                      validator: (value) {
                                        final uri = Uri.tryParse(
                                          value?.trim() ?? '',
                                        );
                                        if (uri == null ||
                                            ![
                                              'http',
                                              'https',
                                            ].contains(uri.scheme) ||
                                            uri.host.isEmpty ||
                                            uri.userInfo.isNotEmpty ||
                                            uri.hasQuery ||
                                            uri.hasFragment) {
                                          return '请输入 HTTP(S) 地址，不包含密钥或查询参数';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_kind == ProviderKind.compatible ||
                                      _kind == ProviderKind.baidu)
                                    _fieldRow(
                                      _kind == ProviderKind.baidu
                                          ? _field(
                                              'APP ID',
                                              TextFormField(
                                                key: const Key(
                                                  'provider-app-id',
                                                ),
                                                controller: _appId,
                                                onChanged:
                                                    _configurationChanged,
                                                enabled: !_saving,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: '百度翻译应用 ID',
                                                    ),
                                                validator: (value) =>
                                                    value == null ||
                                                        value.trim().isEmpty
                                                    ? '请填写百度翻译 APP ID'
                                                    : null,
                                              ),
                                            )
                                          : _field(
                                              '模型名称',
                                              TextFormField(
                                                key: const Key(
                                                  'provider-model',
                                                ),
                                                controller: _model,
                                                onChanged:
                                                    _configurationChanged,
                                                enabled: !_saving,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      hintText: '填写模型 ID',
                                                    ),
                                                validator: (value) =>
                                                    value == null ||
                                                        value.trim().isEmpty
                                                    ? '请填写模型名称'
                                                    : null,
                                              ),
                                            ),
                                      _keyField(),
                                    )
                                  else
                                    _keyField(),
                                ],
                              ),
                            ),
                            if (_kind == ProviderKind.compatible) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  10,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: _line),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.bolt_rounded,
                                      size: 21,
                                      color: primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '流式显示译文',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '边生成边显示，不支持时可关闭',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: _muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _streaming,
                                      onChanged: _saving
                                          ? null
                                          : (value) => setState(() {
                                              _clearTest();
                                              _streaming = value;
                                            }),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _buildTestResult(context),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.error,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrollableBody(Widget child) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: Scrollbar(
      controller: _formScroll,
      thumbVisibility: true,
      thickness: 4,
      radius: const Radius.circular(4),
      child: child,
    ),
  );

  Widget _sectionHeading(String title, String subtitle) => Wrap(
    spacing: 10,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
      Text(subtitle, style: TextStyle(fontSize: 11, color: _muted)),
    ],
  );

  Widget _field(String label, Widget input, {bool optional = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _ink,
              ),
            ),
            if (optional) ...[
              const SizedBox(width: 6),
              Text('可选', style: TextStyle(fontSize: 10, color: _muted)),
            ],
          ],
        ),
      ),
      Semantics(label: label, child: input),
    ],
  );

  Widget _fieldRow(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 520
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 16),
              Expanded(child: second),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 16), second],
          ),
  );

  Widget _keyField() => _field(
    _kind == ProviderKind.baidu ? '密钥（Secret Key）' : 'API Key',
    TextFormField(
      key: const Key('provider-api-key'),
      controller: _apiKey,
      onChanged: _configurationChanged,
      obscureText: _obscure,
      enabled: !_saving && !_loading,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: _loading
            ? '正在读取密钥…'
            : _kind == ProviderKind.baidu || _kind == ProviderKind.deepl
            ? '填写服务密钥'
            : '按服务要求填写',
        suffixIcon: IconButton(
          tooltip: _obscure ? '显示密钥' : '隐藏密钥',
          onPressed: () => setState(() {
            _obscure = !_obscure;
          }),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 18,
            color: _muted,
          ),
        ),
      ),
      validator: (value) =>
          (_kind == ProviderKind.deepl || _kind == ProviderKind.baidu) &&
              (value?.trim().isEmpty ?? true)
          ? (_kind == ProviderKind.baidu ? '请填写百度翻译密钥' : 'DeepL 需要 API Key')
          : null,
    ),
    optional:
        _kind == ProviderKind.compatible ||
        _kind == ProviderKind.libreTranslate,
  );

  Widget _footer() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: _line)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (constraints.maxWidth >= 600)
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 15, color: _muted),
                  const SizedBox(width: 6),
                  Text(
                    '密钥仅保存在本机',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
            )
          else
            const Spacer(),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _saving || _loading || _keyUnavailable
                ? null
                : _testService,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              side: BorderSide(color: _line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: Icon(
              _testing ? Icons.stop_rounded : Icons.network_check_rounded,
              size: 17,
            ),
            label: Text(
              _testing ? '取消测试' : '测试连接',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            key: const Key('provider-save'),
            onPressed: _saving || _loading || _keyUnavailable || _testing
                ? null
                : _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.check_rounded, size: 17),
            label: Text(
              _saving ? '正在保存…' : '保存服务',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildTestResult(BuildContext context) {
    final hasResult = _testTranslation != null || _testError != null;
    final success = _testTranslation != null;
    final color = _testError != null
        ? Theme.of(context).colorScheme.error
        : success
        ? (_dark ? const Color(0xFF76DBB5) : const Color(0xFF188260))
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasResult || _testing ? color.withValues(alpha: 0.06) : _panel,
        border: Border.all(
          color: hasResult ? color.withValues(alpha: 0.18) : _line,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_testing)
                SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(
                  hasResult
                      ? success
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded
                      : Icons.network_check_rounded,
                  size: 19,
                  color: color,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _testing
                      ? '正在测试…'
                      : hasResult
                      ? success
                            ? '测试成功'
                            : '测试失败'
                      : '连接验证',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: hasResult || _testing ? color : _ink,
                  ),
                ),
              ),
              if (_testElapsed != null)
                Text(
                  '${(_testElapsed!.inMilliseconds / 1000).toStringAsFixed(1)} 秒',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
            ],
          ),
          const SizedBox(height: 7),
          if (hasResult && !_testing)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 100),
              child: SingleChildScrollView(
                child: SelectableText(
                  _testError ?? _testTranslation!,
                  style: TextStyle(fontSize: 12, height: 1.6, color: _ink),
                ),
              ),
            )
          else
            Text(
              '使用 Hello, world! 验证配置，无需先保存。',
              style: TextStyle(fontSize: 11, color: _muted, height: 1.6),
            ),
        ],
      ),
    );
  }

  ProviderConfig _currentConfig() => ProviderConfig(
    id: widget.provider?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
    name: _name.text.trim().isEmpty ? _kind.label : _name.text.trim(),
    kind: _kind,
    endpoint: _endpoint.text.trim(),
    model: _model.text.trim(),
    appId: _appId.text.trim(),
    enabled: widget.provider?.enabled ?? true,
    streaming: _streaming,
  );

  Future<void> _testService() async {
    if (_testing) {
      setState(_clearTest);
      return;
    }
    _validatingTest = true;
    final valid = _form.currentState!.validate();
    _validatingTest = false;
    if (!valid) return;
    final token = CancellationToken();
    final stopwatch = Stopwatch()..start();
    setState(() {
      _clearTest();
      _error = null;
      _testToken = token;
    });
    try {
      final translation = await widget.controller.translator.translate(
        TranslationRequest(
          provider: _currentConfig(),
          text: 'Hello, world!',
          source: 'en',
          target: 'zh',
          apiKey: _apiKey.text.trim(),
        ),
        token,
      );
      if (!mounted || _testToken != token) return;
      setState(() {
        _testTranslation = translation;
      });
    } on TranslationCancelled {
      // Cancellation clears the result before aborting the request.
    } catch (error) {
      if (!mounted || _testToken != token) return;
      setState(() {
        _testError = error is TranslationFailure
            ? error.message
            : '测试未完成，请检查服务配置和网络后重试。';
      });
    } finally {
      stopwatch.stop();
      if (mounted && _testToken == token) {
        setState(() {
          _testElapsed = stopwatch.elapsed;
          _testToken = null;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveProvider(
        _currentConfig(),
        _apiKey.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '保存失败。请确认本地目录可写，并且系统钥匙串已解锁。';
          _saving = false;
        });
      }
    }
  }
}

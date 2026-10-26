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
    for (final controller in [_name, _endpoint, _model, _apiKey, _appId]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.provider == null ? '添加翻译服务' : '编辑翻译服务',
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '连接你的服务，译文将在翻译页单独展示。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 22),
              DropdownButtonFormField<ProviderKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: '接口类型'),
                items: ProviderKind.values
                    .map(
                      (kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(
                          kind.label,
                          style: const TextStyle(fontSize: 13),
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
                          _endpoint.text = kind.defaultEndpoint;
                        });
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                onChanged: _configurationChanged,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: '显示名称',
                  hintText: '例如：我的翻译助手',
                ),
                validator: (value) =>
                    !_validatingTest && (value == null || value.trim().isEmpty)
                    ? '请为这个服务取一个名字'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _endpoint,
                onChanged: _configurationChanged,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: '服务地址',
                  hintText: 'https://example.com/v1',
                ),
                validator: (value) {
                  final uri = Uri.tryParse(value?.trim() ?? '');
                  if (uri == null ||
                      !['http', 'https'].contains(uri.scheme) ||
                      uri.host.isEmpty ||
                      uri.userInfo.isNotEmpty ||
                      uri.hasQuery ||
                      uri.hasFragment) {
                    return '请输入 HTTP(S) 地址，不包含密钥或查询参数';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_kind == ProviderKind.compatible) ...[
                TextFormField(
                  controller: _model,
                  onChanged: _configurationChanged,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: '模型名称',
                    hintText: '填写服务商提供的模型 ID',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写模型名称' : null,
                ),
                const SizedBox(height: 16),
              ],
              if (_kind == ProviderKind.baidu) ...[
                TextFormField(
                  controller: _appId,
                  onChanged: _configurationChanged,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'APP ID',
                    hintText: '百度翻译开放平台的应用 ID',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '请填写百度翻译 APP ID'
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _apiKey,
                onChanged: _configurationChanged,
                obscureText: _obscure,
                enabled: !_saving && !_loading,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _kind == ProviderKind.baidu
                      ? '密钥（Secret Key）'
                      : _kind == ProviderKind.deepl
                      ? 'API Key'
                      : 'API Key（按服务要求填写）',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? '显示密钥' : '隐藏密钥',
                    onPressed: () => setState(() {
                      _obscure = !_obscure;
                    }),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                    ),
                  ),
                ),
                validator: (value) =>
                    (_kind == ProviderKind.deepl ||
                            _kind == ProviderKind.baidu) &&
                        (value?.trim().isEmpty ?? true)
                    ? (_kind == ProviderKind.baidu
                          ? '请填写百度翻译密钥'
                          : 'DeepL 需要 API Key')
                    : null,
              ),
              if (_kind == ProviderKind.compatible)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('流式显示译文', style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                    '服务不支持流式响应时可以关闭',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _streaming,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _clearTest();
                          _streaming = value;
                        }),
                ),
              const SizedBox(height: 12),
              const Text(
                '密钥仅存入系统钥匙串。支持同一类型添加多个服务配置。',
                style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.8),
              ),
              const SizedBox(height: 8),
              const Text(
                '测试连接会使用当前填写的信息，将 Hello, world! 从英文翻译为简体中文。无需先保存。',
                style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.8),
              ),
              if (_testing || _testTranslation != null || _testError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildTestResult(context),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                      height: 1.7,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      OutlinedButton.icon(
        onPressed: _saving || _loading || _keyUnavailable ? null : _testService,
        icon: Icon(
          _testing ? Icons.stop_rounded : Icons.network_check_rounded,
          size: 18,
        ),
        label: Text(_testing ? '取消测试' : '测试连接'),
      ),
      FilledButton(
        onPressed: _saving || _loading || _keyUnavailable || _testing
            ? null
            : _save,
        child: Text(_saving ? '正在保存…' : '保存服务'),
      ),
    ],
  );

  Widget _buildTestResult(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = _testError == null ? colors.primary : colors.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_testing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  _testError == null
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 18,
                  color: color,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _testing
                      ? '正在测试…'
                      : _testError == null
                      ? '测试成功'
                      : '测试失败',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
              if (_testElapsed != null)
                Text(
                  '${(_testElapsed!.inMilliseconds / 1000).toStringAsFixed(1)} 秒',
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ),
          if (!_testing) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: SelectableText(
                  _testError ?? _testTranslation!,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
              ),
            ),
          ],
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

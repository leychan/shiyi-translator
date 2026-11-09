import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/pronunciation_service.dart';

class Pronunciation extends StatefulWidget {
  const Pronunciation({super.key, required this.text, required this.language});
  final String text;
  final String language;

  @override
  State<Pronunciation> createState() => _PronunciationState();
}

class _PronunciationState extends State<Pronunciation> {
  Process? _speech;
  bool _speaking = false;
  bool _loading = false;
  String? _phonetic;
  int _generation = 0;
  int _speechGeneration = 0;

  @override
  void didUpdateWidget(Pronunciation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.language != widget.language) {
      _generation++;
      _speechGeneration++;
      _speech?.kill();
      _speech = null;
      _speaking = false;
      _loading = false;
      _phonetic = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    _speechGeneration++;
    _speech?.kill();
    super.dispose();
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _speak() async {
    if (_speaking) {
      _speechGeneration++;
      _speech?.kill();
      _speech = null;
      setState(() => _speaking = false);
      return;
    }
    final generation = _speechGeneration;
    setState(() => _speaking = true);
    try {
      final process = await PronunciationService.shared.speak(
        widget.text.trim(),
      );
      if (!mounted || generation != _speechGeneration) {
        process.kill();
        return;
      }
      _speech = process;
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      final code = await process.exitCode;
      if (mounted && generation == _speechGeneration && code != 0) {
        _error(Exception('朗读失败，请检查系统英文语音和音频输出。'));
      }
    } catch (error) {
      if (generation == _speechGeneration) _error(error);
    } finally {
      if (mounted && generation == _speechGeneration) {
        setState(() {
          _speaking = false;
          _speech = null;
        });
      }
    }
  }

  Future<void> _lookup() async {
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final value = await PronunciationService.shared.phonetic(widget.text);
      if (mounted && generation == _generation) {
        setState(() => _phonetic = value);
      }
    } catch (error) {
      if (generation == _generation) _error(error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PronunciationService.isEnglish(widget.language, widget.text)) {
      return const SizedBox.shrink();
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: _speaking ? '停止朗读' : '朗读英文',
          onPressed: _speak,
          icon: Icon(
            _speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
            size: 18,
          ),
        ),
        if (PronunciationService.word(widget.text) != null)
          if (_phonetic != null)
            SelectableText(_phonetic!, style: const TextStyle(fontSize: 13))
          else
            TextButton(
              onPressed: _loading ? null : _lookup,
              child: Text(_loading ? '查询中…' : '查询音标（联网）'),
            ),
      ],
    );
  }
}

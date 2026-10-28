import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../app_identity.dart';

/// Registration lives in the OS, so the system remains the source of truth.
class AutostartService {
  AutostartService({
    String? executable,
    Map<String, String>? environment,
    String? operatingSystem,
  }) : _executable = executable ?? Platform.resolvedExecutable,
       _environment = environment ?? Platform.environment,
       _operatingSystem = operatingSystem ?? Platform.operatingSystem;

  static const channel = MethodChannel('dev.justtranslator/desktop');
  static const desktopId = 'dev.justtranslator.just_translator';
  final String _executable;
  final Map<String, String> _environment;
  final String _operatingSystem;

  File get _linuxEntry {
    final configured = _environment['XDG_CONFIG_HOME'];
    final home = _environment['HOME'];
    final String directory;
    if (configured != null && configured.startsWith('/')) {
      directory = configured;
    } else if (home != null && home.startsWith('/')) {
      directory = '$home/.config';
    } else {
      throw const FileSystemException(
        'User configuration directory unavailable',
      );
    }
    return File('$directory/autostart/$desktopId.desktop');
  }

  Future<bool> isEnabled() async {
    if (_operatingSystem == 'linux') {
      final file = _linuxEntry;
      if (!await file.exists()) return false;
      final values = <String, String>{};
      var inEntry = false;
      for (final line in const LineSplitter().convert(
        await file.readAsString(),
      )) {
        final trimmed = line.trim();
        if (trimmed.startsWith('[')) {
          inEntry = trimmed == '[Desktop Entry]';
        } else if (inEntry && !trimmed.startsWith('#')) {
          final separator = trimmed.indexOf('=');
          if (separator > 0) {
            values[trimmed.substring(0, separator).trim()] = trimmed
                .substring(separator + 1)
                .trim();
          }
        }
      }
      return values['Type'] == 'Application' &&
          (values['Exec']?.isNotEmpty ?? false) &&
          values['Hidden'] != 'true' &&
          values['X-GNOME-Autostart-enabled'] != 'false';
    }
    if (_operatingSystem == 'windows' || _operatingSystem == 'macos') {
      return await channel.invokeMethod<bool>('isAutostartEnabled') ?? false;
    }
    throw UnsupportedError('Autostart is only available on desktop');
  }

  Future<void> setEnabled(bool enabled) async {
    if (_operatingSystem == 'linux') {
      final file = _linuxEntry;
      if (!enabled) {
        if (await file.exists()) await file.delete();
        return;
      }
      // GIO checks argv[0] before expanding %% in executable names. An env
      // trampoline keeps literal percent signs in an argument instead.
      final prefix = _executable.contains('%') ? '/usr/bin/env -- ' : '';
      final command =
          '$prefix${_quoteDesktopArgument(_executable)} --autostart';
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      try {
        await temporary.writeAsString('''[Desktop Entry]
Type=Application
Name=$appEnglishName
Name[zh_CN]=$appName
Comment=Start Shiyi Translator in the system tray
Exec=$command
Icon=$desktopId
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
''', flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      return;
    }
    if (_operatingSystem == 'windows' || _operatingSystem == 'macos') {
      await channel.invokeMethod<void>('setAutostartEnabled', {
        'enabled': enabled,
      });
      return;
    }
    throw UnsupportedError('Autostart is only available on desktop');
  }

  String _quoteDesktopArgument(String value) {
    if (!value.startsWith('/') || value.contains(RegExp(r'[\x00-\x1f=]'))) {
      throw const FormatException('Invalid executable path');
    }
    // Exec quoting is decoded after the desktop-file string escape layer.
    var escaped = value.replaceAllMapped(
      RegExp(r'[\\"`$]'),
      (match) => '\\${match[0]}',
    );
    escaped = escaped.replaceAll('\\', '\\\\').replaceAll('%', '%%');
    return '"$escaped"';
  }
}

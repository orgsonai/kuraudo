/// Kuraudo アプリ設定ストア
///
/// OS のキーリング（Linux Secret Service 等）が無い環境でも残す必要がある設定を、
/// OS 標準のアプリ設定フォルダに JSON で保存する。
///   Linux:   ~/.local/share/com.zerotoship.kuraudo/kuraudo_app_config.json
///   Windows: %APPDATA%\com.zerotoship\kuraudo\kuraudo_app_config.json
///   Android: アプリ専用領域
///
/// 平文ファイルのため、PIN や同期の認証情報などの秘密は保存しない。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppConfigStore {
  static const String _fileName = 'kuraudo_app_config.json';
  static const String _kVaultPath = 'vaultPath';
  static const String _kSecurityFallbackAccepted = 'securityFallbackAccepted';
  static const String _kSecuritySettings = 'securitySettings';

  Map<String, dynamic> _data = {};

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  /// 設定ファイルを読み込む。無い・壊れている場合は空として扱う
  Future<void> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) _data = decoded;
    } catch (_) {
      _data = {};
    }
  }

  Future<bool> _save() async {
    try {
      final file = await _file;
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_data));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 最後に開いた Vault のフルパス
  String? get vaultPath {
    final value = _data[_kVaultPath];
    return value is String ? value : null;
  }

  Future<bool> setVaultPath(String path) {
    _data[_kVaultPath] = path;
    return _save();
  }

  /// キーリングが使えない環境で、セキュリティ設定のファイル保存にユーザーが同意したか
  bool get securityFallbackAccepted => _data[_kSecurityFallbackAccepted] == true;

  /// ファイルに保存したセキュリティ設定（同意済みの場合のみ存在）
  Map<String, dynamic> get securitySettings {
    final value = _data[_kSecuritySettings];
    return value is Map<String, dynamic>
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  /// セキュリティ設定を保存する。呼び出し側でユーザーの同意を得てから使うこと
  Future<bool> saveSecuritySettings(Map<String, dynamic> settings) {
    _data[_kSecurityFallbackAccepted] = true;
    _data[_kSecuritySettings] = settings;
    return _save();
  }
}

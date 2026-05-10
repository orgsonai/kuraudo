/// Kuraudo WebDAV 同期バックエンド
///
/// 自前WebDAVサーバー（Nginx/Apache）、Nextcloud、ownCloud、
/// Synology、QNAP等のWebDAV対応ストレージを同期先として扱う。
///
/// 設定:
///   - serverUrl: WebDAVサーバーURL（例: https://nextcloud.example.com/remote.php/dav/files/user/）
///   - username: ユーザー名
///   - password: パスワード（SecureStorageに保存、平文ファイルには書かない）
///   - remotePath: リモート上のパス（デフォルト: /Kuraudo/）
///
/// 認証: HTTP Basic認証
/// 通信: HTTPS推奨（HTTPも技術的には可能だが警告を出す）
library;

import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import 'sync_backend.dart';

/// WebDAV同期バックエンド
class WebDAVBackend implements SyncBackend {
  static const _secureStorage = FlutterSecureStorage();
  // 接続情報のSecureStorageキー
  static const _kServerUrlKey = 'webdav_server_url';
  static const _kUsernameKey = 'webdav_username';
  static const _kPasswordKey = 'webdav_password';
  static const _kRemotePathKey = 'webdav_remote_path';
  static const _kLastSyncTimeKey = 'webdav_last_sync_time';
  static const int _maxBackups = 3;
  static const String _defaultRemotePath = '/Kuraudo/';

  webdav.Client? _client;
  String? _serverUrl;
  String? _username;
  String? _password;
  String _remotePath = _defaultRemotePath;
  String _vaultName = 'Default';
  DateTime? _lastSyncTime;
  SyncStatus _status = SyncStatus.idle;

  // ── SyncBackend インターフェース ──

  @override
  SyncBackendInfo get info => const SyncBackendInfo(
        kind: SyncBackendKind.webdav,
        displayName: 'WebDAV',
        backendId: 'webdav',
        requiresNetwork: true,
      );

  @override
  bool get isReady => _client != null && _serverUrl != null;

  @override
  String? get displayLabel {
    if (_serverUrl == null) return null;
    if (_username == null) return _serverUrl;
    return '$_username@${Uri.tryParse(_serverUrl!)?.host ?? _serverUrl}';
  }

  @override
  SyncStatus get status => _status;

  @override
  DateTime? get lastSyncTime => _lastSyncTime;

  @override
  void setVaultName(String name) {
    _vaultName = name.replaceAll(RegExp(r'[^\w\-]'), '_');
  }

  /// 現在のVault名に対応する同期ファイル名
  String get _fileName => 'kuraudo_$_vaultName.kuraudo';

  /// 現在のVault名に対応するバックアッププレフィックス
  String get _backupPrefix => 'kuraudo_backup_${_vaultName}_';

  /// パス連結（先頭/末尾のスラッシュを正規化）
  String _joinPath(String base, String name) {
    final b = base.endsWith('/') ? base : '$base/';
    final n = name.startsWith('/') ? name.substring(1) : name;
    return '$b$n';
  }

  /// Vaultファイルのリモートパス
  String get _remoteFilePath => _joinPath(_remotePath, _fileName);

  /// バックアップディレクトリのリモートパス
  String get _remoteBackupDir => _joinPath(_remotePath, 'kuraudo_backups/');

  // ── 設定 ──

  /// WebDAV接続情報を設定（永続化される）
  /// 戻り値: 接続テスト結果（true=成功）
  Future<bool> configure({
    required String serverUrl,
    required String username,
    required String password,
    String? remotePath,
  }) async {
    final url = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
    final path = remotePath ?? _defaultRemotePath;

    final client = webdav.newClient(
      url,
      user: username,
      password: password,
      debug: false,
    );

    try {
      // 接続テスト: ping的な操作（リモートパスのreadDirを試す）
      // パスがなければ作成を試みる
      try {
        await client.readDir(path);
      } catch (_) {
        // ディレクトリ未作成の可能性 → mkdir試行
        try {
          await client.mkdirAll(path);
        } catch (e) {
          return false; // 接続失敗
        }
      }

      // 接続成功: 永続化
      _client = client;
      _serverUrl = url;
      _username = username;
      _password = password;
      _remotePath = path;

      await _secureStorage.write(key: _kServerUrlKey, value: url);
      await _secureStorage.write(key: _kUsernameKey, value: username);
      await _secureStorage.write(key: _kPasswordKey, value: password);
      await _secureStorage.write(key: _kRemotePathKey, value: path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 保存された接続情報を読み込む（クライアント生成・接続テストはしない）
  Future<bool> _loadCredentials() async {
    try {
      _serverUrl = await _secureStorage.read(key: _kServerUrlKey);
      _username = await _secureStorage.read(key: _kUsernameKey);
      _password = await _secureStorage.read(key: _kPasswordKey);
      _remotePath = await _secureStorage.read(key: _kRemotePathKey) ?? _defaultRemotePath;
      return _serverUrl != null && _username != null && _password != null;
    } catch (_) {
      return false;
    }
  }

  /// 既存の認証情報で接続を再構築
  Future<bool> _reconnect() async {
    if (!await _loadCredentials()) return false;
    if (_serverUrl == null || _username == null || _password == null) return false;
    try {
      _client = webdav.newClient(
        _serverUrl!,
        user: _username!,
        password: _password!,
        debug: false,
      );
      // 簡易接続テスト
      await _client!.readDir(_remotePath);
      return true;
    } catch (_) {
      _client = null;
      return false;
    }
  }

  // ── 接続管理 ──

  @override
  Future<bool> connect() async {
    // 対話的接続: UIからconfigure()で設定する想定
    // ここでは保存済み認証情報があれば再接続を試みる
    return await _reconnect();
  }

  @override
  Future<bool> silentConnect() async {
    return await _reconnect();
  }

  @override
  Future<void> disconnect() async {
    _client = null;
    _serverUrl = null;
    _username = null;
    _password = null;
    _lastSyncTime = null;
    try {
      await _secureStorage.delete(key: _kServerUrlKey);
      await _secureStorage.delete(key: _kUsernameKey);
      await _secureStorage.delete(key: _kPasswordKey);
      await _secureStorage.delete(key: _kRemotePathKey);
      await _secureStorage.delete(key: _kLastSyncTimeKey);
    } catch (_) {}
    _status = SyncStatus.notSignedIn;
  }

  // ── 基本ファイル操作 ──

  @override
  Future<SyncResult> upload(Uint8List fileBytes) async {
    if (_client == null) {
      return SyncResult(status: SyncStatus.notSignedIn, message: 'WebDAV接続が設定されていません');
    }
    try {
      _status = SyncStatus.syncing;
      // 親ディレクトリ確認
      try {
        await _client!.mkdirAll(_remotePath);
      } catch (_) {
        // 既存の可能性
      }
      await _client!.write(_remoteFilePath, fileBytes);
      _status = SyncStatus.success;
      return SyncResult(
        status: SyncStatus.success,
        message: 'WebDAVにアップロードしました',
        action: SyncAction.uploaded,
        remoteModifiedAt: await getRemoteModifiedTime(),
      );
    } catch (e) {
      _status = SyncStatus.error;
      return SyncResult(status: SyncStatus.error, message: 'アップロード失敗: $e');
    }
  }

  @override
  Future<Uint8List?> download() async {
    if (_client == null) return null;
    try {
      final bytes = await _client!.read(_remoteFilePath);
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DateTime?> getRemoteModifiedTime() async {
    if (_client == null) return null;
    try {
      // readDirで親フォルダを確認し、目当てのファイルのmtimeを取得
      final files = await _client!.readDir(_remotePath);
      for (final f in files) {
        if (f.name == _fileName) {
          return f.mTime;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> deleteRemoteFile() async {
    if (_client == null) return false;
    try {
      await _client!.remove(_remoteFilePath);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── 高レベル操作 ──

  @override
  Future<SyncResult> smartSync({
    required Uint8List localFileBytes,
    required DateTime localModifiedAt,
  }) async {
    if (_client == null) {
      return SyncResult(status: SyncStatus.notSignedIn, message: 'WebDAV接続が設定されていません');
    }

    final remoteModifiedAt = await getRemoteModifiedTime();

    if (remoteModifiedAt == null) {
      return await uploadAndRecord(localFileBytes);
    }

    if (_lastSyncTime == null) {
      if (remoteModifiedAt.isAfter(localModifiedAt)) {
        _lastSyncTime = remoteModifiedAt;
        await _saveLastSyncTime();
        return SyncResult(
          status: SyncStatus.success,
          message: 'リモートが新しいためダウンロードします',
          action: SyncAction.downloaded,
          remoteModifiedAt: remoteModifiedAt,
        );
      } else {
        return await uploadAndRecord(localFileBytes);
      }
    }

    final localChanged = localModifiedAt.isAfter(_lastSyncTime!);
    final remoteChanged = remoteModifiedAt.isAfter(_lastSyncTime!);

    if (!localChanged && !remoteChanged) {
      _status = SyncStatus.success;
      return SyncResult(status: SyncStatus.success, message: '変更なし', action: SyncAction.none);
    }
    if (localChanged && !remoteChanged) {
      return await uploadAndRecord(localFileBytes);
    }
    if (!localChanged && remoteChanged) {
      _lastSyncTime = remoteModifiedAt;
      await _saveLastSyncTime();
      return SyncResult(
        status: SyncStatus.success,
        message: 'リモートからダウンロードします',
        action: SyncAction.downloaded,
        remoteModifiedAt: remoteModifiedAt,
      );
    }
    return SyncResult(
      status: SyncStatus.success,
      message: 'ローカルとリモートの両方に変更があります',
      action: SyncAction.conflict,
      remoteModifiedAt: remoteModifiedAt,
    );
  }

  @override
  Future<SyncResult> uploadAndRecord(Uint8List fileBytes) async {
    final result = await upload(fileBytes);
    if (result.status == SyncStatus.success) {
      _lastSyncTime = DateTime.now();
      await _saveLastSyncTime();
    }
    return result;
  }

  @override
  Future<void> loadLastSyncTime() async {
    try {
      final s = await _secureStorage.read(key: _kLastSyncTimeKey);
      if (s != null) {
        _lastSyncTime = DateTime.tryParse(s);
      }
    } catch (_) {}
  }

  Future<void> _saveLastSyncTime() async {
    if (_lastSyncTime == null) return;
    try {
      await _secureStorage.write(
        key: _kLastSyncTimeKey,
        value: _lastSyncTime!.toIso8601String(),
      );
    } catch (_) {}
  }

  // ── バックアップ ──

  @override
  Future<SyncResult> createBackup(Uint8List fileBytes, {String label = 'manual'}) async {
    if (_client == null) {
      return SyncResult(status: SyncStatus.notSignedIn, message: 'WebDAV接続が設定されていません');
    }
    try {
      // バックアップディレクトリ作成
      try {
        await _client!.mkdirAll(_remoteBackupDir);
      } catch (_) {}

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupName = '$_backupPrefix${label}_$timestamp.kuraudo';
      final backupPath = _joinPath(_remoteBackupDir, backupName);

      await _client!.write(backupPath, fileBytes);
      await _pruneBackups(label);

      return SyncResult(
        status: SyncStatus.success,
        message: 'バックアップを作成しました',
        action: SyncAction.uploaded,
      );
    } catch (e) {
      return SyncResult(status: SyncStatus.error, message: 'バックアップ失敗: $e');
    }
  }

  /// 古いバックアップを削除（ラベル別に最大_maxBackups件保持）
  Future<void> _pruneBackups(String label) async {
    if (_client == null) return;
    try {
      final files = await _client!.readDir(_remoteBackupDir);
      final prefix = '$_backupPrefix${label}_';
      final backups = files
          .where((f) =>
              f.name != null &&
              f.name!.startsWith(prefix) &&
              f.name!.endsWith('.kuraudo'))
          .toList();

      // ファイル名にタイムスタンプが含まれるので降順ソート
      backups.sort((a, b) => (b.name ?? '').compareTo(a.name ?? ''));

      if (backups.length > _maxBackups) {
        for (int i = _maxBackups; i < backups.length; i++) {
          final name = backups[i].name;
          if (name == null) continue;
          try {
            await _client!.remove(_joinPath(_remoteBackupDir, name));
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @override
  Future<List<SyncBackupEntry>> listBackups() async {
    if (_client == null) return [];
    try {
      final files = await _client!.readDir(_remoteBackupDir);
      final prefix = _backupPrefix;
      final backups = files
          .where((f) =>
              f.name != null &&
              f.name!.startsWith(prefix) &&
              f.name!.endsWith('.kuraudo'))
          .toList();

      backups.sort((a, b) => (b.name ?? '').compareTo(a.name ?? ''));

      final result = <SyncBackupEntry>[];
      for (final f in backups) {
        final name = f.name ?? '';
        String? label;
        final m = RegExp(r'kuraudo_backup_.+?_(manual|auto)_').firstMatch(name);
        if (m != null) label = m.group(1);

        result.add(SyncBackupEntry(
          id: _joinPath(_remoteBackupDir, name),  // WebDAVではフルリモートパスをIDに
          name: name,
          modifiedAt: f.mTime,
          sizeBytes: f.size,
          label: label,
        ));
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Uint8List?> downloadBackup(String backupId) async {
    // backupIdはリモートのフルパス
    if (_client == null) return null;
    try {
      final bytes = await _client!.read(backupId);
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }
}

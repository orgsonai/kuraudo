/// Kuraudo ローカルパス同期バックエンド
///
/// 任意のディレクトリ（SMBマウント先、外付けドライブ、Syncthing管理フォルダなど）を
/// 同期先として扱う。dart:ioのみで動作するためネットワーク不要。
///
/// 設定:
///   - syncDirectory: 同期先ディレクトリのフルパス（例: /mnt/smb/kuraudo, Z:\kuraudo）
///
/// プラットフォーム対応:
///   - Linux/Windows/macOS: フルパス指定（任意のマウント済みパス）
///   - Android: getExternalStorageDirectory()配下のパスを推奨（SAF URI非対応）
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_backend.dart';

/// ローカルパス同期バックエンド
class LocalPathBackend implements SyncBackend {
  static const _secureStorage = FlutterSecureStorage();
  static const _kSyncDirKey = 'localpath_sync_dir';
  static const _kLastSyncTimeKey = 'localpath_last_sync_time';
  static const int _maxBackups = 3;

  String? _syncDirectory;
  String _vaultName = 'Default';
  DateTime? _lastSyncTime;
  SyncStatus _status = SyncStatus.idle;

  // ── SyncBackend インターフェース ──

  @override
  SyncBackendInfo get info => const SyncBackendInfo(
        kind: SyncBackendKind.localPath,
        displayName: 'ローカルパス',
        backendId: 'local',
        requiresNetwork: false,
      );

  @override
  bool get isReady => _syncDirectory != null && Directory(_syncDirectory!).existsSync();

  @override
  String? get displayLabel => _syncDirectory;

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

  /// 現在のVault名に対応するバックアップディレクトリ
  String get _backupDirName => 'kuraudo_backups';

  /// 同期ファイルのフルパス
  String? get _syncFilePath {
    if (_syncDirectory == null) return null;
    return '$_syncDirectory${Platform.pathSeparator}$_fileName';
  }

  /// バックアップディレクトリのフルパス
  String? get _backupDirPath {
    if (_syncDirectory == null) return null;
    return '$_syncDirectory${Platform.pathSeparator}$_backupDirName';
  }

  // ── 設定 ──

  /// 同期先ディレクトリを設定（永続化される）
  Future<bool> setSyncDirectory(String path) async {
    final dir = Directory(path);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // 書き込みテスト
      final testFile = File('$path${Platform.pathSeparator}.kuraudo_write_test');
      await testFile.writeAsString('test');
      await testFile.delete();

      _syncDirectory = path;
      await _secureStorage.write(key: _kSyncDirKey, value: path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 保存された同期ディレクトリを読み込む
  Future<String?> _loadSyncDirectory() async {
    try {
      _syncDirectory = await _secureStorage.read(key: _kSyncDirKey);
      return _syncDirectory;
    } catch (_) {
      return null;
    }
  }

  // ── 接続管理（ローカルでは「ディレクトリ設定」が接続相当） ──

  @override
  Future<bool> connect() async {
    // 対話的接続: UIから setSyncDirectory() で別途設定する想定
    // ここでは保存済みパスがあればロードする
    final loaded = await _loadSyncDirectory();
    return loaded != null && Directory(loaded).existsSync();
  }

  @override
  Future<bool> silentConnect() async {
    final loaded = await _loadSyncDirectory();
    return loaded != null && Directory(loaded).existsSync();
  }

  @override
  Future<void> disconnect() async {
    _syncDirectory = null;
    _lastSyncTime = null;
    try {
      await _secureStorage.delete(key: _kSyncDirKey);
      await _secureStorage.delete(key: _kLastSyncTimeKey);
    } catch (_) {}
    _status = SyncStatus.notSignedIn;
  }

  // ── 基本ファイル操作 ──

  @override
  Future<SyncResult> upload(Uint8List fileBytes) async {
    final path = _syncFilePath;
    if (path == null) {
      return SyncResult(status: SyncStatus.notSignedIn, message: '同期ディレクトリが設定されていません');
    }
    try {
      _status = SyncStatus.syncing;
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(fileBytes);
      _status = SyncStatus.success;
      return SyncResult(
        status: SyncStatus.success,
        message: 'ローカルパスに保存しました',
        action: SyncAction.uploaded,
        remoteModifiedAt: await file.lastModified(),
      );
    } catch (e) {
      _status = SyncStatus.error;
      return SyncResult(status: SyncStatus.error, message: '保存に失敗: $e');
    }
  }

  @override
  Future<Uint8List?> download() async {
    final path = _syncFilePath;
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DateTime?> getRemoteModifiedTime() async {
    final path = _syncFilePath;
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.lastModified();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> deleteRemoteFile() async {
    final path = _syncFilePath;
    if (path == null) return false;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
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
    if (_syncDirectory == null) {
      return SyncResult(status: SyncStatus.notSignedIn, message: '同期ディレクトリが設定されていません');
    }

    final remoteModifiedAt = await getRemoteModifiedTime();

    // リモートにファイルがない → アップロード
    if (remoteModifiedAt == null) {
      return await uploadAndRecord(localFileBytes);
    }

    // 前回同期時刻が無い場合（初回）→ 新しい方を採用
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
    // 両方変更 → コンフリクト
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
    final backupDir = _backupDirPath;
    if (backupDir == null) {
      return SyncResult(status: SyncStatus.notSignedIn, message: '同期ディレクトリが設定されていません');
    }
    try {
      final dir = Directory(backupDir);
      await dir.create(recursive: true);

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupName = 'kuraudo_backup_${_vaultName}_${label}_$timestamp.kuraudo';
      final backupPath = '$backupDir${Platform.pathSeparator}$backupName';

      await File(backupPath).writeAsBytes(fileBytes);
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
    final backupDir = _backupDirPath;
    if (backupDir == null) return;
    try {
      final dir = Directory(backupDir);
      if (!await dir.exists()) return;

      final prefix = 'kuraudo_backup_${_vaultName}_${label}_';
      final files = await dir.list().toList();
      final backups = files
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith(prefix) &&
                       f.uri.pathSegments.last.endsWith('.kuraudo'))
          .toList();

      // ファイル名にタイムスタンプが含まれるので、降順ソートで新→旧
      backups.sort((a, b) => b.path.compareTo(a.path));

      if (backups.length > _maxBackups) {
        for (int i = _maxBackups; i < backups.length; i++) {
          try { await backups[i].delete(); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @override
  Future<List<SyncBackupEntry>> listBackups() async {
    final backupDir = _backupDirPath;
    if (backupDir == null) return [];
    try {
      final dir = Directory(backupDir);
      if (!await dir.exists()) return [];

      final prefix = 'kuraudo_backup_${_vaultName}_';
      final files = await dir.list().toList();
      final backups = files
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith(prefix) &&
                       f.uri.pathSegments.last.endsWith('.kuraudo'))
          .toList();

      backups.sort((a, b) => b.path.compareTo(a.path));

      final result = <SyncBackupEntry>[];
      for (final f in backups) {
        final name = f.uri.pathSegments.last;
        // ラベル抽出: kuraudo_backup_<vault>_<label>_<timestamp>.kuraudo
        String? label;
        final m = RegExp(r'kuraudo_backup_.+?_(manual|auto)_').firstMatch(name);
        if (m != null) label = m.group(1);

        DateTime? modifiedAt;
        int? sizeBytes;
        try {
          final stat = await f.stat();
          modifiedAt = stat.modified;
          sizeBytes = stat.size;
        } catch (_) {}

        result.add(SyncBackupEntry(
          id: f.path,        // ローカルではフルパスをIDとして使用
          name: name,
          modifiedAt: modifiedAt,
          sizeBytes: sizeBytes,
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
    // ローカルではbackupIdはフルパス
    try {
      final file = File(backupId);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

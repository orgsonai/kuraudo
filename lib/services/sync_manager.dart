/// Kuraudo 同期マネージャー
/// 
/// VaultService と GoogleDriveService を統合し、
/// ローカル・ファースト原則に基づくハイブリッド同期を実現
/// 
/// v2.0: パスワード自動取得、スマート同期、バックアップ管理
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'vault_service.dart';
import 'google_drive_service.dart';
import '../core/kuraudo_file.dart';
import '../models/vault_entry.dart';

/// 同期イベント（UIへの通知用）
class SyncEvent {
  final SyncStatus status;
  final String message;
  final SyncAction? action;

  SyncEvent({
    required this.status,
    required this.message,
    this.action,
  });
}

/// 同期マネージャー
class SyncManager {
  final VaultService vaultService;
  final GoogleDriveService driveService;
  final Connectivity _connectivity = Connectivity();

  void Function(SyncEvent)? onSyncEvent;

  SyncManager({
    required this.vaultService,
    required this.driveService,
    this.onSyncEvent,
  });

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// マスターパスワードを取得（VaultServiceから自動）
  String? get _masterPassword => vaultService.masterPassword;

  // ── 自動同期（Vault解錠時に呼ばれる） ──

  /// ActiveVault名をDriveServiceに反映
  void _syncVaultName() {
    final name = vaultService.vault?.vaultName ?? 'Default';
    driveService.setVaultName(name);
  }

  Future<SyncResult?> autoSync() async {
    if (!await isOnline) {
      _emit(SyncEvent(status: SyncStatus.offline, message: 'オフラインモード'));
      return null;
    }

    if (!driveService.isSignedIn) {
      final success = await driveService.silentSignIn();
      if (!success) return null;
    }

    if (vaultService.state != VaultState.unlocked) return null;

    _syncVaultName();

    final localBytes = await _readLocalFile();
    if (localBytes == null) return null;

    final localModifiedAt = vaultService.vault?.updatedAt ?? DateTime.now();

    _emit(SyncEvent(status: SyncStatus.syncing, message: '同期中...'));

    final result = await driveService.smartSync(
      localFileBytes: localBytes,
      localModifiedAt: localModifiedAt,
    );

    // 衝突時は自動マージを試行
    if (result.action == SyncAction.conflict && _masterPassword != null) {
      _emit(SyncEvent(status: SyncStatus.syncing, message: '自動マージ中...'));
      final mergeResult = await mergeSync();
      return mergeResult;
    }

    _emit(SyncEvent(status: result.status, message: result.message, action: result.action));
    return result;
  }

  // ── 手動アップロード ──

  Future<SyncResult> forceUpload() async {
    if (!driveService.isSignedIn) return SyncResult(status: SyncStatus.notSignedIn, message: 'サインインしてください');
    _syncVaultName();
    final localBytes = await _readLocalFile();
    if (localBytes == null) return SyncResult(status: SyncStatus.error, message: 'ローカルファイルが見つかりません');

    _emit(SyncEvent(status: SyncStatus.syncing, message: 'アップロード中...'));
    final result = await driveService.uploadAndRecord(localBytes);
    _emit(SyncEvent(status: result.status, message: result.message, action: result.action));
    return result;
  }

  // ── ダウンロード（パスワード不要） ──

  Future<SyncResult> forceDownload([String? masterPassword]) async {
    if (!driveService.isSignedIn) return SyncResult(status: SyncStatus.notSignedIn, message: 'サインインしてください');
    _syncVaultName();

    final pw = masterPassword ?? _masterPassword;
    if (pw == null) return SyncResult(status: SyncStatus.error, message: 'パスワードが取得できません');

    _emit(SyncEvent(status: SyncStatus.syncing, message: 'ダウンロード中...'));

    final remoteBytes = await driveService.download();
    if (remoteBytes == null) {
      _emit(SyncEvent(status: SyncStatus.error, message: 'クラウドにデータがありません'));
      return SyncResult(status: SyncStatus.error, message: 'クラウドにデータがありません');
    }

    try {
      final filePath = vaultService.filePath ?? await vaultService.defaultFilePath;
      await File(filePath).writeAsBytes(remoteBytes);
      vaultService.lock();
      await vaultService.unlock(pw, filePath: filePath);

      _emit(SyncEvent(status: SyncStatus.success, message: 'クラウドからダウンロードしました', action: SyncAction.downloaded));
      return SyncResult(status: SyncStatus.success, message: 'クラウドからダウンロードしました', action: SyncAction.downloaded);
    } catch (e) {
      _emit(SyncEvent(status: SyncStatus.error, message: '復号に失敗しました'));
      return SyncResult(status: SyncStatus.error, message: '復号に失敗しました: $e');
    }
  }

  // ── 保存時の自動同期＋自動バックアップ ──

  Future<void> onVaultSaved() async {
    if (!driveService.isSignedIn) return;
    if (!await isOnline) return;
    _syncVaultName();

    final localBytes = await _readLocalFile();
    if (localBytes != null) {
      // アップロード
      await driveService.uploadAndRecord(localBytes);
      // 自動バックアップ（毎回ではなく1日1回程度）
      await _autoBackupIfNeeded(localBytes);
    }
  }

  /// 1日1回の自動バックアップ（クラウド＋ローカル、各3世代保持）
  Future<void> _autoBackupIfNeeded(Uint8List fileBytes) async {
    try {
      final backups = await driveService.listBackups();
      final autoBackups = backups.where((f) => f.name?.contains('auto_') ?? false).toList();
      if (autoBackups.isNotEmpty) {
        final latest = autoBackups.first.modifiedTime;
        if (latest != null && DateTime.now().difference(latest).inHours < 24) {
          return; // 24時間以内にバックアップ済み
        }
      }
      // クラウド自動バックアップ
      await driveService.createBackup(fileBytes, label: 'auto');
      // ローカル自動バックアップ（手動とは別世代管理）
      await _createLocalBackup(fileBytes, label: 'auto');
    } catch (_) {}
  }

  // ── マージ同期（パスワード自動取得） ──

  Future<SyncResult> mergeSync([String? masterPassword]) async {
    if (!driveService.isSignedIn) return SyncResult(status: SyncStatus.notSignedIn, message: 'サインインしてください');
    if (vaultService.state != VaultState.unlocked || vaultService.vault == null) {
      return SyncResult(status: SyncStatus.error, message: 'Vaultがアンロックされていません');
    }
    _syncVaultName();

    final pw = masterPassword ?? _masterPassword;
    if (pw == null) return SyncResult(status: SyncStatus.error, message: 'パスワードが取得できません');

    _emit(SyncEvent(status: SyncStatus.syncing, message: 'マージ同期中...'));

    final remoteBytes = await driveService.download();
    if (remoteBytes == null) {
      _emit(SyncEvent(status: SyncStatus.syncing, message: 'クラウドにデータなし、アップロード中...'));
      final localBytes = await _readLocalFile();
      if (localBytes != null) await driveService.uploadAndRecord(localBytes);
      _emit(SyncEvent(status: SyncStatus.success, message: 'ローカルデータをアップロードしました', action: SyncAction.uploaded));
      return SyncResult(status: SyncStatus.success, message: 'ローカルデータをアップロードしました', action: SyncAction.uploaded);
    }

    try {
      final kuraudoFile = KuraudoFile();
      final remoteJson = kuraudoFile.decode(remoteBytes, pw);
      final remoteVault = Vault.fromJson(remoteJson);

      final result = vaultService.vault!.mergeWith(remoteVault);

      // マージ後は常にアップロード
      await vaultService.save();
      final localBytes = await _readLocalFile();
      if (localBytes != null) await driveService.uploadAndRecord(localBytes);

      final msg = result.hasChanges ? 'マージ完了: $result' : '同期済み（変更なし）';
      _emit(SyncEvent(status: SyncStatus.success, message: msg, action: result.hasChanges ? SyncAction.downloaded : SyncAction.none));
      return SyncResult(status: SyncStatus.success, message: msg, action: result.hasChanges ? SyncAction.downloaded : SyncAction.none);
    } catch (e) {
      _emit(SyncEvent(status: SyncStatus.error, message: 'マージに失敗: $e'));
      return SyncResult(status: SyncStatus.error, message: 'マージに失敗しました: $e');
    }
  }

  // ── 手動バックアップ（ローカル＋クラウド） ──

  Future<SyncResult> createManualBackup() async {
    final localBytes = await _readLocalFile();
    if (localBytes == null) return SyncResult(status: SyncStatus.error, message: 'ローカルファイルが見つかりません');
    _syncVaultName();
    _emit(SyncEvent(status: SyncStatus.syncing, message: 'バックアップ作成中...'));

    // ローカルバックアップ
    final localResult = await _createLocalBackup(localBytes, label: 'manual');

    // クラウドバックアップ（サインイン済みの場合のみ）
    String cloudMsg = '';
    if (driveService.isSignedIn) {
      final cloudResult = await driveService.createBackup(localBytes, label: 'manual');
      cloudMsg = '\nクラウド: ${cloudResult.message}';
    }

    final msg = 'ローカル: $localResult$cloudMsg';
    _emit(SyncEvent(status: SyncStatus.success, message: msg, action: SyncAction.uploaded));
    return SyncResult(status: SyncStatus.success, message: msg, action: SyncAction.uploaded);
  }

  /// ローカルバックアップを作成（ラベル別に最大3世代保持）
  Future<String> _createLocalBackup(Uint8List fileBytes, {String label = 'manual'}) async {
    try {
      final dir = await _getBackupDir();
      final vaultName = (vaultService.vault?.vaultName ?? 'Default').replaceAll(RegExp(r'[^\w\-]'), '_');
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final backupPath = '${dir.path}/kuraudo_backup_${label}_${vaultName}_$timestamp.kuraudo';
      await File(backupPath).writeAsBytes(fileBytes);

      // 古いバックアップを削除（このラベル＋Vault名の分のみ、3世代保持）
      await _pruneLocalBackups(dir, vaultName, label);

      return '保存しました ($backupPath)';
    } catch (e) {
      return '失敗: $e';
    }
  }

  Future<Directory> _getBackupDir() async {
    final dir = Directory('${(await _getDocDir()).path}/kuraudo_backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _getDocDir() async {
    final path = vaultService.filePath;
    if (path != null) return File(path).parent;
    final defaultPath = await vaultService.defaultFilePath;
    return File(defaultPath).parent;
  }

  Future<void> _pruneLocalBackups(Directory dir, String vaultName, String label) async {
    try {
      final prefix = 'kuraudo_backup_${label}_${vaultName}_';
      final files = await dir.list().where((e) => e is File && e.path.split('/').last.startsWith(prefix)).cast<File>().toList();
      files.sort((a, b) => b.path.compareTo(a.path)); // 新しい順
      if (files.length > 3) {
        for (int i = 3; i < files.length; i++) {
          await files[i].delete();
        }
      }
    } catch (_) {}
  }

  /// ローカルバックアップ一覧を取得（auto/manual両方、ActiveVault名のみ）
  Future<List<File>> listLocalBackups() async {
    try {
      final dir = await _getBackupDir();
      final vaultName = (vaultService.vault?.vaultName ?? 'Default').replaceAll(RegExp(r'[^\w\-]'), '_');
      // auto_VaultName_ と manual_VaultName_ の両方を取得
      final files = await dir.list().where((e) {
        if (e is! File) return false;
        final name = e.path.split('/').last;
        return name.startsWith('kuraudo_backup_manual_${vaultName}_') ||
               name.startsWith('kuraudo_backup_auto_${vaultName}_') ||
               name.startsWith('kuraudo_backup_${vaultName}_'); // 旧形式互換
      }).cast<File>().toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// ローカルバックアップからリストア
  Future<SyncResult> restoreFromLocalBackup(String backupPath) async {
    final pw = _masterPassword;
    if (pw == null) return SyncResult(status: SyncStatus.error, message: 'パスワードが取得できません');

    _emit(SyncEvent(status: SyncStatus.syncing, message: 'リストア中...'));
    try {
      final backupBytes = await File(backupPath).readAsBytes();
      final filePath = vaultService.filePath ?? await vaultService.defaultFilePath;
      await File(filePath).writeAsBytes(backupBytes);
      vaultService.lock();
      await vaultService.unlock(pw, filePath: filePath);
      _emit(SyncEvent(status: SyncStatus.success, message: 'バックアップからリストアしました', action: SyncAction.downloaded));
      return SyncResult(status: SyncStatus.success, message: 'バックアップからリストアしました', action: SyncAction.downloaded);
    } catch (e) {
      _emit(SyncEvent(status: SyncStatus.error, message: 'リストア失敗: $e'));
      return SyncResult(status: SyncStatus.error, message: 'リストア失敗: $e');
    }
  }

  /// クラウドバックアップからリストア
  Future<SyncResult> restoreFromCloudBackup(String fileId) async {
    if (!driveService.isSignedIn) return SyncResult(status: SyncStatus.notSignedIn, message: 'サインインしてください');
    final pw = _masterPassword;
    if (pw == null) return SyncResult(status: SyncStatus.error, message: 'パスワードが取得できません');

    _emit(SyncEvent(status: SyncStatus.syncing, message: 'クラウドバックアップからリストア中...'));
    try {
      final backupBytes = await driveService.downloadBackup(fileId);
      if (backupBytes == null) return SyncResult(status: SyncStatus.error, message: 'ダウンロード失敗');
      final filePath = vaultService.filePath ?? await vaultService.defaultFilePath;
      await File(filePath).writeAsBytes(backupBytes);
      vaultService.lock();
      await vaultService.unlock(pw, filePath: filePath);
      _emit(SyncEvent(status: SyncStatus.success, message: 'クラウドバックアップからリストアしました', action: SyncAction.downloaded));
      return SyncResult(status: SyncStatus.success, message: 'クラウドバックアップからリストアしました', action: SyncAction.downloaded);
    } catch (e) {
      _emit(SyncEvent(status: SyncStatus.error, message: 'リストア失敗: $e'));
      return SyncResult(status: SyncStatus.error, message: 'リストア失敗: $e');
    }
  }

  // ── ユーティリティ ──

  Future<Uint8List?> _readLocalFile() async {
    try {
      final filePath = vaultService.filePath ?? await vaultService.defaultFilePath;
      final file = File(filePath);
      if (await file.exists()) return await file.readAsBytes();
      return null;
    } catch (_) {
      return null;
    }
  }

  void _emit(SyncEvent event) {
    onSyncEvent?.call(event);
  }
}

/// Kuraudo 同期バックエンド共通インターフェース
///
/// 全ての同期方式（Google Drive / WebDAV / ローカルパス）が
/// 実装すべき共通APIを定義する。
///
/// SyncManager はこのインターフェースに依存することで、
/// バックエンドを切り替え可能にする。
library;

import 'dart:typed_data';

import 'google_drive_service.dart' show SyncResult, SyncStatus, SyncAction;

// 共通型を再エクスポート
export 'google_drive_service.dart' show SyncResult, SyncStatus, SyncAction;

/// バックエンド種別の識別子
enum SyncBackendKind {
  googleDrive,
  webdav,
  localPath,
}

/// バックエンドのメタ情報
class SyncBackendInfo {
  final SyncBackendKind kind;
  final String displayName;     // 'Google Drive' / 'WebDAV' / 'ローカルパス'
  final String backendId;       // 'gdrive' / 'webdav' / 'local'
  final bool requiresNetwork;   // true=ネット必須、false=ローカル

  const SyncBackendInfo({
    required this.kind,
    required this.displayName,
    required this.backendId,
    required this.requiresNetwork,
  });
}

/// 全同期バックエンドの共通インターフェース
abstract class SyncBackend {
  /// バックエンドのメタ情報
  SyncBackendInfo get info;

  // ── 設定状態 ──

  /// バックエンドが利用可能（ログイン済み・接続情報あり）か
  bool get isReady;

  /// 表示用ラベル（例: Google Drive ならログインメール、WebDAV ならホスト名、Local なら パス）
  String? get displayLabel;

  // ── Vault名（マルチVault対応用） ──

  /// 現在のVault名を設定（ファイル名生成に使われる）
  void setVaultName(String name);

  // ── 認証/接続 ──

  /// 対話的サインイン/接続セットアップ
  /// Google Drive ならOAuthブラウザ、WebDAV/Local なら設定UIを呼び出す（実装側はUIを開かず、設定を受け取る形でも可）
  Future<bool> connect();

  /// 既存の認証情報で静かに接続（起動時の自動復帰用）
  Future<bool> silentConnect();

  /// 切断・サインアウト
  Future<void> disconnect();

  // ── 基本ファイル操作 ──

  /// リモートにアップロード
  Future<SyncResult> upload(Uint8List fileBytes);

  /// リモートからダウンロード（無ければnull）
  Future<Uint8List?> download();

  /// リモートの最終更新時刻（無ければnull）
  Future<DateTime?> getRemoteModifiedTime();

  /// リモートファイルを削除
  Future<bool> deleteRemoteFile();

  // ── 高レベル操作 ──

  /// スマート同期（タイムスタンプ比較で自動アップ/ダウン判定）
  Future<SyncResult> smartSync({
    required Uint8List localFileBytes,
    required DateTime localModifiedAt,
  });

  /// アップロードしつつ最終同期時刻を記録
  Future<SyncResult> uploadAndRecord(Uint8List fileBytes);

  /// 最終同期時刻をロード（永続ストレージから）
  Future<void> loadLastSyncTime();

  /// 最終同期時刻
  DateTime? get lastSyncTime;

  /// 現在の同期ステータス
  SyncStatus get status;

  // ── バックアップ ──

  /// バックアップを作成
  /// [label] 'manual' / 'auto' などの分類ラベル
  Future<SyncResult> createBackup(Uint8List fileBytes, {String label = 'manual'});

  /// バックアップ一覧を取得
  /// 戻り値はバックエンド非依存のメタ情報
  Future<List<SyncBackupEntry>> listBackups();

  /// バックアップをダウンロード
  Future<Uint8List?> downloadBackup(String backupId);
}

/// バックアップエントリのメタ情報（バックエンド非依存）
class SyncBackupEntry {
  /// バックエンド固有のID（GoogleDriveならファイルID、WebDAVならパスなど）
  final String id;
  /// 表示用名前
  final String name;
  /// 作成・最終更新日時（バックアップなので作成≒更新）
  final DateTime? modifiedAt;
  /// サイズ（バイト、不明ならnull）
  final int? sizeBytes;
  /// 分類ラベル（manual / auto）
  final String? label;

  const SyncBackupEntry({
    required this.id,
    required this.name,
    this.modifiedAt,
    this.sizeBytes,
    this.label,
  });
}

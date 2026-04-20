/// Kuraudo Vault サービス
/// 
/// 暗号化エンジンとファイルシステムを統合し、
/// Vault の読み込み・保存・管理を一元的に行う
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto_engine.dart';
import '../core/kuraudo_file.dart';
import '../models/vault_entry.dart';

/// Vault サービスの状態
enum VaultState {
  locked,     // ロック中（パスワード未入力）
  unlocked,   // アンロック済み
  empty,      // 新規（ファイルなし）
}

/// Vault サービス
class VaultService {
  final KuraudoFile _kuraudoFile = KuraudoFile();
  final Uuid _uuid = const Uuid();

  Vault? _vault;
  String? _masterPassword;
  String? _filePath;
  KdfParams _kdfParams;

  // 派生鍵キャッシュ（Argon2idを毎回実行しない）
  Uint8List? _cachedKey;
  Uint8List? _cachedSalt;

  VaultState _state = VaultState.locked;

  VaultService({
    KdfParams? kdfParams,
  }) : _kdfParams = kdfParams ?? const KdfParams();

  /// 現在の状態
  VaultState get state => _state;

  /// 現在のVault（アンロック時のみ）
  Vault? get vault => _vault;

  /// マスターパスワード（アンロック時のみ、同期用）
  String? get masterPassword => _masterPassword;

  /// 現在のファイルパス
  String? get filePath => _filePath;

  /// エントリ数
  int get entryCount => _vault?.entries.length ?? 0;

  /// デフォルトの保存パスを取得
  Future<String> get defaultFilePath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/kuraudo.kuraudo';
  }

  /// ファイルが存在するか確認
  Future<bool> vaultFileExists([String? path]) async {
    final filePath = path ?? await defaultFilePath;
    return File(filePath).exists();
  }

  /// 新しいVaultを作成
  /// 
  /// [masterPassword] マスターパスワード
  /// [vaultName] Vault名（省略時: "Default"）
  Future<void> createVault(
    String masterPassword, {
    String? vaultName,
    String? filePath,
  }) async {
    _vault = Vault(vaultName: vaultName ?? 'Default');
    _masterPassword = masterPassword;
    _filePath = filePath ?? await defaultFilePath;
    _state = VaultState.unlocked;

    // 派生鍵をキャッシュ（初回のみArgon2id実行）
    _deriveAndCacheKey();

    await save();
  }

  /// 既存のVaultをアンロック
  /// 
  /// [masterPassword] マスターパスワード
  /// [filePath] ファイルパス（省略時: デフォルト）
  Future<void> unlock(String masterPassword, {String? filePath}) async {
    final path = filePath ?? await defaultFilePath;
    final file = File(path);

    if (!await file.exists()) {
      throw FileSystemException('Vaultファイルが見つかりません', path);
    }

    final fileBytes = await file.readAsBytes();
    final jsonString = _kuraudoFile.decode(Uint8List.fromList(fileBytes), masterPassword);

    _vault = Vault.fromJson(jsonString);
    _masterPassword = masterPassword;
    _filePath = path;
    _state = VaultState.unlocked;

    // ファイルからKDFパラメータを読み込み
    final header = KuraudoHeader.fromBytes(Uint8List.fromList(fileBytes));
    _kdfParams = header.kdfParams;

    // 派生鍵をキャッシュ（以降のsaveでArgon2idスキップ）
    _deriveAndCacheKey();
  }

  /// Vaultをロック（メモリから平文データを消去）
  void lock() {
    _vault = null;
    _masterPassword = null;
    // キャッシュ鍵をメモリからクリア
    _cachedKey?.fillRange(0, _cachedKey!.length, 0);
    _cachedKey = null;
    _cachedSalt = null;
    _state = VaultState.locked;
  }

  /// 保存後に呼ばれるコールバック（同期用）
  void Function()? onSaved;

  /// Vaultを保存
  Future<void> save() async {
    if (_state != VaultState.unlocked || _vault == null || _masterPassword == null) {
      throw StateError('Vaultがアンロックされていません');
    }

    final jsonString = _vault!.toJson();
    final fileBytes = _kuraudoFile.encode(
      jsonString,
      _masterPassword!,
      kdfParams: _kdfParams,
      cachedKey: _cachedKey,
      cachedSalt: _cachedSalt,
    );

    final file = File(_filePath!);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(fileBytes);

    // 保存後コールバック（SyncManagerへ通知）
    onSaved?.call();
  }

  /// エントリを追加
  Future<VaultEntry> addEntry({
    required String title,
    required String username,
    required String password,
    String? email,
    String? url,
    String? notes,
    String? category,
    List<String>? tags,
    bool favorite = false,
  }) async {
    _ensureUnlocked();

    final entry = VaultEntry(
      uuid: _uuid.v4(),
      title: title,
      username: username,
      password: password,
      email: email,
      url: url,
      notes: notes,
      category: category,
      tags: tags,
      favorite: favorite,
    );

    _vault!.addEntry(entry);
    await save();
    return entry;
  }

  /// エントリを更新
  Future<void> updateEntry(VaultEntry entry) async {
    _ensureUnlocked();
    _vault!.updateEntry(entry);
    await save();
  }

  /// エントリを削除（完全削除）
  Future<void> deleteEntry(String uuid) async {
    _ensureUnlocked();
    _vault!.removeEntry(uuid);
    await save();
  }

  /// エントリをゴミ箱に移動
  Future<void> trashEntry(String uuid) async {
    _ensureUnlocked();
    _vault!.trashEntry(uuid);
    await save();
  }

  /// ゴミ箱からエントリを復元
  Future<void> restoreEntry(String uuid) async {
    _ensureUnlocked();
    _vault!.restoreEntry(uuid);
    await save();
  }

  /// ゴミ箱を空にする
  Future<void> emptyTrash() async {
    _ensureUnlocked();
    _vault!.emptyTrash();
    await save();
  }

  /// ゴミ箱のエントリ一覧
  List<VaultEntry> get trashedEntries {
    _ensureUnlocked();
    return _vault!.trashedEntries;
  }

  /// マスターパスワードを変更
  Future<void> changeMasterPassword(
    String newPassword, {
    KdfParams? newKdfParams,
  }) async {
    _ensureUnlocked();
    _masterPassword = newPassword;
    if (newKdfParams != null) {
      _kdfParams = newKdfParams;
    }
    // 新しいパスワードで鍵を再派生・キャッシュ
    _deriveAndCacheKey();
    await save();
  }

  /// 検索
  List<VaultEntry> search(String query) {
    _ensureUnlocked();
    return _vault!.search(query);
  }

  /// メールアドレス別グルーピング
  Map<String, List<VaultEntry>> groupByEmail() {
    _ensureUnlocked();
    return _vault!.groupByEmail();
  }

  /// カテゴリ別グルーピング
  Map<String, List<VaultEntry>> groupByCategory() {
    _ensureUnlocked();
    return _vault!.groupByCategory();
  }

  /// お気に入り
  List<VaultEntry> get favorites {
    _ensureUnlocked();
    return _vault!.favorites;
  }

  /// UUIDで新規生成
  String generateUuid() => _uuid.v4();

  /// 派生鍵をキャッシュ（Argon2idは1回だけ実行）
  void _deriveAndCacheKey() {
    if (_masterPassword == null) return;
    final engine = CryptoEngine();
    // 古いキャッシュ鍵をクリア
    _cachedKey?.fillRange(0, _cachedKey!.length, 0);
    _cachedSalt = engine.generateSalt();
    _cachedKey = engine.deriveKey(_masterPassword!, _cachedSalt!, params: _kdfParams);
  }

  /// アンロック状態を確認
  void _ensureUnlocked() {
    if (_state != VaultState.unlocked || _vault == null) {
      throw StateError('Vaultがアンロックされていません');
    }
  }
}

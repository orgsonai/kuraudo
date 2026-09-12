/// Kuraudo 秘密保管庫
///
/// 同期の認証情報（Google のトークン、WebDAV のパスワード等）の保存先。
///
/// - OS のキーリングが使える場合は、従来どおりそこに保存する
///   （Android Keystore / Linux Secret Service / Windows Credential Manager）
/// - 使えない場合は、Vault と同じ Argon2id + AES-256-GCM で暗号化したファイル
///   （アプリ設定フォルダの kuraudo_secrets.enc）に保存する。復号にマスター
///   パスワードが要るため、Vault を解錠している間だけ読み書きできる
///
/// Argon2id は解錠時の 1 回だけ実行し、派生鍵は解錠中のみメモリに持つ。
/// このファイルは端末内にとどめる（Vault と違い同期・バックアップの対象にしない）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../core/crypto_engine.dart';

class SecretStore {
  SecretStore._();

  /// 各同期バックエンドが共有する実体
  static final SecretStore instance = SecretStore._();

  static const FlutterSecureStorage _keyring = FlutterSecureStorage();

  /// 暗号化ファイル名（アプリ設定フォルダに置く）
  static const String _fileName = 'kuraudo_secrets.enc';

  /// キーリングが使えるかを 1 度だけ確かめるための読み取りキー
  static const String _probeKey = 'kuraudo_keyring_probe';

  /// ファイル形式: "KSEC"(4) + 版(2) + KDFパラメータ(12) + ソルト(32) + ノンス(12) + 暗号文
  static const List<int> _magic = <int>[0x4B, 0x53, 0x45, 0x43];
  static const int _formatVersion = 1;
  static const int _kdfOffset = 6;
  static const int _saltOffset = 18;
  static const int _nonceOffset = 50;
  static const int _headerSize = 62;

  final CryptoEngine _engine = CryptoEngine();

  bool? _keyringUsable;
  Map<String, String>? _cache; // 復号済みの内容（解錠中のみ保持）
  Uint8List? _key; // 派生鍵（解錠中のみ保持）
  Uint8List? _salt;
  KdfParams _kdfParams = _defaultKdfParams;

  static KdfParams get _defaultKdfParams =>
      Platform.isAndroid || Platform.isIOS ? KdfParams.mobile : KdfParams.desktop;

  /// テスト用: 保存先ディレクトリを差し替える
  @visibleForTesting
  Directory? directoryOverride;

  /// キーリングが無く、暗号化ファイルを使っているか
  bool get usesEncryptedFile => _keyringUsable == false;

  /// Vault 解錠時に呼ぶ。暗号化ファイルを復号してメモリに読み込む
  ///
  /// キーリングが使える環境、および解錠済みの場合は何もしない。
  Future<void> unlock(String masterPassword) async {
    if (await _useKeyring() || _cache != null) return;
    try {
      final file = await _file();
      if (await file.exists()) {
        _loadFromBytes(await file.readAsBytes(), masterPassword);
        return;
      }
    } catch (_) {
      // 壊れている・パスワードが変わった等。空から作り直す
    }
    _salt = _engine.generateSalt();
    _kdfParams = _defaultKdfParams;
    _key = _engine.deriveKey(masterPassword, _salt!, params: _kdfParams);
    _cache = <String, String>{};
  }

  /// Vault ロック時に呼ぶ。メモリ上の秘密と派生鍵を捨てる
  void lock() {
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _salt = null;
    _cache = null;
  }

  /// マスターパスワード変更時に呼ぶ。新しいパスワードで保存し直す
  Future<void> rekey(String newMasterPassword) async {
    if (_cache == null) return;
    _key?.fillRange(0, _key!.length, 0);
    _salt = _engine.generateSalt();
    _kdfParams = _defaultKdfParams;
    _key = _engine.deriveKey(newMasterPassword, _salt!, params: _kdfParams);
    await _persist();
  }

  Future<String?> read({required String key}) async {
    if (await _useKeyring()) {
      try {
        return await _keyring.read(key: key);
      } catch (_) {
        return null;
      }
    }
    return _cache?[key];
  }

  Future<void> write({required String key, required String? value}) async {
    if (await _useKeyring()) {
      try {
        await _keyring.write(key: key, value: value);
      } catch (_) {}
      return;
    }
    final cache = _cache;
    if (cache == null) return; // 施錠中は復号鍵が無いので保存しない
    if (value == null) {
      cache.remove(key);
    } else {
      cache[key] = value;
    }
    await _persist();
  }

  Future<void> delete({required String key}) async {
    if (await _useKeyring()) {
      try {
        await _keyring.delete(key: key);
      } catch (_) {}
      return;
    }
    final cache = _cache;
    if (cache == null || cache.remove(key) == null) return;
    await _persist();
  }

  /// キーリングが使えるかを 1 度だけ調べて覚える
  Future<bool> _useKeyring() async {
    final known = _keyringUsable;
    if (known != null) return known;
    try {
      await _keyring.read(key: _probeKey);
      _keyringUsable = true;
    } catch (_) {
      _keyringUsable = false;
    }
    return _keyringUsable!;
  }

  Future<File> _file() async {
    final dir = directoryOverride ?? await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  /// ヘッダーを読み、鍵を派生して復号する（Argon2id はここでの 1 回だけ）
  void _loadFromBytes(Uint8List bytes, String masterPassword) {
    if (bytes.length <= _headerSize) {
      throw const FormatException('秘密保管庫のファイルが短すぎます');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('秘密保管庫のファイル形式が不正です');
      }
    }
    _kdfParams = KdfParams.fromBytes(
        Uint8List.sublistView(bytes, _kdfOffset, _saltOffset));
    _salt = Uint8List.fromList(bytes.sublist(_saltOffset, _nonceOffset));
    final nonce = Uint8List.fromList(bytes.sublist(_nonceOffset, _headerSize));
    _key = _engine.deriveKey(masterPassword, _salt!, params: _kdfParams);
    final plain =
        _engine.decrypt(Uint8List.sublistView(bytes, _headerSize), _key!, nonce);

    final decoded = jsonDecode(utf8.decode(plain));
    final restored = <String, String>{};
    if (decoded is Map) {
      decoded.forEach((key, value) {
        if (key is String && value is String) restored[key] = value;
      });
    }
    _cache = restored;
  }

  /// 現在の内容を暗号化して書き出す（ノンスは毎回作り直す）
  Future<void> _persist() async {
    final cache = _cache;
    final key = _key;
    final salt = _salt;
    if (cache == null || key == null || salt == null) return;
    try {
      final nonce = _engine.generateNonce();
      final ciphertext = _engine.encrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(cache))),
        key,
        nonce,
      );
      final output = BytesBuilder()
        ..add(_magic)
        ..add(_uint16le(_formatVersion))
        ..add(_kdfParams.toBytes())
        ..add(salt)
        ..add(nonce)
        ..add(ciphertext);

      final file = await _file();
      await file.parent.create(recursive: true);
      // 書き込み途中で壊さないよう、一時ファイルに書いてから置き換える
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(output.takeBytes(), flush: true);
      await temp.rename(file.path);
    } catch (_) {}
  }

  static Uint8List _uint16le(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}

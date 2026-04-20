/// Kuraudo ファイルフォーマット (.kuraudo)
/// 
/// バイナリ形式:
/// ┌──────────────────────────────────────────────┐
/// │ Magic Number    (4 bytes)  "KRAD"            │
/// │ Format Version  (2 bytes)  uint16 LE         │
/// │ KDF Params      (12 bytes) memory/iter/lanes │
/// │ Salt            (32 bytes) Argon2用ソルト     │
/// │ Nonce           (12 bytes) AES-GCM用ノンス   │
/// ├──────────────────────────────────────────────┤
/// │ Encrypted Payload (可変長)                    │
/// │   暗号化されたJSONデータ + GCM Auth Tag(16B)  │
/// └──────────────────────────────────────────────┘
/// 
/// Header合計: 4 + 2 + 12 + 32 + 12 = 62 bytes
library;

import 'dart:convert';
import 'dart:typed_data';

import 'crypto_engine.dart';

/// .kuraudo ファイルのマジックナンバー
const List<int> kuraudoMagic = [0x4B, 0x52, 0x41, 0x44]; // "KRAD"

/// 現在のフォーマットバージョン
const int kuraudoFormatVersion = 1;

/// ファイルヘッダーサイズ
const int headerSize = 62; // 4 + 2 + 12 + 32 + 12

/// .kuraudo ファイルのヘッダー
class KuraudoHeader {
  final int formatVersion;
  final KdfParams kdfParams;
  final Uint8List salt;   // 32 bytes
  final Uint8List nonce;  // 12 bytes

  KuraudoHeader({
    required this.formatVersion,
    required this.kdfParams,
    required this.salt,
    required this.nonce,
  });

  /// ヘッダーをバイト列に変換
  Uint8List toBytes() {
    final buffer = BytesBuilder();

    // Magic Number
    buffer.add(kuraudoMagic);

    // Format Version (uint16 LE)
    final versionBytes = Uint8List(2);
    ByteData.sublistView(versionBytes).setUint16(0, formatVersion, Endian.little);
    buffer.add(versionBytes);

    // KDF Params (12 bytes)
    buffer.add(kdfParams.toBytes());

    // Salt (32 bytes)
    buffer.add(salt);

    // Nonce (12 bytes)
    buffer.add(nonce);

    return buffer.toBytes();
  }

  /// バイト列からヘッダーを解析
  factory KuraudoHeader.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw const FormatException('ファイルが小さすぎます（ヘッダー不足）');
    }

    // Magic Number 検証
    for (int i = 0; i < 4; i++) {
      if (bytes[i] != kuraudoMagic[i]) {
        throw const FormatException('無効なファイル形式です（マジックナンバー不一致）');
      }
    }

    // Format Version
    final version = ByteData.sublistView(bytes, 4, 6).getUint16(0, Endian.little);
    if (version > kuraudoFormatVersion) {
      throw FormatException(
        'このバージョンのKuraudoでは開けません（ファイル: v$version, アプリ: v$kuraudoFormatVersion）',
      );
    }

    // KDF Params
    final kdfParams = KdfParams.fromBytes(Uint8List.sublistView(bytes, 6, 18));

    // Salt
    final salt = Uint8List.sublistView(bytes, 18, 50);

    // Nonce
    final nonce = Uint8List.sublistView(bytes, 50, 62);

    return KuraudoHeader(
      formatVersion: version,
      kdfParams: kdfParams,
      salt: Uint8List.fromList(salt),
      nonce: Uint8List.fromList(nonce),
    );
  }
}

/// .kuraudo ファイルの読み書きを行うクラス
class KuraudoFile {
  final CryptoEngine _engine = CryptoEngine();

  /// Vault データを .kuraudo 形式のバイト列に変換（暗号化）
  /// 
  /// [jsonData] 暗号化するJSONデータ（エントリ群）
  /// [masterPassword] マスターパスワード
  /// [kdfParams] KDFパラメータ（省略時はデフォルト）
  /// [cachedKey] キャッシュ済み派生鍵（省略時はArgon2idで毎回派生）
  /// [cachedSalt] キャッシュ済みソルト（cachedKeyと併用）
  Uint8List encode(
    String jsonData,
    String masterPassword, {
    KdfParams kdfParams = const KdfParams(),
    Uint8List? cachedKey,
    Uint8List? cachedSalt,
  }) {
    // キャッシュ済み鍵がある場合はそれを使用（Argon2idスキップ）
    final Uint8List salt;
    final Uint8List key;
    final bool shouldClearKey;

    if (cachedKey != null && cachedSalt != null) {
      salt = cachedSalt;
      key = cachedKey;
      shouldClearKey = false; // キャッシュ鍵はクリアしない
    } else {
      salt = _engine.generateSalt();
      key = _engine.deriveKey(masterPassword, salt, params: kdfParams);
      shouldClearKey = true;
    }

    // ノンスは毎回新規生成（セキュリティ上必須）
    final nonce = _engine.generateNonce();

    // JSONデータを暗号化
    final encryptedPayload = _engine.encryptJson(jsonData, key, nonce);

    // ヘッダーを構築
    final header = KuraudoHeader(
      formatVersion: kuraudoFormatVersion,
      kdfParams: kdfParams,
      salt: salt,
      nonce: nonce,
    );

    // ヘッダー + 暗号化ペイロードを結合
    final buffer = BytesBuilder();
    buffer.add(header.toBytes());
    buffer.add(encryptedPayload);

    // キャッシュ鍵でない場合のみメモリからクリア
    if (shouldClearKey) {
      key.fillRange(0, key.length, 0);
    }

    return buffer.toBytes();
  }

  /// .kuraudo 形式のバイト列を復号してJSONデータを返す
  /// 
  /// [fileBytes] .kuraudo ファイルの内容
  /// [masterPassword] マスターパスワード
  /// 戻り値: 復号されたJSON文字列
  /// 例外: パスワード不一致、ファイル改ざん時
  String decode(Uint8List fileBytes, String masterPassword) {
    // ヘッダーを解析
    final header = KuraudoHeader.fromBytes(fileBytes);

    // 暗号化ペイロードを取り出し
    final encryptedPayload = Uint8List.sublistView(fileBytes, headerSize);

    if (encryptedPayload.isEmpty) {
      throw const FormatException('暗号化データがありません');
    }

    // マスターパスワードから鍵を派生（ヘッダーのKDFパラメータを使用）
    final key = _engine.deriveKey(
      masterPassword,
      header.salt,
      params: header.kdfParams,
    );

    try {
      // 復号
      final jsonString = _engine.decryptToJson(encryptedPayload, key, header.nonce);
      return jsonString;
    } catch (e) {
      throw FormatException(
        'マスターパスワードが正しくないか、ファイルが破損しています ($e)',
      );
    } finally {
      // 鍵をメモリからクリア
      key.fillRange(0, key.length, 0);
    }
  }

  /// マスターパスワードの変更（再暗号化）
  /// 
  /// [fileBytes] 既存の .kuraudo ファイル
  /// [oldPassword] 現在のマスターパスワード
  /// [newPassword] 新しいマスターパスワード
  /// [newKdfParams] 新しいKDFパラメータ（省略時は既存パラメータを引き継ぎ）
  Uint8List changePassword(
    Uint8List fileBytes,
    String oldPassword,
    String newPassword, {
    KdfParams? newKdfParams,
  }) {
    // 旧パスワードで復号
    final jsonData = decode(fileBytes, oldPassword);

    // ヘッダーから既存KDFパラメータを取得
    final header = KuraudoHeader.fromBytes(fileBytes);

    // 新パスワードで再暗号化（ソルト・ノンスは新規生成される）
    return encode(
      jsonData,
      newPassword,
      kdfParams: newKdfParams ?? header.kdfParams,
    );
  }
}

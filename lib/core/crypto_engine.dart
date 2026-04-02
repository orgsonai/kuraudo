/// Kuraudo 暗号化エンジン
/// 
/// Argon2id による鍵派生 + AES-256-GCM による暗号化/復号
/// データファイルが第三者に渡ってもマスターパスワードなしでは解読不可能な構成
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' hide Argon2Parameters, Argon2BytesGenerator;
import 'package:argon2/argon2.dart';

/// Argon2id KDF パラメータ
/// ヘッダーに保存し、将来の強化時にも旧ファイルの読み込みを保証する
class KdfParams {
  final int memorySizeKB;  // メモリコスト (KB)
  final int iterations;     // 反復回数
  final int parallelism;    // 並列度

  const KdfParams({
    this.memorySizeKB = 65536,  // 64MB（OWASP推奨水準）
    this.iterations = 3,
    this.parallelism = 4,
  });

  /// デフォルトパラメータ（モバイル向け — UX配慮で控えめ）
  static const mobile = KdfParams(
    memorySizeKB: 32768,  // 32MB
    iterations: 3,
    parallelism: 2,
  );

  /// デスクトップ向けパラメータ
  static const desktop = KdfParams(
    memorySizeKB: 65536,  // 64MB
    iterations: 3,
    parallelism: 4,
  );

  /// バイト列からの復元（ファイルヘッダー読み込み用）
  factory KdfParams.fromBytes(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const FormatException('KdfParams: バイト列が短すぎます');
    }
    final view = ByteData.sublistView(bytes);
    return KdfParams(
      memorySizeKB: view.getUint32(0, Endian.little),
      iterations: view.getUint32(4, Endian.little),
      parallelism: view.getUint32(8, Endian.little),
    );
  }

  /// バイト列への変換（ファイルヘッダー書き込み用）
  Uint8List toBytes() {
    final bytes = Uint8List(12);
    final view = ByteData.sublistView(bytes);
    view.setUint32(0, memorySizeKB, Endian.little);
    view.setUint32(4, iterations, Endian.little);
    view.setUint32(8, parallelism, Endian.little);
    return bytes;
  }

  @override
  String toString() =>
      'KdfParams(memory: ${memorySizeKB}KB, iterations: $iterations, parallelism: $parallelism)';
}

/// 暗号化エンジン本体
class CryptoEngine {
  static const int saltLength = 32;       // ソルト長 (バイト)
  static const int nonceLength = 12;      // AES-GCM ノンス長 (バイト)
  static const int keyLength = 32;        // AES-256 鍵長 (バイト)
  static const int tagLength = 16;        // GCM 認証タグ長 (バイト)

  final Random _secureRandom = Random.secure();

  /// 暗号学的に安全な乱数バイト列を生成
  Uint8List generateRandomBytes(int length) {
    return Uint8List.fromList(
      List.generate(length, (_) => _secureRandom.nextInt(256)),
    );
  }

  /// ソルトを生成
  Uint8List generateSalt() => generateRandomBytes(saltLength);

  /// ノンスを生成
  Uint8List generateNonce() => generateRandomBytes(nonceLength);

  /// Argon2id でマスターパスワードから暗号化鍵を派生
  /// 
  /// [masterPassword] マスターパスワード
  /// [salt] ソルト（32バイト）
  /// [params] KDFパラメータ
  /// 戻り値: 256ビット (32バイト) の派生鍵
  Uint8List deriveKey(
    String masterPassword,
    Uint8List salt, {
    KdfParams params = const KdfParams(),
  }) {
    // Argon2id パラメータを構築
    // argon2パッケージは memoryPowerOf2 または memory(KB直指定) を受け付ける
    final parameters = Argon2Parameters(
      Argon2Parameters.ARGON2_id,  // Argon2id
      salt,
      version: Argon2Parameters.ARGON2_VERSION_13,
      iterations: params.iterations,
      memory: params.memorySizeKB,  // KB単位で直接指定
      lanes: params.parallelism,
    );

    final argon2 = Argon2BytesGenerator();
    argon2.init(parameters);

    final passwordBytes = parameters.converter.convert(masterPassword);
    final result = Uint8List(keyLength);
    argon2.generateBytes(passwordBytes, result, 0, result.length);

    // 入力パスワードバイトをメモリからクリア
    if (passwordBytes is Uint8List) {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
    }

    return result;
  }

  /// AES-256-GCM で暗号化
  /// 
  /// [plaintext] 平文バイト列
  /// [key] 256ビット鍵
  /// [nonce] 12バイトのノンス
  /// 戻り値: 暗号文 + 認証タグ（16バイト）が結合されたバイト列
  Uint8List encrypt(Uint8List plaintext, Uint8List key, Uint8List nonce) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // encrypt
        AEADParameters(
          KeyParameter(key),
          tagLength * 8, // タグ長をビット単位で指定
          nonce,
          Uint8List(0), // AAD
        ),
      );

    final outputSize = cipher.getOutputSize(plaintext.length);
    final output = Uint8List(outputSize);
    var offset = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
    offset += cipher.doFinal(output, offset);

    // 実際に書き込まれたバイト数でトリム
    return Uint8List.fromList(output.sublist(0, offset));
  }

  /// AES-256-GCM で復号
  /// 
  /// [ciphertextWithTag] 暗号文 + 認証タグ（encrypt の出力）
  /// [key] 256ビット鍵
  /// [nonce] 12バイトのノンス
  /// 戻り値: 平文バイト列
  /// 例外: 認証タグが不一致の場合（改ざん検知）
  Uint8List decrypt(Uint8List ciphertextWithTag, Uint8List key, Uint8List nonce) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(
          KeyParameter(key),
          tagLength * 8,
          nonce,
          Uint8List(0),
        ),
      );

    final outputSize = cipher.getOutputSize(ciphertextWithTag.length);
    final output = Uint8List(outputSize);
    var offset = cipher.processBytes(
      ciphertextWithTag, 0, ciphertextWithTag.length, output, 0,
    );
    offset += cipher.doFinal(output, offset);

    // 実際に書き込まれたバイト数でトリム
    return Uint8List.fromList(output.sublist(0, offset));
  }

  /// JSON文字列を暗号化
  /// 
  /// 便利メソッド: JSON → UTF-8 → AES-256-GCM暗号化
  Uint8List encryptJson(String json, Uint8List key, Uint8List nonce) {
    final plaintext = Uint8List.fromList(utf8.encode(json));
    return encrypt(plaintext, key, nonce);
  }

  /// 暗号文をJSON文字列に復号
  /// 
  /// 便利メソッド: AES-256-GCM復号 → UTF-8 → JSON文字列
  String decryptToJson(Uint8List ciphertextWithTag, Uint8List key, Uint8List nonce) {
    final plaintext = decrypt(ciphertextWithTag, key, nonce);
    return utf8.decode(plaintext);
  }
}

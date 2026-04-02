/// Kuraudo TOTP 生成器
/// 
/// RFC 6238 準拠の Time-based One-Time Password 生成
/// Google Authenticator互換
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// TOTP パラメータ
class TotpParams {
  final String secret;      // Base32エンコードされたシークレット
  final int digits;          // コード桁数（通常6）
  final int period;          // 更新間隔（秒、通常30）
  final String algorithm;    // ハッシュアルゴリズム（SHA1/SHA256/SHA512）

  const TotpParams({
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.algorithm = 'SHA1',
  });

  /// otpauth:// URI からパース
  /// 例: otpauth://totp/Example:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&digits=6&period=30
  factory TotpParams.fromUri(String uri) {
    final parsed = Uri.parse(uri);

    if (parsed.scheme != 'otpauth' || parsed.host != 'totp') {
      throw FormatException('無効なTOTP URIです: $uri');
    }

    final params = parsed.queryParameters;
    final secret = params['secret'];
    if (secret == null || secret.isEmpty) {
      throw const FormatException('シークレットが見つかりません');
    }

    return TotpParams(
      secret: secret.toUpperCase(),
      digits: int.tryParse(params['digits'] ?? '') ?? 6,
      period: int.tryParse(params['period'] ?? '') ?? 30,
      algorithm: (params['algorithm'] ?? 'SHA1').toUpperCase(),
    );
  }

  /// otpauth:// URI に変換
  String toUri({String? issuer, String? accountName}) {
    final label = issuer != null && accountName != null
        ? '$issuer:$accountName'
        : accountName ?? 'Kuraudo';
    final params = <String, String>{
      'secret': secret,
      'digits': digits.toString(),
      'period': period.toString(),
      'algorithm': algorithm,
    };
    if (issuer != null) params['issuer'] = issuer;

    return Uri(
      scheme: 'otpauth',
      host: 'totp',
      path: '/$label',
      queryParameters: params,
    ).toString();
  }
}

/// TOTP 生成結果
class TotpCode {
  final String code;
  final int remainingSeconds;
  final int period;

  TotpCode({
    required this.code,
    required this.remainingSeconds,
    required this.period,
  });

  /// 残り時間の割合（0.0〜1.0）
  double get progress => remainingSeconds / period;
}

/// TOTP 生成器
class TotpGenerator {
  /// 現在のTOTPコードを生成
  TotpCode generate(TotpParams params, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final epoch = currentTime.millisecondsSinceEpoch ~/ 1000;
    final timeStep = epoch ~/ params.period;
    final remaining = params.period - (epoch % params.period);

    final code = _generateCode(params.secret, timeStep, params.digits, params.algorithm);

    return TotpCode(
      code: code,
      remainingSeconds: remaining,
      period: params.period,
    );
  }

  /// HOTP (RFC 4226) の内部実装
  String _generateCode(String base32Secret, int counter, int digits, String algorithm) {
    // Base32 デコード
    final key = _base32Decode(base32Secret);

    // カウンターを8バイトのビッグエンディアンに変換
    final counterBytes = Uint8List(8);
    final view = ByteData.sublistView(counterBytes);
    view.setInt64(0, counter, Endian.big);

    // HMAC 計算
    final hmacResult = _hmac(key, counterBytes, algorithm);

    // Dynamic Truncation
    final offset = hmacResult[hmacResult.length - 1] & 0x0f;
    final binary = ((hmacResult[offset] & 0x7f) << 24) |
        ((hmacResult[offset + 1] & 0xff) << 16) |
        ((hmacResult[offset + 2] & 0xff) << 8) |
        (hmacResult[offset + 3] & 0xff);

    final otp = binary % pow(10, digits).toInt();
    return otp.toString().padLeft(digits, '0');
  }

  /// HMAC を計算
  Uint8List _hmac(Uint8List key, Uint8List data, String algorithm) {
    final Mac mac;
    switch (algorithm) {
      case 'SHA256':
        mac = HMac(SHA256Digest(), 64);
        break;
      case 'SHA512':
        mac = HMac(SHA512Digest(), 128);
        break;
      case 'SHA1':
      default:
        mac = HMac(SHA1Digest(), 64);
        break;
    }

    mac.init(KeyParameter(key));
    return mac.process(data);
  }

  /// Base32 デコード（RFC 4648）
  Uint8List _base32Decode(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final clean = input.replaceAll(RegExp(r'[\s=]'), '').toUpperCase();

    final output = <int>[];
    int buffer = 0;
    int bitsLeft = 0;

    for (final c in clean.codeUnits) {
      final val = alphabet.indexOf(String.fromCharCode(c));
      if (val < 0) continue;

      buffer = (buffer << 5) | val;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        output.add((buffer >> (bitsLeft - 8)) & 0xff);
        bitsLeft -= 8;
      }
    }

    return Uint8List.fromList(output);
  }

  /// ランダムなBase32シークレットを生成（手動追加用）
  String generateSecret({int length = 32}) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final random = Random.secure();
    return List.generate(length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }
}

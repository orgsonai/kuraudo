/// Kuraudo パスワード生成器
/// 
/// カスタマイズ可能な強度設定でパスワードとパスフレーズを生成
library;

import 'dart:math';

/// パスワード生成の設定
class PasswordGeneratorConfig {
  final int length;
  final bool useUppercase;
  final bool useLowercase;
  final bool useDigits;
  final bool useSymbols;
  final bool useSpaces;          // スペースを含める
  final bool useExtendedSymbols; // 拡張特殊文字を含める
  final String excludeChars;      // 除外する文字
  final String customSymbols;     // カスタム記号セット

  const PasswordGeneratorConfig({
    this.length = 20,
    this.useUppercase = true,
    this.useLowercase = true,
    this.useDigits = true,
    this.useSymbols = true,
    this.useSpaces = false,
    this.useExtendedSymbols = false,
    this.excludeChars = '',
    this.customSymbols = '!@#\$%^&*()-_=+[]{}|;:,.<>?',
  });

  /// 最低限の強度（数字のみ PIN）
  static const pin4 = PasswordGeneratorConfig(
    length: 4,
    useUppercase: false,
    useLowercase: false,
    useDigits: true,
    useSymbols: false,
  );

  /// 高強度
  static const strong = PasswordGeneratorConfig(
    length: 24,
    useUppercase: true,
    useLowercase: true,
    useDigits: true,
    useSymbols: true,
  );

  /// 最高強度（全文字種）
  static const maximum = PasswordGeneratorConfig(
    length: 32,
    useUppercase: true,
    useLowercase: true,
    useDigits: true,
    useSymbols: true,
    useSpaces: true,
    useExtendedSymbols: true,
  );
}

/// パスワード強度の評価結果
enum PasswordStrength {
  veryWeak,
  weak,
  fair,
  strong,
  veryStrong,
}

/// パスワード強度の表示情報
extension PasswordStrengthDisplay on PasswordStrength {
  String get label {
    switch (this) {
      case PasswordStrength.veryWeak:
        return '非常に弱い';
      case PasswordStrength.weak:
        return '弱い';
      case PasswordStrength.fair:
        return '普通';
      case PasswordStrength.strong:
        return '強い';
      case PasswordStrength.veryStrong:
        return '非常に強い';
    }
  }

  /// 0.0 ~ 1.0 のスコア
  double get score {
    switch (this) {
      case PasswordStrength.veryWeak:
        return 0.2;
      case PasswordStrength.weak:
        return 0.4;
      case PasswordStrength.fair:
        return 0.6;
      case PasswordStrength.strong:
        return 0.8;
      case PasswordStrength.veryStrong:
        return 1.0;
    }
  }
}

/// パスワード生成器
class PasswordGenerator {
  static const String _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String _digits = '0123456789';
  static const String _extendedSymbols = '~`\\/\'"';

  final Random _random = Random.secure();

  /// パスワードを生成
  String generate(PasswordGeneratorConfig config) {
    // 使用する文字プールを構築
    final pool = StringBuffer();
    final required = <String>[]; // 各カテゴリから最低1文字を保証

    if (config.useLowercase) {
      final chars = _filterChars(_lowercase, config.excludeChars);
      pool.write(chars);
      if (chars.isNotEmpty) required.add(chars);
    }
    if (config.useUppercase) {
      final chars = _filterChars(_uppercase, config.excludeChars);
      pool.write(chars);
      if (chars.isNotEmpty) required.add(chars);
    }
    if (config.useDigits) {
      final chars = _filterChars(_digits, config.excludeChars);
      pool.write(chars);
      if (chars.isNotEmpty) required.add(chars);
    }
    if (config.useSymbols) {
      final chars = _filterChars(config.customSymbols, config.excludeChars);
      pool.write(chars);
      if (chars.isNotEmpty) required.add(chars);
    }
    if (config.useExtendedSymbols) {
      final chars = _filterChars(_extendedSymbols, config.excludeChars);
      pool.write(chars);
      if (chars.isNotEmpty) required.add(chars);
    }
    if (config.useSpaces) {
      if (!config.excludeChars.contains(' ')) {
        pool.write(' ');
        // スペースはrequiredには入れない（先頭・末尾にスペースが来ないように）
      }
    }

    final poolStr = pool.toString();
    if (poolStr.isEmpty) {
      throw ArgumentError('パスワードに使用できる文字がありません');
    }

    if (config.length < required.length) {
      throw ArgumentError(
        'パスワード長(${config.length})が、必要な文字種(${required.length}種)より短いです',
      );
    }

    // 各カテゴリから1文字ずつ確保
    final chars = <String>[];
    for (final reqChars in required) {
      chars.add(reqChars[_random.nextInt(reqChars.length)]);
    }

    // 残りをランダムに埋める
    while (chars.length < config.length) {
      chars.add(poolStr[_random.nextInt(poolStr.length)]);
    }

    // シャッフル（Fisher-Yates）
    for (int i = chars.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }

    return chars.join();
  }

  /// パスフレーズを生成（単語区切り）
  /// 
  /// [wordCount] 単語数
  /// [separator] 区切り文字
  /// [capitalize] 各単語の先頭を大文字にするか
  /// [addNumber] 末尾に数字を付加するか
  String generatePassphrase({
    int wordCount = 4,
    String separator = '-',
    bool capitalize = true,
    bool addNumber = true,
  }) {
    // EFF Diceware の短いリストから抜粋した簡易単語リスト
    // 実運用では完全なDicewareリストを使用する
    final words = _basicWordList;

    final selected = <String>[];
    for (int i = 0; i < wordCount; i++) {
      var word = words[_random.nextInt(words.length)];
      if (capitalize) {
        word = word[0].toUpperCase() + word.substring(1);
      }
      selected.add(word);
    }

    var result = selected.join(separator);
    if (addNumber) {
      result += separator + _random.nextInt(1000).toString().padLeft(3, '0');
    }

    return result;
  }

  /// パスワードを複数件バッチ生成（テキスト形式）
  /// 
  /// [config] 生成設定
  /// [count] 生成件数（デフォルト20）
  /// 戻り値: 1行1パスワードのテキスト（番号なし）
  String generateBatch(
    PasswordGeneratorConfig config, {
    int count = 20,
  }) {
    final buffer = StringBuffer();
    for (int i = 0; i < count; i++) {
      buffer.writeln(generate(config));
    }
    return buffer.toString().trimRight();
  }

  /// パスフレーズを複数件バッチ生成（テキスト形式）
  String generatePassphraseBatch({
    int count = 20,
    int wordCount = 4,
    String separator = '-',
    bool capitalize = true,
    bool addNumber = true,
  }) {
    final buffer = StringBuffer();
    for (int i = 0; i < count; i++) {
      buffer.writeln(generatePassphrase(
        wordCount: wordCount,
        separator: separator,
        capitalize: capitalize,
        addNumber: addNumber,
      ));
    }
    return buffer.toString().trimRight();
  }

  /// パスワード強度を評価（辞書攻撃耐性を含む）
  PasswordStrength evaluateStrength(String password) {
    if (password.isEmpty) return PasswordStrength.veryWeak;

    int score = 0;
    final len = password.length;

    // 長さによるスコア
    if (len >= 8) score++;
    if (len >= 12) score++;
    if (len >= 16) score++;
    if (len >= 24) score++;

    // 文字種によるスコア
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) score++;

    // エントロピー推定
    int poolSize = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) poolSize += 26;
    if (RegExp(r'[A-Z]').hasMatch(password)) poolSize += 26;
    if (RegExp(r'[0-9]').hasMatch(password)) poolSize += 10;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) poolSize += 33;

    final entropy = poolSize > 0 ? len * (log(poolSize) / log(2)) : 0;
    if (entropy >= 60) score++;
    if (entropy >= 80) score++;
    if (entropy >= 100) score++;

    // 連続文字・繰り返しのペナルティ
    if (RegExp(r'(.)\1{2,}').hasMatch(password)) score--;
    if (RegExp(r'(012|123|234|345|456|567|678|789|890)').hasMatch(password)) score--;
    if (RegExp(r'(abc|bcd|cde|def|efg|fgh|ghi|hij|ijk|jkl|klm|lmn|mno|nop|opq|pqr|qrs|rst|stu|tuv|uvw|vwx|wxy|xyz)', caseSensitive: false).hasMatch(password)) score--;

    // ── 辞書攻撃耐性チェック ──
    final lower = password.toLowerCase();

    // よく使われるパスワードのブラックリスト
    if (_commonPasswords.contains(lower)) score -= 4;

    // よく使われるパターン（キーボード配列等）
    for (final pattern in _commonPatterns) {
      if (lower.contains(pattern)) score -= 2;
    }

    // 辞書単語の検出（4文字以上の単語が含まれていたらペナルティ）
    int wordMatches = 0;
    for (final word in _dictionaryWords) {
      if (lower.contains(word)) wordMatches++;
    }
    if (wordMatches >= 1) score--;
    if (wordMatches >= 2) score -= 2;

    // 数字のみ・英字のみの短いパスワードに追加ペナルティ
    if (len <= 8 && RegExp(r'^[0-9]+$').hasMatch(password)) score -= 2;
    if (len <= 8 && RegExp(r'^[a-zA-Z]+$').hasMatch(password)) score -= 1;

    // リート表記の検出（p@ssw0rd, l3tme1n 等）
    final deleet = lower
        .replaceAll('@', 'a').replaceAll('0', 'o').replaceAll('1', 'i')
        .replaceAll('3', 'e').replaceAll('\$', 's').replaceAll('5', 's')
        .replaceAll('7', 't').replaceAll('!', 'i').replaceAll('4', 'a');
    if (_commonPasswords.contains(deleet)) score -= 3;
    for (final word in _dictionaryWords) {
      if (deleet.contains(word) && !lower.contains(word)) {
        score--;
        break;
      }
    }

    if (score <= 2) return PasswordStrength.veryWeak;
    if (score <= 4) return PasswordStrength.weak;
    if (score <= 6) return PasswordStrength.fair;
    if (score <= 8) return PasswordStrength.strong;
    return PasswordStrength.veryStrong;
  }

  /// よく使われるパスワード（トップ100から抜粋）
  static const _commonPasswords = {
    'password', 'password1', 'password123', '123456', '12345678',
    '123456789', '1234567890', 'qwerty', 'abc123', 'monkey',
    'master', 'dragon', 'login', 'princess', 'football',
    'shadow', 'sunshine', 'trustno1', 'iloveyou', 'batman',
    'access', 'hello', 'charlie', 'donald', 'passw0rd',
    'qwerty123', 'letmein', 'welcome', 'admin', 'starwars',
    'baseball', 'superman', 'michael', 'ashley', 'jessica',
    'mustang', 'ninja', 'test', 'pass', 'abcdef',
    '111111', '000000', '666666', '121212', '654321',
    'password!', 'changeme', 'secret', 'love', 'money',
  };

  /// よく使われるパターン（キーボード配列等）
  static const _commonPatterns = [
    'qwerty', 'qwertz', 'azerty', 'asdf', 'zxcv',
    'qazwsx', '1qaz2wsx', 'aaa', 'abcabc', '1q2w3e',
    'passwd', 'pass1234', 'admin123', 'root',
  ];

  /// 辞書単語（頻出の英単語、4文字以上のみ）
  static const _dictionaryWords = [
    'password', 'dragon', 'master', 'monkey', 'shadow',
    'sunshine', 'princess', 'football', 'baseball', 'superman',
    'batman', 'login', 'welcome', 'hello', 'charlie',
    'love', 'summer', 'winter', 'spring', 'autumn',
    'orange', 'banana', 'apple', 'purple', 'green',
    'black', 'white', 'house', 'sport', 'magic',
    'music', 'movie', 'power', 'super', 'happy',
    'lucky', 'trust', 'freedom', 'private', 'secret',
    'computer', 'internet', 'server', 'system', 'access',
    'admin', 'user', 'guest', 'test', 'demo',
  ];

  /// 除外文字を適用した文字列を返す
  String _filterChars(String source, String exclude) {
    if (exclude.isEmpty) return source;
    return source.split('').where((c) => !exclude.contains(c)).join();
  }

  /// 簡易単語リスト（パスフレーズ用）
  /// 本番では EFF Diceware の完全リスト（7776語）に置き換え予定
  static const _basicWordList = [
    'apple', 'brave', 'cloud', 'dance', 'eagle', 'flame', 'glass',
    'heart', 'ivory', 'jewel', 'karma', 'light', 'maple', 'noble',
    'ocean', 'piano', 'quest', 'river', 'storm', 'tiger', 'unity',
    'vivid', 'water', 'xenon', 'youth', 'zebra', 'amber', 'blade',
    'coral', 'delta', 'ember', 'frost', 'grove', 'haven', 'index',
    'lunar', 'magic', 'north', 'orbit', 'pixel', 'quilt', 'ridge',
    'solar', 'trail', 'ultra', 'vapor', 'wheat', 'atlas', 'bloom',
    'cedar', 'drift', 'epoch', 'forge', 'grain', 'haste', 'ionic',
    'lotus', 'metro', 'nexus', 'omega', 'prism', 'quota', 'reign',
    'slate', 'thorn', 'umbra', 'voice', 'wren', 'azure', 'birch',
    'crest', 'dusk', 'fable', 'glyph', 'halo', 'jade', 'knack',
    'lemon', 'marsh', 'niche', 'olive', 'plume', 'ruby', 'sage',
    'tide', 'urban', 'vault', 'waltz', 'yarn', 'zeal', 'arch',
    'bolt', 'cape', 'dove', 'echo', 'fern', 'gust', 'haze',
  ];
}

/// Kuraudo Autofill サービス
/// 
/// Android Autofill Service API 連携の基盤
/// Windows/Linux ではキーボードショートカットでクリップボード経由
library;

import 'dart:io';

import 'package:flutter/services.dart';
import '../models/vault_entry.dart';

/// クリップボード完全クリア
/// 
/// Linux: Wayland(wl-copy --clear) / X11(xclip, xsel) を自動検出して使用
/// Android 9+: ClipboardManager.clearPrimaryClip()
///   ※ Gboard等のキーボードアプリ独自の履歴はOS制限で消去不可
///   ※ Android 13+: EXTRA_IS_SENSITIVE で履歴保存自体を防止（copyToClipboardSensitiveで対応）
/// Windows: PowerShell でクリア
Future<void> clearClipboardFully() async {
  if (Platform.isAndroid) {
    try {
      const channel = MethodChannel('com.zerotoship.kuraudo/autofill');
      await channel.invokeMethod('clearClipboard');
      return;
    } catch (_) {}
  } else if (Platform.isLinux) {
    await _clearClipboardLinux();
    return;
  } else if (Platform.isWindows) {
    try {
      await Process.run('powershell', ['-command',
        'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::Clear()']);
      return;
    } catch (_) {}
  }
  // フォールバック
  await Clipboard.setData(const ClipboardData(text: ''));
}

/// Linux: Wayland / X11 / XWayland を自動検出してクリップボードをクリア
///
/// クリップボード履歴マネージャーへの対策:
/// - KDE Klipper: クリップボードの所有権を放棄するとKlipperが空エントリとして認識
/// - GNOME Clipboard History等: 空文字セットで上書き
/// - PRIMARY / CLIPBOARD / SECONDARY の3つのセレクション全てをクリア
Future<void> _clearClipboardLinux() async {
  final isWayland = Platform.environment['XDG_SESSION_TYPE'] == 'wayland' ||
      Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty == true;

  if (isWayland) {
    // Wayland: wl-copy --clear（wl-clipboardパッケージ）
    try {
      final result = await Process.run('wl-copy', ['--clear']);
      if (result.exitCode == 0) return;
    } catch (_) {}
    // wl-copy がない場合: 空文字を渡す
    try {
      final process = await Process.start('wl-copy', ['--clear']);
      await process.exitCode;
      return;
    } catch (_) {}
  }

  // X11 または Waylandフォールバック（XWayland経由でxclipが使えるケースもある）
  // xsel（--delete はセレクション所有権を放棄する = より確実なクリア）
  try {
    await Process.run('xsel', ['--clipboard', '--delete']);
    await Process.run('xsel', ['--primary', '--delete']);
    return;
  } catch (_) {}

  // xclip（空文字をセット）
  try {
    // 空文字をstdinから流し込む
    var process = await Process.start('xclip', ['-selection', 'clipboard']);
    process.stdin.write('');
    await process.stdin.close();
    await process.exitCode;

    process = await Process.start('xclip', ['-selection', 'primary']);
    process.stdin.write('');
    await process.stdin.close();
    await process.exitCode;
    return;
  } catch (_) {}

  // 全て失敗した場合のフォールバック
  await Clipboard.setData(const ClipboardData(text: ''));
}

/// クリップボードにコピー（クリップボード履歴への保存を防止）
/// 
/// Android 13+: ClipDescription.EXTRA_IS_SENSITIVE で
/// キーボードアプリの履歴保存を防止
/// Linux (KDE Klipper): xdotool type で直接入力（クリップボードを経由しない）
///   クリップボードコピー時は xclip + x-kde-passwordManagerHint で履歴防止
/// Linux (GNOME等): タイムアウトクリアで対応
Future<void> copyToClipboardSensitive(String text) async {
  if (Platform.isAndroid) {
    try {
      const channel = MethodChannel('com.zerotoship.kuraudo/autofill');
      await channel.invokeMethod('copyWithSensitiveFlag', {'text': text});
      return;
    } catch (_) {}
  } else if (Platform.isLinux) {
    // xclip があればそちらを使用（Flutter APIはクリップボードマネージャーに検知されやすい）
    final copied = await _copyToClipboardLinux(text);
    if (copied) return;
  }
  await Clipboard.setData(ClipboardData(text: text));
}

/// Linux: クリップボードにコピー（外部コマンド経由）
/// 
/// xclip / wl-copy で直接コピーすることで、Flutterの標準APIよりも
/// クリップボードマネージャーとの互換性が向上する。
/// ただし x-kde-passwordManagerHint の付与はxclipの制約上困難なため、
/// タイムアウトクリアと併用で対応する。
Future<bool> _copyToClipboardLinux(String text) async {
  final isWayland = Platform.environment['XDG_SESSION_TYPE'] == 'wayland' ||
      Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty == true;

  if (isWayland) {
    try {
      // wl-copy: Waylandネイティブのクリップボードコマンド
      final process = await Process.start('wl-copy', []);
      process.stdin.write(text);
      await process.stdin.close();
      final exitCode = await process.exitCode;
      if (exitCode == 0) return true;
    } catch (_) {}
  }

  // X11: xclip
  try {
    final process = await Process.start(
      'xclip', ['-selection', 'clipboard'],
    );
    process.stdin.write(text);
    await process.stdin.close();
    final exitCode = await process.exitCode;
    if (exitCode == 0) return true;
  } catch (_) {}

  // xsel
  try {
    final process = await Process.start(
      'xsel', ['--clipboard', '--input'],
    );
    process.stdin.write(text);
    await process.stdin.close();
    final exitCode = await process.exitCode;
    if (exitCode == 0) return true;
  } catch (_) {}

  return false;
}

/// クリップボードにコピーし、指定秒後に完全クリア
Future<void> copyAndScheduleClear(
  String text, {
  int clearAfterSeconds = 30,
  bool autoClearEnabled = true,
}) async {
  // センシティブフラグ付きでコピー（Android 13+でキーボード履歴防止）
  await copyToClipboardSensitive(text);
  if (autoClearEnabled && clearAfterSeconds > 0) {
    Future.delayed(Duration(seconds: clearAfterSeconds), () {
      clearClipboardFully();
    });
  }
}

/// Autofill の対象フィールド
enum AutofillField {
  username,
  password,
  email,
}

/// Autofill マッチ結果
class AutofillMatch {
  final VaultEntry entry;
  final double relevance; // 0.0〜1.0

  AutofillMatch({
    required this.entry,
    required this.relevance,
  });
}

/// Autofill サービス
class AutofillService {
  static const _channel = MethodChannel('com.zerotoship.kuraudo/autofill');

  /// URLまたはパッケージ名からマッチするエントリを検索
  /// 
  /// [identifier] URL (ブラウザ) またはパッケージ名 (アプリ)
  /// [entries] 検索対象のエントリ一覧
  List<AutofillMatch> findMatches(String identifier, List<VaultEntry> entries) {
    final matches = <AutofillMatch>[];
    final identifierLower = identifier.toLowerCase();

    // URLからドメインを抽出
    String? domain;
    try {
      final uri = Uri.parse(identifier);
      domain = uri.host.toLowerCase();
      // www. を除去
      if (domain.startsWith('www.')) {
        domain = domain.substring(4);
      }
    } catch (_) {
      domain = identifierLower;
    }

    for (final entry in entries) {
      double relevance = 0.0;

      // URL完全一致
      if (entry.url != null) {
        final entryUrl = entry.url!.toLowerCase();
        try {
          final entryDomain = Uri.parse(entryUrl).host.toLowerCase()
              .replaceFirst(RegExp(r'^www\.'), '');
          if (domain == entryDomain) {
            relevance = 1.0;
          } else if (domain != null && entryDomain.contains(domain)) {
            relevance = 0.8;
          } else if (domain != null && domain.contains(entryDomain)) {
            relevance = 0.7;
          }
        } catch (_) {
          if (entryUrl.contains(identifierLower)) {
            relevance = 0.6;
          }
        }
      }

      // タイトルにドメインが含まれる
      if (relevance == 0.0 && domain != null) {
        final titleLower = entry.title.toLowerCase();
        // ドメインのメイン部分（例: google.com → google）
        final mainDomain = domain.split('.').first;
        if (titleLower.contains(mainDomain)) {
          relevance = 0.5;
        }
      }

      if (relevance > 0.0) {
        matches.add(AutofillMatch(entry: entry, relevance: relevance));
      }
    }

    // 関連度順にソート
    matches.sort((a, b) => b.relevance.compareTo(a.relevance));
    return matches;
  }

  /// クリップボードにコピーし、一定時間後にクリア
  /// 
  /// [text] コピーするテキスト
  /// [clearAfterSeconds] 自動クリアまでの秒数（0で無効化）
  Future<void> copyToClipboard(
    String text, {
    int clearAfterSeconds = 30,
  }) async {
    // 共通関数を使用（センシティブフラグ + 自動クリア）
    await copyAndScheduleClear(
      text,
      clearAfterSeconds: clearAfterSeconds,
      autoClearEnabled: clearAfterSeconds > 0,
    );
  }

  /// Android: Autofill Service として登録されているか確認
  Future<bool> isAutofillServiceEnabled() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isAutofillEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android: Autofill Service 設定画面を開く
  Future<void> openAutofillSettings() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('openAutofillSettings');
    } catch (_) {
      // 設定画面を開けない場合は無視
    }
  }

  /// Android: ネイティブ側のAutofillキャッシュにエントリを送信
  /// 
  /// Vault解錠時やエントリ更新時に呼び出して、
  /// AutofillServiceがフォームマッチングに使用するデータを最新化する。
  Future<void> updateNativeCache(List<VaultEntry> entries) async {
    if (!Platform.isAndroid) return;

    try {
      final data = entries.map((e) => {
        'uuid': e.uuid,
        'title': e.title,
        'username': e.username,
        'password': e.password,
        'email': e.email ?? '',
        'url': e.url ?? '',
      }).toList();
      await _channel.invokeMethod('updateEntries', {'entries': data});
    } catch (_) {
      // 失敗しても無視（Autofill非対応端末等）
    }
  }

  /// Windows/Linux: グローバルホットキーの登録
  /// 
  /// ※ 実際のグローバルホットキーはプラットフォーム固有のプラグインが必要
  /// ここではキーバインド定義のみ
  static const String defaultHotkey = 'Ctrl+Alt+K';

  /// デスクトップ向け自動入力（クリップボード経由）
  /// 
  /// 1. ユーザー名をクリップボードにコピー → Ctrl+V相当のペースト
  /// 2. Tab キー送信
  /// 3. パスワードをクリップボードにコピー → Ctrl+V相当のペースト
  /// 4. 30秒後にクリップボードクリア
  /// 
  /// Windows/Linux共通でProcess.runを使ってキーストロークを送信
  Future<AutoTypeResult> autoType(VaultEntry entry) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return AutoTypeResult(success: false, message: 'モバイルではAutofill Serviceを使用してください');
    }

    try {
      if (Platform.isLinux) {
        return await _autoTypeLinux(entry);
      } else if (Platform.isWindows) {
        return await _autoTypeWindows(entry);
      }
      return AutoTypeResult(success: false, message: 'このプラットフォームは未対応です');
    } catch (e) {
      return AutoTypeResult(success: false, message: '自動入力に失敗: $e');
    }
  }

  /// Linux: xdotool を使用した自動入力
  Future<AutoTypeResult> _autoTypeLinux(VaultEntry entry) async {
    // xdotool が利用可能か確認
    final which = await Process.run('which', ['xdotool']);
    if (which.exitCode != 0) {
      // xdotool がない場合はクリップボードフォールバック
      return await _clipboardFallback(entry);
    }

    // 少し待ってからフォーカスを元ウィンドウに戻す
    await Future.delayed(const Duration(milliseconds: 300));

    // ユーザー名を入力
    if (entry.username.isNotEmpty) {
      await Process.run('xdotool', ['type', '--clearmodifiers', '--delay', '12', entry.username]);
      await Future.delayed(const Duration(milliseconds: 50));
      // Tab で次のフィールドへ
      await Process.run('xdotool', ['key', 'Tab']);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // パスワードを入力
    await Process.run('xdotool', ['type', '--clearmodifiers', '--delay', '12', entry.password]);

    return AutoTypeResult(success: true, message: '自動入力が完了しました');
  }

  /// Windows: PowerShell SendKeys を使用した自動入力
  Future<AutoTypeResult> _autoTypeWindows(VaultEntry entry) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));

      if (entry.username.isNotEmpty) {
        // ユーザー名をクリップボードにコピーしてペースト
        await copyToClipboardSensitive(entry.username);
        await Process.run('powershell', ['-command',
          'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("^v"); Start-Sleep -Milliseconds 100; [System.Windows.Forms.SendKeys]::SendWait("{TAB}")'
        ]);
        await Future.delayed(const Duration(milliseconds: 150));
      }

      // パスワードをクリップボードにコピーしてペースト
      await copyToClipboardSensitive(entry.password);
      await Process.run('powershell', ['-command',
        'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("^v")'
      ]);

      // 30秒後にクリップボードクリア
      Future.delayed(const Duration(seconds: 30), () {
        clearClipboardFully();
      });

      return AutoTypeResult(success: true, message: '自動入力が完了しました');
    } catch (e) {
      return await _clipboardFallback(entry);
    }
  }

  /// フォールバック: クリップボードに順番コピー
  Future<AutoTypeResult> _clipboardFallback(VaultEntry entry) async {
    await copyToClipboard(entry.username, clearAfterSeconds: 0);
    await Future.delayed(const Duration(milliseconds: 100));
    await copyToClipboard(entry.password);
    return AutoTypeResult(
      success: true,
      message: 'ユーザー名→パスワードの順でクリップボードにコピーしました\n'
          'Linux: sudo pacman -S xdotool で完全な自動入力が利用可能になります',
    );
  }
}

/// 自動入力の結果
class AutoTypeResult {
  final bool success;
  final String message;

  AutoTypeResult({required this.success, required this.message});
}

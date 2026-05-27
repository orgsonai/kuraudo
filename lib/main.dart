import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services/vault_service.dart';
import 'services/google_drive_service.dart';
import 'services/sync_backend.dart';
import 'services/local_path_backend.dart';
import 'services/webdav_backend.dart';
import 'services/sync_manager.dart';
import 'services/autofill_service.dart';
import 'ui/theme/kuraudo_theme.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KuraudoApp());
}

class KuraudoApp extends StatefulWidget {
  const KuraudoApp({super.key});

  static _KuraudoAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_KuraudoAppState>();

  @override
  State<KuraudoApp> createState() => _KuraudoAppState();
}

class _KuraudoAppState extends State<KuraudoApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kuraudo',
      debugShowCheckedModeBanner: false,
      theme: KuraudoTheme.light,
      darkTheme: KuraudoTheme.dark,
      themeMode: _themeMode,
      home: const KuraudoRoot(),
    );
  }
}

class KuraudoRoot extends StatefulWidget {
  const KuraudoRoot({super.key});
  @override
  State<KuraudoRoot> createState() => _KuraudoRootState();
}

class _KuraudoRootState extends State<KuraudoRoot> with WidgetsBindingObserver {
  final VaultService _vaultService = VaultService();

  // 利用可能な全バックエンド（必要な時にインスタンス生成、ここでは事前確保）
  final GoogleDriveService _googleDriveBackend = GoogleDriveService();
  final WebDAVBackend _webdavBackend = WebDAVBackend();
  final LocalPathBackend _localPathBackend = LocalPathBackend();

  /// 現在選択されている同期方式
  SyncBackendKind _backendKind = SyncBackendKind.googleDrive;

  /// 現在のバックエンド実体
  SyncBackend get _currentBackend {
    switch (_backendKind) {
      case SyncBackendKind.googleDrive: return _googleDriveBackend;
      case SyncBackendKind.webdav: return _webdavBackend;
      case SyncBackendKind.localPath: return _localPathBackend;
    }
  }

  late final SyncManager _syncManager;

  bool _isLoading = true;
  bool _isNewVault = false;
  String? _lastVaultPath;

  // 自動ロック
  DateTime? _lastActiveTime;
  DateTime? _lastInteractionTime;  // 最終操作時刻（フォアグラウンド用）
  int _autoLockMinutes = 5;
  int _passwordExpiryDays = 90;
  String _themeModeStr = 'dark';
  bool _autoSyncEnabled = true;
  bool _realtimeSyncEnabled = true;
  bool _clipboardAutoClear = true; // クリップボード自動クリア

  // PIN/生体認証
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  int _pinThresholdMinutes = 5; // この時間以内ならPIN/生体で解除可
  bool _pinLockoutPersistent = false; // H-02: PIN試行回数の永続化（任意適用）
  bool _quickLocked = false;    // true=短時間ロック（PIN可）, false=通常ロック（マスターPW必須）
  final _secureStorage = const FlutterSecureStorage();

  // フォアグラウンド無操作監視用タイマー（30秒ごとに_checkAutoLockを呼ぶ）
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncManager = SyncManager(vaultService: _vaultService, backend: _currentBackend);
    // 保存時コールバック: リアルタイム同期 + Autofillキャッシュ更新
    _vaultService.onSaved = () {
      if (_autoSyncEnabled && _realtimeSyncEnabled) {
        _syncManager.onVaultSaved();
      }
      _updateAutofillCache();
    };
    // M-04: ロック時コールバック: Android Autofillネイティブキャッシュをクリア
    // ロック中はパスワード平文がネイティブメモリに残らない
    _vaultService.onLocked = () {
      AutofillService().clearNativeCache();
    };
    _loadSettings();
    _startIdleTimer();
  }

  // ── フォアグラウンド無操作監視 ──
  // 定期的に_checkAutoLock()を呼び、設定されたタイムアウトを超えていたらロックする。
  // 周期は自動ロック設定に応じて調整（1分設定なら10秒、それ以上なら30秒）。
  void _startIdleTimer() {
    _idleTimer?.cancel();
    // 自動ロック無効・即時ロックはタイマー不要
    if (_autoLockMinutes <= 0) return;
    final periodSec = _autoLockMinutes == 1 ? 10 : 30;
    _idleTimer = Timer.periodic(Duration(seconds: periodSec), (_) {
      if (!mounted) return;
      _checkAutoLock();
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // バックグラウンドに移行した時刻を記録
      _lastActiveTime ??= DateTime.now();
      // セキュリティ: バックグラウンド移行時にクリップボードをクリア
      if (_clipboardAutoClear) _clearClipboardIfSensitive();
    } else if (state == AppLifecycleState.inactive) {
      // inactive（通知バーを引き下げた等）でも記録
      _lastActiveTime ??= DateTime.now();
    } else if (state == AppLifecycleState.detached) {
      // アプリ終了時にクリップボードをクリア
      if (_clipboardAutoClear) clearClipboardFully();
      // M-04: アプリ終了時にAutofillネイティブキャッシュもクリア
      // プロセスが残るケース（OSがプロセスを保持する場合）に備える
      AutofillService().clearNativeCache();
    } else if (state == AppLifecycleState.resumed) {
      _checkAutoLock();
      // フォアグラウンドに戻ったら操作時刻をリセット
      _lastInteractionTime = DateTime.now();
    }
  }

  /// クリップボードにパスワード等のセンシティブデータがある場合クリア
  void _clearClipboardIfSensitive() {
    if (_vaultService.state == VaultState.unlocked) {
      clearClipboardFully();
    }
  }

  void _checkAutoLock() {
    if (_autoLockMinutes == 0 || _vaultService.state != VaultState.unlocked) {
      _lastActiveTime = null;
      return;
    }
    // すでに画面ロック中なら何もしない（ロック画面でタイマーが走り続けるのを防ぐ）
    if (_quickLocked) return;

    bool shouldLock = false;
    int elapsedSeconds = 0;

    // 即時ロック（-1）の場合はバックグラウンド復帰時に常にロック
    if (_autoLockMinutes < 0) {
      if (_lastActiveTime != null) {
        elapsedSeconds = DateTime.now().difference(_lastActiveTime!).inSeconds;
        shouldLock = true;
      }
      _lastActiveTime = null;
    }
    // バックグラウンド経過時間チェック
    else if (_lastActiveTime != null) {
      elapsedSeconds = DateTime.now().difference(_lastActiveTime!).inSeconds;
      if (elapsedSeconds >= _autoLockMinutes * 60) {
        shouldLock = true;
      }
      _lastActiveTime = null;
    }
    // フォアグラウンドでの無操作時間チェック
    else if (_lastInteractionTime != null) {
      elapsedSeconds = DateTime.now().difference(_lastInteractionTime!).inSeconds;
      if (elapsedSeconds >= _autoLockMinutes * 60) {
        shouldLock = true;
      }
    }

    if (!shouldLock) return;

    // PIN/生体認証が有効かつ閾値以内 → 画面ロックのみ（Vault暗号化しない）
    final canQuickUnlock = (_pinEnabled || _biometricEnabled) &&
        (_autoLockMinutes < 0 || elapsedSeconds < _pinThresholdMinutes * 60);
    if (canQuickUnlock) {
      _quickLocked = true;
      _popAllChildRoutes();
      setState(() {});
    } else {
      // 長時間 or PIN/生体無効 → 完全ロック
      _quickLocked = false;
      _vaultService.lock();
      _popAllChildRoutes();
      setState(() {});
    }
  }

  /// ロック発動時に、上に積まれている子画面（設定・エントリ詳細など）を全てpopして
  /// ロック画面が確実に最前面になるようにする
  void _popAllChildRoutes() {
    if (!mounted) return;
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null) return;
    // 最下層（MaterialApp.home）だけ残して全てpop
    navigator.popUntil((route) => route.isFirst);
  }

  /// フォアグラウンド操作検知用（HomeScreenから呼ばれる）
  void resetInteractionTime() {
    _lastInteractionTime = DateTime.now();
  }

  /// SecureStorageに保存するキー: 最後に使ったVaultのフルパス
  static const String _kVaultPathKey = 'vault_path';

  /// M-01: セキュリティ重要設定の SecureStorage キー（プレフィックス kuraudo_sec_）
  ///
  /// これらは値を改ざんされると自動ロックや PIN 認証が無効化されるため、
  /// OS のキーストア（Android Keystore / Linux Secret Service /
  /// Windows Credential Manager）経由で保護する。
  ///
  /// 非セキュリティ設定（themeMode, syncBackend 等）は従来通り
  /// kuraudo_settings.json に平文 JSON 保存する。
  static const String _kSecAutoLockMinutes = 'kuraudo_sec_auto_lock_minutes';
  static const String _kSecClipboardAutoClear = 'kuraudo_sec_clipboard_auto_clear';
  static const String _kSecPinEnabled = 'kuraudo_sec_pin_enabled';
  static const String _kSecBiometricEnabled = 'kuraudo_sec_biometric_enabled';
  static const String _kSecPinThresholdMinutes = 'kuraudo_sec_pin_threshold_minutes';
  static const String _kSecPinLockoutPersistent = 'kuraudo_sec_pin_lockout_persistent';
  /// マイグレーション済みフラグ（旧 JSON から SecureStorage への移行が完了したか）
  static const String _kSecMigrationDone = 'kuraudo_sec_migration_v1_done';

  /// 設定ファイルのパスを取得（Vaultと同じフォルダの kuraudo_settings.json）
  /// Vaultパスが未確定の場合は null を返す
  String? get _settingsPath {
    if (_lastVaultPath == null) return null;
    final dir = File(_lastVaultPath!).parent.path;
    return '$dir${Platform.pathSeparator}kuraudo_settings.json';
  }

  Future<void> _loadSettings() async {
    // 1. SecureStorageから前回のVaultパスを取得
    try {
      _lastVaultPath = await _secureStorage.read(key: _kVaultPathKey);
    } catch (_) {}

    // 2. Vaultフォルダの設定ファイル（非セキュリティ項目）を読み込み
    final settingsPath = _settingsPath;
    Map<String, dynamic> jsonSettings = {};
    if (settingsPath != null) {
      try {
        final file = File(settingsPath);
        if (await file.exists()) {
          jsonSettings = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        }
      } catch (_) {}
    }

    // 3. 非セキュリティ項目を平文 JSON から読み込み
    _passwordExpiryDays = jsonSettings['passwordExpiryDays'] as int? ?? 90;
    _themeModeStr = jsonSettings['themeMode'] as String? ?? 'dark';
    _autoSyncEnabled = jsonSettings['autoSyncEnabled'] as bool? ?? true;
    _realtimeSyncEnabled = jsonSettings['realtimeSyncEnabled'] as bool? ?? true;
    final backendId = jsonSettings['syncBackend'] as String? ?? 'gdrive';
    _backendKind = _parseBackendKind(backendId);
    _syncManager.setBackend(_currentBackend);

    // 4. M-01: セキュリティ重要項目を SecureStorage から読み込み
    //    マイグレーション未実施なら旧 JSON から移行する
    await _loadSecuritySettings(jsonSettings);

    _applyThemeMode();

    // 5. 起動時のVault状態判定
    if (_lastVaultPath != null && await File(_lastVaultPath!).exists()) {
      setState(() { _isNewVault = false; _isLoading = false; });
    } else {
      // Vaultが未指定 or ファイルが消えている → 新規作成扱い
      _lastVaultPath = null;
      setState(() { _isNewVault = true; _isLoading = false; });
    }
    // 保存済み設定でタイマーを再起動（周期調整のため）
    _startIdleTimer();
  }

  /// M-01: セキュリティ重要設定を SecureStorage から読み込む
  ///
  /// マイグレーション未実施の場合（旧バージョンからのアップデート）、
  /// 旧 JSON [legacyJson] の値を SecureStorage に書き出してから完了フラグを立てる。
  /// それ以降は SecureStorage のみが信頼できるソースとなる。
  ///
  /// SecureStorage 読み込み失敗時は安全側の既定値を採用（ロックは有効、PINは無効など）。
  Future<void> _loadSecuritySettings(Map<String, dynamic> legacyJson) async {
    try {
      final migrated = await _secureStorage.read(key: _kSecMigrationDone);
      if (migrated != 'true') {
        // 初回マイグレーション: 旧 JSON 値を SecureStorage へ移行
        await _migrateSecuritySettings(legacyJson);
      }

      // SecureStorage から読み込み（マイグレーション後はこれが信頼できるソース）
      _autoLockMinutes = int.tryParse(
        await _secureStorage.read(key: _kSecAutoLockMinutes) ?? '',
      ) ?? 5;
      _clipboardAutoClear = (await _secureStorage.read(key: _kSecClipboardAutoClear)) != 'false';
      _pinEnabled = (await _secureStorage.read(key: _kSecPinEnabled)) == 'true';
      _biometricEnabled = (await _secureStorage.read(key: _kSecBiometricEnabled)) == 'true';
      _pinThresholdMinutes = int.tryParse(
        await _secureStorage.read(key: _kSecPinThresholdMinutes) ?? '',
      ) ?? 5;
      _pinLockoutPersistent = (await _secureStorage.read(key: _kSecPinLockoutPersistent)) == 'true';
    } catch (_) {
      // SecureStorage 読み込み失敗時は安全側の既定値を採用
      _autoLockMinutes = 5;
      _clipboardAutoClear = true;
      _pinEnabled = false;
      _biometricEnabled = false;
      _pinThresholdMinutes = 5;
      _pinLockoutPersistent = false;
    }
  }

  /// M-01: 旧 kuraudo_settings.json のセキュリティ項目を SecureStorage に移行
  ///
  /// 既存ユーザーのアップデート時に1回だけ実行される。
  /// 旧 JSON ファイルからセキュリティ関連キーを削除し、平文 JSON を再保存する。
  Future<void> _migrateSecuritySettings(Map<String, dynamic> legacyJson) async {
    try {
      // 旧 JSON から値を取り出して SecureStorage へ書き込み
      // 旧キーが無い場合は既定値を書き込む（新規インストール時はこれ）
      await _secureStorage.write(
        key: _kSecAutoLockMinutes,
        value: (legacyJson['autoLockMinutes'] as int? ?? 5).toString(),
      );
      await _secureStorage.write(
        key: _kSecClipboardAutoClear,
        value: (legacyJson['clipboardAutoClear'] as bool? ?? true).toString(),
      );
      await _secureStorage.write(
        key: _kSecPinEnabled,
        value: (legacyJson['pinEnabled'] as bool? ?? false).toString(),
      );
      await _secureStorage.write(
        key: _kSecBiometricEnabled,
        value: (legacyJson['biometricEnabled'] as bool? ?? false).toString(),
      );
      await _secureStorage.write(
        key: _kSecPinThresholdMinutes,
        value: (legacyJson['pinThresholdMinutes'] as int? ?? 5).toString(),
      );
      await _secureStorage.write(
        key: _kSecPinLockoutPersistent,
        value: (legacyJson['pinLockoutPersistent'] as bool? ?? false).toString(),
      );

      // 完了フラグ
      await _secureStorage.write(key: _kSecMigrationDone, value: 'true');

      // 旧 JSON ファイルからセキュリティ項目を削除
      // （平文ファイルに残っていると改ざんの誘因になるため）
      final settingsPath = _settingsPath;
      if (settingsPath != null) {
        try {
          final file = File(settingsPath);
          if (await file.exists()) {
            final cleaned = Map<String, dynamic>.from(legacyJson);
            cleaned.remove('autoLockMinutes');
            cleaned.remove('clipboardAutoClear');
            cleaned.remove('pinEnabled');
            cleaned.remove('biometricEnabled');
            cleaned.remove('pinThresholdMinutes');
            cleaned.remove('pinLockoutPersistent');
            await file.writeAsString(jsonEncode(cleaned));
          }
        } catch (_) {}
      }
    } catch (_) {
      // マイグレーション失敗時はフラグを立てない（次回起動時に再試行）
    }
  }

  /// M-01: 非セキュリティ設定を平文 JSON に保存
  ///
  /// セキュリティ重要項目（autoLockMinutes 等）は _saveSecuritySetting() で
  /// SecureStorage へ保存されるため、ここには含めない。
  Future<void> _saveSettings() async {
    final settingsPath = _settingsPath;
    if (settingsPath == null) return; // Vault未指定なら保存先がないのでスキップ
    try {
      final file = File(settingsPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'passwordExpiryDays': _passwordExpiryDays,
        'themeMode': _themeModeStr,
        'autoSyncEnabled': _autoSyncEnabled,
        'realtimeSyncEnabled': _realtimeSyncEnabled,
        'syncBackend': _backendIdOf(_backendKind),
      }));
    } catch (_) {}
  }

  /// M-01: 単一のセキュリティ設定を SecureStorage に保存
  ///
  /// [key] は _kSec* のいずれか。値は文字列化して書き込む。
  /// SecureStorage 書き込み失敗時は静かに無視する（次回操作で再試行される）。
  Future<void> _saveSecuritySetting(String key, dynamic value) async {
    try {
      await _secureStorage.write(key: key, value: value.toString());
    } catch (_) {}
  }

  /// バックエンドID文字列 ↔ enum の変換
  static SyncBackendKind _parseBackendKind(String id) {
    switch (id) {
      case 'webdav': return SyncBackendKind.webdav;
      case 'local': return SyncBackendKind.localPath;
      case 'gdrive':
      default: return SyncBackendKind.googleDrive;
    }
  }

  static String _backendIdOf(SyncBackendKind kind) {
    switch (kind) {
      case SyncBackendKind.googleDrive: return 'gdrive';
      case SyncBackendKind.webdav: return 'webdav';
      case SyncBackendKind.localPath: return 'local';
    }
  }

  /// バックエンド変更時のハンドラ（設定画面から呼ばれる）
  void _onBackendChanged(SyncBackendKind kind) {
    setState(() {
      _backendKind = kind;
      _syncManager.setBackend(_currentBackend);
    });
    _saveSettings();
  }

  void _onUnlocked() {
    _quickLocked = false;
    setState(() {});
    if (_autoSyncEnabled) _syncManager.autoSync();
    _lastActiveTime = null;
    _lastInteractionTime = DateTime.now();
    // Android Autofill キャッシュを更新
    _updateAutofillCache();
  }

  void _updateAutofillCache() {
    final entries = _vaultService.vault?.activeEntries;
    if (entries != null && entries.isNotEmpty) {
      AutofillService().updateNativeCache(entries);
    }
  }

  Future<void> _onVaultPathChanged(String path) async {
    _lastVaultPath = path;
    // SecureStorageに永続化（次回起動時にこのVaultを開く）
    try {
      await _secureStorage.write(key: _kVaultPathKey, value: path);
    } catch (_) {}
    // 新しいVaultフォルダに設定ファイルを作成/更新
    await _saveSettings();
  }

  void _applyThemeMode() {
    final app = KuraudoApp.of(context);
    if (app == null) return;
    switch (_themeModeStr) {
      case 'light': app.setThemeMode(ThemeMode.light);
      case 'system': app.setThemeMode(ThemeMode.system);
      default: app.setThemeMode(ThemeMode.dark);
    }
  }

  void _onThemeModeChanged(String mode) {
    _themeModeStr = mode;
    _applyThemeMode();
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: KuraudoTheme.accent)));
    }

    if (_vaultService.state == VaultState.unlocked && !_quickLocked) {
      return HomeScreen(
        vaultService: _vaultService,
        backend: _currentBackend,
        backendKind: _backendKind,
        googleDriveBackend: _googleDriveBackend,
        webdavBackend: _webdavBackend,
        localPathBackend: _localPathBackend,
        onBackendChanged: _onBackendChanged,
        syncManager: _syncManager,
        onLock: () => setState(() {}),
        onInteraction: resetInteractionTime,
        autoLockMinutes: _autoLockMinutes,
        passwordExpiryDays: _passwordExpiryDays,
        // M-01: autoLockMinutes はセキュリティ重要 → SecureStorage に保存
        onAutoLockChanged: (v) {
          _autoLockMinutes = v;
          _saveSecuritySetting(_kSecAutoLockMinutes, v);
          _startIdleTimer();
        },
        onPasswordExpiryChanged: (v) { _passwordExpiryDays = v; _saveSettings(); },
        themeMode: _themeModeStr,
        onThemeModeChanged: _onThemeModeChanged,
        autoSyncEnabled: _autoSyncEnabled,
        realtimeSyncEnabled: _realtimeSyncEnabled,
        onAutoSyncChanged: (v) { _autoSyncEnabled = v; _saveSettings(); },
        onRealtimeSyncChanged: (v) { _realtimeSyncEnabled = v; _saveSettings(); },
        clipboardAutoClear: _clipboardAutoClear,
        // M-01: clipboardAutoClear はセキュリティ重要 → SecureStorage に保存
        onClipboardAutoClearChanged: (v) {
          _clipboardAutoClear = v;
          _saveSecuritySetting(_kSecClipboardAutoClear, v);
        },
        pinEnabled: _pinEnabled,
        biometricEnabled: _biometricEnabled,
        pinThresholdMinutes: _pinThresholdMinutes,
        // M-01: PIN/生体認証関連はすべてセキュリティ重要 → SecureStorage に保存
        onPinEnabledChanged: (v) {
          _pinEnabled = v;
          _saveSecuritySetting(_kSecPinEnabled, v);
        },
        onBiometricEnabledChanged: (v) {
          _biometricEnabled = v;
          _saveSecuritySetting(_kSecBiometricEnabled, v);
        },
        onPinThresholdChanged: (v) {
          _pinThresholdMinutes = v;
          _saveSecuritySetting(_kSecPinThresholdMinutes, v);
        },
        pinLockoutPersistent: _pinLockoutPersistent,
        onPinLockoutPersistentChanged: (v) {
          _pinLockoutPersistent = v;
          _saveSecuritySetting(_kSecPinLockoutPersistent, v);
        },
        secureStorage: _secureStorage,
      );
    }

    return LockScreen(
      vaultService: _vaultService,
      isNewVault: _isNewVault,
      lastVaultPath: _lastVaultPath,
      onUnlocked: _onUnlocked,
      onVaultPathChanged: _onVaultPathChanged,
      onSwitchToNew: () => setState(() => _isNewVault = true),
      onSwitchToExisting: () => setState(() => _isNewVault = false),
      quickLocked: _quickLocked,
      pinEnabled: _pinEnabled,
      biometricEnabled: _biometricEnabled,
      pinLockoutPersistent: _pinLockoutPersistent,
      secureStorage: _secureStorage,
      onQuickUnlocked: () {
        // PIN/生体認証で解除成功 → 前回のVaultを再アンロック
        _quickLocked = false;
        _onUnlocked();
      },
      onForceFullLock: () {
        // quickLock解除→完全ロック画面に遷移
        _quickLocked = false;
        setState(() {});
      },
    );
  }
}

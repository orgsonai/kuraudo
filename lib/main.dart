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

    // 2. Vaultフォルダの設定ファイルから本体設定を読み込み
    final settingsPath = _settingsPath;
    if (settingsPath != null) {
      try {
        final file = File(settingsPath);
        if (await file.exists()) {
          final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          _autoLockMinutes = json['autoLockMinutes'] as int? ?? 5;
          _passwordExpiryDays = json['passwordExpiryDays'] as int? ?? 90;
          _themeModeStr = json['themeMode'] as String? ?? 'dark';
          _autoSyncEnabled = json['autoSyncEnabled'] as bool? ?? true;
          _realtimeSyncEnabled = json['realtimeSyncEnabled'] as bool? ?? true;
          _clipboardAutoClear = json['clipboardAutoClear'] as bool? ?? true;
          _pinEnabled = json['pinEnabled'] as bool? ?? false;
          _biometricEnabled = json['biometricEnabled'] as bool? ?? false;
          _pinThresholdMinutes = json['pinThresholdMinutes'] as int? ?? 5;

          // バックエンド種別をロード
          final backendId = json['syncBackend'] as String? ?? 'gdrive';
          _backendKind = _parseBackendKind(backendId);
          _syncManager.setBackend(_currentBackend);

          _applyThemeMode();
        }
      } catch (_) {}
    }

    // 3. 起動時のVault状態判定
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

  Future<void> _saveSettings() async {
    final settingsPath = _settingsPath;
    if (settingsPath == null) return; // Vault未指定なら保存先がないのでスキップ
    try {
      final file = File(settingsPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'autoLockMinutes': _autoLockMinutes,
        'passwordExpiryDays': _passwordExpiryDays,
        'themeMode': _themeModeStr,
        'autoSyncEnabled': _autoSyncEnabled,
        'realtimeSyncEnabled': _realtimeSyncEnabled,
        'clipboardAutoClear': _clipboardAutoClear,
        'pinEnabled': _pinEnabled,
        'biometricEnabled': _biometricEnabled,
        'pinThresholdMinutes': _pinThresholdMinutes,
        'syncBackend': _backendIdOf(_backendKind),
      }));
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
        onAutoLockChanged: (v) { _autoLockMinutes = v; _saveSettings(); _startIdleTimer(); },
        onPasswordExpiryChanged: (v) { _passwordExpiryDays = v; _saveSettings(); },
        themeMode: _themeModeStr,
        onThemeModeChanged: _onThemeModeChanged,
        autoSyncEnabled: _autoSyncEnabled,
        realtimeSyncEnabled: _realtimeSyncEnabled,
        onAutoSyncChanged: (v) { _autoSyncEnabled = v; _saveSettings(); },
        onRealtimeSyncChanged: (v) { _realtimeSyncEnabled = v; _saveSettings(); },
        clipboardAutoClear: _clipboardAutoClear,
        onClipboardAutoClearChanged: (v) { _clipboardAutoClear = v; _saveSettings(); },
        pinEnabled: _pinEnabled,
        biometricEnabled: _biometricEnabled,
        pinThresholdMinutes: _pinThresholdMinutes,
        onPinEnabledChanged: (v) { _pinEnabled = v; _saveSettings(); },
        onBiometricEnabledChanged: (v) { _biometricEnabled = v; _saveSettings(); },
        onPinThresholdChanged: (v) { _pinThresholdMinutes = v; _saveSettings(); },
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

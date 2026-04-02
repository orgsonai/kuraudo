import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services/vault_service.dart';
import 'services/google_drive_service.dart';
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
  final GoogleDriveService _driveService = GoogleDriveService();
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

  // PIN/生体認証
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  int _pinThresholdMinutes = 5; // この時間以内ならPIN/生体で解除可
  bool _quickLocked = false;    // true=短時間ロック（PIN可）, false=通常ロック（マスターPW必須）
  final _secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncManager = SyncManager(vaultService: _vaultService, driveService: _driveService);
    // 保存時コールバック: リアルタイム同期 + Autofillキャッシュ更新
    _vaultService.onSaved = () {
      if (_autoSyncEnabled && _realtimeSyncEnabled) {
        _syncManager.onVaultSaved();
      }
      _updateAutofillCache();
    };
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // バックグラウンドに移行した時刻を記録
      _lastActiveTime ??= DateTime.now();
      // セキュリティ: バックグラウンド移行時にクリップボードをクリア
      _clearClipboardIfSensitive();
    } else if (state == AppLifecycleState.inactive) {
      // inactive（通知バーを引き下げた等）でも記録
      _lastActiveTime ??= DateTime.now();
    } else if (state == AppLifecycleState.detached) {
      // アプリ終了時にクリップボードをクリア
      Clipboard.setData(const ClipboardData(text: ''));
    } else if (state == AppLifecycleState.resumed) {
      _checkAutoLock();
      // フォアグラウンドに戻ったら操作時刻をリセット
      _lastInteractionTime = DateTime.now();
    }
  }

  /// クリップボードにパスワード等のセンシティブデータがある場合クリア
  void _clearClipboardIfSensitive() {
    // Vaultがアンロック中の場合のみクリア（ロック中はコピー操作が発生しないため）
    if (_vaultService.state == VaultState.unlocked) {
      Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  void _checkAutoLock() {
    if (_autoLockMinutes == 0 || _vaultService.state != VaultState.unlocked) {
      _lastActiveTime = null;
      return;
    }

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
      setState(() {});
    } else {
      // 長時間 or PIN/生体無効 → 完全ロック
      _quickLocked = false;
      _vaultService.lock();
      setState(() {});
    }
  }

  /// フォアグラウンド操作検知用（HomeScreenから呼ばれる）
  void resetInteractionTime() {
    _lastInteractionTime = DateTime.now();
  }

  Future<String> get _settingsPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/kuraudo_settings.json';
  }

  Future<void> _loadSettings() async {
    try {
      final file = File(await _settingsPath);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _lastVaultPath = json['lastVaultPath'] as String?;
        _autoLockMinutes = json['autoLockMinutes'] as int? ?? 5;
        _passwordExpiryDays = json['passwordExpiryDays'] as int? ?? 90;
        _themeModeStr = json['themeMode'] as String? ?? 'dark';
        _autoSyncEnabled = json['autoSyncEnabled'] as bool? ?? true;
        _realtimeSyncEnabled = json['realtimeSyncEnabled'] as bool? ?? true;
        _pinEnabled = json['pinEnabled'] as bool? ?? false;
        _biometricEnabled = json['biometricEnabled'] as bool? ?? false;
        _pinThresholdMinutes = json['pinThresholdMinutes'] as int? ?? 5;
        _applyThemeMode();
      }
    } catch (_) {}

    if (_lastVaultPath != null && await File(_lastVaultPath!).exists()) {
      setState(() { _isNewVault = false; _isLoading = false; });
    } else {
      final exists = await _vaultService.vaultFileExists();
      setState(() { _isNewVault = !exists; _isLoading = false; });
    }
  }

  Future<void> _saveSettings() async {
    try {
      final file = File(await _settingsPath);
      await file.writeAsString(jsonEncode({
        'lastVaultPath': _lastVaultPath,
        'autoLockMinutes': _autoLockMinutes,
        'passwordExpiryDays': _passwordExpiryDays,
        'themeMode': _themeModeStr,
        'autoSyncEnabled': _autoSyncEnabled,
        'realtimeSyncEnabled': _realtimeSyncEnabled,
        'pinEnabled': _pinEnabled,
        'biometricEnabled': _biometricEnabled,
        'pinThresholdMinutes': _pinThresholdMinutes,
      }));
    } catch (_) {}
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

  void _onVaultPathChanged(String path) {
    _lastVaultPath = path;
    _saveSettings();
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
        driveService: _driveService,
        syncManager: _syncManager,
        onLock: () => setState(() {}),
        onInteraction: resetInteractionTime,
        autoLockMinutes: _autoLockMinutes,
        passwordExpiryDays: _passwordExpiryDays,
        onAutoLockChanged: (v) { _autoLockMinutes = v; _saveSettings(); },
        onPasswordExpiryChanged: (v) { _passwordExpiryDays = v; _saveSettings(); },
        themeMode: _themeModeStr,
        onThemeModeChanged: _onThemeModeChanged,
        autoSyncEnabled: _autoSyncEnabled,
        realtimeSyncEnabled: _realtimeSyncEnabled,
        onAutoSyncChanged: (v) { _autoSyncEnabled = v; _saveSettings(); },
        onRealtimeSyncChanged: (v) { _realtimeSyncEnabled = v; _saveSettings(); },
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

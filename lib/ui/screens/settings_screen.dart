/// Kuraudo 設定画面
/// 
/// マスターパスワード変更、エクスポート、アプリ情報
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../services/csv_importer.dart';
import '../../services/vault_service.dart';
import '../../services/autofill_service.dart';
import '../../models/vault_entry.dart';
import '../theme/kuraudo_theme.dart';

class SettingsScreen extends StatefulWidget {
  final VaultService vaultService;
  final int autoLockMinutes;
  final int passwordExpiryDays;
  final void Function(int) onAutoLockChanged;
  final void Function(int) onPasswordExpiryChanged;
  final String themeMode;
  final void Function(String) onThemeModeChanged;
  final bool autoSyncEnabled;
  final bool realtimeSyncEnabled;
  final void Function(bool) onAutoSyncChanged;
  final void Function(bool) onRealtimeSyncChanged;
  // PIN/生体認証
  final bool pinEnabled;
  final bool biometricEnabled;
  final int pinThresholdMinutes;
  final void Function(bool) onPinEnabledChanged;
  final void Function(bool) onBiometricEnabledChanged;
  final void Function(int) onPinThresholdChanged;
  final FlutterSecureStorage? secureStorage;

  const SettingsScreen({
    super.key,
    required this.vaultService,
    this.autoLockMinutes = 5,
    this.passwordExpiryDays = 90,
    required this.onAutoLockChanged,
    required this.onPasswordExpiryChanged,
    this.themeMode = 'dark',
    required this.onThemeModeChanged,
    this.autoSyncEnabled = true,
    this.realtimeSyncEnabled = true,
    required this.onAutoSyncChanged,
    required this.onRealtimeSyncChanged,
    this.pinEnabled = false,
    this.biometricEnabled = false,
    this.pinThresholdMinutes = 5,
    required this.onPinEnabledChanged,
    required this.onBiometricEnabledChanged,
    required this.onPinThresholdChanged,
    this.secureStorage,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _importer = CsvImporter();
  final _localAuth = LocalAuthentication();
  late int _autoLockMinutes;
  late int _passwordExpiryDays;
  late String _themeMode;
  late bool _autoSyncEnabled;
  late bool _realtimeSyncEnabled;
  late bool _pinEnabled;
  late bool _biometricEnabled;
  late int _pinThresholdMinutes;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _autoLockMinutes = widget.autoLockMinutes;
    _passwordExpiryDays = widget.passwordExpiryDays;
    _themeMode = widget.themeMode;
    _autoSyncEnabled = widget.autoSyncEnabled;
    _realtimeSyncEnabled = widget.realtimeSyncEnabled;
    _pinEnabled = widget.pinEnabled;
    _biometricEnabled = widget.biometricEnabled;
    _pinThresholdMinutes = widget.pinThresholdMinutes;
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    try {
      _biometricAvailable = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<String?> _showPinSetupDialog() async {
    String pin = '';
    String confirmPin = '';
    String? error;
    bool step2 = false;

    return showDialog<String>(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text(step2 ? 'PINを確認' : 'PINを設定（4桁）'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) {
              final current = step2 ? confirmPin : pin;
              return Container(
                width: 18, height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < current.length ? KuraudoTheme.accent : Colors.transparent,
                  border: Border.all(color: KuraudoTheme.accent, width: 2),
                ),
              );
            })),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(fontSize: 12, color: KuraudoTheme.danger)),
            ],
            const SizedBox(height: 16),
            SizedBox(width: 240, child: Column(children: [
              for (final row in [['1','2','3'], ['4','5','6'], ['7','8','9'], ['','0','⌫']])
                Row(mainAxisAlignment: MainAxisAlignment.center, children: row.map((key) {
                  if (key.isEmpty) return const SizedBox(width: 64, height: 52);
                  return SizedBox(width: 64, height: 52, child: InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: () {
                      setDialogState(() { error = null; });
                      if (key == '⌫') {
                        if (step2 && confirmPin.isNotEmpty) {
                          setDialogState(() => confirmPin = confirmPin.substring(0, confirmPin.length - 1));
                        } else if (!step2 && pin.isNotEmpty) {
                          setDialogState(() => pin = pin.substring(0, pin.length - 1));
                        }
                      } else {
                        if (step2) {
                          if (confirmPin.length < 4) {
                            confirmPin += key;
                            setDialogState(() {});
                            if (confirmPin.length == 4) {
                              if (confirmPin == pin) {
                                Navigator.pop(ctx, pin);
                              } else {
                                setDialogState(() { error = 'PINが一致しません'; confirmPin = ''; step2 = false; pin = ''; });
                              }
                            }
                          }
                        } else {
                          if (pin.length < 4) {
                            pin += key;
                            setDialogState(() {});
                            if (pin.length == 4) {
                              setDialogState(() => step2 = true);
                            }
                          }
                        }
                      }
                    },
                    child: Center(child: key == '⌫'
                      ? const Icon(Icons.backspace_rounded, size: 20)
                      : Text(key, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
                    ),
                  ));
                }).toList()),
            ])),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル'))],
        );
      });
    });
  }

  Future<void> _changePassword() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => const _ChangePasswordDialog(),
    );

    if (result == null) return;

    try {
      await widget.vaultService.changeMasterPassword(result['new']!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('マスターパスワードを変更しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('パスワード変更に失敗しました: $e')),
        );
      }
    }
  }

  Future<String> _getExportDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _export(String formatName, String fileExt, String Function(List<VaultEntry>) generator) async {
    final entries = widget.vaultService.vault?.activeEntries ?? [];
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('エクスポートするエントリがありません')));
      return;
    }

    // マスターパスワード再確認
    final pwConfirm = await showDialog<String>(context: context, builder: (ctx) {
      final ctrl = TextEditingController();
      bool obscure = true;
      return StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('パスワード確認'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('エクスポートデータには平文のパスワードが含まれます。\nマスターパスワードを入力して確認してください。',
            style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            obscureText: obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'マスターパスワード',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                onPressed: () => setDialogState(() => obscure = !obscure),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('確認')),
        ],
      ));
    });
    if (pwConfirm == null || pwConfirm.isEmpty) return;

    // パスワード検証
    if (pwConfirm != widget.vaultService.masterPassword) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('マスターパスワードが正しくありません')),
        );
      }
      return;
    }

    final method = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text('$formatName エクスポート'),
      content: Text('${entries.length}件のエントリをエクスポートします。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
        TextButton(onPressed: () => Navigator.pop(ctx, 'clipboard'), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.copy_rounded, size: 16), SizedBox(width: 6), Text('クリップボード')])),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, 'file'), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.save_rounded, size: 16), SizedBox(width: 6), Text('ファイル保存')])),
      ],
    ));
    if (method == null) return;
    final data = generator(entries);
    if (method == 'clipboard') {
      Clipboard.setData(ClipboardData(text: data));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${entries.length}件を${formatName}形式でコピーしました\n30秒後にクリップボードをクリアします')));
      // 30秒後にクリップボードクリア
      Future.delayed(const Duration(seconds: 30), () {
        Clipboard.setData(const ClipboardData(text: ''));
      });
    } else {
      final dir = await _getExportDir();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final path = '$dir/kuraudo_${fileExt}_$timestamp.${fileExt.contains('json') ? 'json' : 'csv'}';
      await File(path).writeAsString(data);
      if (mounted) {
        // 自動削除オプション付きで通知
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${entries.length}件を${formatName}にエクスポート:\n$path'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'ファイルを削除',
            onPressed: () async {
              try {
                await File(path).delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('エクスポートファイルを削除しました')),
                  );
                }
              } catch (_) {}
            },
          ),
        ));
      }
    }
  }

  Future<void> _exportKeePassCsv() => _export('KeePass CSV', 'keepass', (e) => _importer.exportKeePassCsv(e));
  Future<void> _exportJson() => _export('JSON', 'json', (e) => _importer.exportJson(e));
  Future<void> _exportBitwardenCsv() => _export('Bitwarden CSV', 'bitwarden', (e) => _importer.exportBitwardenCsv(e));

  void _openAutofillSettings() {
    final autofill = AutofillService();
    autofill.openAutofillSettings();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entryCount = widget.vaultService.entryCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
        children: [
          const SizedBox(height: 8),

          // ── Vault情報 ──
          _SectionHeader(title: 'Vault'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: KuraudoTheme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: KuraudoTheme.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.vaultService.vault?.vaultName ?? 'Vault',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$entryCount 件のエントリ',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── 外観 ──
          _SectionHeader(title: '外観'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.palette_rounded, size: 20),
                const SizedBox(width: 12),
                const Expanded(child: Text('テーマ', style: TextStyle(fontSize: 14))),
                DropdownButton<String>(
                  value: _themeMode,
                  underline: const SizedBox(),
                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                  dropdownColor: cs.surfaceContainerHighest,
                  items: const [
                    DropdownMenuItem(value: 'dark', child: Text('ダーク')),
                    DropdownMenuItem(value: 'light', child: Text('ライト')),
                    DropdownMenuItem(value: 'system', child: Text('システム連動')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _themeMode = v);
                      widget.onThemeModeChanged(v);
                    }
                  },
                ),
              ]),
            ),
          ),

          // ── セキュリティ ──
          _SectionHeader(title: 'セキュリティ'),
          _SettingsTile(
            icon: Icons.key_rounded,
            title: 'マスターパスワードを変更',
            subtitle: 'Argon2id + AES-256-GCM',
            onTap: _changePassword,
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.lock_clock_rounded, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('自動ロック', style: TextStyle(fontSize: 14))),
                  DropdownButton<int>(
                    value: _autoLockMinutes,
                    underline: const SizedBox(),
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                    dropdownColor: cs.surfaceContainerHighest,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('無効')),
                      DropdownMenuItem(value: -1, child: Text('即時')),
                      DropdownMenuItem(value: 1, child: Text('1分')),
                      DropdownMenuItem(value: 3, child: Text('3分')),
                      DropdownMenuItem(value: 5, child: Text('5分')),
                      DropdownMenuItem(value: 10, child: Text('10分')),
                      DropdownMenuItem(value: 15, child: Text('15分')),
                      DropdownMenuItem(value: 30, child: Text('30分')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _autoLockMinutes = v);
                        widget.onAutoLockChanged(v);
                      }
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.schedule_rounded, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('パスワード有効期限', style: TextStyle(fontSize: 14))),
                  DropdownButton<int>(
                    value: _passwordExpiryDays,
                    underline: const SizedBox(),
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                    dropdownColor: cs.surfaceContainerHighest,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('無効')),
                      DropdownMenuItem(value: 30, child: Text('30日')),
                      DropdownMenuItem(value: 60, child: Text('60日')),
                      DropdownMenuItem(value: 90, child: Text('90日')),
                      DropdownMenuItem(value: 180, child: Text('180日')),
                      DropdownMenuItem(value: 365, child: Text('1年')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _passwordExpiryDays = v);
                        widget.onPasswordExpiryChanged(v);
                      }
                    },
                  ),
                ]),
                Text('バックグラウンド移行後、指定時間が経過するとVaultを自動ロックします', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),

          // ── 簡易ロック解除 ──
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.pin_rounded, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('PINで解除', style: TextStyle(fontSize: 14))),
                  Switch(
                    value: _pinEnabled,
                    activeColor: KuraudoTheme.accent,
                    onChanged: (v) async {
                      if (v) {
                        // PIN設定ダイアログ
                        final pin = await _showPinSetupDialog();
                        if (pin == null) return;
                        await widget.secureStorage?.write(key: 'kuraudo_pin', value: pin);
                      } else {
                        await widget.secureStorage?.delete(key: 'kuraudo_pin');
                      }
                      setState(() => _pinEnabled = v);
                      widget.onPinEnabledChanged(v);
                    },
                  ),
                ]),
                if (_biometricAvailable) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.fingerprint_rounded, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('生体認証で解除', style: TextStyle(fontSize: 14))),
                    Switch(
                      value: _biometricEnabled,
                      activeColor: KuraudoTheme.accent,
                      onChanged: (v) {
                        setState(() => _biometricEnabled = v);
                        widget.onBiometricEnabledChanged(v);
                      },
                    ),
                  ]),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.timer_rounded, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('簡易解除の有効時間', style: TextStyle(fontSize: 14))),
                  DropdownButton<int>(
                    value: _pinThresholdMinutes,
                    underline: const SizedBox(),
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                    dropdownColor: cs.surfaceContainerHighest,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1分')),
                      DropdownMenuItem(value: 3, child: Text('3分')),
                      DropdownMenuItem(value: 5, child: Text('5分')),
                      DropdownMenuItem(value: 10, child: Text('10分')),
                      DropdownMenuItem(value: 30, child: Text('30分')),
                    ],
                    onChanged: (_pinEnabled || _biometricEnabled) ? (v) {
                      if (v != null) {
                        setState(() => _pinThresholdMinutes = v);
                        widget.onPinThresholdChanged(v);
                      }
                    } : null,
                  ),
                ]),
                Text('自動ロック後、この時間以内ならPIN/生体認証で解除可能。\n超過するとマスターパスワードが必要です', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.4)),
                if (_pinEnabled) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final pin = await _showPinSetupDialog();
                        if (pin != null) {
                          await widget.secureStorage?.write(key: 'kuraudo_pin', value: pin);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PINを変更しました')));
                        }
                      },
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('PINを変更', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ]),
            ),
          ),

          // ── クラウド同期 ──
          _SectionHeader(title: 'クラウド同期'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.cloud_sync_rounded, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('自動同期', style: TextStyle(fontSize: 14))),
                  Switch(
                    value: _autoSyncEnabled,
                    activeColor: KuraudoTheme.accent,
                    onChanged: (v) {
                      setState(() => _autoSyncEnabled = v);
                      widget.onAutoSyncChanged(v);
                    },
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text('解錠時の自動同期と保存時の自動アップロードを制御します', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.sync_rounded, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('リアルタイム同期', style: TextStyle(fontSize: 14))),
                  Switch(
                    value: _realtimeSyncEnabled && _autoSyncEnabled,
                    activeColor: KuraudoTheme.accent,
                    onChanged: _autoSyncEnabled ? (v) {
                      setState(() => _realtimeSyncEnabled = v);
                      widget.onRealtimeSyncChanged(v);
                    } : null,
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text('エントリ保存の度に即座にクラウドにアップロードします\n自動同期がOFFの場合は無効になります', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.4)),
                ),
              ]),
            ),
          ),

          // ── データ管理 ──
          _SectionHeader(title: 'データ管理'),
          _SettingsTile(
            icon: Icons.download_rounded,
            title: 'KeePass CSV エクスポート',
            subtitle: 'ファイル保存 / クリップボード',
            onTap: _exportKeePassCsv,
          ),
          _SettingsTile(
            icon: Icons.shield_rounded,
            title: 'Bitwarden CSV エクスポート',
            subtitle: 'ファイル保存 / クリップボード',
            onTap: _exportBitwardenCsv,
          ),
          _SettingsTile(
            icon: Icons.code_rounded,
            title: 'JSON エクスポート',
            subtitle: 'ファイル保存 / クリップボード',
            onTap: _exportJson,
          ),

          // ── 自動入力 ──
          if (Platform.isAndroid) ...[
            _SectionHeader(title: '自動入力'),
            _SettingsTile(
              icon: Icons.auto_fix_high_rounded,
              title: 'Autofill Service',
              subtitle: 'ブラウザ・アプリで自動入力を有効化',
              onTap: _openAutofillSettings,
            ),
          ],
          if (Platform.isLinux || Platform.isWindows) ...[
            _SectionHeader(title: '自動入力'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.keyboard_rounded, size: 20, color: KuraudoTheme.accent),
                      const SizedBox(width: 10),
                      const Text('デスクトップ自動入力', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'エントリ詳細画面の「自動入力」ボタンから、ブラウザのログインフォームに'
                      'ユーザー名とパスワードを自動入力できます。\n\n'
                      '使い方:\n'
                      '1. ブラウザでログインページを開く\n'
                      '2. ユーザー名フィールドにフォーカスを合わせる\n'
                      '3. Kuraudoに戻り「自動入力」をタップ\n'
                      '4. 3秒以内にブラウザに切り替える',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
                    ),
                    if (Platform.isLinux) ...[
                      const SizedBox(height: 8),
                      Text(
                        '※ Linux: xdotool が必要です（sudo pacman -S xdotool）\n'
                        '   未インストールの場合はクリップボードコピーにフォールバックします',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.7), height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // ── アプリ情報 ──
          _SectionHeader(title: 'アプリ情報'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Kuraudo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'v0.1.0',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Google Drive同期型パスワードマネージャー\n'
                    'Zero to Ship プロジェクト',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暗号化: Argon2id (KDF) + AES-256-GCM\n'
                    'ファイル形式: .kuraudo (独自バイナリ)\n'
                    'フレームワーク: Flutter',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

/// パスワード変更ダイアログ
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_newCtrl.text.length < 8) {
      setState(() => _error = 'パスワードは8文字以上必要です');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'パスワードが一致しません');
      return;
    }
    Navigator.pop(context, {'new': _newCtrl.text});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('マスターパスワードを変更'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _newCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '新しいパスワード',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'パスワード確認',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 12,
                color: KuraudoTheme.danger,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('変更'),
        ),
      ],
    );
  }
}

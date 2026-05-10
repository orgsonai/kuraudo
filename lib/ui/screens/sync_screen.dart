/// Kuraudo 同期画面
///
/// バックエンド選択（Google Drive / WebDAV / ローカルパス）と
/// 同期操作・バックアップ管理を統合した画面
library;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../services/google_drive_service.dart';
import '../../services/sync_backend.dart';
import '../../services/local_path_backend.dart';
import '../../services/webdav_backend.dart';
import '../../services/sync_manager.dart';
import '../../services/vault_service.dart';
import '../theme/kuraudo_theme.dart';

class SyncScreen extends StatefulWidget {
  final VaultService vaultService;
  final SyncBackend backend;
  final SyncBackendKind backendKind;
  final GoogleDriveService googleDriveBackend;
  final WebDAVBackend webdavBackend;
  final LocalPathBackend localPathBackend;
  final void Function(SyncBackendKind) onBackendChanged;
  final SyncManager syncManager;

  const SyncScreen({
    super.key,
    required this.vaultService,
    required this.backend,
    required this.backendKind,
    required this.googleDriveBackend,
    required this.webdavBackend,
    required this.localPathBackend,
    required this.onBackendChanged,
    required this.syncManager,
  });

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _isSyncing = false;
  String? _lastMessage;
  SyncAction? _lastAction;

  @override
  void initState() {
    super.initState();
    _loadLastSyncTime();
  }

  Future<void> _loadLastSyncTime() async {
    await widget.backend.loadLastSyncTime();
    if (mounted) setState(() {});
  }

  String get _lastSyncTimeText {
    final t = widget.backend.lastSyncTime;
    if (t == null) return '未同期';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '数秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    return '${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // ── バックエンド固有の接続処理 ──

  Future<void> _connect() async {
    setState(() => _isSyncing = true);
    bool success = false;
    String message = '';
    switch (widget.backendKind) {
      case SyncBackendKind.googleDrive:
        success = await widget.googleDriveBackend.signIn();
        message = success
            ? 'サインインしました: ${widget.googleDriveBackend.accountEmail}'
            : 'サインインに失敗しました';
        break;
      case SyncBackendKind.webdav:
        if (!mounted) break;
        success = await _showWebDAVConfigDialog();
        message = success ? 'WebDAV接続を設定しました' : 'WebDAV接続設定をキャンセルまたは失敗しました';
        break;
      case SyncBackendKind.localPath:
        if (!mounted) break;
        success = await _showLocalPathConfigDialog();
        message = success ? 'ローカルパスを設定しました' : 'ローカルパス設定をキャンセルまたは失敗しました';
        break;
    }
    setState(() {
      _isSyncing = false;
      _lastMessage = message;
    });
    if (success) _autoSync();
  }

  Future<void> _disconnect() async {
    final confirm = await _confirmDialog('切断', '現在のバックエンドから切断します。\n認証情報がクリアされます。実行しますか？', isDangerous: true);
    if (confirm != true) return;
    await widget.backend.disconnect();
    setState(() {
      _lastMessage = '切断しました';
      _lastAction = null;
    });
  }

  /// WebDAV設定ダイアログ
  Future<bool> _showWebDAVConfigDialog() async {
    final urlCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final pathCtrl = TextEditingController(text: '/Kuraudo/');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WebDAV接続設定'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'サーバーURL',
                    hintText: 'https://nextcloud.example.com/remote.php/dav/files/user/',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: 'ユーザー名'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(labelText: 'パスワード'),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pathCtrl,
                  decoration: const InputDecoration(labelText: 'リモートパス（オプション）'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('接続')),
        ],
      ),
    );
    if (result != true) return false;

    return await widget.webdavBackend.configure(
      serverUrl: urlCtrl.text.trim(),
      username: userCtrl.text.trim(),
      password: passCtrl.text,
      remotePath: pathCtrl.text.trim().isEmpty ? null : pathCtrl.text.trim(),
    );
  }

  /// ローカルパス設定ダイアログ（ディレクトリ選択）
  Future<bool> _showLocalPathConfigDialog() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '同期先フォルダを選択',
      );
      if (selected == null) return false;
      return await widget.localPathBackend.setSyncDirectory(selected);
    } catch (_) {
      return false;
    }
  }

  // ── バックエンド切り替え ──

  Future<void> _showBackendSelector() async {
    final selected = await showDialog<SyncBackendKind>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('同期方式を選択'),
        children: [
          _BackendOption(
            kind: SyncBackendKind.googleDrive,
            label: 'Google Drive',
            description: 'Googleアカウントでクラウド同期',
            isSelected: widget.backendKind == SyncBackendKind.googleDrive,
            onTap: () => Navigator.pop(ctx, SyncBackendKind.googleDrive),
          ),
          _BackendOption(
            kind: SyncBackendKind.webdav,
            label: 'WebDAV',
            description: 'Nextcloud / Synology / 自前サーバー',
            isSelected: widget.backendKind == SyncBackendKind.webdav,
            onTap: () => Navigator.pop(ctx, SyncBackendKind.webdav),
          ),
          _BackendOption(
            kind: SyncBackendKind.localPath,
            label: 'ローカルパス',
            description: 'SMBマウント先 / 外付けドライブ / 共有フォルダ',
            isSelected: widget.backendKind == SyncBackendKind.localPath,
            onTap: () => Navigator.pop(ctx, SyncBackendKind.localPath),
          ),
        ],
      ),
    );
    if (selected != null && selected != widget.backendKind) {
      widget.onBackendChanged(selected);
      // 新しいバックエンドの状態反映のため画面再構築
      if (mounted) Navigator.pop(context, true);
    }
  }

  // ── 同期操作 ──

  Future<bool?> _confirmDialog(String title, String message, {bool isDangerous = false}) {
    return showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 13, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), style: isDangerous ? TextButton.styleFrom(foregroundColor: KuraudoTheme.danger) : null, child: const Text('実行')),
      ],
    ));
  }

  Future<void> _autoSync() async {
    final confirm = await _confirmDialog('自動同期', 'リモートとローカルを比較して自動で同期します。\n実行しますか？');
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = '同期中...'; });
    final result = await widget.syncManager.autoSync();
    setState(() { _isSyncing = false; if (result != null) { _lastMessage = result.message; _lastAction = result.action; } else { _lastMessage = '同期をスキップしました'; } });
  }

  Future<void> _forceUpload() async {
    final confirm = await _confirmDialog('ローカル → リモート', 'ローカルのデータでリモートを上書きします。\n実行しますか？');
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = 'アップロード中...'; });
    final result = await widget.syncManager.forceUpload();
    setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
  }

  Future<void> _forceDownload() async {
    final confirm = await _confirmDialog('リモート → ローカル', 'リモートのデータでローカルを上書きします。\n現在のローカルデータは失われます。実行しますか？', isDangerous: true);
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = 'ダウンロード中...'; });
    final result = await widget.syncManager.forceDownload();
    setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
    if (result.action == SyncAction.downloaded && mounted) { Navigator.pop(context, true); }
  }

  Future<void> _mergeSync() async {
    final confirm = await _confirmDialog('マージ同期', 'リモートとローカルをUUID単位で比較・統合します。\nデータ消失はありません。実行しますか？');
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = 'マージ同期中...'; });
    final result = await widget.syncManager.mergeSync();
    setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
    if (result.action == SyncAction.downloaded && mounted) { Navigator.pop(context, true); }
  }

  Future<void> _createBackup() async {
    final confirm = await _confirmDialog('手動バックアップ', 'ローカルとリモートにバックアップを作成します。\n実行しますか？');
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = 'バックアップ作成中...'; });
    final result = await widget.syncManager.createManualBackup();
    setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
  }

  // ── バックアップ復元ダイアログ ──

  Future<void> _showRestoreDialog() async {
    final localBackups = await widget.syncManager.listLocalBackups();
    if (!mounted) return;

    final cs = Theme.of(context).colorScheme;
    final cloudBackups = widget.backend.isReady ? await widget.backend.listBackups() : <SyncBackupEntry>[];

    if (!mounted) return;

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('バックアップからリストア'),
      content: SizedBox(width: 400, height: 400, child: ListView(children: [
        if (localBackups.isNotEmpty) ...[
          Text('ローカル', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          ...localBackups.map((f) {
            final name = f.path.split('/').last;
            return ListTile(
              dense: true,
              leading: const Icon(Icons.folder_rounded, size: 18),
              title: Text(name, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                  title: const Text('リストア確認'),
                  content: Text('$nameからリストアしますか？\n現在のデータは上書きされます。'),
                  actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')), TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: KuraudoTheme.warning), child: const Text('リストア'))],
                ));
                if (confirm == true) {
                  setState(() { _isSyncing = true; _lastMessage = 'リストア中...'; });
                  final result = await widget.syncManager.restoreFromLocalBackup(f.path);
                  setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
                  if (result.action == SyncAction.downloaded && mounted) Navigator.pop(context, true);
                }
              },
            );
          }),
          const Divider(),
        ],
        if (cloudBackups.isNotEmpty) ...[
          Text('リモート', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          ...cloudBackups.map((f) {
            final name = f.name;
            return ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_rounded, size: 18),
              title: Text(name, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              subtitle: f.modifiedAt != null ? Text('${f.modifiedAt}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)) : null,
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                  title: const Text('リストア確認'),
                  content: Text('$nameからリストアしますか？\n現在のデータは上書きされます。'),
                  actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')), TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: KuraudoTheme.warning), child: const Text('リストア'))],
                ));
                if (confirm == true && f.id.isNotEmpty) {
                  setState(() { _isSyncing = true; _lastMessage = 'リモートからリストア中...'; });
                  final result = await widget.syncManager.restoreFromCloudBackup(f.id);
                  setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
                  if (result.action == SyncAction.downloaded && mounted) Navigator.pop(context, true);
                }
              },
            );
          }),
        ],
        if (localBackups.isEmpty && cloudBackups.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(40), child: Text('バックアップがありません', style: TextStyle(color: cs.onSurfaceVariant)))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
    ));
  }

  // ── ステータス色/アイコン ──

  Color _statusColor() {
    if (widget.backend.status == SyncStatus.error) return KuraudoTheme.danger;
    if (widget.backend.status == SyncStatus.success) return KuraudoTheme.accent;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  IconData _statusIcon() {
    if (widget.backend.status == SyncStatus.error) return Icons.error_rounded;
    if (widget.backend.status == SyncStatus.success) return Icons.check_circle_rounded;
    if (widget.backend.status == SyncStatus.syncing) return Icons.sync_rounded;
    return Icons.info_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isReady = widget.backend.isReady;
    final info = widget.backend.info;

    return Scaffold(
      appBar: AppBar(
        title: const Text('同期'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: '同期方式を変更',
            onPressed: _showBackendSelector,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── 接続状態カード ──
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isReady
                              ? KuraudoTheme.accent.withValues(alpha: 0.1)
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _backendIcon(info.kind, isReady),
                          color: isReady ? KuraudoTheme.accent : cs.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isReady ? '${info.displayName} 連携中' : '${info.displayName} 未接続',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isReady
                                  ? widget.backend.displayLabel ?? info.displayName
                                  : _connectHint(info.kind),
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (isReady) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(Icons.schedule_rounded, size: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                                const SizedBox(width: 4),
                                Text(
                                  '最終同期: $_lastSyncTimeText',
                                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                                ),
                              ]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ── 接続/切断ボタン ──
              if (!isReady)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _connect,
                    icon: _isSyncing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_connectIcon(info.kind), size: 18),
                    label: Text(_connectButtonLabel(info.kind)),
                  ),
                )
              else ...[
                _SyncActionTile(icon: Icons.sync_rounded, title: '自動同期', subtitle: 'タイムスタンプを比較して自動判定', onTap: _isSyncing ? null : _autoSync, isLoading: _isSyncing),
                _SyncActionTile(icon: Icons.cloud_upload_rounded, title: 'ローカル → リモート', subtitle: '現在のデータをアップロード', onTap: _isSyncing ? null : _forceUpload),
                _SyncActionTile(icon: Icons.cloud_download_rounded, title: 'リモート → ローカル', subtitle: 'リモートのデータでローカルを上書き', onTap: _isSyncing ? null : _forceDownload, isDangerous: true),
                _SyncActionTile(icon: Icons.merge_rounded, title: 'マージ同期', subtitle: 'UUID単位で比較・統合（データ消失なし）', onTap: _isSyncing ? null : _mergeSync),

                const SizedBox(height: 16),
                Text('バックアップ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                _SyncActionTile(icon: Icons.backup_rounded, title: '手動バックアップ', subtitle: 'ローカル＋リモートに保存（最大3世代保持）', onTap: _isSyncing ? null : _createBackup),
                _SyncActionTile(icon: Icons.restore_rounded, title: 'バックアップからリストア', subtitle: 'ローカル/リモートのバックアップを復元', onTap: _isSyncing ? null : _showRestoreDialog),

                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('切断'),
                  style: OutlinedButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                ),
              ],

              if (_lastMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(_statusIcon(), size: 18, color: _statusColor()),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_lastMessage!, style: TextStyle(fontSize: 12, color: _statusColor()))),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── ヘルパー ──

  IconData _backendIcon(SyncBackendKind kind, bool isReady) {
    if (!isReady) return Icons.cloud_off_rounded;
    switch (kind) {
      case SyncBackendKind.googleDrive: return Icons.cloud_done_rounded;
      case SyncBackendKind.webdav: return Icons.dns_rounded;
      case SyncBackendKind.localPath: return Icons.folder_rounded;
    }
  }

  IconData _connectIcon(SyncBackendKind kind) {
    switch (kind) {
      case SyncBackendKind.googleDrive: return Icons.login_rounded;
      case SyncBackendKind.webdav: return Icons.dns_rounded;
      case SyncBackendKind.localPath: return Icons.folder_open_rounded;
    }
  }

  String _connectButtonLabel(SyncBackendKind kind) {
    switch (kind) {
      case SyncBackendKind.googleDrive: return 'Googleアカウントでサインイン';
      case SyncBackendKind.webdav: return 'WebDAVサーバーに接続';
      case SyncBackendKind.localPath: return '同期先フォルダを選択';
    }
  }

  String _connectHint(SyncBackendKind kind) {
    switch (kind) {
      case SyncBackendKind.googleDrive: return 'サインインして同期を有効化';
      case SyncBackendKind.webdav: return 'サーバーURLとアカウントを設定';
      case SyncBackendKind.localPath: return '同期先のフォルダを選択';
    }
  }
}

// ── 同期アクションタイル ──

class _SyncActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isDangerous;
  final bool isLoading;

  const _SyncActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDangerous = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isDangerous ? KuraudoTheme.danger : cs.onSurface;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      ),
    );
  }
}

// ── バックエンド選択肢 ──

class _BackendOption extends StatelessWidget {
  final SyncBackendKind kind;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _BackendOption({
    required this.kind,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
        color: isSelected ? KuraudoTheme.accent : cs.onSurfaceVariant,
      ),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(description, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      onTap: onTap,
    );
  }
}

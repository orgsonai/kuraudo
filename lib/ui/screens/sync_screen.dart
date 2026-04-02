/// Kuraudo 同期画面
/// 
/// Googleアカウント連携、同期ステータス表示、手動同期操作
library;

import 'package:flutter/material.dart';
import '../../services/google_drive_service.dart';
import '../../services/sync_manager.dart';
import '../../services/vault_service.dart';
import '../theme/kuraudo_theme.dart';

class SyncScreen extends StatefulWidget {
  final VaultService vaultService;
  final GoogleDriveService driveService;
  final SyncManager syncManager;

  const SyncScreen({
    super.key,
    required this.vaultService,
    required this.driveService,
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
    await widget.driveService.loadLastSyncTime();
    if (mounted) setState(() {});
  }

  String get _lastSyncTimeText {
    final t = widget.driveService.lastSyncTime;
    if (t == null) return '未同期';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '数秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    return '${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _signIn() async {
    setState(() => _isSyncing = true);

    final success = await widget.driveService.signIn();

    setState(() {
      _isSyncing = false;
      _lastMessage = success
          ? 'サインインしました: ${widget.driveService.accountEmail}'
          : 'サインインに失敗しました';
    });

    if (success) {
      _autoSync();
    }
  }

  Future<void> _signOut() async {
    await widget.driveService.signOut();
    setState(() {
      _lastMessage = 'サインアウトしました';
      _lastAction = null;
    });
  }

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
    final confirm = await _confirmDialog('自動同期', 'クラウドとローカルを比較して自動で同期します。\n実行しますか？');
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = '同期中...'; });
    final result = await widget.syncManager.autoSync();
    setState(() { _isSyncing = false; if (result != null) { _lastMessage = result.message; _lastAction = result.action; } else { _lastMessage = '同期をスキップしました'; } });
  }

  Future<void> _forceUpload() async {
    final confirm = await _confirmDialog('ローカル → クラウド', 'ローカルのデータでクラウドを上書きします。\n実行しますか？');
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = 'アップロード中...'; });
    final result = await widget.syncManager.forceUpload();
    setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
  }

  Future<void> _forceDownload() async {
    final confirm = await _confirmDialog('クラウド → ローカル', 'クラウドのデータでローカルを上書きします。\n現在のローカルデータは失われます。実行しますか？', isDangerous: true);
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = 'ダウンロード中...'; });
    final result = await widget.syncManager.forceDownload();
    setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
    if (result.action == SyncAction.downloaded && mounted) { Navigator.pop(context, true); }
  }

  Future<void> _mergeSync() async {
    final confirm = await _confirmDialog('マージ同期', 'クラウドとローカルをUUID単位で比較・統合します。\nデータ消失はありません。実行しますか？');
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = 'マージ同期中...'; });
    final result = await widget.syncManager.mergeSync();
    setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
    if (result.action == SyncAction.downloaded && mounted) { Navigator.pop(context, true); }
  }

  Future<void> _createBackup() async {
    final confirm = await _confirmDialog('手動バックアップ', 'ローカルとクラウドにバックアップを作成します。\n実行しますか？');
    if (confirm != true) return;
    setState(() { _isSyncing = true; _lastMessage = 'バックアップ作成中...'; });
    final result = await widget.syncManager.createManualBackup();
    setState(() { _isSyncing = false; _lastMessage = result.message; _lastAction = result.action; });
  }

  Future<void> _showRestoreDialog() async {
    final localBackups = await widget.syncManager.listLocalBackups();
    if (!mounted) return;

    final cs = Theme.of(context).colorScheme;
    final cloudBackups = widget.driveService.isSignedIn ? await widget.driveService.listBackups() : <dynamic>[];

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
          Text('クラウド', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          ...cloudBackups.map((f) {
            final name = f.name ?? 'unknown';
            return ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_rounded, size: 18),
              title: Text(name, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              subtitle: f.modifiedTime != null ? Text('${f.modifiedTime}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)) : null,
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                  title: const Text('リストア確認'),
                  content: Text('$nameからリストアしますか？\n現在のデータは上書きされます。'),
                  actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')), TextButton(onPressed: () => Navigator.pop(c, true), style: TextButton.styleFrom(foregroundColor: KuraudoTheme.warning), child: const Text('リストア'))],
                ));
                if (confirm == true && f.id != null) {
                  setState(() { _isSyncing = true; _lastMessage = 'クラウドからリストア中...'; });
                  final result = await widget.syncManager.restoreFromCloudBackup(f.id!);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSignedIn = widget.driveService.isSignedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('クラウド同期'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSignedIn
                          ? KuraudoTheme.accent.withValues(alpha: 0.1)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isSignedIn
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      color: isSignedIn
                          ? KuraudoTheme.accent
                          : cs.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSignedIn ? 'Google Drive 連携中' : 'Google Drive 未接続',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isSignedIn
                              ? widget.driveService.accountEmail ?? ''
                              : 'サインインして同期を有効化',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (isSignedIn) ...[
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

          // ── サインイン/サインアウト ──
          if (!isSignedIn)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _signIn,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login_rounded, size: 18),
                label: const Text('Googleアカウントでサインイン'),
              ),
            )
          else ...[
            // ── 同期操作 ──
            _SyncActionTile(
              icon: Icons.sync_rounded,
              title: '自動同期',
              subtitle: 'タイムスタンプを比較して自動判定',
              onTap: _isSyncing ? null : _autoSync,
              isLoading: _isSyncing,
            ),
            _SyncActionTile(
              icon: Icons.cloud_upload_rounded,
              title: 'ローカル → クラウド',
              subtitle: '現在のデータをアップロード',
              onTap: _isSyncing ? null : _forceUpload,
            ),
            _SyncActionTile(
              icon: Icons.cloud_download_rounded,
              title: 'クラウド → ローカル',
              subtitle: 'クラウドのデータでローカルを上書き',
              onTap: _isSyncing ? null : _forceDownload,
              isDangerous: true,
            ),
            _SyncActionTile(
              icon: Icons.merge_rounded,
              title: 'マージ同期（v2.0）',
              subtitle: 'UUID単位で比較・統合（データ消失なし）',
              onTap: _isSyncing ? null : _mergeSync,
            ),

            const SizedBox(height: 16),

            // ── バックアップ ──
            Text('バックアップ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            _SyncActionTile(
              icon: Icons.backup_rounded,
              title: '手動バックアップ',
              subtitle: 'ローカル＋クラウドに保存（最大3世代保持）',
              onTap: _isSyncing ? null : _createBackup,
            ),
            _SyncActionTile(
              icon: Icons.restore_rounded,
              title: 'バックアップからリストア',
              subtitle: 'ローカル/クラウドのバックアップを復元',
              onTap: _isSyncing ? null : _showRestoreDialog,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text('自動バックアップ: 保存時に1日1回自動作成されます\n手動/自動それぞれ最大3世代保持（合計最大6つ）', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.5)),
            ),

            const SizedBox(height: 16),

            // ── サインアウト ──
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('サインアウト'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
              ),
            ),
          ],

          // ── ステータスメッセージ ──
          if (_lastMessage != null) ...[
            const SizedBox(height: 16),
            Card(
              color: _statusColor.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(_statusIcon, size: 18, color: _statusColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _lastMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── 同期の仕組み説明 ──
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: KuraudoTheme.info),
                      const SizedBox(width: 6),
                      Text(
                        '同期の仕組み',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: KuraudoTheme.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Kuraudoはローカル・ファースト設計です。\n'
                    '\n'
                    '• データは常にローカルに保存され、オフラインでも使えます\n'
                    '• Google Driveには暗号化済みファイルがアップロードされます\n'
                    '• クラウド上のファイルを見ても、パスワードなしでは読めません\n'
                    '• 解錠時に自動同期（衝突時は自動マージ）\n'
                    '• 保存時に自動アップロード＋1日1回自動バックアップ\n'
                    '• バックアップは手動/自動とも最大3世代保持',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
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

  Color get _statusColor {
    if (_lastAction == SyncAction.conflict) return KuraudoTheme.warning;
    if (widget.driveService.status == SyncStatus.error) return KuraudoTheme.danger;
    if (widget.driveService.status == SyncStatus.success) return KuraudoTheme.accent;
    return KuraudoTheme.info;
  }

  IconData get _statusIcon {
    if (_lastAction == SyncAction.conflict) return Icons.warning_rounded;
    if (widget.driveService.status == SyncStatus.error) return Icons.error_rounded;
    if (widget.driveService.status == SyncStatus.success) return Icons.check_circle_rounded;
    return Icons.info_rounded;
  }
}

class _SyncActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool isDangerous;

  const _SyncActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.isLoading = false,
    this.isDangerous = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon,
                size: 20,
                color: isDangerous ? KuraudoTheme.warning : KuraudoTheme.accent),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

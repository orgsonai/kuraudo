/// Kuraudo アカウント紐付けビュー
/// 
/// 同一メールアドレスやユーザー名を使用しているサービスを横断的に表示
/// メールアドレス変更時の影響範囲を可視化
library;

import 'package:flutter/material.dart';
import '../../models/vault_entry.dart';
import '../../services/vault_service.dart';
import '../theme/kuraudo_theme.dart';
import 'entry_detail_screen.dart';

class AccountLinkScreen extends StatefulWidget {
  final VaultService vaultService;

  const AccountLinkScreen({
    super.key,
    required this.vaultService,
  });

  @override
  State<AccountLinkScreen> createState() => _AccountLinkScreenState();
}

class _AccountLinkScreenState extends State<AccountLinkScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// メールアドレス別グルーピング（2件以上のもの）
  Map<String, List<VaultEntry>> get _emailGroups {
    return widget.vaultService.groupByEmail();
  }

  /// ユーザー名別グルーピング（2件以上のもの）
  Map<String, List<VaultEntry>> get _usernameGroups {
    final map = <String, List<VaultEntry>>{};
    for (final e in widget.vaultService.vault?.entries ?? []) {
      if (e.username.isNotEmpty) {
        map.putIfAbsent(e.username, () => []).add(e);
      }
    }
    map.removeWhere((_, list) => list.length < 2);
    return map;
  }

  void _openEntry(VaultEntry entry) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryDetailScreen(
          vaultService: widget.vaultService,
          entry: entry,
        ),
      ),
    );
    if (result == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('アカウント紐付け'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: KuraudoTheme.accent,
          labelColor: KuraudoTheme.accent,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: const [
            Tab(text: 'メール別'),
            Tab(text: 'ユーザー名別'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: TabBarView(
        controller: _tabController,
        children: [
          _GroupListView(
            groups: _emailGroups,
            icon: Icons.email_rounded,
            emptyMessage: '同じメールアドレスを使っている\nサービスはありません',
            onTapEntry: _openEntry,
          ),
          _GroupListView(
            groups: _usernameGroups,
            icon: Icons.person_rounded,
            emptyMessage: '同じユーザー名を使っている\nサービスはありません',
            onTapEntry: _openEntry,
          ),
        ],
      ),
        ),
      ),
    );
  }
}

/// グループ一覧ビュー
class _GroupListView extends StatelessWidget {
  final Map<String, List<VaultEntry>> groups;
  final IconData icon;
  final String emptyMessage;
  final void Function(VaultEntry) onTapEntry;

  const _GroupListView({
    required this.groups,
    required this.icon,
    required this.emptyMessage,
    required this.onTapEntry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keys = groups.keys.toList()..sort();

    if (keys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off_rounded, size: 48,
                color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: keys.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final key = keys[index];
        final entries = groups[key]!;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── ヘッダー ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: KuraudoTheme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        key,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: KuraudoTheme.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${entries.length}件',
                        style: const TextStyle(
                          fontSize: 11,
                          color: KuraudoTheme.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, indent: 16, endIndent: 16),

              // ── エントリリスト ──
              ...entries.map((entry) => ListTile(
                dense: true,
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      entry.title.isNotEmpty
                          ? entry.title[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  entry.title,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: entry.url != null
                    ? Text(
                        entry.url!,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () => onTapEntry(entry),
              )),

              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }
}

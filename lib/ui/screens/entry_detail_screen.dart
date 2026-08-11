/// Kuraudo エントリ詳細画面
///
/// パスワード表示/非表示、コピー、履歴、編集、削除
library;

import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as material show Text;
import 'package:flutter/services.dart';
import '../../l10n/kuraudo_localizations.dart';
import '../../models/vault_entry.dart';
import '../../services/autofill_service.dart';
import '../../services/vault_service.dart';
import '../theme/kuraudo_theme.dart';
import '../widgets/totp_display.dart';
import 'entry_edit_screen.dart';

class EntryDetailScreen extends StatefulWidget {
  final VaultService vaultService;
  final VaultEntry entry;

  const EntryDetailScreen({
    super.key,
    required this.vaultService,
    required this.entry,
  });

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  late VaultEntry _entry;
  bool _showPassword = false;
  bool _showHistory = false;
  final Set<int> _visibleHistoryPasswords = {};

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  void _copyToClipboard(String text, String label) {
    if (label.contains('パスワード')) {
      // パスワードは完全クリア付きでコピー
      copyAndScheduleClear(text);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$labelをコピー（30秒後クリア）'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$labelをコピーしました'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _performAutoType() async {
    final autofill = AutofillService();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('3秒以内にブラウザに切り替えてください...'),
        duration: Duration(seconds: 3),
      ),
    );
    // 3秒待ってからAutoType実行（ユーザーがブラウザに切り替える時間）
    await Future.delayed(const Duration(seconds: 3));
    final result = await autofill.autoType(_entry);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _edit() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryEditScreen(
          vaultService: widget.vaultService,
          existingEntry: _entry,
        ),
      ),
    );
    if (result == true) {
      // 更新されたエントリを再取得
      final updated = widget.vaultService.vault?.findByUuid(_entry.uuid);
      if (updated != null) {
        setState(() => _entry = updated);
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ゴミ箱に移動'),
        content: Text('「${_entry.title}」をゴミ箱に移動しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: KuraudoTheme.danger),
            child: const Text('ゴミ箱に移動'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.vaultService.trashEntry(_entry.uuid);
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _toggleFavorite() async {
    _entry.favorite = !_entry.favorite;
    _entry.updatedAt = DateTime.now();
    await widget.vaultService.updateEntry(_entry);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text.raw(_entry.title),
        actions: [
          IconButton(
            icon: Icon(
              _entry.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _entry.favorite ? KuraudoTheme.warning : null,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 20),
            onPressed: _edit,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete();
            },
            popUpAnimationStyle: AnimationStyle(duration: Duration.zero),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_rounded,
                      size: 18,
                      color: KuraudoTheme.danger,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'ゴミ箱に移動',
                      style: TextStyle(color: KuraudoTheme.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── ヘッダーカード ──
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: KuraudoTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text.raw(
                            _entry.title.isNotEmpty
                                ? _entry.title[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: KuraudoTheme.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.raw(
                              _entry.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_entry.category != null) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text.raw(
                                  _entry.category!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ── フィールド一覧 ──
              if (_entry.username.isNotEmpty)
                _FieldTile(
                  icon: Icons.person_rounded,
                  label: 'ユーザー名',
                  value: _entry.username,
                  onCopy: () => _copyToClipboard(_entry.username, 'ユーザー名'),
                ),

              _FieldTile(
                icon: Icons.key_rounded,
                label: 'パスワード',
                value: _showPassword ? _entry.password : '••••••••••••',
                onCopy: () => _copyToClipboard(_entry.password, 'パスワード'),
                trailing: IconButton(
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
                isMonospace: _showPassword,
              ),

              if (_entry.email != null && _entry.email!.isNotEmpty)
                _FieldTile(
                  icon: Icons.email_rounded,
                  label: 'メール',
                  value: _entry.email!,
                  onCopy: () => _copyToClipboard(_entry.email!, 'メール'),
                ),

              if (_entry.url != null && _entry.url!.isNotEmpty)
                _FieldTile(
                  icon: Icons.link_rounded,
                  label: 'URL',
                  value: _entry.url!,
                  onCopy: () => _copyToClipboard(_entry.url!, 'URL'),
                ),

              // ── デスクトップ自動入力 ──
              if (Platform.isLinux || Platform.isWindows) ...[
                const SizedBox(height: 4),
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 4,
                  ),
                  child: InkWell(
                    onTap: _performAutoType,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: KuraudoTheme.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.keyboard_rounded,
                              size: 18,
                              color: KuraudoTheme.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '自動入力',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'ブラウザにユーザー名＋パスワードを入力',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 20,
                            color: KuraudoTheme.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              if (_entry.notes != null && _entry.notes!.isNotEmpty)
                _FieldTile(
                  icon: Icons.notes_rounded,
                  label: 'メモ',
                  value: _entry.notes!,
                  onCopy: () => _copyToClipboard(_entry.notes!, 'メモ'),
                  multiline: true,
                  selectable: true,
                ),

              // ── TOTP ──
              if (_entry.totp != null && _entry.totp!.isNotEmpty) ...[
                const SizedBox(height: 8),
                TotpDisplay(totpSecret: _entry.totp!),
              ],

              // ── タグ ──
              if (_entry.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'タグ',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _entry.tags
                              .map(
                                (t) => Chip(
                                  label: Text.raw(t),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // ── パスワード履歴 ──
              if (_entry.passwordHistory.isNotEmpty) ...[
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () =>
                            setState(() => _showHistory = !_showHistory),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'パスワード履歴（${_entry.passwordHistory.length}件）',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                _showHistory
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 20,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_showHistory)
                        ...List.generate(_entry.passwordHistory.length, (i) {
                          final record = _entry.passwordHistory[i];
                          final isVisible = _visibleHistoryPasswords.contains(
                            i,
                          );
                          return ListTile(
                            dense: true,
                            title: Text.raw(
                              isVisible ? record.password : '••••••••',
                              style: TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            subtitle: Text.raw(
                              _formatDate(record.changedAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    isVisible
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () => setState(() {
                                    if (isVisible) {
                                      _visibleHistoryPasswords.remove(i);
                                    } else {
                                      _visibleHistoryPasswords.add(i);
                                    }
                                  }),
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () => _copyToClipboard(
                                    record.password,
                                    '旧パスワード',
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],

              // ── メタ情報 ──
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '作成: ${_formatDate(_entry.createdAt)}\n'
                  '更新: ${_formatDate(_entry.updatedAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
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

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// フィールド表示タイル
class _FieldTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;
  final Widget? trailing;
  final bool isMonospace;
  final bool multiline;
  final bool selectable;

  const _FieldTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
    this.trailing,
    this.isMonospace = false,
    this.multiline = false,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                if (trailing != null) trailing!,
                if (onCopy != null)
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    onPressed: onCopy,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (selectable)
              _GlyphBoundedSelectableText(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: isMonospace ? 'monospace' : null,
                  height: multiline ? 1.5 : null,
                ),
              )
            else
              Text.raw(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: isMonospace ? 'monospace' : null,
                  height: multiline ? 1.5 : null,
                ),
                maxLines: multiline ? null : 2,
                overflow: multiline ? null : TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Selectable multi-line text whose highlight is limited to rendered glyphs.
///
/// A single SelectableText paints the newline selection up to the paragraph's
/// widest line. Splitting visual lines avoids that artificial horizontal
/// highlight. Each visual line keeps its trailing newline in the same text
/// paragraph, so copying a selection across lines also preserves line breaks.
class _GlyphBoundedSelectableText extends StatelessWidget {
  final String data;
  final TextStyle? style;

  const _GlyphBoundedSelectableText(this.data, {this.style});

  @override
  Widget build(BuildContext context) {
    final lines = data.split('\n');
    final selectionTextByLine = List<String>.filled(lines.length, '');
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].isEmpty) continue;
      var nextContent = index + 1;
      while (nextContent < lines.length && lines[nextContent].isEmpty) {
        nextContent++;
      }
      final newlineCount = nextContent < lines.length
          ? nextContent - index
          : lines.length - 1 - index;
      selectionTextByLine[index] =
          '${lines[index]}${List.filled(newlineCount, '\n').join()}';
    }
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final lineHeight = MediaQuery.textScalerOf(context).scale(
          effectiveStyle.fontSize ?? 14,
        ) *
        (effectiveStyle.height ?? 1);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < lines.length; index++)
            ClipRect(
              child: SizedBox(
                height: lineHeight,
                child: material.Text.rich(
                  TextSpan(
                    text: selectionTextByLine[index],
                  ),
                  style: effectiveStyle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

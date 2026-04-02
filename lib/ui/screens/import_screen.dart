/// Kuraudo インポート画面
/// 
/// KeePassXC / Bitwarden CSVのインポートUI
library;

import 'dart:io';

import 'package:flutter/material.dart';
import '../../services/csv_importer.dart';
import '../../services/vault_service.dart';
import '../theme/kuraudo_theme.dart';

class ImportScreen extends StatefulWidget {
  final VaultService vaultService;

  const ImportScreen({
    super.key,
    required this.vaultService,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _importer = CsvImporter();

  ImportSource _selectedSource = ImportSource.keepassxcCsv;
  String? _filePath;
  String? _csvContent;
  ImportResult? _result;
  bool _isImporting = false;
  bool _imported = false;

  final _pasteController = TextEditingController();

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  void _importFromPaste() {
    final content = _pasteController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSVデータを貼り付けてください')),
      );
      return;
    }

    setState(() {
      _csvContent = content;
      _result = null;
    });

    _runImport(content);
  }

  void _runImport(String content) {
    ImportResult result;
    switch (_selectedSource) {
      case ImportSource.keepassxcCsv:
        result = _importer.importKeePassXC(content);
        break;
      case ImportSource.bitwardenCsv:
        result = _importer.importBitwarden(content);
        break;
      case ImportSource.bitwardenJson:
        result = _importer.importBitwardenJson(content);
        break;
      case ImportSource.onePasswordCsv:
        result = _importer.import1Password(content);
        break;
      case ImportSource.chromeCsv:
        result = _importer.importChromeCsv(content);
        break;
      case ImportSource.genericCsv:
        result = _importer.importKeePassXC(content);
        break;
    }

    setState(() => _result = result);
  }

  /// コンテンツベースの重複判定キー
  static String _contentKey(String title, String username, String? url) {
    final t = title.trim().toLowerCase();
    final u = username.trim().toLowerCase();
    final normalizedUrl = (url ?? '').trim().toLowerCase()
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '')
        .replaceFirst(RegExp(r'/$'), '');
    if (t.isEmpty) return '';
    return '$t|$u|$normalizedUrl';
  }

  Future<void> _confirmImport() async {
    if (_result == null || _result!.entries.isEmpty) return;

    // 既存エントリとの重複を検出
    final existingEntries = widget.vaultService.vault?.activeEntries ?? [];
    final existingKeys = <String>{};
    for (final e in existingEntries) {
      final key = _contentKey(e.title, e.username, e.url);
      if (key.isNotEmpty) existingKeys.add(key);
    }

    int duplicateCount = 0;
    for (final entry in _result!.entries) {
      final key = _contentKey(entry.title, entry.username, entry.url);
      if (key.isNotEmpty && existingKeys.contains(key)) {
        duplicateCount++;
      }
    }

    // 重複がある場合は選択肢を表示
    String? action;
    if (duplicateCount > 0) {
      action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重複エントリの検出'),
          content: Text(
            '${_result!.importedCount}件中${duplicateCount}件が既存エントリと重複しています。\n\n'
            '重複の判定基準: タイトル + ユーザー名 + URL が一致',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child: Text('重複をスキップ（${_result!.importedCount - duplicateCount}件）'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: Text('全てインポート（${_result!.importedCount}件）'),
            ),
          ],
        ),
      );
      if (action == null) return;
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('インポート確認'),
          content: Text(
            '${_result!.importedCount}件のエントリをインポートします。\n'
            '既存のエントリは影響を受けません。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('インポート'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      action = 'all';
    }

    setState(() => _isImporting = true);

    try {
      int importedCount = 0;
      int skippedCount = 0;

      for (final entry in _result!.entries) {
        if (action == 'skip') {
          final key = _contentKey(entry.title, entry.username, entry.url);
          if (key.isNotEmpty && existingKeys.contains(key)) {
            skippedCount++;
            continue;
          }
        }
        widget.vaultService.vault!.addEntry(entry);
        importedCount++;
      }
      await widget.vaultService.save();

      setState(() => _imported = true);

      if (mounted) {
        final msg = skippedCount > 0
            ? '$importedCount件をインポート、$skippedCount件の重複をスキップしました'
            : '$importedCount件をインポートしました';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('インポートに失敗しました: $e')),
        );
      }
    } finally {
      setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('インポート'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'インポート元',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SourceChip(
                label: 'KeePassXC',
                icon: Icons.key_rounded,
                selected: _selectedSource == ImportSource.keepassxcCsv,
                onTap: () => setState(
                    () => _selectedSource = ImportSource.keepassxcCsv),
              ),
              _SourceChip(
                label: 'Bitwarden CSV',
                icon: Icons.shield_rounded,
                selected: _selectedSource == ImportSource.bitwardenCsv,
                onTap: () => setState(
                    () => _selectedSource = ImportSource.bitwardenCsv),
              ),
              _SourceChip(
                label: 'Bitwarden JSON',
                icon: Icons.shield_rounded,
                selected: _selectedSource == ImportSource.bitwardenJson,
                onTap: () => setState(
                    () => _selectedSource = ImportSource.bitwardenJson),
              ),
              _SourceChip(
                label: '1Password',
                icon: Icons.lock_rounded,
                selected: _selectedSource == ImportSource.onePasswordCsv,
                onTap: () => setState(
                    () => _selectedSource = ImportSource.onePasswordCsv),
              ),
              _SourceChip(
                label: 'Chrome',
                icon: Icons.language_rounded,
                selected: _selectedSource == ImportSource.chromeCsv,
                onTap: () => setState(
                    () => _selectedSource = ImportSource.chromeCsv),
              ),
              _SourceChip(
                label: '汎用CSV',
                icon: Icons.table_chart_rounded,
                selected: _selectedSource == ImportSource.genericCsv,
                onTap: () =>
                    setState(() => _selectedSource = ImportSource.genericCsv),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── ヒント ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: KuraudoTheme.info),
                      const SizedBox(width: 6),
                      Text(
                        'エクスポート手順',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: KuraudoTheme.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getHintText(),
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
          const SizedBox(height: 20),

          // ── CSV貼り付けエリア ──
          Text(
            'CSVデータを貼り付け',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pasteController,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: 'ここにCSVをペースト...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _importFromPaste,
              icon: const Icon(Icons.analytics_rounded, size: 18),
              label: const Text('解析する'),
            ),
          ),
          const SizedBox(height: 20),

          // ── 解析結果 ──
          if (_result != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _result!.importedCount > 0
                              ? Icons.check_circle_rounded
                              : Icons.warning_rounded,
                          size: 18,
                          color: _result!.importedCount > 0
                              ? KuraudoTheme.accent
                              : KuraudoTheme.warning,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '解析結果',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _ResultRow(label: '検出行数', value: '${_result!.totalRows}'),
                    _ResultRow(
                      label: 'インポート可能',
                      value: '${_result!.importedCount}件',
                      valueColor: KuraudoTheme.accent,
                    ),
                    if (_result!.skippedCount > 0)
                      _ResultRow(
                        label: 'スキップ',
                        value: '${_result!.skippedCount}件',
                        valueColor: KuraudoTheme.warning,
                      ),

                    if (_result!.warnings.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 4),
                      ...(_result!.warnings.take(5).map((w) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              w,
                              style: TextStyle(
                                fontSize: 11,
                                color: KuraudoTheme.warning,
                              ),
                            ),
                          ))),
                      if (_result!.warnings.length > 5)
                        Text(
                          '他${_result!.warnings.length - 5}件の警告...',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],

                    // プレビュー（最初の3件）
                    if (_result!.entries.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 4),
                      Text(
                        'プレビュー',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ..._result!.entries.take(3).map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Center(
                                    child: Text(
                                      e.title.isNotEmpty
                                          ? e.title[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.title,
                                        style: const TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        e.username,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )),
                      if (_result!.entries.length > 3)
                        Text(
                          '他${_result!.entries.length - 3}件...',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── インポートボタン ──
            if (_result!.entries.isNotEmpty && !_imported)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isImporting ? null : _confirmImport,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    _isImporting
                        ? 'インポート中...'
                        : '${_result!.importedCount}件をインポート',
                  ),
                ),
              ),

            if (_imported)
              Card(
                color: KuraudoTheme.accent.withValues(alpha: 0.1),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: KuraudoTheme.accent, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'インポートが完了しました',
                          style: TextStyle(
                            color: KuraudoTheme.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],

          // ── セキュリティ注意 ──
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.security_rounded,
                      size: 16, color: KuraudoTheme.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CSVファイルにはパスワードが平文で含まれています。'
                      'インポート後はCSVファイルを安全に削除してください。',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
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

  String _getHintText() {
    switch (_selectedSource) {
      case ImportSource.keepassxcCsv:
        return 'KeePassXC → データベース → CSVにエクスポート\n'
            'ヘッダー行を含めてエクスポートしてください。';
      case ImportSource.bitwardenCsv:
        return 'Bitwarden → ツール → データをエクスポート → CSV\n'
            'マスターパスワードの入力が求められます。';
      case ImportSource.bitwardenJson:
        return 'Bitwarden → ツール → データをエクスポート → JSON\n'
            'フォルダ構造も保持されます。';
      case ImportSource.onePasswordCsv:
        return '1Password → ファイル → エクスポート → CSV\n'
            'ヘッダー行を含めてエクスポートしてください。';
      case ImportSource.chromeCsv:
        return 'Chrome → 設定 → パスワード → エクスポート\n'
            'またはchrome://password-manager/settings から。';
      case ImportSource.genericCsv:
        return 'Title, Username, Password 列を含むCSVに対応。\n'
            'ヘッダー行が必要です。';
    }
  }
}

class _SourceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SourceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? KuraudoTheme.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? KuraudoTheme.accent.withValues(alpha: 0.4)
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? KuraudoTheme.accent
                    : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? KuraudoTheme.accent
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ResultRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

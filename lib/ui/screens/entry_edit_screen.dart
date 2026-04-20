/// Kuraudo エントリ編集画面
/// 
/// 新規作成 / 既存エントリの編集
/// パスワード生成器を内蔵
library;

import 'package:flutter/material.dart';
import '../../core/password_generator.dart';
import '../../models/vault_entry.dart';
import '../../services/vault_service.dart';
import '../theme/kuraudo_theme.dart';
import '../widgets/password_generator_sheet.dart';

class EntryEditScreen extends StatefulWidget {
  final VaultService vaultService;
  final VaultEntry? existingEntry;
  final String? initialCategory;

  const EntryEditScreen({
    super.key,
    required this.vaultService,
    this.existingEntry,
    this.initialCategory,
  });

  bool get isEditing => existingEntry != null;

  @override
  State<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends State<EntryEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _tagsCtrl;
  late final TextEditingController _totpCtrl;

  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _favorite = false;

  final _generator = PasswordGenerator();

  @override
  void initState() {
    super.initState();
    final e = widget.existingEntry;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _usernameCtrl = TextEditingController(text: e?.username ?? '');
    _passwordCtrl = TextEditingController(text: e?.password ?? '');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _urlCtrl = TextEditingController(text: e?.url ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _categoryCtrl = TextEditingController(
      text: e?.category ?? (widget.initialCategory != '未分類' ? widget.initialCategory : '') ?? '',
    );
    _tagsCtrl = TextEditingController(text: e?.tags.join(', ') ?? '');
    _totpCtrl = TextEditingController(text: e?.totp ?? '');
    _favorite = e?.favorite ?? false;
  }

  /// 既存のカテゴリ一覧を取得
  List<String> get _existingCategories {
    final cats = <String>{};
    for (final e in widget.vaultService.vault?.entries ?? []) {
      if (e.category != null && e.category!.isNotEmpty) cats.add(e.category!);
    }
    return cats.toList()..sort();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    _urlCtrl.dispose();
    _notesCtrl.dispose();
    _categoryCtrl.dispose();
    _tagsCtrl.dispose();
    _totpCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final tags = _tagsCtrl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      // TOTPシークレットをクリーンアップ
      final rawTotp = _totpCtrl.text.trim();
      String? cleanTotp;
      if (rawTotp.isNotEmpty) {
        if (rawTotp.startsWith('otpauth://')) {
          // otpauth:// URI はそのまま
          cleanTotp = rawTotp;
        } else {
          // 生のBase32: 空白除去 + 大文字変換
          cleanTotp = rawTotp.replaceAll(RegExp(r'\s+'), '').toUpperCase();
        }
      }

      if (widget.isEditing) {
        final entry = widget.existingEntry!;

        // パスワードが変更されていたら履歴に追加
        if (_passwordCtrl.text != entry.password) {
          entry.updatePassword(_passwordCtrl.text);
        }

        entry.title = _titleCtrl.text;
        entry.username = _usernameCtrl.text;
        entry.email = _emailCtrl.text.isNotEmpty ? _emailCtrl.text : null;
        entry.url = _urlCtrl.text.isNotEmpty ? _urlCtrl.text : null;
        entry.notes = _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null;
        entry.category = _categoryCtrl.text.isNotEmpty ? _categoryCtrl.text : null;
        entry.tags = tags;
        entry.totp = cleanTotp;
        entry.favorite = _favorite;
        entry.updatedAt = DateTime.now();

        await widget.vaultService.updateEntry(entry);
      } else {
        final newEntry = await widget.vaultService.addEntry(
          title: _titleCtrl.text,
          username: _usernameCtrl.text,
          password: _passwordCtrl.text,
          email: _emailCtrl.text.isNotEmpty ? _emailCtrl.text : null,
          url: _urlCtrl.text.isNotEmpty ? _urlCtrl.text : null,
          notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
          category: _categoryCtrl.text.isNotEmpty ? _categoryCtrl.text : null,
          tags: tags,
          favorite: _favorite,
        );
        // TOTPがあれば追加保存
        if (cleanTotp != null) {
          newEntry.totp = cleanTotp;
          await widget.vaultService.updateEntry(newEntry);
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openPasswordGenerator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PasswordGeneratorSheet(
        onSelect: (password) {
          setState(() {
            _passwordCtrl.text = password;
            _obscurePassword = false; // 生成されたパスワードを見せる
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // パスワード強度
    final strength = _generator.evaluateStrength(_passwordCtrl.text);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'エントリを編集' : '新規エントリ'),
        actions: [
          IconButton(
            icon: Icon(
              _favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _favorite ? KuraudoTheme.warning : null,
            ),
            onPressed: () => setState(() => _favorite = !_favorite),
          ),
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── タイトル（必須）──
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'タイトル *',
                hintText: 'サービス名',
                prefixIcon: Icon(Icons.title_rounded, size: 20),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'タイトルは必須です' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),

            // ── ユーザー名 ──
            TextFormField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'ユーザー名',
                hintText: 'ログインID',
                prefixIcon: Icon(Icons.person_rounded, size: 20),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),

            // ── パスワード ──
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}), // 強度表示を更新
              decoration: InputDecoration(
                labelText: 'パスワード *',
                prefixIcon: const Icon(Icons.key_rounded, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      tooltip: 'パスワード生成',
                      onPressed: _openPasswordGenerator,
                      style: IconButton.styleFrom(
                        foregroundColor: KuraudoTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'パスワードは必須です' : null,
            ),

            // ── パスワード強度バー ──
            if (_passwordCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: strength.score,
                        backgroundColor: cs.outline,
                        color: _strengthColor(strength),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    strength.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: _strengthColor(strength),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),

            // ── メール ──
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'メールアドレス',
                prefixIcon: Icon(Icons.email_rounded, size: 20),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),

            // ── URL ──
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://',
                prefixIcon: Icon(Icons.link_rounded, size: 20),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),

            // ── カテゴリ/フォルダ（矢印プルダウンのみで選択 or 新規入力）──
            TextFormField(
              controller: _categoryCtrl,
              decoration: InputDecoration(
                labelText: 'カテゴリ/フォルダ',
                hintText: '既存フォルダから選択 or 新規入力',
                prefixIcon: const Icon(Icons.folder_rounded, size: 20),
                suffixIcon: _existingCategories.isNotEmpty
                    ? PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
                        tooltip: '既存フォルダから選択',
                        popUpAnimationStyle: AnimationStyle(duration: Duration.zero),
                        onSelected: (v) { _categoryCtrl.text = v; },
                        itemBuilder: (_) => _existingCategories.map((c) => PopupMenuItem(value: c, child: Row(children: [const Icon(Icons.folder_rounded, size: 16), const SizedBox(width: 8), Text(c)]))).toList(),
                      )
                    : null,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),

            // ── タグ ──
            TextFormField(
              controller: _tagsCtrl,
              decoration: const InputDecoration(
                labelText: 'タグ',
                hintText: 'カンマ区切りで入力',
                prefixIcon: Icon(Icons.label_rounded, size: 20),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),

            // ── メモ ──
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'メモ',
                prefixIcon: Icon(Icons.notes_rounded, size: 20),
                alignLabelWithHint: true,
              ),
              maxLines: null,
              minLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 14),

            // ── TOTP シークレット ──
            TextFormField(
              controller: _totpCtrl,
              decoration: const InputDecoration(
                labelText: 'TOTP シークレット',
                hintText: 'Base32キー or otpauth://...',
                prefixIcon: Icon(Icons.security_rounded, size: 20),
              ),
              textInputAction: TextInputAction.done,
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Color _strengthColor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.veryWeak:
        return KuraudoTheme.danger;
      case PasswordStrength.weak:
        return const Color(0xFFEF4444);
      case PasswordStrength.fair:
        return KuraudoTheme.warning;
      case PasswordStrength.strong:
        return KuraudoTheme.accent;
      case PasswordStrength.veryStrong:
        return const Color(0xFF22C55E);
    }
  }
}

/// Kuraudo メイン画面
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/vault_entry.dart';
import '../../services/vault_service.dart';
import '../../services/google_drive_service.dart';
import '../../services/sync_manager.dart';
import '../../services/autofill_service.dart';
import '../../core/password_generator.dart';
import '../theme/kuraudo_theme.dart';
import 'entry_detail_screen.dart';
import 'entry_edit_screen.dart';
import 'account_link_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';

class HomeScreen extends StatefulWidget {
  final VaultService vaultService;
  final GoogleDriveService driveService;
  final SyncManager syncManager;
  final VoidCallback onLock;
  final VoidCallback? onInteraction;
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
  // クリップボード自動クリア
  final bool clipboardAutoClear;
  final void Function(bool) onClipboardAutoClearChanged;
  // PIN/生体認証
  final bool pinEnabled;
  final bool biometricEnabled;
  final int pinThresholdMinutes;
  final void Function(bool) onPinEnabledChanged;
  final void Function(bool) onBiometricEnabledChanged;
  final void Function(int) onPinThresholdChanged;
  final dynamic secureStorage; // FlutterSecureStorage
  const HomeScreen({super.key, required this.vaultService, required this.driveService, required this.syncManager, required this.onLock, this.onInteraction, this.autoLockMinutes = 5, this.passwordExpiryDays = 90, required this.onAutoLockChanged, required this.onPasswordExpiryChanged, this.themeMode = 'dark', required this.onThemeModeChanged, this.autoSyncEnabled = true, this.realtimeSyncEnabled = true, required this.onAutoSyncChanged, required this.onRealtimeSyncChanged, this.clipboardAutoClear = true, required this.onClipboardAutoClearChanged, this.pinEnabled = false, this.biometricEnabled = false, this.pinThresholdMinutes = 5, required this.onPinEnabledChanged, required this.onBiometricEnabledChanged, required this.onPinThresholdChanged, this.secureStorage});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _SortMode { titleAsc, titleDesc, createdAsc, createdDesc, updatedAsc, updatedDesc }

class _HomeScreenState extends State<HomeScreen> {
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedCategory;
  bool _showFavoritesOnly = false;
  bool _showTrash = false;
  _SortMode _sortMode = _SortMode.updatedDesc;
  int _focusedIndex = -1;
  String _statusMessage = '';
  List<VaultEntry> _cachedEntries = [];
  bool _dirty = true;
  bool _searchFocused = false;
  bool _multiSelectMode = false;
  final Set<String> _selectedUuids = {};

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _loadUIState();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // ── キーボード（Focus系ウィジェット不使用） ──
  bool _onKey(KeyEvent event) {
    if (_searchFocused) return false; // 検索フィールド入力中はスルー
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final entries = _cachedEntries;
    final i = _focusedIndex;
    final k = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;

    if (ctrl && k == LogicalKeyboardKey.keyC && i >= 0 && i < entries.length) { _copyPassword(entries[i]); return true; }
    if (ctrl && k == LogicalKeyboardKey.keyB && i >= 0 && i < entries.length) { _copyUsername(entries[i]); return true; }
    if (!alt && k == LogicalKeyboardKey.arrowDown && entries.isNotEmpty) { setState(() => _focusedIndex = (i + 1).clamp(0, entries.length - 1)); return true; }
    if (!alt && k == LogicalKeyboardKey.arrowUp && entries.isNotEmpty) { setState(() => _focusedIndex = (i - 1).clamp(0, entries.length - 1)); return true; }
    if (k == LogicalKeyboardKey.enter && i >= 0 && i < entries.length) { _openEntry(entries[i]); return true; }
    if (alt && k == LogicalKeyboardKey.arrowUp && i > 0) { _moveEntry(i, -1); return true; }
    if (alt && k == LogicalKeyboardKey.arrowDown && i >= 0 && i < entries.length - 1) { _moveEntry(i, 1); return true; }
    return false;
  }

  // ── エントリキャッシュ ──
  List<VaultEntry> get _entries {
    if (!_dirty) return _cachedEntries;
    var e = _showTrash
        ? List<VaultEntry>.from(widget.vaultService.vault?.trashedEntries ?? [])
        : List<VaultEntry>.from(widget.vaultService.vault?.activeEntries ?? []);
    if (!_showTrash && _showFavoritesOnly) e = e.where((x) => x.favorite).toList();
    if (!_showTrash && _selectedCategory != null) e = e.where((x) => (x.category ?? '未分類') == _selectedCategory).toList();
    if (_searchQuery.isNotEmpty) { final q = _searchQuery.toLowerCase(); e = e.where((x) => x.title.toLowerCase().contains(q) || x.username.toLowerCase().contains(q) || (x.email?.toLowerCase().contains(q) ?? false) || (x.url?.toLowerCase().contains(q) ?? false)).toList(); }
    switch (_sortMode) {
      case _SortMode.titleAsc: e.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _SortMode.titleDesc: e.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
      case _SortMode.createdAsc: e.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _SortMode.createdDesc: e.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _SortMode.updatedAsc: e.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case _SortMode.updatedDesc: e.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    _cachedEntries = e;
    _dirty = false;
    return e;
  }

  void _markDirty() => _dirty = true;
  List<String> get _categories { final c = <String>{}; for (final e in widget.vaultService.vault?.activeEntries ?? []) c.add(e.category ?? '未分類'); return c.toList()..sort(); }
  Map<String, int> get _categoryCounts { final m = <String, int>{}; for (final e in widget.vaultService.vault?.activeEntries ?? []) { final c = e.category ?? '未分類'; m[c] = (m[c] ?? 0) + 1; } return m; }
  void _refresh() {
    // 選択中のカテゴリにエントリが無くなった場合はリセット
    if (_selectedCategory != null && !_categories.contains(_selectedCategory)) {
      _selectedCategory = null;
    }
    _markDirty(); setState(() {});
  }

  void _showStatus(String msg) { _statusMessage = msg; setState(() {}); Future.delayed(const Duration(seconds: 4), () { if (mounted && _statusMessage == msg) setState(() => _statusMessage = ''); }); }

  Future<String> get _statePath async { final d = await getApplicationDocumentsDirectory(); return '${d.path}/kuraudo_ui_state.json'; }
  Future<void> _loadUIState() async { try { final f = File(await _statePath); if (await f.exists()) { final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>; _selectedCategory = j['selectedCategory'] as String?; _showFavoritesOnly = j['showFavoritesOnly'] as bool? ?? false; _sortMode = _SortMode.values[j['sortMode'] as int? ?? 5]; _markDirty(); setState(() {}); } } catch (_) {} }
  Future<void> _saveUIState() async { try { final f = File(await _statePath); await f.writeAsString(jsonEncode({'selectedCategory': _selectedCategory, 'showFavoritesOnly': _showFavoritesOnly, 'sortMode': _sortMode.index})); } catch (_) {} }

  void _setCategory(String? c) { _selectedCategory = c; _showTrash = false; _focusedIndex = -1; _markDirty(); setState(() {}); _saveUIState(); }
  void _setSort(_SortMode m) { _sortMode = m; _focusedIndex = -1; _markDirty(); setState(() {}); _saveUIState(); }
  void _setTrashView() { _showTrash = !_showTrash; if (_showTrash) { _selectedCategory = null; _showFavoritesOnly = false; } _focusedIndex = -1; _markDirty(); setState(() {}); }
  void _setFavFilter() { _showFavoritesOnly = !_showFavoritesOnly; if (_showFavoritesOnly) { _selectedCategory = null; _showTrash = false; } _focusedIndex = -1; _markDirty(); setState(() {}); _saveUIState(); }

  Future<void> _addEntry() async { final r = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EntryEditScreen(vaultService: widget.vaultService, initialCategory: _selectedCategory))); if (r == true) _refresh(); }
  Future<void> _openEntry(VaultEntry e) async { final r = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EntryDetailScreen(vaultService: widget.vaultService, entry: e))); if (r == true) _refresh(); }
  Future<void> _duplicateEntry(VaultEntry e) async { widget.vaultService.vault?.addEntry(VaultEntry(uuid: Uuid().v4(), title: '${e.title} (コピー)', username: e.username, password: e.password, email: e.email, url: e.url, notes: e.notes, category: e.category, tags: List.from(e.tags), totp: e.totp, favorite: false)); await widget.vaultService.save(); _showStatus('複製しました'); _refresh(); }
  void _copyPassword(VaultEntry e) {
    copyAndScheduleClear(e.password, autoClearEnabled: widget.clipboardAutoClear);
    _showStatus('パスワードをコピー${widget.clipboardAutoClear ? "（30秒後クリア）" : ""}');
  }
  void _copyUsername(VaultEntry e) {
    Clipboard.setData(ClipboardData(text: e.username));
    _showStatus('ユーザー名をコピー');
  }
  Future<void> _openUrl(String url) async { var u = url; if (!u.startsWith('http')) u = 'https://$u'; try { await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication); } catch (_) { _showStatus('URLを開けませんでした'); } }

  Future<void> _renameCategory(String old) async {
    final ctrl = TextEditingController(text: old == '未分類' ? '' : old);
    final existingCats = _categories.where((c) => c != old).toList();
    final n = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('カテゴリ/フォルダ名を変更'), content: Row(children: [
      Expanded(child: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '新しいフォルダ名'), onSubmitted: (v) => Navigator.pop(ctx, v))),
      if (existingCats.isNotEmpty) PopupMenuButton<String>(
        icon: const Icon(Icons.arrow_drop_down_rounded, size: 24),
        tooltip: '既存フォルダから選択',
        popUpAnimationStyle: AnimationStyle(duration: Duration.zero),
        onSelected: (v) { ctrl.text = v; },
        itemBuilder: (_) => existingCats.map((c) => PopupMenuItem(value: c, child: Row(children: [const Icon(Icons.folder_rounded, size: 16), const SizedBox(width: 8), Text(c)]))).toList(),
      ),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')), ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('変更'))]));
    if (n == null) return; final t = n.trim().isEmpty ? null : n.trim();
    for (final e in widget.vaultService.vault?.entries ?? []) { if ((e.category ?? '未分類') == old) { e.category = t; e.updatedAt = DateTime.now(); } }
    await widget.vaultService.save(); if (_selectedCategory == old) _selectedCategory = t ?? '未分類'; _showStatus('フォルダ名を変更しました'); _refresh();
  }

  void _moveEntry(int idx, int dir) {
    final all = widget.vaultService.vault?.entries; if (all == null) return;
    final filtered = _cachedEntries;
    if (idx + dir < 0 || idx + dir >= filtered.length) return;
    final a = filtered[idx], b = filtered[idx + dir];
    final ai = all.indexOf(a), bi = all.indexOf(b);
    if (ai >= 0 && bi >= 0) { all[ai] = b; all[bi] = a; widget.vaultService.save(); _focusedIndex = idx + dir; _refresh(); }
  }

  void _showWeakPasswords() {
    final gen = PasswordGenerator(); final weak = <VaultEntry>[];
    for (final e in widget.vaultService.vault?.activeEntries ?? []) { final s = gen.evaluateStrength(e.password); if (s == PasswordStrength.veryWeak || s == PasswordStrength.weak) weak.add(e); }
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('弱いパスワード（${weak.length}件）'), content: SizedBox(width: 400, height: 300, child: weak.isEmpty ? const Center(child: Text('弱いパスワードはありません 🎉')) : ListView(children: weak.map((e) => ListTile(dense: true, title: Text(e.title), subtitle: Text(e.username), leading: const Icon(Icons.warning_rounded, color: KuraudoTheme.warning, size: 18), onTap: () { Navigator.pop(ctx); _openEntry(e); })).toList())), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))]));
  }

  // ── ダッシュボード統計 ──
  int get _weakCount { final gen = PasswordGenerator(); int c = 0; for (final e in widget.vaultService.vault?.activeEntries ?? []) { final s = gen.evaluateStrength(e.password); if (s == PasswordStrength.veryWeak || s == PasswordStrength.weak) c++; } return c; }
  int get _duplicatePasswordCount { final pws = <String, int>{}; for (final e in widget.vaultService.vault?.activeEntries ?? []) { if (e.password.isNotEmpty) pws[e.password] = (pws[e.password] ?? 0) + 1; } return pws.values.where((c) => c > 1).fold(0, (a, b) => a + b); }
  List<VaultEntry> get _expiredPasswords { if (widget.passwordExpiryDays <= 0) return []; final cutoff = DateTime.now().subtract(Duration(days: widget.passwordExpiryDays)); return (widget.vaultService.vault?.activeEntries ?? []).where((e) => e.updatedAt.isBefore(cutoff)).toList(); }

  List<Widget> _buildStatsBadges(ColorScheme cs) {
    final badges = <Widget>[];
    final weak = _weakCount;
    final dup = _duplicatePasswordCount;
    if (weak > 0) badges.addAll([Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: KuraudoTheme.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.warning_rounded, size: 10, color: KuraudoTheme.danger), const SizedBox(width: 3), Text('弱$weak', style: TextStyle(fontSize: 10, color: KuraudoTheme.danger))])), const SizedBox(width: 4)]);
    if (dup > 0) badges.addAll([Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: KuraudoTheme.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.copy_rounded, size: 10, color: KuraudoTheme.warning), const SizedBox(width: 3), Text('重複$dup', style: TextStyle(fontSize: 10, color: KuraudoTheme.warning))])), const SizedBox(width: 4)]);
    return badges;
  }

  void _showExpiredPasswords() {
    final expired = _expiredPasswords;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('期限切れパスワード（${expired.length}件）'), content: SizedBox(width: 400, height: 300, child: expired.isEmpty ? const Center(child: Text('期限切れのパスワードはありません 🎉')) : ListView(children: expired.map((e) { final days = DateTime.now().difference(e.updatedAt).inDays; return ListTile(dense: true, title: Text(e.title), subtitle: Text('${days}日前に更新'), leading: const Icon(Icons.schedule_rounded, color: KuraudoTheme.warning, size: 18), onTap: () { Navigator.pop(ctx); _openEntry(e); }); }).toList())), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))]));
  }

  void _showDuplicatePasswords() {
    final pws = <String, List<VaultEntry>>{};
    for (final e in widget.vaultService.vault?.activeEntries ?? []) {
      if (e.password.isNotEmpty) pws.putIfAbsent(e.password, () => []).add(e);
    }
    pws.removeWhere((_, list) => list.length < 2);
    final groups = pws.values.toList();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('重複パスワード（${groups.length}グループ）'),
      content: SizedBox(width: 400, height: 400, child: groups.isEmpty
        ? const Center(child: Text('重複パスワードはありません 🎉'))
        : ListView(children: groups.map((group) => ExpansionTile(
            title: Text('${group.length}件が同じパスワード', style: const TextStyle(fontSize: 13)),
            leading: Icon(Icons.copy_rounded, size: 18, color: KuraudoTheme.warning),
            children: group.map((e) => ListTile(dense: true, title: Text(e.title), subtitle: Text(e.username), onTap: () { Navigator.pop(ctx); _openEntry(e); })).toList(),
          )).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
    ));
  }

  void _toggleSelect(String uuid) {
    setState(() {
      if (_selectedUuids.contains(uuid)) { _selectedUuids.remove(uuid); } else { _selectedUuids.add(uuid); }
      if (_selectedUuids.isEmpty) _multiSelectMode = false;
    });
  }

  void _enterMultiSelect(String uuid) {
    setState(() { _multiSelectMode = true; _selectedUuids.add(uuid); });
  }

  Future<void> _bulkChangeCategory() async {
    final ctrl = TextEditingController();
    final newCat = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text('${_selectedUuids.length}件のカテゴリを変更'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '新しいカテゴリ名')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('変更')),
      ],
    ));
    if (newCat == null) return;
    final cat = newCat.trim().isEmpty ? null : newCat.trim();
    for (final uuid in _selectedUuids) {
      final e = widget.vaultService.vault?.findByUuid(uuid);
      if (e != null) { e.category = cat; e.updatedAt = DateTime.now(); }
    }
    await widget.vaultService.save();
    _showStatus('${_selectedUuids.length}件のカテゴリを変更しました');
    setState(() { _multiSelectMode = false; _selectedUuids.clear(); });
    _refresh();
  }

  Future<void> _bulkTrash() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('${_selectedUuids.length}件をゴミ箱に移動'),
      content: const Text('選択したエントリをゴミ箱に移動しますか？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: KuraudoTheme.danger), child: const Text('ゴミ箱に移動')),
      ],
    ));
    if (confirm != true) return;
    for (final uuid in _selectedUuids) { await widget.vaultService.trashEntry(uuid); }
    _showStatus('${_selectedUuids.length}件をゴミ箱に移動しました');
    setState(() { _multiSelectMode = false; _selectedUuids.clear(); });
    _refresh();
  }

  void _ctxMenu(VaultEntry e, Offset pos) {
    showMenu<dynamic>(context: context, position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1), popUpAnimationStyle: AnimationStyle(duration: Duration.zero), items: <PopupMenuEntry<dynamic>>[
      PopupMenuItem<dynamic>(onTap: () => _copyPassword(e), child: const Row(children: [Icon(Icons.key_rounded, size: 16), SizedBox(width: 8), Text('パスワードをコピー')])),
      PopupMenuItem<dynamic>(onTap: () => _copyUsername(e), child: const Row(children: [Icon(Icons.person_rounded, size: 16), SizedBox(width: 8), Text('ユーザー名をコピー')])),
      if (e.url != null && e.url!.isNotEmpty) PopupMenuItem<dynamic>(onTap: () => _openUrl(e.url!), child: const Row(children: [Icon(Icons.open_in_new_rounded, size: 16), SizedBox(width: 8), Text('ブラウザで開く')])),
      const PopupMenuDivider(),
      PopupMenuItem<dynamic>(onTap: () => _openEntry(e), child: const Row(children: [Icon(Icons.edit_rounded, size: 16), SizedBox(width: 8), Text('編集')])),
      PopupMenuItem<dynamic>(onTap: () => _duplicateEntry(e), child: const Row(children: [Icon(Icons.copy_all_rounded, size: 16), SizedBox(width: 8), Text('複製')])),
      const PopupMenuDivider(),
      PopupMenuItem<dynamic>(onTap: () async { await widget.vaultService.trashEntry(e.uuid); _showStatus('ゴミ箱に移動しました'); _refresh(); }, child: Row(children: [Icon(Icons.delete_rounded, size: 16, color: KuraudoTheme.danger), const SizedBox(width: 8), Text('ゴミ箱に移動', style: TextStyle(color: KuraudoTheme.danger))])),
    ]);
  }

  String _fmtDate(DateTime dt) => '${dt.year}/${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')}';

  void _showSortMenu(BuildContext ctx) {
    final RenderBox button = ctx.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(ctx).overlay!.context.findRenderObject() as RenderBox;
    final pos = button.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = RelativeRect.fromLTRB(pos.dx, pos.dy + button.size.height, overlay.size.width - pos.dx - button.size.width, 0);
    showMenu<_SortMode>(context: ctx, position: rect, popUpAnimationStyle: AnimationStyle(duration: Duration.zero), items: <PopupMenuEntry<_SortMode>>[
      _smi(_SortMode.titleAsc, 'タイトル（A→Z）'), _smi(_SortMode.titleDesc, 'タイトル（Z→A）'), const PopupMenuDivider(),
      _smi(_SortMode.createdDesc, '作成日（新しい順）'), _smi(_SortMode.createdAsc, '作成日（古い順）'), const PopupMenuDivider(),
      _smi(_SortMode.updatedDesc, '更新日（新しい順）'), _smi(_SortMode.updatedAsc, '更新日（古い順）'),
    ]).then((v) { if (v != null) _setSort(v); });
  }

  void _showMainMenu(BuildContext ctx) {
    final RenderBox button = ctx.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(ctx).overlay!.context.findRenderObject() as RenderBox;
    final pos = button.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = RelativeRect.fromLTRB(pos.dx, pos.dy + button.size.height, overlay.size.width - pos.dx - button.size.width, 0);
    showMenu<String>(context: ctx, position: rect, popUpAnimationStyle: AnimationStyle(duration: Duration.zero), items: <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'sync', child: Row(children: [Icon(Icons.cloud_sync_rounded, size: 18), SizedBox(width: 10), Text('クラウド同期')])),
      const PopupMenuItem(value: 'accounts', child: Row(children: [Icon(Icons.people_rounded, size: 18), SizedBox(width: 10), Text('アカウント紐付け')])),
      const PopupMenuItem(value: 'import', child: Row(children: [Icon(Icons.upload_rounded, size: 18), SizedBox(width: 10), Text('インポート')])),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'weak', child: Row(children: [Icon(Icons.warning_rounded, size: 18), SizedBox(width: 10), Text('弱いパスワード')])),
      const PopupMenuItem(value: 'duplicate', child: Row(children: [Icon(Icons.copy_rounded, size: 18), SizedBox(width: 10), Text('重複パスワード')])),
      const PopupMenuItem(value: 'expired', child: Row(children: [Icon(Icons.schedule_rounded, size: 18), SizedBox(width: 10), Text('期限切れパスワード')])),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_rounded, size: 18), SizedBox(width: 10), Text('設定')])),
    ]).then((v) { if (v == null) return; switch(v) { case 'sync': Navigator.push(context, MaterialPageRoute(builder: (_) => SyncScreen(vaultService: widget.vaultService, driveService: widget.driveService, syncManager: widget.syncManager))).then((_) => _refresh()); case 'accounts': Navigator.push(context, MaterialPageRoute(builder: (_) => AccountLinkScreen(vaultService: widget.vaultService))).then((_) => _refresh()); case 'import': Navigator.push(context, MaterialPageRoute(builder: (_) => ImportScreen(vaultService: widget.vaultService))).then((_) => _refresh()); case 'settings': Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(vaultService: widget.vaultService, autoLockMinutes: widget.autoLockMinutes, passwordExpiryDays: widget.passwordExpiryDays, onAutoLockChanged: widget.onAutoLockChanged, onPasswordExpiryChanged: widget.onPasswordExpiryChanged, themeMode: widget.themeMode, onThemeModeChanged: widget.onThemeModeChanged, autoSyncEnabled: widget.autoSyncEnabled, realtimeSyncEnabled: widget.realtimeSyncEnabled, onAutoSyncChanged: widget.onAutoSyncChanged, onRealtimeSyncChanged: widget.onRealtimeSyncChanged, clipboardAutoClear: widget.clipboardAutoClear, onClipboardAutoClearChanged: widget.onClipboardAutoClearChanged, pinEnabled: widget.pinEnabled, biometricEnabled: widget.biometricEnabled, pinThresholdMinutes: widget.pinThresholdMinutes, onPinEnabledChanged: widget.onPinEnabledChanged, onBiometricEnabledChanged: widget.onBiometricEnabledChanged, onPinThresholdChanged: widget.onPinThresholdChanged, secureStorage: widget.secureStorage))); case 'weak': _showWeakPasswords(); case 'duplicate': _showDuplicatePasswords(); case 'expired': _showExpiredPasswords(); } });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 700;
    return Listener(
      onPointerDown: (_) => widget.onInteraction?.call(),
      onPointerMove: (_) => widget.onInteraction?.call(),
      child: Scaffold(
      appBar: AppBar(title: _multiSelectMode ? Text('${_selectedUuids.length}件選択中') : const Text('Kuraudo'),
        leading: _multiSelectMode
          ? IconButton(icon: const Icon(Icons.close_rounded, size: 20), tooltip: '選択解除', onPressed: () => setState(() { _multiSelectMode = false; _selectedUuids.clear(); }))
          : IconButton(icon: const Icon(Icons.lock_rounded, size: 20), tooltip: 'ロック', onPressed: () { widget.vaultService.lock(); widget.onLock(); }),
        actions: _multiSelectMode ? [
          IconButton(icon: const Icon(Icons.select_all_rounded, size: 20), tooltip: '全選択', onPressed: () => setState(() { for (final e in _cachedEntries) _selectedUuids.add(e.uuid); })),
          IconButton(icon: const Icon(Icons.folder_rounded, size: 20), tooltip: 'カテゴリ変更', onPressed: _selectedUuids.isNotEmpty ? _bulkChangeCategory : null),
          IconButton(icon: Icon(Icons.delete_rounded, size: 20, color: KuraudoTheme.danger), tooltip: 'ゴミ箱に移動', onPressed: _selectedUuids.isNotEmpty ? _bulkTrash : null),
        ] : [
          Builder(builder: (btnCtx) => IconButton(icon: const Icon(Icons.sort_rounded, size: 20), tooltip: 'ソート', onPressed: () => _showSortMenu(btnCtx))),
          IconButton(icon: Icon(_showFavoritesOnly ? Icons.star_rounded : Icons.star_outline_rounded, color: _showFavoritesOnly ? KuraudoTheme.warning : null), tooltip: 'お気に入り', onPressed: _setFavFilter),
          if (!isWide) IconButton(icon: Icon(Icons.delete_rounded, size: 20, color: _showTrash ? KuraudoTheme.danger : null), tooltip: 'ゴミ箱', onPressed: _setTrashView),
          Builder(builder: (btnCtx) => IconButton(icon: const Icon(Icons.more_vert_rounded, size: 20), tooltip: 'メニュー', onPressed: () => _showMainMenu(btnCtx))),
        ],
      ),
      body: Column(children: [
        Expanded(child: isWide ? _wide(entries, cs) : _narrow(entries, cs)),
        if (_statusMessage.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), color: cs.surfaceContainerHighest, child: Row(children: [const Icon(Icons.info_outline_rounded, size: 14, color: KuraudoTheme.accent), const SizedBox(width: 8), Expanded(child: Text(_statusMessage, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)), GestureDetector(onTap: () => setState(() => _statusMessage = ''), child: Icon(Icons.close_rounded, size: 14, color: cs.onSurfaceVariant))])),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: _addEntry, child: const Icon(Icons.add_rounded)),
    ));
  }

  PopupMenuItem<_SortMode> _smi(_SortMode m, String l) => PopupMenuItem(value: m, child: Row(children: [if (_sortMode == m) const Icon(Icons.check_rounded, size: 16, color: KuraudoTheme.accent) else const SizedBox(width: 16), const SizedBox(width: 8), Text(l, style: const TextStyle(fontSize: 13))]));

  Widget _wide(List<VaultEntry> entries, ColorScheme cs) => Row(children: [
    SizedBox(width: 220, child: Container(decoration: BoxDecoration(border: Border(right: BorderSide(color: cs.outline))), child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 8), child: Row(children: [Icon(Icons.folder_rounded, size: 16, color: cs.onSurfaceVariant), const SizedBox(width: 6), Text('フォルダ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))])),
      _FT(label: 'すべて', count: widget.vaultService.vault?.activeEntries.length ?? 0, sel: _selectedCategory == null && !_showFavoritesOnly && !_showTrash, icon: Icons.all_inbox_rounded, onTap: () { _showTrash = false; _setCategory(null); }),
      _FT(label: 'お気に入り', count: widget.vaultService.vault?.favorites.length ?? 0, sel: _showFavoritesOnly, icon: Icons.star_rounded, iconColor: KuraudoTheme.warning, onTap: _setFavFilter),
      const Divider(height: 1, indent: 16, endIndent: 16),
      Expanded(child: ListView(children: [for (final cat in _categories) _FT(label: cat, count: _categoryCounts[cat] ?? 0, sel: _selectedCategory == cat && !_showTrash, icon: Icons.folder_rounded, onTap: () => _setCategory(_selectedCategory == cat ? null : cat), onRename: () => _renameCategory(cat))])),
      const Divider(height: 1, indent: 16, endIndent: 16),
      _FT(label: 'ゴミ箱', count: widget.vaultService.vault?.trashedEntries.length ?? 0, sel: _showTrash, icon: Icons.delete_rounded, iconColor: KuraudoTheme.danger, onTap: _setTrashView),
    ]))),
    Expanded(child: _showTrash ? _trashList(entries, cs) : _pcList(entries, cs)),
  ]);

  Widget _narrow(List<VaultEntry> entries, ColorScheme cs) => _showTrash ? _trashListMobile(entries, cs) : _mobList(entries, cs);

  /// ゴミ箱リスト（PC）
  Widget _trashList(List<VaultEntry> entries, ColorScheme cs) {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8), child: Row(children: [
        Icon(Icons.delete_rounded, size: 18, color: KuraudoTheme.danger),
        const SizedBox(width: 8),
        Text('ゴミ箱', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(width: 8),
        Text('${entries.length}件', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
        const Spacer(),
        if (entries.isNotEmpty) TextButton.icon(
          onPressed: () => _emptyTrash(),
          icon: Icon(Icons.delete_forever_rounded, size: 16, color: KuraudoTheme.danger),
          label: Text('ゴミ箱を空にする', style: TextStyle(fontSize: 12, color: KuraudoTheme.danger)),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ])),
      const Divider(height: 1),
      Expanded(child: entries.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.delete_outline_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('ゴミ箱は空です', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
          ]))
        : ListView.builder(itemCount: entries.length, padding: const EdgeInsets.only(bottom: 80), itemBuilder: (_, i) {
            final e = entries[i];
            return Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Row(children: [
              Container(width: 32, height: 32, decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Center(child: Text(e.title.isNotEmpty ? e.title[0].toUpperCase() : '?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)))),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: Text(e.title, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(e.category ?? '未分類', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)), overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text('削除: ${_fmtDate(e.deletedAt!)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace'))),
              Tooltip(message: '復元', waitDuration: Duration.zero, child: IconButton(icon: Icon(Icons.restore_rounded, size: 18, color: KuraudoTheme.accent), onPressed: () async { await widget.vaultService.restoreEntry(e.uuid); _showStatus('復元しました'); _refresh(); }, visualDensity: VisualDensity.compact)),
              Tooltip(message: '完全に削除', waitDuration: Duration.zero, child: IconButton(icon: Icon(Icons.delete_forever_rounded, size: 18, color: KuraudoTheme.danger), onPressed: () async {
                final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('完全に削除'), content: Text('「${e.title}」を完全に削除しますか？\nこの操作は取り消せません。'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')), TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: KuraudoTheme.danger), child: const Text('削除'))]));
                if (confirm == true) { await widget.vaultService.deleteEntry(e.uuid); _showStatus('完全に削除しました'); _refresh(); }
              }, visualDensity: VisualDensity.compact)),
            ]));
          }),
      ),
    ]);
  }

  /// ゴミ箱リスト（モバイル）
  Widget _trashListMobile(List<VaultEntry> entries, ColorScheme cs) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700), child: Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
      Icon(Icons.delete_rounded, size: 18, color: KuraudoTheme.danger),
      const SizedBox(width: 8),
      Text('ゴミ箱 (${entries.length}件)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
      const Spacer(),
      if (entries.isNotEmpty) TextButton(onPressed: _emptyTrash, child: Text('空にする', style: TextStyle(fontSize: 12, color: KuraudoTheme.danger))),
    ])),
    Expanded(child: entries.isEmpty
      ? Center(child: Text('ゴミ箱は空です', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)))
      : ListView.builder(itemCount: entries.length, padding: const EdgeInsets.only(bottom: 80), itemBuilder: (_, i) {
          final e = entries[i];
          return Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Center(child: Text(e.title.isNotEmpty ? e.title[0].toUpperCase() : '?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis), const SizedBox(height: 2), Text('削除: ${_fmtDate(e.deletedAt!)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))])),
            IconButton(icon: Icon(Icons.restore_rounded, size: 20, color: KuraudoTheme.accent), tooltip: '復元', onPressed: () async { await widget.vaultService.restoreEntry(e.uuid); _showStatus('復元しました'); _refresh(); }),
            IconButton(icon: Icon(Icons.delete_forever_rounded, size: 20, color: KuraudoTheme.danger), tooltip: '完全削除', onPressed: () async {
              final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('完全に削除'), content: Text('「${e.title}」を完全に削除しますか？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')), TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: KuraudoTheme.danger), child: const Text('削除'))]));
              if (confirm == true) { await widget.vaultService.deleteEntry(e.uuid); _showStatus('完全に削除しました'); _refresh(); }
            }),
          ])));
        })),
  ])));

  Future<void> _emptyTrash() async {
    final count = widget.vaultService.trashedEntries.length;
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('ゴミ箱を空にする'), content: Text('$count件のエントリを完全に削除しますか？\nこの操作は取り消せません。'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')), TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: KuraudoTheme.danger), child: const Text('すべて削除'))]));
    if (confirm == true) { await widget.vaultService.emptyTrash(); _showStatus('ゴミ箱を空にしました'); _refresh(); }
  }

  Widget _pcList(List<VaultEntry> entries, ColorScheme cs) {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Focus(
        onFocusChange: (f) => _searchFocused = f,
        child: TextField(controller: _searchCtrl, onChanged: (v) { _searchQuery = v; _markDirty(); setState(() {}); }, decoration: InputDecoration(hintText: 'エントリを検索...', prefixIcon: const Icon(Icons.search_rounded, size: 20), suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), tooltip: 'クリア', onPressed: () { _searchCtrl.clear(); _searchQuery = ''; _markDirty(); setState(() {}); }) : null, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12))),
      )),
      Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outline))),
        child: Row(children: [const SizedBox(width: 48), Expanded(flex: 3, child: Text('タイトル', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))), Expanded(flex: 3, child: Text('ユーザー名', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))), Expanded(flex: 2, child: Text('カテゴリ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))), Expanded(flex: 2, child: Text('更新日', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))), const SizedBox(width: 80)])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: Row(children: [Text('${entries.length}件', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace')), if (_selectedCategory != null) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: KuraudoTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text(_selectedCategory!, style: const TextStyle(fontSize: 10, color: KuraudoTheme.accent)))], const Spacer(), ..._buildStatsBadges(cs)])),
      if (_expiredPasswords.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2), child: GestureDetector(onTap: _showExpiredPasswords, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: KuraudoTheme.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: KuraudoTheme.warning.withValues(alpha: 0.3))), child: Row(children: [Icon(Icons.schedule_rounded, size: 14, color: KuraudoTheme.warning), const SizedBox(width: 6), Text('${_expiredPasswords.length}件のパスワードが${widget.passwordExpiryDays}日以上未変更', style: TextStyle(fontSize: 11, color: KuraudoTheme.warning)), const Spacer(), Icon(Icons.chevron_right_rounded, size: 16, color: KuraudoTheme.warning)])))),
      Expanded(child: entries.isEmpty
        ? Center(child: Text('エントリがありません', style: TextStyle(color: cs.onSurfaceVariant)))
        : ListView.builder(itemCount: entries.length, padding: const EdgeInsets.only(bottom: 80), itemBuilder: (_, i) {
            final e = entries[i];
            final isSel = _selectedUuids.contains(e.uuid);
            return Listener(
              onPointerDown: (_) => setState(() => _focusedIndex = i),
              child: GestureDetector(
                onDoubleTap: () => _multiSelectMode ? _toggleSelect(e.uuid) : _openEntry(e),
                onLongPress: () => _multiSelectMode ? null : _enterMultiSelect(e.uuid),
                onTap: _multiSelectMode ? () => _toggleSelect(e.uuid) : null,
                onSecondaryTapUp: (d) => _ctxMenu(e, d.globalPosition),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), color: isSel ? KuraudoTheme.accent.withValues(alpha: 0.15) : (_focusedIndex == i ? KuraudoTheme.accent.withValues(alpha: 0.08) : Colors.transparent),
                  child: Row(children: [
                    if (_multiSelectMode) ...[
                      SizedBox(width: 32, height: 32, child: Checkbox(value: isSel, onChanged: (_) => _toggleSelect(e.uuid), activeColor: KuraudoTheme.accent, visualDensity: VisualDensity.compact)),
                      const SizedBox(width: 8),
                    ] else ...[
                      Container(width: 32, height: 32, decoration: BoxDecoration(color: KuraudoTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Center(child: Text(e.title.isNotEmpty ? e.title[0].toUpperCase() : '?', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KuraudoTheme.accent)))),
                    ],
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: Row(children: [if (e.favorite) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.star_rounded, size: 12, color: KuraudoTheme.warning)), Expanded(child: Text(e.title, style: TextStyle(fontSize: 13, fontWeight: _focusedIndex == i ? FontWeight.w600 : FontWeight.w400), overflow: TextOverflow.ellipsis))])),
                    Expanded(flex: 3, child: Text(e.username, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Text(e.category ?? '未分類', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)), overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Text(_fmtDate(e.updatedAt), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace'))),
                    if (e.url != null && e.url!.isNotEmpty) Tooltip(message: e.url!, waitDuration: Duration.zero, child: GestureDetector(onTap: () => _openUrl(e.url!), child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.open_in_new_rounded, size: 14, color: KuraudoTheme.info)))) else const SizedBox(width: 34),
                    Tooltip(message: 'Ctrl+C', waitDuration: Duration.zero, child: GestureDetector(onTap: () => _copyPassword(e), child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.copy_rounded, size: 14, color: cs.onSurfaceVariant)))),
                  ])),
              ),
            );
          }),
      ),
    ]);
  }

  Widget _mobList(List<VaultEntry> entries, ColorScheme cs) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700), child: Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: TextField(controller: _searchCtrl, onChanged: (v) { _searchQuery = v; _markDirty(); setState(() {}); }, decoration: InputDecoration(hintText: 'エントリを検索...', prefixIcon: const Icon(Icons.search_rounded, size: 20), suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), tooltip: 'クリア', onPressed: () { _searchCtrl.clear(); _searchQuery = ''; _markDirty(); setState(() {}); }) : null, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)))),
    if (_categories.length > 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.outline)), child: DropdownButtonHideUnderline(child: DropdownButton<String?>(value: _selectedCategory, isExpanded: true, icon: const Icon(Icons.folder_rounded, size: 18), hint: const Text('すべてのカテゴリ', style: TextStyle(fontSize: 13)), style: TextStyle(fontSize: 13, color: cs.onSurface), dropdownColor: cs.surfaceContainerHighest, items: [DropdownMenuItem<String?>(value: null, child: Row(children: [const Icon(Icons.all_inbox_rounded, size: 16), const SizedBox(width: 8), const Text('すべて'), const Spacer(), Text('${widget.vaultService.vault?.activeEntries.length ?? 0}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace'))])), ..._categories.map((c) => DropdownMenuItem<String?>(value: c, child: Row(children: [const Icon(Icons.folder_rounded, size: 16), const SizedBox(width: 8), Expanded(child: Text(c, overflow: TextOverflow.ellipsis)), Text('${_categoryCounts[c] ?? 0}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace')), const SizedBox(width: 4), GestureDetector(onTap: () => _renameCategory(c), child: Icon(Icons.edit_rounded, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.5)))])))], onChanged: (v) => _setCategory(v))))),
    const SizedBox(height: 8),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [Text('${entries.length}件', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontFamily: 'monospace'))])),
    const SizedBox(height: 4),
    Expanded(child: entries.isEmpty ? Center(child: Text('エントリがありません\n＋ボタンで追加しましょう', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14))) : ListView.builder(itemCount: entries.length, padding: const EdgeInsets.only(bottom: 80), itemBuilder: (_, i) {
      final e = entries[i];
      final isSel = _selectedUuids.contains(e.uuid);
      return Card(child: InkWell(
        onTap: _multiSelectMode ? () => _toggleSelect(e.uuid) : () => _openEntry(e),
        onLongPress: _multiSelectMode ? null : () => _enterMultiSelect(e.uuid),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: isSel ? BoxDecoration(color: KuraudoTheme.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)) : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            if (_multiSelectMode) ...[
              SizedBox(width: 42, height: 42, child: Center(child: Checkbox(value: isSel, onChanged: (_) => _toggleSelect(e.uuid), activeColor: KuraudoTheme.accent))),
            ] else ...[
              Container(width: 42, height: 42, decoration: BoxDecoration(color: KuraudoTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Center(child: Text(e.title.isNotEmpty ? e.title[0].toUpperCase() : '?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: KuraudoTheme.accent)))),
            ],
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [if (e.favorite) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.star_rounded, size: 14, color: KuraudoTheme.warning)), Expanded(child: Text(e.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))]), const SizedBox(height: 2), Text(e.username.isNotEmpty ? e.username : e.email ?? '', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)])),
            if (!_multiSelectMode) ...[
              if (e.url != null && e.url!.isNotEmpty) IconButton(icon: const Icon(Icons.open_in_new_rounded, size: 16), tooltip: 'ブラウザで開く', onPressed: () => _openUrl(e.url!), style: IconButton.styleFrom(foregroundColor: KuraudoTheme.info), visualDensity: VisualDensity.compact),
              IconButton(icon: const Icon(Icons.copy_rounded, size: 18), tooltip: 'パスワードをコピー', onPressed: () => _copyPassword(e), style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant)),
            ],
          ]),
        ),
      ));
    })),
  ])));
}

class _FT extends StatelessWidget {
  final String label; final int count; final bool sel; final IconData icon; final Color? iconColor; final VoidCallback onTap; final VoidCallback? onRename;
  const _FT({required this.label, required this.count, required this.sel, required this.icon, this.iconColor, required this.onTap, this.onRename});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), color: sel ? KuraudoTheme.accent.withValues(alpha: 0.08) : Colors.transparent, child: Row(children: [
      Icon(icon, size: 16, color: sel ? KuraudoTheme.accent : (iconColor ?? cs.onSurfaceVariant)), const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w400, color: sel ? KuraudoTheme.accent : cs.onSurface), overflow: TextOverflow.ellipsis)),
      Text('$count', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
      if (onRename != null) ...[const SizedBox(width: 4), GestureDetector(onTap: onRename, child: Icon(Icons.edit_rounded, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.5)))],
    ])));
  }
}

/// Kuraudo ロック画面
/// Vault場所指定、新規/既存切替、任意ファイル読み込み
/// PIN/生体認証による簡易ロック解除
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../services/vault_service.dart';
import '../theme/kuraudo_theme.dart';

class LockScreen extends StatefulWidget {
  final VaultService vaultService;
  final bool isNewVault;
  final String? lastVaultPath;
  final VoidCallback onUnlocked;
  final void Function(String path) onVaultPathChanged;
  final VoidCallback onSwitchToNew;
  final VoidCallback onSwitchToExisting;
  // PIN/生体認証
  final bool quickLocked;
  final bool pinEnabled;
  final bool biometricEnabled;
  final FlutterSecureStorage? secureStorage;
  final VoidCallback? onQuickUnlocked;
  final VoidCallback? onForceFullLock;

  const LockScreen({
    super.key,
    required this.vaultService,
    required this.isNewVault,
    this.lastVaultPath,
    required this.onUnlocked,
    required this.onVaultPathChanged,
    required this.onSwitchToNew,
    required this.onSwitchToExisting,
    this.quickLocked = false,
    this.pinEnabled = false,
    this.biometricEnabled = false,
    this.secureStorage,
    this.onQuickUnlocked,
    this.onForceFullLock,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _pathController = TextEditingController();
  final _focusNode = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _showPathField = false;

  // PIN入力
  String _pinInput = '';
  String? _pinError;
  int _pinFailCount = 0;
  static const int _maxPinAttempts = 5;
  final _localAuth = LocalAuthentication();

  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    if (widget.lastVaultPath != null) {
      _pathController.text = widget.lastVaultPath!;
    }

    // quickLocked時に生体認証を自動トリガー
    if (widget.quickLocked && widget.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  @override
  void didUpdateWidget(covariant LockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // quickLocked状態に遷移した時に生体認証を自動トリガー
    if (widget.quickLocked && widget.biometricEnabled && !oldWidget.quickLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
    // quickLockedに遷移したらPIN入力をリセット
    if (widget.quickLocked && !oldWidget.quickLocked) {
      _pinInput = '';
      _pinError = null;
      _pinFailCount = 0;
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _pathController.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _showFileBrowser(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _FileBrowserDialog(
        isNewVault: widget.isNewVault,
      ),
    );
    if (result != null) {
      setState(() {
        _pathController.text = result;
      });
    }
  }

  Future<void> _tryBiometric() async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canAuth) {
        if (mounted) setState(() => _pinError = 'この端末は生体認証に対応していません');
        return;
      }
      final availableBio = await _localAuth.getAvailableBiometrics();
      if (availableBio.isEmpty) {
        if (mounted) setState(() => _pinError = '生体認証が登録されていません。端末の設定で指紋/顔を登録してください');
        return;
      }
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Kuraudoのロックを解除',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (didAuth && mounted) {
        widget.onQuickUnlocked?.call();
      }
    } catch (e) {
      if (mounted) setState(() => _pinError = '生体認証エラー: $e');
    }
  }

  Future<void> _verifyPin() async {
    if (_pinInput.length != 4) return;
    final storage = widget.secureStorage;
    if (storage == null) return;

    // 試行回数超過 → マスターパスワード強制
    if (_pinFailCount >= _maxPinAttempts) {
      setState(() {
        _pinError = 'PIN試行回数を超えました。マスターパスワードで解除してください';
        _pinInput = '';
      });
      return;
    }

    try {
      final savedPin = await storage.read(key: 'kuraudo_pin');
      if (savedPin != null && savedPin == _pinInput) {
        _pinFailCount = 0; // 成功時リセット
        widget.onQuickUnlocked?.call();
      } else {
        _pinFailCount++;
        final remaining = _maxPinAttempts - _pinFailCount;
        if (remaining <= 0) {
          setState(() {
            _pinError = 'PIN試行回数を超えました。マスターパスワードで解除してください';
            _pinInput = '';
          });
        } else {
          setState(() {
            _pinError = 'PINが正しくありません（残り$remaining回）';
            _pinInput = '';
          });
        }
      }
    } catch (_) {
      setState(() { _pinError = '認証エラー'; _pinInput = ''; });
    }
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;

    if (widget.isNewVault) {
      final confirm = _confirmController.text;
      if (password != confirm) {
        setState(() => _errorMessage = 'パスワードが一致しません');
        return;
      }
      if (password.length < 8) {
        setState(() => _errorMessage = '8文字以上のパスワードを設定してください');
        return;
      }
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final path = _pathController.text.trim().isNotEmpty ? _pathController.text.trim() : null;

      if (widget.isNewVault) {
        await widget.vaultService.createVault(password, filePath: path);
      } else {
        await widget.vaultService.unlock(password, filePath: path);
      }

      // パスを保存
      final usedPath = path ?? await widget.vaultService.defaultFilePath;
      widget.onVaultPathChanged(usedPath);
      widget.onUnlocked();
    } catch (e) {
      setState(() {
        _errorMessage = widget.isNewVault
            ? 'Vault の作成に失敗しました: $e'
            : 'アンロックに失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // quickLocked = PIN/生体認証で解除可能な短時間ロック
    if (widget.quickLocked) {
      return Scaffold(
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ロゴ
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: KuraudoTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: KuraudoTheme.accent.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.lock_open_rounded, size: 40, color: KuraudoTheme.accent),
                      ),
                      const SizedBox(height: 24),
                      Text('ロック中', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
                      const SizedBox(height: 8),
                      Text('PIN または生体認証で解除', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 32),

                      // PIN入力ドット表示
                      if (widget.pinEnabled) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (i) => Container(
                            width: 18, height: 18,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pinInput.length ? KuraudoTheme.accent : Colors.transparent,
                              border: Border.all(color: KuraudoTheme.accent, width: 2),
                            ),
                          )),
                        ),
                        if (_pinError != null) ...[
                          const SizedBox(height: 8),
                          Text(_pinError!, style: const TextStyle(fontSize: 12, color: KuraudoTheme.danger)),
                        ],
                        const SizedBox(height: 24),

                        // テンキーパッド
                        SizedBox(
                          width: 280,
                          child: Column(children: [
                            for (final row in [['1','2','3'], ['4','5','6'], ['7','8','9'], ['','0','⌫']])
                              Row(mainAxisAlignment: MainAxisAlignment.center, children: row.map((key) {
                                if (key.isEmpty) return const SizedBox(width: 76, height: 60);
                                return SizedBox(width: 76, height: 60, child: InkWell(
                                  borderRadius: BorderRadius.circular(30),
                                  onTap: () {
                                    setState(() { _pinError = null; });
                                    if (key == '⌫') {
                                      if (_pinInput.isNotEmpty) setState(() => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
                                    } else if (_pinInput.length < 4) {
                                      _pinInput += key;
                                      setState(() {});
                                      if (_pinInput.length == 4) _verifyPin();
                                    }
                                  },
                                  child: Center(child: key == '⌫'
                                    ? Icon(Icons.backspace_rounded, size: 22, color: cs.onSurface)
                                    : Text(key, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: cs.onSurface)),
                                  ),
                                ));
                              }).toList()),
                          ]),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 生体認証ボタン
                      if (widget.biometricEnabled) ...[
                        ElevatedButton.icon(
                          onPressed: _tryBiometric,
                          icon: const Icon(Icons.fingerprint_rounded, size: 24),
                          label: const Text('生体認証で解除'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // マスターパスワードで解除リンク
                      TextButton(
                        onPressed: () {
                          widget.vaultService.lock();
                          widget.onForceFullLock?.call();
                        },
                        child: Text('マスターパスワードで解除', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 通常のロック画面
    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ロゴ
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: KuraudoTheme.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: KuraudoTheme.accent.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.lock_rounded, size: 40, color: KuraudoTheme.accent),
                    ),
                    const SizedBox(height: 24),

                    Text('Kuraudo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text('蔵人', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 32),

                    // 新規/既存 切替
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ModeChip(label: '既存Vault', selected: !widget.isNewVault, onTap: widget.onSwitchToExisting),
                        const SizedBox(width: 8),
                        _ModeChip(label: '新規作成', selected: widget.isNewVault, onTap: widget.onSwitchToNew),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ファイルパス設定
                    GestureDetector(
                      onTap: () => setState(() => _showPathField = !_showPathField),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open_rounded, size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text('Vault場所を指定', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          Icon(_showPathField ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                    if (_showPathField) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _pathController,
                        decoration: InputDecoration(
                          hintText: 'デフォルト: ~/Documents/kuraudo.kuraudo',
                          labelText: 'ファイルパス',
                          prefixIcon: const Icon(Icons.folder_rounded, size: 18),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.folder_open_rounded, size: 18),
                            tooltip: 'エクスプローラーで選択',
                            onPressed: () => _showFileBrowser(context),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          helperText: widget.isNewVault ? '新規作成先（フォルダアイコンで選択可）' : '読み込むファイル（フォルダアイコンで選択可）',
                          helperStyle: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // パスワード入力
                    TextField(
                      controller: _passwordController,
                      focusNode: _focusNode,
                      obscureText: _obscurePassword,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: widget.isNewVault ? 'マスターパスワード（新規）' : 'マスターパスワード',
                        prefixIcon: const Icon(Icons.key_rounded, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 20),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      onSubmitted: (_) => widget.isNewVault ? null : _submit(),
                    ),
                    if (widget.isNewVault) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: _confirmController,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          labelText: 'パスワードを確認',
                          prefixIcon: const Icon(Icons.key_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 20),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // エラー
                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: KuraudoTheme.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: KuraudoTheme.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          Icon(Icons.error_outline_rounded, size: 16, color: KuraudoTheme.danger),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_errorMessage!, style: TextStyle(fontSize: 13, color: KuraudoTheme.danger))),
                        ]),
                      ),
                    const SizedBox(height: 20),

                    // ボタン
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(widget.isNewVault ? 'Vault を作成' : 'アンロック', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // バージョン
                    Text('v0.1.0', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontFamily: 'monospace')),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? KuraudoTheme.accent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? KuraudoTheme.accent : Theme.of(context).colorScheme.outline),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? KuraudoTheme.accent : Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
    );
  }
}

/// ファイルエクスプローラーダイアログ
class _FileBrowserDialog extends StatefulWidget {
  final bool isNewVault;
  const _FileBrowserDialog({required this.isNewVault});
  @override
  State<_FileBrowserDialog> createState() => _FileBrowserDialogState();
}

class _FileBrowserDialogState extends State<_FileBrowserDialog> {
  late Directory _currentDir;
  List<FileSystemEntity> _items = [];
  bool _isLoading = true;
  String? _selectedFile;
  final _fileNameController = TextEditingController(text: 'kuraudo.kuraudo');

  @override
  void initState() {
    super.initState();
    _initDir();
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  Future<void> _initDir() async {
    final dir = await getApplicationDocumentsDirectory();
    _currentDir = dir;
    await _loadDir();
  }

  Future<void> _loadDir() async {
    setState(() => _isLoading = true);
    try {
      final items = <FileSystemEntity>[];
      await for (final entity in _currentDir.list()) {
        if (entity is Directory) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (!name.startsWith('.')) items.add(entity);
        } else if (entity is File) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.endsWith('.kuraudo') || widget.isNewVault) {
            if (!name.startsWith('.')) items.add(entity);
          }
        }
      }
      items.sort((a, b) {
        if (a is Directory && b is File) return -1;
        if (a is File && b is Directory) return 1;
        return a.path.split(Platform.pathSeparator).last.toLowerCase()
            .compareTo(b.path.split(Platform.pathSeparator).last.toLowerCase());
      });
      setState(() { _items = items; _isLoading = false; _selectedFile = null; });
    } catch (e) {
      setState(() { _items = []; _isLoading = false; });
    }
  }

  void _navigateTo(Directory dir) {
    _currentDir = dir;
    _loadDir();
  }

  void _goUp() {
    final parent = _currentDir.parent;
    if (parent.path != _currentDir.path) {
      _navigateTo(parent);
    }
  }

  String _shortPath(String path) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.folder_open_rounded, size: 20, color: KuraudoTheme.accent),
        const SizedBox(width: 8),
        Text(widget.isNewVault ? '保存先を選択' : 'Vaultファイルを選択', style: const TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(children: [
          // パスバー
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                onPressed: _goUp,
                tooltip: '上のフォルダ',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(
                _shortPath(_currentDir.path),
                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              )),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: _loadDir,
                tooltip: '更新',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          // ファイルリスト
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: KuraudoTheme.accent))
                : _items.isEmpty
                    ? Center(child: Text(
                        widget.isNewVault ? 'このフォルダに保存できます' : '.kuraudoファイルがありません',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ))
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i];
                          final name = item.path.split(Platform.pathSeparator).last;
                          final isDir = item is Directory;
                          final isSelected = !isDir && _selectedFile == item.path;
                          return InkWell(
                            onTap: () {
                              if (isDir) {
                                _navigateTo(item as Directory);
                              } else {
                                setState(() => _selectedFile = item.path);
                              }
                            },
                            onDoubleTap: () {
                              if (isDir) {
                                _navigateTo(item as Directory);
                              } else {
                                Navigator.pop(context, item.path);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              color: isSelected ? KuraudoTheme.accent.withValues(alpha: 0.1) : Colors.transparent,
                              child: Row(children: [
                                Icon(
                                  isDir ? Icons.folder_rounded : Icons.lock_rounded,
                                  size: 18,
                                  color: isDir ? KuraudoTheme.warning : KuraudoTheme.accent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(name, style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  color: cs.onSurface,
                                ), overflow: TextOverflow.ellipsis)),
                                if (!isDir) Text(
                                  _fileSize(item as File),
                                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace'),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
          ),
          // 新規作成時のファイル名入力
          if (widget.isNewVault) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _fileNameController,
              decoration: InputDecoration(
                labelText: 'ファイル名',
                prefixIcon: const Icon(Icons.insert_drive_file_rounded, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                helperText: '.kuraudo拡張子が自動付与されます',
                helperStyle: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () {
            if (widget.isNewVault) {
              var name = _fileNameController.text.trim();
              if (name.isEmpty) name = 'kuraudo';
              if (!name.endsWith('.kuraudo')) name = '$name.kuraudo';
              Navigator.pop(context, '${_currentDir.path}${Platform.pathSeparator}$name');
            } else if (_selectedFile != null) {
              Navigator.pop(context, _selectedFile);
            }
          },
          child: Text(widget.isNewVault ? 'ここに保存' : '選択'),
        ),
      ],
    );
  }

  String _fileSize(File file) {
    try {
      final bytes = file.lengthSync();
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } catch (_) {
      return '';
    }
  }
}

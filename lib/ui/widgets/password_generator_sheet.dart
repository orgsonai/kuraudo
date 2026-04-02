/// Kuraudo パスワード生成器ボトムシート
/// 
/// パスワード/パスフレーズ生成UIウィジェット
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/password_generator.dart';
import '../theme/kuraudo_theme.dart';

class PasswordGeneratorSheet extends StatefulWidget {
  final void Function(String password) onSelect;

  const PasswordGeneratorSheet({
    super.key,
    required this.onSelect,
  });

  @override
  State<PasswordGeneratorSheet> createState() => _PasswordGeneratorSheetState();
}

class _PasswordGeneratorSheetState extends State<PasswordGeneratorSheet> {
  final _generator = PasswordGenerator();

  // パスワード設定
  double _length = 20;
  bool _useUppercase = true;
  bool _useLowercase = true;
  bool _useDigits = true;
  bool _useSymbols = true;
  bool _useSpaces = false;
  bool _useExtendedSymbols = false;

  // 詳細設定
  bool _showAdvanced = false;
  String _customSymbols = r'!@#$%^&*()-_=+[]{}|;:,.<>?';
  String _excludeChars = '';
  final _customSymbolsCtrl = TextEditingController();
  final _excludeCharsCtrl = TextEditingController();

  // パスフレーズ設定
  int _wordCount = 4;
  bool _capitalize = true;
  bool _addNumber = true;

  // 生成モード
  bool _isPassphrase = false;
  bool _showBatch = false;

  // 生成されたパスワード
  String _generated = '';
  String _batchResult = '';

  @override
  void initState() {
    super.initState();
    _customSymbolsCtrl.text = _customSymbols;
    _excludeCharsCtrl.text = _excludeChars;
    _regenerate();
  }

  @override
  void dispose() {
    _customSymbolsCtrl.dispose();
    _excludeCharsCtrl.dispose();
    super.dispose();
  }

  PasswordGeneratorConfig get _currentConfig => PasswordGeneratorConfig(
    length: _length.round(),
    useUppercase: _useUppercase,
    useLowercase: _useLowercase,
    useDigits: _useDigits,
    useSymbols: _useSymbols,
    useSpaces: _useSpaces,
    useExtendedSymbols: _useExtendedSymbols,
    customSymbols: _customSymbols,
    excludeChars: _excludeChars,
  );

  void _regenerate() {
    try {
      if (_isPassphrase) {
        _generated = _generator.generatePassphrase(
          wordCount: _wordCount,
          capitalize: _capitalize,
          addNumber: _addNumber,
        );
      } else {
        _generated = _generator.generate(_currentConfig);
      }
    } catch (e) {
      _generated = 'エラー: 設定を確認してください';
    }
    _showBatch = false;
    _batchResult = '';
    setState(() {});
  }

  void _generateBatch() {
    try {
      if (_isPassphrase) {
        _batchResult = _generator.generatePassphraseBatch(
          count: 20,
          wordCount: _wordCount,
          capitalize: _capitalize,
          addNumber: _addNumber,
        );
      } else {
        _batchResult = _generator.generateBatch(_currentConfig, count: 20);
      }
    } catch (e) {
      _batchResult = 'エラー: $e';
    }
    setState(() => _showBatch = true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final strength = _generator.evaluateStrength(_generated);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: cs.outline),
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── ハンドル ──
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── タイトル ──
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 18, color: KuraudoTheme.accent),
                    const SizedBox(width: 8),
                    const Text(
                      'パスワード生成',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                // ── 生成結果 ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Column(
                    children: [
                      SelectableText(
                        _generated,
                        style: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      // 強度バー
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: strength.score,
                                backgroundColor: cs.outline,
                                color: _strengthColor(strength),
                                minHeight: 3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            strength.label,
                            style: TextStyle(
                              fontSize: 10,
                              color: _strengthColor(strength),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── アクションボタン ──
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _regenerate,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('再生成'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _generated));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('コピーしました')),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('コピー'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          widget.onSelect(_generated);
                          Navigator.pop(context);
                        },
                        child: const Text('使用'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── モード切替 ──
                Row(
                  children: [
                    _ModeChip(
                      label: 'パスワード',
                      selected: !_isPassphrase,
                      onTap: () {
                        setState(() => _isPassphrase = false);
                        _regenerate();
                      },
                    ),
                    const SizedBox(width: 8),
                    _ModeChip(
                      label: 'パスフレーズ',
                      selected: _isPassphrase,
                      onTap: () {
                        setState(() => _isPassphrase = true);
                        _regenerate();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── 設定 ──
                if (!_isPassphrase) ...[
                  // 文字数スライダー
                  Row(
                    children: [
                      Text('文字数', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      const Spacer(),
                      Text(
                        '${_length.round()}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _length,
                    min: 4,
                    max: 64,
                    divisions: 60,
                    activeColor: KuraudoTheme.accent,
                    onChanged: (v) {
                      _length = v;
                      _regenerate();
                    },
                  ),

                  // 文字種トグル
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _ToggleChip(label: 'A-Z', value: _useUppercase, onChanged: (v) { _useUppercase = v; _regenerate(); }),
                      _ToggleChip(label: 'a-z', value: _useLowercase, onChanged: (v) { _useLowercase = v; _regenerate(); }),
                      _ToggleChip(label: '0-9', value: _useDigits, onChanged: (v) { _useDigits = v; _regenerate(); }),
                      _ToggleChip(label: '!@#\$', value: _useSymbols, onChanged: (v) { _useSymbols = v; _regenerate(); }),
                      _ToggleChip(label: 'スペース', value: _useSpaces, onChanged: (v) { _useSpaces = v; _regenerate(); }),
                      _ToggleChip(label: '~`\\/\'"', value: _useExtendedSymbols, onChanged: (v) { _useExtendedSymbols = v; _regenerate(); }),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 詳細設定の展開/折りたたみ
                  GestureDetector(
                    onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                    child: Row(children: [
                      Icon(_showAdvanced ? Icons.expand_less_rounded : Icons.tune_rounded, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text('詳細設定', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      if (_excludeChars.isNotEmpty || _customSymbols != r'!@#$%^&*()-_=+[]{}|;:,.<>?') ...[
                        const SizedBox(width: 6),
                        Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: KuraudoTheme.accent)),
                      ],
                    ]),
                  ),

                  if (_showAdvanced) ...[
                    const SizedBox(height: 8),
                    // プリセットボタン
                    Text('プリセット', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _PresetChip(label: '標準', onTap: () {
                        _customSymbolsCtrl.text = r'!@#$%^&*()-_=+[]{}|;:,.<>?';
                        _customSymbols = _customSymbolsCtrl.text;
                        _excludeCharsCtrl.text = '';
                        _excludeChars = '';
                        _regenerate();
                      }),
                      _PresetChip(label: '記号少なめ', onTap: () {
                        _customSymbolsCtrl.text = r'!@#-_';
                        _customSymbols = _customSymbolsCtrl.text;
                        _excludeCharsCtrl.text = '';
                        _excludeChars = '';
                        _regenerate();
                      }),
                      _PresetChip(label: '紛らわしい文字除外', onTap: () {
                        _excludeCharsCtrl.text = 'lI1O0oS5';
                        _excludeChars = _excludeCharsCtrl.text;
                        _regenerate();
                      }),
                      _PresetChip(label: 'URLセーフ', onTap: () {
                        _customSymbolsCtrl.text = '-_.~';
                        _customSymbols = _customSymbolsCtrl.text;
                        _excludeCharsCtrl.text = '';
                        _excludeChars = '';
                        _regenerate();
                      }),
                    ]),
                    const SizedBox(height: 10),

                    // カスタム特殊文字フィールド
                    TextField(
                      controller: _customSymbolsCtrl,
                      decoration: InputDecoration(
                        labelText: '使用する特殊文字',
                        hintText: r'!@#$%^&*()-_=+',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        prefixIcon: const Icon(Icons.text_fields_rounded, size: 18),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.restore_rounded, size: 16),
                          tooltip: 'デフォルトに戻す',
                          onPressed: () {
                            _customSymbolsCtrl.text = r'!@#$%^&*()-_=+[]{}|;:,.<>?';
                            _customSymbols = _customSymbolsCtrl.text;
                            _regenerate();
                          },
                        ),
                      ),
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      onChanged: (v) { _customSymbols = v; _regenerate(); },
                    ),
                    const SizedBox(height: 8),

                    // 除外文字フィールド
                    TextField(
                      controller: _excludeCharsCtrl,
                      decoration: InputDecoration(
                        labelText: '除外する文字',
                        hintText: '例: lI1O0o',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        prefixIcon: const Icon(Icons.block_rounded, size: 18),
                        suffixIcon: _excludeChars.isNotEmpty ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          tooltip: 'クリア',
                          onPressed: () {
                            _excludeCharsCtrl.text = '';
                            _excludeChars = '';
                            _regenerate();
                          },
                        ) : null,
                      ),
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      onChanged: (v) { _excludeChars = v; _regenerate(); },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '現在の文字プール: ${_buildPoolPreview()}',
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 12),

                  // バッチ生成ボタン
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _generateBatch,
                      icon: const Icon(Icons.list_rounded, size: 18),
                      label: const Text('20件サンプル生成'),
                    ),
                  ),
                ] else ...[
                  // パスフレーズ設定
                  Row(
                    children: [
                      Text('単語数', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      const Spacer(),
                      Text(
                        '$_wordCount',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _wordCount.toDouble(),
                    min: 3,
                    max: 8,
                    divisions: 5,
                    activeColor: KuraudoTheme.accent,
                    onChanged: (v) {
                      _wordCount = v.round();
                      _regenerate();
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      _ToggleChip(label: '先頭大文字', value: _capitalize, onChanged: (v) { _capitalize = v; _regenerate(); }),
                      _ToggleChip(label: '数字追加', value: _addNumber, onChanged: (v) { _addNumber = v; _regenerate(); }),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _generateBatch,
                      icon: const Icon(Icons.list_rounded, size: 18),
                      label: const Text('20件サンプル生成'),
                    ),
                  ),
                ],

                // ── バッチ生成結果 ──
                if (_showBatch && _batchResult.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cs.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '20件サンプル',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _batchResult));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('20件をコピーしました')),
                                );
                              },
                              visualDensity: VisualDensity.compact,
                              tooltip: '全件コピー',
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () => setState(() => _showBatch = false),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          _batchResult,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
      ),
    );
  }

  String _buildPoolPreview() {
    final buf = StringBuffer();
    if (_useLowercase) buf.write('a-z ');
    if (_useUppercase) buf.write('A-Z ');
    if (_useDigits) buf.write('0-9 ');
    if (_useSymbols && _customSymbols.isNotEmpty) {
      final preview = _customSymbols.length > 12 ? '${_customSymbols.substring(0, 12)}…' : _customSymbols;
      buf.write('[$preview] ');
    }
    if (_useExtendedSymbols) buf.write('~`\\/"\'');
    if (_useSpaces) buf.write(' ␣');
    if (_excludeChars.isNotEmpty) buf.write(' 除外: $_excludeChars');
    return buf.toString().trim();
  }

  Color _strengthColor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.veryWeak: return KuraudoTheme.danger;
      case PasswordStrength.weak: return const Color(0xFFEF4444);
      case PasswordStrength.fair: return KuraudoTheme.warning;
      case PasswordStrength.strong: return KuraudoTheme.accent;
      case PasswordStrength.veryStrong: return const Color(0xFF22C55E);
    }
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? KuraudoTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? KuraudoTheme.accent.withValues(alpha: 0.4) : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? KuraudoTheme.accent : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool value;
  final void Function(bool) onChanged;

  const _ToggleChip({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      showCheckmark: false,
      selectedColor: KuraudoTheme.accent.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        color: value ? KuraudoTheme.accent : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      side: BorderSide(
        color: value ? KuraudoTheme.accent.withValues(alpha: 0.4) : Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cs.outline),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ),
    );
  }
}

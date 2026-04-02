/// Kuraudo TOTP 表示ウィジェット
/// 
/// リアルタイムカウントダウン付きTOTPコード表示
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/totp_generator.dart';
import '../theme/kuraudo_theme.dart';

class TotpDisplay extends StatefulWidget {
  final String totpSecret;

  const TotpDisplay({
    super.key,
    required this.totpSecret,
  });

  @override
  State<TotpDisplay> createState() => _TotpDisplayState();
}

class _TotpDisplayState extends State<TotpDisplay> {
  final _generator = TotpGenerator();
  late TotpParams _params;
  TotpCode? _code;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initTotp();
  }

  void _initTotp() {
    try {
      // otpauth:// URI の場合
      if (widget.totpSecret.startsWith('otpauth://')) {
        _params = TotpParams.fromUri(widget.totpSecret);
      } else {
        // 生のBase32シークレットの場合
        _params = TotpParams(secret: widget.totpSecret.toUpperCase().replaceAll(' ', ''));
      }

      _updateCode();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCode());
    } catch (e) {
      // パースエラー
    }
  }

  void _updateCode() {
    if (!mounted) return;
    setState(() {
      _code = _generator.generate(_params);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    if (_code == null) return;
    Clipboard.setData(ClipboardData(text: _code!.code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('TOTPコードをコピーしました'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_code == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: KuraudoTheme.danger),
              const SizedBox(width: 8),
              Text(
                'TOTPシークレットが無効です',
                style: TextStyle(fontSize: 13, color: KuraudoTheme.danger),
              ),
            ],
          ),
        ),
      );
    }

    final isExpiring = _code!.remainingSeconds <= 5;
    final codeFormatted = _code!.code.length == 6
        ? '${_code!.code.substring(0, 3)} ${_code!.code.substring(3)}'
        : _code!.code;

    return Card(
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.security_rounded, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '二段階認証 (TOTP)',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  // カウントダウン
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isExpiring
                          ? KuraudoTheme.danger.withValues(alpha: 0.1)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_code!.remainingSeconds}s',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: isExpiring ? KuraudoTheme.danger : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    onPressed: _copy,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // コード表示
              Text(
                codeFormatted,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  letterSpacing: 4,
                  color: isExpiring ? KuraudoTheme.danger : KuraudoTheme.accent,
                ),
              ),
              const SizedBox(height: 8),

              // プログレスバー
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _code!.progress,
                  backgroundColor: cs.outline,
                  color: isExpiring ? KuraudoTheme.danger : KuraudoTheme.accent,
                  minHeight: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kuraudo レスポンシブレイアウトヘルパー
/// 
/// PC（広い画面）とモバイル（狭い画面）で適切なレイアウトに切り替える
library;

import 'package:flutter/material.dart';

/// ブレークポイント
class KuraudoBreakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
}

/// 画面サイズ種別
enum ScreenSize { mobile, tablet, desktop }

/// 現在の画面サイズを判定
ScreenSize getScreenSize(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width < KuraudoBreakpoints.mobile) return ScreenSize.mobile;
  if (width < KuraudoBreakpoints.tablet) return ScreenSize.tablet;
  return ScreenSize.desktop;
}

/// PC画面かどうか
bool isWideScreen(BuildContext context) =>
    MediaQuery.of(context).size.width >= KuraudoBreakpoints.mobile;

/// コンテンツ幅を制限するラッパー
/// モバイル: 全幅、PC: maxWidth で中央揃え
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 600,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding != null
            ? Padding(padding: padding!, child: child)
            : child,
      ),
    );
  }
}

/// レスポンシブなPaddingを返す
/// PC: 左右に余白を追加、モバイル: 標準パディング
EdgeInsets responsivePadding(BuildContext context, {
  double horizontal = 16,
  double vertical = 0,
}) {
  if (isWideScreen(context)) {
    return EdgeInsets.symmetric(
      horizontal: horizontal + 8,
      vertical: vertical,
    );
  }
  return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
}

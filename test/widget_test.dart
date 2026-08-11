import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kuraudo/models/vault_entry.dart';
import 'package:kuraudo/services/vault_service.dart';
import 'package:kuraudo/ui/screens/entry_detail_screen.dart';
import 'package:kuraudo/ui/screens/settings_screen.dart';
import 'package:kuraudo/l10n/kuraudo_localizations.dart' as l10n;

void main() {
  testWidgets('詳細画面のメモを範囲選択できる', (tester) async {
    const notes = '必要な部分だけ選択\n\nしてコピーするメモ';
    final entry = VaultEntry(
      uuid: 'test-entry',
      title: 'テスト',
      username: '',
      password: 'password',
      notes: notes,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EntryDetailScreen(
          vaultService: VaultService(),
          entry: entry,
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('必要な部分だけ選択\n\n'), findsOneWidget);
    expect(find.text('してコピーするメモ'), findsOneWidget);
    expect(find.text(notes), findsNothing);

    final selectableLines = tester
        .widgetList<RichText>(find.descendant(
          of: find.byType(SelectionArea),
          matching: find.byType(RichText),
        ))
        .map((text) => text.text.toPlainText())
        .toList();
    expect(
      selectableLines,
      containsAllInOrder(['必要な部分だけ選択\n\n', '', 'してコピーするメモ']),
    );

    final lineBoxes = tester.widgetList<SizedBox>(find.descendant(
      of: find.byType(SelectionArea),
      matching: find.byType(SizedBox),
    ));
    expect(lineBoxes.where((box) => box.height != null).length, 3);
  });

  testWidgets('英語ロケールでUI文言を翻訳する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('ja'), Locale('en')],
        home: Scaffold(body: l10n.Text('設定')),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('設定'), findsNothing);
  });

  testWidgets('入力説明と設定説明を英語へ翻訳する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('ja'), Locale('en')],
        home: Scaffold(
          body: Column(
            children: [
              l10n.Text('マスターパスワード'),
              l10n.Text('既存フォルダから選択または新規入力'),
              l10n.Text('Base32キーまたはotpauth://...'),
              l10n.Text('バックグラウンド移行後、指定時間が経過するとVaultを自動ロックします'),
              l10n.Text('エクスポートデータには平文のパスワードが含まれます。\nマスターパスワードを入力して確認してください。'),
              l10n.Text(
                  '同じVaultを同期するすべての端末で、同じマスターパスワードを使用してください。マスターパスワードが異なる場合は同期できません。'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Master password'), findsOneWidget);
    expect(find.text('Choose an existing folder or enter a new one'),
        findsOneWidget);
    expect(find.text('Base32 key or otpauth://...'), findsOneWidget);
    expect(
        find.text(
            'Automatically locks the vault after the selected background time.'),
        findsOneWidget);
    expect(
        find.text(
            'Exported data contains passwords in plain text.\nEnter your master password to continue.'),
        findsOneWidget);
    expect(
        find.text(
            'Use the same master password on every device that syncs this vault. Syncing is not possible when the master passwords differ.'),
        findsOneWidget);
  });

  testWidgets('設定画面で英語を選択できる', (tester) async {
    String? selectedLanguage;
    l10n.KuraudoLocaleController.onLanguageChanged =
        (value) => selectedLanguage = value;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SettingsScreen(
          vaultService: VaultService(),
          onAutoLockChanged: (_) {},
          onPasswordExpiryChanged: (_) {},
          onThemeModeChanged: (_) {},
          onAutoSyncChanged: (_) {},
          onRealtimeSyncChanged: (_) {},
          onClipboardAutoClearChanged: (_) {},
          onPinEnabledChanged: (_) {},
          onBiometricEnabledChanged: (_) {},
          onPinThresholdChanged: (_) {},
          onPinLockoutPersistentChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('言語'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(selectedLanguage, 'en');
    l10n.KuraudoLocaleController.onLanguageChanged = null;
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuraudo/models/vault_entry.dart';
import 'package:kuraudo/services/vault_service.dart';
import 'package:kuraudo/ui/screens/entry_detail_screen.dart';

void main() {
  testWidgets('詳細画面のメモを範囲選択できる', (tester) async {
    const notes = '必要な部分だけ選択してコピーするメモ';
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

    final selectableMemo = find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == notes,
    );
    expect(selectableMemo, findsOneWidget);
  });
}

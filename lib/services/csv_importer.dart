/// Kuraudo インポーター
/// 
/// KeePassXC CSV および他のパスワードマネージャーからのデータ移行をサポート
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../models/vault_entry.dart';

/// インポート元のアプリ種別
enum ImportSource {
  keepassxcCsv,
  bitwardenCsv,
  bitwardenJson,
  onePasswordCsv,
  chromeCsv,
  genericCsv,
}

/// インポート結果
class ImportResult {
  final List<VaultEntry> entries;
  final int totalRows;
  final int importedCount;
  final int skippedCount;
  final List<String> warnings;

  ImportResult({
    required this.entries,
    required this.totalRows,
    required this.importedCount,
    required this.skippedCount,
    required this.warnings,
  });
}

/// CSVインポーター
class CsvImporter {
  final Uuid _uuid = const Uuid();

  /// KeePassXC CSV をインポート
  /// 
  /// KeePassXC CSV フォーマット:
  /// "Group","Title","Username","Password","URL","Notes","TOTP","Icon","Last Modified","Created"
  ImportResult importKeePassXC(String csvContent) {
    final lines = _parseCsv(csvContent);
    if (lines.isEmpty) {
      return ImportResult(
        entries: [],
        totalRows: 0,
        importedCount: 0,
        skippedCount: 0,
        warnings: ['CSVデータが空です'],
      );
    }

    // ヘッダー行を確認
    final header = lines.first.map((h) => h.toLowerCase().trim()).toList();
    final titleIdx = _findColumn(header, ['title', 'タイトル']);
    final usernameIdx = _findColumn(header, ['username', 'ユーザー名', 'user name']);
    final passwordIdx = _findColumn(header, ['password', 'パスワード']);
    final urlIdx = _findColumn(header, ['url', 'URL']);
    final notesIdx = _findColumn(header, ['notes', 'メモ', 'ノート']);
    final groupIdx = _findColumn(header, ['group', 'グループ', 'folder']);
    final totpIdx = _findColumn(header, ['totp', 'otp']);

    if (titleIdx < 0 && usernameIdx < 0) {
      return ImportResult(
        entries: [],
        totalRows: lines.length - 1,
        importedCount: 0,
        skippedCount: lines.length - 1,
        warnings: ['CSVのヘッダーを認識できません。Title/Username列が必要です。'],
      );
    }

    final entries = <VaultEntry>[];
    final warnings = <String>[];
    int skipped = 0;

    for (int i = 1; i < lines.length; i++) {
      final row = lines[i];
      if (row.isEmpty || (row.length == 1 && row[0].isEmpty)) {
        skipped++;
        continue;
      }

      final title = _getField(row, titleIdx);
      final password = _getField(row, passwordIdx);

      if (title.isEmpty && password.isEmpty) {
        skipped++;
        warnings.add('行${i + 1}: タイトルもパスワードも空のためスキップ');
        continue;
      }

      entries.add(VaultEntry(
        uuid: _uuid.v4(),
        title: title.isNotEmpty ? title : '(無題)',
        username: _getField(row, usernameIdx),
        password: password,
        url: _getField(row, urlIdx).isNotEmpty ? _getField(row, urlIdx) : null,
        notes: _getField(row, notesIdx).isNotEmpty ? _getField(row, notesIdx) : null,
        category: _getField(row, groupIdx).isNotEmpty ? _getField(row, groupIdx) : null,
        totp: _getField(row, totpIdx).isNotEmpty ? _getField(row, totpIdx) : null,
      ));
    }

    return ImportResult(
      entries: entries,
      totalRows: lines.length - 1,
      importedCount: entries.length,
      skippedCount: skipped,
      warnings: warnings,
    );
  }

  /// Bitwarden CSV をインポート
  /// 
  /// Bitwarden CSV フォーマット:
  /// folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
  ImportResult importBitwarden(String csvContent) {
    final lines = _parseCsv(csvContent);
    if (lines.isEmpty) {
      return ImportResult(
        entries: [],
        totalRows: 0,
        importedCount: 0,
        skippedCount: 0,
        warnings: ['CSVデータが空です'],
      );
    }

    final header = lines.first.map((h) => h.toLowerCase().trim()).toList();
    final nameIdx = _findColumn(header, ['name']);
    final usernameIdx = _findColumn(header, ['login_username']);
    final passwordIdx = _findColumn(header, ['login_password']);
    final uriIdx = _findColumn(header, ['login_uri']);
    final notesIdx = _findColumn(header, ['notes']);
    final folderIdx = _findColumn(header, ['folder']);
    final favoriteIdx = _findColumn(header, ['favorite']);
    final totpIdx = _findColumn(header, ['login_totp']);

    final entries = <VaultEntry>[];
    final warnings = <String>[];
    int skipped = 0;

    for (int i = 1; i < lines.length; i++) {
      final row = lines[i];
      if (row.isEmpty || (row.length == 1 && row[0].isEmpty)) {
        skipped++;
        continue;
      }

      final name = _getField(row, nameIdx);
      if (name.isEmpty) {
        skipped++;
        continue;
      }

      entries.add(VaultEntry(
        uuid: _uuid.v4(),
        title: name,
        username: _getField(row, usernameIdx),
        password: _getField(row, passwordIdx),
        url: _getField(row, uriIdx).isNotEmpty ? _getField(row, uriIdx) : null,
        notes: _getField(row, notesIdx).isNotEmpty ? _getField(row, notesIdx) : null,
        category: _getField(row, folderIdx).isNotEmpty ? _getField(row, folderIdx) : null,
        totp: _getField(row, totpIdx).isNotEmpty ? _getField(row, totpIdx) : null,
        favorite: _getField(row, favoriteIdx) == '1',
      ));
    }

    return ImportResult(
      entries: entries,
      totalRows: lines.length - 1,
      importedCount: entries.length,
      skippedCount: skipped,
      warnings: warnings,
    );
  }

  /// エクスポート: KeePass互換CSV
  String exportKeePassCsv(List<VaultEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('"Group","Title","Username","Password","URL","Notes"');

    for (final entry in entries) {
      buffer.writeln([
        _escapeCsv(entry.category ?? ''),
        _escapeCsv(entry.title),
        _escapeCsv(entry.username),
        _escapeCsv(entry.password),
        _escapeCsv(entry.url ?? ''),
        _escapeCsv(entry.notes ?? ''),
      ].join(','));
    }

    return buffer.toString();
  }

  /// エクスポート: JSON
  String exportJson(List<VaultEntry> entries) {
    final data = entries.map((e) => e.toJson()).toList();
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({'entries': data});
  }

  /// エクスポート: Bitwarden互換CSV
  String exportBitwardenCsv(List<VaultEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp');

    for (final entry in entries) {
      buffer.writeln([
        _escapeCsv(entry.category ?? ''),
        entry.favorite ? '1' : '',
        'login',
        _escapeCsv(entry.title),
        _escapeCsv(entry.notes ?? ''),
        '', // fields
        '', // reprompt
        _escapeCsv(entry.url ?? ''),
        _escapeCsv(entry.username),
        _escapeCsv(entry.password),
        _escapeCsv(entry.totp ?? ''),
      ].join(','));
    }

    return buffer.toString();
  }

  /// 1Password CSV をインポート
  /// 
  /// 1Password CSV フォーマット:
  /// Title,URL,Username,Password,Notes,Type
  ImportResult import1Password(String csvContent) {
    final lines = _parseCsv(csvContent);
    if (lines.isEmpty) {
      return ImportResult(
        entries: [],
        totalRows: 0,
        importedCount: 0,
        skippedCount: 0,
        warnings: ['CSVデータが空です'],
      );
    }

    final header = lines.first.map((h) => h.toLowerCase().trim()).toList();
    final titleIdx = _findColumn(header, ['title', 'name']);
    final usernameIdx = _findColumn(header, ['username', 'login_username']);
    final passwordIdx = _findColumn(header, ['password', 'login_password']);
    final urlIdx = _findColumn(header, ['url', 'login_url', 'urls']);
    final notesIdx = _findColumn(header, ['notes', 'notesplain']);
    final tagsIdx = _findColumn(header, ['tags', 'tag']);

    final entries = <VaultEntry>[];
    final warnings = <String>[];
    int skipped = 0;

    for (int i = 1; i < lines.length; i++) {
      final row = lines[i];
      if (row.isEmpty || (row.length == 1 && row[0].isEmpty)) {
        skipped++;
        continue;
      }

      final title = _getField(row, titleIdx);
      if (title.isEmpty) {
        skipped++;
        continue;
      }

      final tagsRaw = _getField(row, tagsIdx);
      final tags = tagsRaw.isNotEmpty
          ? tagsRaw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
          : <String>[];

      entries.add(VaultEntry(
        uuid: _uuid.v4(),
        title: title,
        username: _getField(row, usernameIdx),
        password: _getField(row, passwordIdx),
        url: _getField(row, urlIdx).isNotEmpty ? _getField(row, urlIdx) : null,
        notes: _getField(row, notesIdx).isNotEmpty ? _getField(row, notesIdx) : null,
        tags: tags,
      ));
    }

    return ImportResult(
      entries: entries,
      totalRows: lines.length - 1,
      importedCount: entries.length,
      skippedCount: skipped,
      warnings: warnings,
    );
  }

  /// Bitwarden JSON をインポート
  /// 
  /// Bitwarden JSON フォーマット:
  /// { "items": [{ "type": 1, "name": "...", "login": { "username": "...", ... } }] }
  ImportResult importBitwardenJson(String jsonContent) {
    try {
      final data = jsonDecode(jsonContent) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];

      final entries = <VaultEntry>[];
      final warnings = <String>[];
      int skipped = 0;

      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final type = map['type'] as int? ?? 0;

        // type 1 = Login
        if (type != 1) {
          skipped++;
          continue;
        }

        final name = map['name'] as String? ?? '';
        if (name.isEmpty) {
          skipped++;
          continue;
        }

        final login = map['login'] as Map<String, dynamic>? ?? {};
        final uris = login['uris'] as List<dynamic>?;
        final uri = uris != null && uris.isNotEmpty
            ? (uris[0] as Map<String, dynamic>)['uri'] as String?
            : null;

        final folderId = map['folderId'] as String?;
        // Bitwarden JSONではfolder名はfolders配列に別途定義されるが、
        // 簡易実装ではfolderIdをそのまま使用
        final folderName = folderId;

        entries.add(VaultEntry(
          uuid: _uuid.v4(),
          title: name,
          username: login['username'] as String? ?? '',
          password: login['password'] as String? ?? '',
          url: uri,
          notes: map['notes'] as String?,
          category: folderName,
          totp: login['totp'] as String?,
          favorite: map['favorite'] as bool? ?? false,
        ));
      }

      return ImportResult(
        entries: entries,
        totalRows: items.length,
        importedCount: entries.length,
        skippedCount: skipped,
        warnings: warnings,
      );
    } catch (e) {
      return ImportResult(
        entries: [],
        totalRows: 0,
        importedCount: 0,
        skippedCount: 0,
        warnings: ['JSONの解析に失敗しました: $e'],
      );
    }
  }

  /// Chrome パスワードCSV をインポート
  /// 
  /// Chrome CSV フォーマット:
  /// name,url,username,password,note
  ImportResult importChromeCsv(String csvContent) {
    final lines = _parseCsv(csvContent);
    if (lines.isEmpty) {
      return ImportResult(
        entries: [],
        totalRows: 0,
        importedCount: 0,
        skippedCount: 0,
        warnings: ['CSVデータが空です'],
      );
    }

    final header = lines.first.map((h) => h.toLowerCase().trim()).toList();
    final nameIdx = _findColumn(header, ['name', 'origin', 'title']);
    final urlIdx = _findColumn(header, ['url', 'origin_url']);
    final usernameIdx = _findColumn(header, ['username', 'login']);
    final passwordIdx = _findColumn(header, ['password']);
    final noteIdx = _findColumn(header, ['note', 'notes']);

    final entries = <VaultEntry>[];
    final warnings = <String>[];
    int skipped = 0;

    for (int i = 1; i < lines.length; i++) {
      final row = lines[i];
      if (row.isEmpty || (row.length == 1 && row[0].isEmpty)) {
        skipped++;
        continue;
      }

      var title = _getField(row, nameIdx);
      final url = _getField(row, urlIdx);
      final password = _getField(row, passwordIdx);

      // ChromeではnameがURLの場合がある → ドメイン名を抽出
      if (title.isEmpty && url.isNotEmpty) {
        try {
          title = Uri.parse(url).host;
        } catch (_) {
          title = url;
        }
      }

      if (title.isEmpty && password.isEmpty) {
        skipped++;
        continue;
      }

      entries.add(VaultEntry(
        uuid: _uuid.v4(),
        title: title.isNotEmpty ? title : '(無題)',
        username: _getField(row, usernameIdx),
        password: password,
        url: url.isNotEmpty ? url : null,
        notes: _getField(row, noteIdx).isNotEmpty ? _getField(row, noteIdx) : null,
      ));
    }

    return ImportResult(
      entries: entries,
      totalRows: lines.length - 1,
      importedCount: entries.length,
      skippedCount: skipped,
      warnings: warnings,
    );
  }

  // ── プライベートメソッド ──

  /// CSVをパース（ダブルクォート内の改行に対応）
  List<List<String>> _parseCsv(String content) {
    final rows = <List<String>>[];
    final fields = <String>[];
    final field = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < content.length; i++) {
      final c = content[i];

      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            // エスケープされたダブルクォート ""
            field.write('"');
            i++;
          } else {
            // クォート終了
            inQuotes = false;
          }
        } else {
          // クォート内の文字（改行を含む）
          field.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          fields.add(field.toString());
          field.clear();
        } else if (c == '\n' || (c == '\r' && i + 1 < content.length && content[i + 1] == '\n')) {
          // 行末
          if (c == '\r') i++; // \r\n の \n をスキップ
          fields.add(field.toString());
          field.clear();
          if (fields.any((f) => f.isNotEmpty)) {
            rows.add(List.from(fields));
          }
          fields.clear();
        } else if (c == '\r') {
          // 単独の \r
          fields.add(field.toString());
          field.clear();
          if (fields.any((f) => f.isNotEmpty)) {
            rows.add(List.from(fields));
          }
          fields.clear();
        } else {
          field.write(c);
        }
      }
    }

    // 最終行（末尾に改行がない場合）
    fields.add(field.toString());
    if (fields.any((f) => f.isNotEmpty)) {
      rows.add(List.from(fields));
    }

    return rows;
  }

  /// CSV行をパース（後方互換用、単一行のパースに使用）
  List<String> _parseCsvRow(String row) {
    // _parseCsvが全体パースを担当するため、これは単純な分割にフォールバック
    return _parseCsv(row).isNotEmpty ? _parseCsv(row).first : [];
  }

  /// ヘッダーからカラムインデックスを検索
  int _findColumn(List<String> header, List<String> candidates) {
    for (final c in candidates) {
      final idx = header.indexOf(c.toLowerCase());
      if (idx >= 0) return idx;
    }
    return -1;
  }

  /// 行からフィールドを安全に取得
  String _getField(List<String> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  /// CSV用エスケープ
  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return '"$value"';
  }
}

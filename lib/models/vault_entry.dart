/// Kuraudo データモデル
/// 
/// パスワードエントリとVault（全エントリの集合）の定義
library;

import 'dart:convert';

/// パスワード履歴レコード
class PasswordRecord {
  final String password;
  final DateTime changedAt;

  PasswordRecord({
    required this.password,
    required this.changedAt,
  });

  Map<String, dynamic> toJson() => {
    'password': password,
    'changedAt': changedAt.toIso8601String(),
  };

  factory PasswordRecord.fromJson(Map<String, dynamic> json) => PasswordRecord(
    password: json['password'] as String,
    changedAt: DateTime.parse(json['changedAt'] as String),
  );
}

/// パスワードエントリ
class VaultEntry {
  final String uuid;
  String title;
  String username;
  String password;
  String? email;
  String? url;
  String? notes;
  String? category;
  List<String> tags;
  List<PasswordRecord> passwordHistory;
  String? totp;
  DateTime createdAt;
  DateTime updatedAt;
  bool favorite;
  DateTime? deletedAt; // ゴミ箱移動日時（nullなら通常エントリ）

  VaultEntry({
    required this.uuid,
    required this.title,
    required this.username,
    required this.password,
    this.email,
    this.url,
    this.notes,
    this.category,
    List<String>? tags,
    List<PasswordRecord>? passwordHistory,
    this.totp,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.favorite = false,
    this.deletedAt,
  })  : tags = tags ?? [],
        passwordHistory = passwordHistory ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// ゴミ箱に入っているか
  bool get isDeleted => deletedAt != null;

  /// パスワードを更新し、旧パスワードを履歴に追加
  void updatePassword(String newPassword, {int maxHistory = 10}) {
    if (password == newPassword) return;

    // 旧パスワードを履歴に追加
    passwordHistory.insert(
      0,
      PasswordRecord(password: password, changedAt: DateTime.now()),
    );

    // 履歴の上限を超えたら古いものを削除
    if (passwordHistory.length > maxHistory) {
      passwordHistory = passwordHistory.sublist(0, maxHistory);
    }

    password = newPassword;
    updatedAt = DateTime.now();
  }

  /// JSONシリアライズ
  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'title': title,
    'username': username,
    'password': password,
    'email': email,
    'url': url,
    'notes': notes,
    'category': category,
    'tags': tags,
    'passwordHistory': passwordHistory.map((r) => r.toJson()).toList(),
    'totp': totp,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'favorite': favorite,
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
  };

  /// JSONデシリアライズ
  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
    uuid: json['uuid'] as String,
    title: json['title'] as String,
    username: json['username'] as String? ?? '',
    password: json['password'] as String,
    email: json['email'] as String?,
    url: json['url'] as String?,
    notes: json['notes'] as String?,
    category: json['category'] as String?,
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    passwordHistory: (json['passwordHistory'] as List<dynamic>?)
        ?.map((e) => PasswordRecord.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    totp: json['totp'] as String?,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
    updatedAt: json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : null,
    favorite: json['favorite'] as bool? ?? false,
    deletedAt: json['deletedAt'] != null
        ? DateTime.parse(json['deletedAt'] as String)
        : null,
  );

  /// ディープコピー
  VaultEntry copyWith({
    String? title,
    String? username,
    String? password,
    String? email,
    String? url,
    String? notes,
    String? category,
    List<String>? tags,
    String? totp,
    bool? favorite,
    DateTime? deletedAt,
  }) => VaultEntry(
    uuid: uuid,
    title: title ?? this.title,
    username: username ?? this.username,
    password: password ?? this.password,
    email: email ?? this.email,
    url: url ?? this.url,
    notes: notes ?? this.notes,
    category: category ?? this.category,
    tags: tags ?? List.from(this.tags),
    passwordHistory: List.from(passwordHistory),
    totp: totp ?? this.totp,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    favorite: favorite ?? this.favorite,
    deletedAt: deletedAt,
  );
}

/// Vault: 全エントリの集合体
class Vault {
  final String vaultName;
  final DateTime createdAt;
  DateTime updatedAt;
  List<VaultEntry> entries;

  Vault({
    this.vaultName = 'Default',
    DateTime? createdAt,
    DateTime? updatedAt,
    List<VaultEntry>? entries,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        entries = entries ?? [];

  /// エントリを追加
  void addEntry(VaultEntry entry) {
    entries.add(entry);
    updatedAt = DateTime.now();
  }

  /// エントリを更新（UUIDで一致するものを置換）
  void updateEntry(VaultEntry entry) {
    final index = entries.indexWhere((e) => e.uuid == entry.uuid);
    if (index >= 0) {
      entries[index] = entry;
      updatedAt = DateTime.now();
    }
  }

  /// エントリを削除（完全削除）
  void removeEntry(String uuid) {
    entries.removeWhere((e) => e.uuid == uuid);
    updatedAt = DateTime.now();
  }

  /// エントリをゴミ箱に移動
  void trashEntry(String uuid) {
    final entry = findByUuid(uuid);
    if (entry != null) {
      entry.deletedAt = DateTime.now();
      updatedAt = DateTime.now();
    }
  }

  /// ゴミ箱からエントリを復元
  void restoreEntry(String uuid) {
    final entry = findByUuid(uuid);
    if (entry != null) {
      entry.deletedAt = null;
      updatedAt = DateTime.now();
    }
  }

  /// ゴミ箱を空にする（完全削除）
  void emptyTrash() {
    entries.removeWhere((e) => e.isDeleted);
    updatedAt = DateTime.now();
  }

  /// ゴミ箱のエントリ一覧
  List<VaultEntry> get trashedEntries =>
      entries.where((e) => e.isDeleted).toList();

  /// 通常のエントリ一覧（ゴミ箱を除外）
  List<VaultEntry> get activeEntries =>
      entries.where((e) => !e.isDeleted).toList();

  /// UUIDでエントリを検索
  VaultEntry? findByUuid(String uuid) {
    try {
      return entries.firstWhere((e) => e.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  /// タイトルまたはURLで検索
  List<VaultEntry> search(String query) {
    final q = query.toLowerCase();
    return entries.where((e) =>
      e.title.toLowerCase().contains(q) ||
      (e.url?.toLowerCase().contains(q) ?? false) ||
      (e.email?.toLowerCase().contains(q) ?? false) ||
      e.username.toLowerCase().contains(q) ||
      e.tags.any((tag) => tag.toLowerCase().contains(q))
    ).toList();
  }

  /// 同一メールアドレスを使用しているエントリ群を抽出
  Map<String, List<VaultEntry>> groupByEmail() {
    final map = <String, List<VaultEntry>>{};
    for (final entry in entries) {
      final email = entry.email;
      if (email != null && email.isNotEmpty) {
        map.putIfAbsent(email, () => []).add(entry);
      }
    }
    // 2件以上のもののみ返す
    map.removeWhere((_, list) => list.length < 2);
    return map;
  }

  /// カテゴリ別にグルーピング
  Map<String, List<VaultEntry>> groupByCategory() {
    final map = <String, List<VaultEntry>>{};
    for (final entry in entries) {
      final cat = entry.category ?? '未分類';
      map.putIfAbsent(cat, () => []).add(entry);
    }
    return map;
  }

  /// お気に入りのエントリ
  List<VaultEntry> get favorites =>
      entries.where((e) => e.favorite).toList();

  /// JSONシリアライズ
  String toJson() => jsonEncode({
    'vaultName': vaultName,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'entries': entries.map((e) => e.toJson()).toList(),
  });

  /// UUID単位でマージ（同期v2.0）
  /// 
  /// ルール:
  /// - 同一UUID: updatedAtが新しい方を採用
  /// - ローカルのみ: そのまま保持
  /// - リモートのみ: 追加
  /// - 削除済み（deletedAt）: 削除が新しければ削除を維持
  /// 
  /// 戻り値: MergeResult（追加数・更新数・スキップ数）
  MergeResult mergeWith(Vault remote) {
    int added = 0, updated = 0, skipped = 0;

    final localMap = <String, VaultEntry>{};
    for (final e in entries) {
      localMap[e.uuid] = e;
    }

    // コンテンツベースの重複検出用マップ（タイトル+ユーザー名+URL → ローカルエントリ）
    final contentMap = <String, VaultEntry>{};
    for (final e in entries) {
      final key = _contentKey(e);
      if (key.isNotEmpty) contentMap[key] = e;
    }

    for (final remoteEntry in remote.entries) {
      final localEntry = localMap[remoteEntry.uuid];

      if (localEntry == null) {
        // UUIDがローカルに存在しない
        // → コンテンツベースで重複チェック（インポートで別UUIDが振られたケース）
        final contentKey = _contentKey(remoteEntry);
        final contentDup = contentKey.isNotEmpty ? contentMap[contentKey] : null;
        if (contentDup != null) {
          // 同一コンテンツが既に存在 → スキップ（新しい方のデータでローカルを更新）
          if (remoteEntry.updatedAt.isAfter(contentDup.updatedAt)) {
            final idx = entries.indexWhere((e) => e.uuid == contentDup.uuid);
            if (idx >= 0) {
              // UUIDはローカルのものを維持し、中身だけ更新
              contentDup.title = remoteEntry.title;
              contentDup.username = remoteEntry.username;
              contentDup.password = remoteEntry.password;
              contentDup.email = remoteEntry.email;
              contentDup.url = remoteEntry.url;
              contentDup.notes = remoteEntry.notes;
              contentDup.category = remoteEntry.category;
              contentDup.totp = remoteEntry.totp;
              contentDup.favorite = remoteEntry.favorite;
              contentDup.updatedAt = remoteEntry.updatedAt;
              updated++;
            }
          } else {
            skipped++;
          }
        } else {
          // 本当に新規 → 追加
          entries.add(remoteEntry);
          // コンテンツマップにも追加（以降の重複チェック用）
          if (contentKey.isNotEmpty) contentMap[contentKey] = remoteEntry;
          added++;
        }
      } else {
        // 両方に存在（UUID一致） → updatedAtで比較
        if (remoteEntry.updatedAt.isAfter(localEntry.updatedAt)) {
          final idx = entries.indexWhere((e) => e.uuid == remoteEntry.uuid);
          if (idx >= 0) {
            entries[idx] = remoteEntry;
            updated++;
          }
        } else {
          skipped++;
        }
      }
    }

    updatedAt = DateTime.now();
    return MergeResult(added: added, updated: updated, skipped: skipped);
  }

  /// コンテンツベースの重複判定キーを生成
  /// タイトル + ユーザー名 + URL（正規化済み）で一致判定
  static String _contentKey(VaultEntry e) {
    final title = e.title.trim().toLowerCase();
    final username = e.username.trim().toLowerCase();
    final url = (e.url ?? '').trim().toLowerCase()
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '')
        .replaceFirst(RegExp(r'/$'), '');
    // タイトルが空の場合はキーとして使えない
    if (title.isEmpty) return '';
    return '$title|$username|$url';
  }

  /// JSONデシリアライズ
  factory Vault.fromJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return Vault(
      vaultName: json['vaultName'] as String? ?? 'Default',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      entries: (json['entries'] as List<dynamic>?)
          ?.map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}

/// マージ結果
class MergeResult {
  final int added;
  final int updated;
  final int skipped;

  MergeResult({required this.added, required this.updated, required this.skipped});

  int get totalChanges => added + updated;
  bool get hasChanges => totalChanges > 0;

  @override
  String toString() => '追加: $added件, 更新: $updated件, スキップ: $skipped件';
}

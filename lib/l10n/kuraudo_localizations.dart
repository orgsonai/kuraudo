import 'package:flutter/material.dart' as material;

class KuraudoLocaleController {
  const KuraudoLocaleController._();

  static material.ValueChanged<String>? onLanguageChanged;

  static void change(String languageCode) {
    onLanguageChanged?.call(languageCode);
  }
}

/// Kuraudo UI localization.
///
/// Japanese strings remain the source keys so existing screens can be
/// localized without duplicating widget structure. Exact translations are
/// preferred; phrase replacements also cover messages containing user data.
class KuraudoLocalizations {
  const KuraudoLocalizations._();

  static bool isEnglish(material.BuildContext context) =>
      material.Localizations.localeOf(context).languageCode == 'en';

  static String translate(material.BuildContext context, String source) {
    if (!isEnglish(context)) return source;
    final exact = _english[source];
    if (exact != null) return exact;

    var result = source;
    for (final replacement in _phraseReplacements) {
      result = result.replaceAll(replacement.$1, replacement.$2);
    }
    return result;
  }

  static const Map<String, String> _english = {
    '設定': 'Settings',
    '外観': 'Appearance',
    '言語': 'Language',
    '日本語': 'Japanese',
    '英語': 'English',
    'テーマ': 'Theme',
    'ダーク': 'Dark',
    'ライト': 'Light',
    'システム連動': 'System default',
    'セキュリティ': 'Security',
    '同期': 'Sync',
    'データ管理': 'Data management',
    'アプリ情報': 'About',
    'ライセンス': 'Licenses',
    'キャンセル': 'Cancel',
    '確認': 'Confirm',
    '変更': 'Change',
    '保存': 'Save',
    '削除': 'Delete',
    '閉じる': 'Close',
    'コピー': 'Copy',
    'クリア': 'Clear',
    '復元': 'Restore',
    'リセット': 'Reset',
    'スキップ': 'Skip',
    '戻る': 'Back',
    '次へ': 'Next',
    '完了': 'Done',
    '無効': 'Disabled',
    '即時': 'Immediately',
    'すべて': 'All',
    'お気に入り': 'Favorites',
    'ゴミ箱': 'Trash',
    'タイトル': 'Title',
    'ユーザー名': 'Username',
    'パスワード': 'Password',
    'メール': 'Email',
    'メモ': 'Notes',
    'ノート': 'Notes',
    'カテゴリ': 'Category',
    'タグ': 'Tags',
    'サービス名': 'Service name',
    'ログインID': 'Login ID',
    'メールアドレス': 'Email address',
    '新規エントリ': 'New entry',
    'エントリを編集': 'Edit entry',
    'エントリがありません': 'No entries',
    'エントリがありません\n＋ボタンで追加しましょう': 'No entries\nUse the + button to add one',
    'エントリを検索...': 'Search entries...',
    'インポート': 'Import',
    'インポート元': 'Import source',
    'インポート確認': 'Confirm import',
    'インポート可能': 'Ready to import',
    'インポート中...': 'Importing...',
    'インポートが完了しました': 'Import completed',
    'CSVデータを貼り付け': 'Paste CSV data',
    'ここにCSVをペースト...': 'Paste CSV here...',
    'エクスポート手順': 'Export instructions',
    'クリップボード': 'Clipboard',
    'ファイル保存': 'Save to file',
    'ファイルを削除': 'Delete file',
    '自動ロック': 'Auto-lock',
    'パスワード有効期限': 'Password expiry',
    'マスターパスワードを変更': 'Change master password',
    '現在のパスワード': 'Current password',
    '新しいパスワード': 'New password',
    '新しいパスワード（確認）': 'Confirm new password',
    'マスターパスワード': 'Master password',
    'パスワードを確認': 'Confirm password',
    'パスワード確認': 'Password confirmation',
    'クリップボード自動クリア': 'Clear clipboard automatically',
    '自動同期': 'Automatic sync',
    'リアルタイム同期': 'Real-time sync',
    'デスクトップ自動入力': 'Desktop auto-type',
    'ブラウザ・アプリで自動入力を有効化': 'Enable autofill in browsers and apps',
    'バックアップ': 'Backup',
    'バックアップからリストア': 'Restore from backup',
    'バックアップがありません': 'No backups',
    '同期方式': 'Sync method',
    '同期中...': 'Syncing...',
    'アップロード中...': 'Uploading...',
    'ダウンロード中...': 'Downloading...',
    'オフラインモード': 'Offline mode',
    'サインインしてください': 'Please sign in',
    'Googleアカウントでサインイン': 'Sign in with Google',
    'Googleアカウントでクラウド同期': 'Cloud sync with your Google account',
    '同じVaultを同期するすべての端末で、同じマスターパスワードを使用してください。マスターパスワードが異なる場合は同期できません。':
        'Use the same master password on every device that syncs this vault. Syncing is not possible when the master passwords differ.',
    'WebDAVサーバーに接続': 'Connect to a WebDAV server',
    'WebDAV接続設定': 'WebDAV connection settings',
    'サーバーURL': 'Server URL',
    'リモートパス（オプション）': 'Remote path (optional)',
    'ローカルパス': 'Local path',
    'アカウント紐付け': 'Linked accounts',
    'グループ': 'Groups',
    'ソート': 'Sort',
    'メニュー': 'Menu',
    'ロック': 'Lock',
    '選択解除': 'Clear selection',
    '全選択': 'Select all',
    'カテゴリ変更': 'Change category',
    'ゴミ箱に移動': 'Move to trash',
    '完全削除': 'Delete permanently',
    'ゴミ箱に移動しました': 'Moved to trash',
    '復元しました': 'Restored',
    'ゴミ箱は空です': 'Trash is empty',
    'ゴミ箱を空にする': 'Empty trash',
    'この操作は取り消せません。': 'This action cannot be undone.',
    'パスワードをコピー': 'Copy password',
    'ブラウザで開く': 'Open in browser',
    '自動入力': 'Auto-type',
    'ブラウザにユーザー名＋パスワードを入力': 'Type the username and password into the browser',
    'パスワード履歴': 'Password history',
    '作成': 'Created',
    '更新': 'Updated',
    'パスワード生成': 'Generate password',
    'パスフレーズ': 'Passphrase',
    '生成': 'Generate',
    '文字数': 'Length',
    '大文字': 'Uppercase',
    '小文字': 'Lowercase',
    '数字': 'Numbers',
    '記号': 'Symbols',
    'スペース': 'Space',
    'ハイフン': 'Hyphen',
    'アンダースコア': 'Underscore',
    '全件コピー': 'Copy all',
    'TOTPコードをコピーしました': 'TOTP code copied',
    'TOTPシークレットが無効です': 'Invalid TOTP secret',
    'Kuraudoのロックを解除': 'Unlock Kuraudo',
    'アンロック': 'Unlock',
    'Vault を作成': 'Create vault',
    'Vaultファイルを選択': 'Select vault file',
    'Vault場所を指定': 'Choose vault location',
    'エクスプローラーで選択': 'Browse',
    'ファイルパス': 'File path',
    'ファイル名': 'File name',
    'このフォルダに保存できます': 'You can save in this folder',
    '上のフォルダ': 'Parent folder',
    'フォルダ': 'Folder',
    'フォルダを作成': 'Create folder',
    '新しいフォルダ名': 'New folder name',
    '新しいカテゴリ名': 'New category name',
    '既存フォルダから選択': 'Choose an existing folder',
    'すべてのカテゴリ': 'All categories',
    'カテゴリ/フォルダ': 'Category/folder',
    '既存フォルダから選択または新規入力': 'Choose an existing folder or enter a new one',
    'Base32キーまたはotpauth://...': 'Base32 key or otpauth://...',
    'カンマ区切りで入力': 'Separate with commas',
    'タイトルは必須です': 'Title is required',
    'パスワードが一致しません': 'Passwords do not match',
    '8文字以上のパスワードを設定してください': 'Use a password of at least 8 characters',
    'コピーしました': 'Copied',
    '保存しました': 'Saved',
    'エラー': 'Error',
    '再試行': 'Retry',
    'タイトル *': 'Title *',
    'パスワード *': 'Password *',
    'TOTP シークレット': 'TOTP secret',
    '使用する特殊文字': 'Symbols to use',
    '除外する文字': 'Characters to exclude',
    '例: lI1O0o': 'Example: lI1O0o',
    'デフォルトに戻す': 'Restore defaults',
    '詳細設定': 'Advanced settings',
    'プリセット': 'Presets',
    '標準': 'Standard',
    '記号少なめ': 'Fewer symbols',
    '紛らわしい文字除外': 'Exclude ambiguous characters',
    'URLセーフ': 'URL safe',
    'プレビュー': 'Preview',
    '再生成': 'Regenerate',
    '単語数': 'Word count',
    '先頭大文字': 'Capitalize first letter',
    '数字追加': 'Add a number',
    '20件サンプル生成': 'Generate 20 samples',
    '20件サンプル': '20 samples',
    'ファイル保存 / クリップボード': 'Save to file / Clipboard',
    'KeePass CSV エクスポート': 'Export KeePass CSV',
    'Bitwarden CSV エクスポート': 'Export Bitwarden CSV',
    'JSON エクスポート': 'Export JSON',
    'エクスポートするエントリがありません': 'There are no entries to export',
    'エクスポートファイルを削除しました': 'Export file deleted',
    'CSVデータを貼り付けてください': 'Paste CSV data',
    'CSVファイルにはパスワードが平文で含まれています。': 'CSV files contain passwords in plain text.',
    'インポート後はCSVファイルを安全に削除してください。':
        'Securely delete the CSV file after importing.',
    'ヘッダー行が必要です。': 'A header row is required.',
    'ヘッダー行を含めてエクスポートしてください。': 'Include the header row when exporting.',
    '解析する': 'Analyze',
    '解析結果': 'Analysis results',
    '検出行数': 'Rows detected',
    '重複エントリの検出': 'Duplicate entry detection',
    '重複の判定基準: タイトル + ユーザー名 + URL が一致':
        'Duplicates are matched by title + username + URL',
    '全てインポート': 'Import all',
    '重複をスキップ': 'Skip duplicates',
    '弱いパスワード': 'Weak passwords',
    '重複パスワード': 'Duplicate passwords',
    '期限切れパスワード': 'Expired passwords',
    '弱いパスワードはありません 🎉': 'No weak passwords 🎉',
    '重複パスワードはありません 🎉': 'No duplicate passwords 🎉',
    '期限切れのパスワードはありません 🎉': 'No expired passwords 🎉',
    '作成日（新しい順）': 'Created (newest)',
    '作成日（古い順）': 'Created (oldest)',
    '更新日（新しい順）': 'Updated (newest)',
    '更新日（古い順）': 'Updated (oldest)',
    'タイトル（A→Z）': 'Title (A→Z)',
    'タイトル（Z→A）': 'Title (Z→A)',
    '未分類': 'Uncategorized',
    '編集': 'Edit',
    '複製': 'Duplicate',
    '新規作成': 'Create new',
    '既存Vault': 'Existing vault',
    '保存先を選択': 'Choose save location',
    'ここに保存': 'Save here',
    '選択': 'Select',
    '新規作成先（フォルダアイコンで選択可）': 'New file location (use the folder icon to browse)',
    '読み込むファイル（フォルダアイコンで選択可）': 'File to open (use the folder icon to browse)',
    'マスターパスワード（新規）': 'New master password',
    '1分': '1 minute',
    '3分': '3 minutes',
    '5分': '5 minutes',
    '10分': '10 minutes',
    '15分': '15 minutes',
    '30分': '30 minutes',
    '30日': '30 days',
    '60日': '60 days',
    '90日': '90 days',
    '180日': '180 days',
    '365日': '365 days',
    '1年': '1 year',
    '.kuraudoファイルがありません': 'No .kuraudo files',
    '.kuraudo拡張子が自動付与されます': 'The .kuraudo extension is added automatically',
    'デフォルト: ~/Documents/kuraudo.kuraudo':
        'Default: ~/Documents/kuraudo.kuraudo',
    'ロック中': 'Locked',
    'PINで解除': 'Unlock with PIN',
    '生体認証で解除': 'Unlock with biometrics',
    'マスターパスワードで解除': 'Unlock with master password',
    'PIN または生体認証で解除': 'Unlock with PIN or biometrics',
    'PINを設定（4桁）': 'Set PIN (4 digits)',
    'PINを確認': 'Confirm PIN',
    'PINを変更': 'Change PIN',
    'PINを変更しました': 'PIN changed',
    'PINロックアウトを永続化': 'Persist PIN lockout',
    '簡易解除の有効時間': 'Quick unlock duration',
    'この端末は生体認証に対応していません': 'This device does not support biometrics',
    '失敗カウンタをリセット': 'Reset failure counter',
    'カウンタをリセット': 'Reset counter',
    '手動バックアップ': 'Manual backup',
    'リストア': 'Restore',
    'リストア確認': 'Confirm restore',
    'マージ同期': 'Merge sync',
    'ローカル → リモート': 'Local → Remote',
    'リモート → ローカル': 'Remote → Local',
    'ローカル': 'Local',
    'リモート': 'Remote',
    '未同期': 'Never synced',
    '切断': 'Disconnect',
    '接続': 'Connect',
    '実行': 'Run',
    '同期方式を変更': 'Change sync method',
    '同期方式を選択': 'Choose a sync method',
    '同期先フォルダを選択': 'Choose sync folder',
    'サーバーURLとアカウントを設定': 'Configure server URL and account',
    'HTTP接続は安全ではありません': 'HTTP connections are not secure',
    'リスクを承知で続行': 'Continue anyway',
    'それでも続行しますか？': 'Continue anyway?',
    '自動ロック後、この時間以内ならPIN/生体認証で解除可能。\n超過するとマスターパスワードが必要です':
        'After auto-lock, PIN or biometrics can unlock the vault for this period.\nAfterward, the master password is required.',
    'バックグラウンド移行後、指定時間が経過するとVaultを自動ロックします':
        'Automatically locks the vault after the selected background time.',
    'アプリ再起動越しに試行回数を保持': 'Keep the attempt count across app restarts',
    'ONにすると 5回失敗で5分→10分→30分→60分の段階的バックオフ。\n再起動しても試行回数がリセットされません。\nOFF（既定）: 5回失敗するとマスターパスワード入力に切替':
        'When enabled, every 5 failures triggers a progressive 5, 10, 30, then 60-minute lockout.\nThe attempt count is retained after restarting the app.\nWhen disabled (default), 5 failures switch to master-password entry.',
    '永続化されたPIN失敗カウンタとロックアウト時刻をクリアします。':
        'Clear the saved PIN failure count and lockout time.',
    'PIN失敗カウンタをリセットしました': 'The PIN failure counter was reset',
    'パスワードコピー後30秒で自動クリア。\nバックグラウンド移行時・アプリ終了時にも即座にクリア。\nLinux: xclip/xsel/wl-copy を自動検出してクリア。\nAndroid 13+ではキーボード履歴への保存を防止。\n※ KDE Klipperのクリップボード履歴も30秒後に自動削除。\n※ 一部のクリップボードマネージャーでは手動削除が必要です。':
        'Clears automatically 30 seconds after copying a password.\nAlso clears immediately when the app enters the background or exits.\nLinux: automatically detects xclip, xsel, or wl-copy.\nAndroid 13+: prevents saving to keyboard history.\nKDE Klipper history is also cleared after 30 seconds.\nSome clipboard managers may require manual deletion.',
    '解錠時の自動同期と保存時の自動アップロードを制御します（同期方式は同期画面の⇄から選択）':
        'Controls automatic sync on unlock and upload on save (choose the sync method using ⇄ on the Sync screen).',
    'エントリ保存の度に即座にリモートにアップロードします\n自動同期がOFFの場合は無効になります':
        'Uploads immediately whenever an entry is saved.\nDisabled when automatic sync is off.',
    'エントリ詳細画面の「自動入力」ボタンから、ブラウザのログインフォームにユーザー名とパスワードを自動入力できます。\n\n使い方:\n1. ブラウザでログインページを開く\n2. ユーザー名フィールドにフォーカスを合わせる\n3. Kuraudoに戻り「自動入力」をタップ\n4. 3秒以内にブラウザに切り替える':
        'Use the Auto-type button on an entry details screen to enter the username and password in a browser login form.\n\nHow to use:\n1. Open the login page in your browser\n2. Focus the username field\n3. Return to Kuraudo and select Auto-type\n4. Switch back to the browser within 3 seconds',
    '※ Linux: xdotool が必要です（sudo pacman -S xdotool）\n   未インストールの場合はクリップボードコピーにフォールバックします':
        'Linux requires xdotool (sudo pacman -S xdotool).\nIf it is unavailable, Kuraudo falls back to copying to the clipboard.',
    '暗号化: Argon2id (KDF) + AES-256-GCM\nファイル形式: .kuraudo (独自バイナリ)\nフレームワーク: Flutter':
        'Encryption: Argon2id (KDF) + AES-256-GCM\nFile format: .kuraudo (custom binary)\nFramework: Flutter',
    'エクスポートデータには平文のパスワードが含まれます。\nマスターパスワードを入力して確認してください。':
        'Exported data contains passwords in plain text.\nEnter your master password to continue.',
    'マスターパスワードが正しくありません': 'The master password is incorrect',
    'マスターパスワードを変更しました': 'Master password changed',
    '現在のパスワードを入力してください': 'Enter the current password',
    '現在のパスワードが正しくありません': 'The current password is incorrect',
    '新しいパスワードは8文字以上必要です': 'The new password must be at least 8 characters',
    '新しいパスワードは現在のものと異なる必要があります':
        'The new password must differ from the current password',
    '新しいパスワードが一致しません': 'The new passwords do not match',
    'GPL-3.0 — オープンソースライセンス': 'GPL-3.0 — Open-source license',
    'Google Drive同期型パスワードマネージャー\nZero to Ship プロジェクト':
        'Password manager with Google Drive sync\nZero to Ship project',
    'OS のキーリングが使えません': 'The OS keyring is unavailable',
    'PIN での解除は使えません。同期先の接続情報は再起動すると消えます。':
        'PIN unlock is unavailable. Sync connection details are lost when the app restarts.',
    '自動ロックとクリップボードの設定は設定ファイルに保存しています。':
        'Auto-lock and clipboard settings are saved in the settings file.',
    '自動ロックとクリップボードの設定は、変更するときに設定ファイルへ保存するか確認します。':
        'When you change auto-lock or clipboard settings, Kuraudo asks whether to save them in the settings file.',
    'KDE ウォレットや GNOME キーリングを有効にすると、すべて安全に保存できます。':
        'Enable KDE Wallet or GNOME Keyring to store everything securely.',
    '設定ファイルに保存しますか？': 'Save to the settings file?',
    'OS のキーリングが使えないため、この設定を安全な場所に保存できません。\n\n設定ファイルに保存すると再起動後も残りますが、ファイルを書き換えられると設定が変わるおそれがあります。\n保存しない場合、再起動すると元に戻ります。':
        'This setting cannot be stored securely because the OS keyring is unavailable.\n\nIf you save it in the settings file, it stays after restarting, but anyone who can edit the file could change it.\nIf you do not save it, it resets when the app restarts.',
    '保存しない': "Don't save",
    '設定ファイルに保存': 'Save to settings file',
  };

  static const List<(String, String)> _phraseReplacements = [
    ('マスターパスワード', 'master password'),
    ('パスワード', 'password'),
    ('ユーザー名', 'username'),
    ('エントリ', 'entry'),
    ('クリップボード', 'clipboard'),
    ('バックアップ', 'backup'),
    ('インポート', 'import'),
    ('エクスポート', 'export'),
    ('アップロード', 'upload'),
    ('ダウンロード', 'download'),
    ('ゴミ箱', 'trash'),
    ('カテゴリ', 'category'),
    ('をコピーしました', ' copied'),
    ('をコピー', 'Copy '),
    ('に失敗しました', ' failed'),
    ('失敗', ' failed'),
    ('が完了しました', ' completed'),
    ('完了しました', 'Completed'),
    ('がありません', ' not found'),
    ('ありません', 'None'),
    ('してください', 'Please proceed'),
    ('件の', ' '),
    ('件', ''),
    ('日以上未変更', ' days without changes'),
    ('日前に更新', ' days ago'),
    ('時間前', ' hours ago'),
    ('分前', ' minutes ago'),
    ('分', ' min'),
    ('秒', ' sec'),
    ('中...', '...'),
    ('を削除', 'Delete '),
    ('を復元', 'Restore '),
    ('を保存', 'Save '),
    ('を選択', 'Select '),
    ('を変更', 'Change '),
    ('を作成', 'Create '),
    ('を追加', 'Add '),
    ('を開けませんでした', ' could not be opened'),
    ('正しくありません', ' is incorrect'),
    ('エラー:', 'Error:'),
    ('エラー', 'Error'),
    ('警告', 'Warning'),
    ('キャンセル', 'Cancel'),
    ('確認', 'Confirm'),
    ('設定', 'Settings'),
    ('同期', 'Sync'),
    ('保存', 'Save'),
    ('削除', 'Delete'),
    ('復元', 'Restore'),
    ('変更', 'Change'),
    ('新規', 'New'),
    ('現在', 'Current'),
    ('古い', 'Old'),
  ];
}

extension KuraudoLocalizedString on String {
  String l10n(material.BuildContext context) =>
      KuraudoLocalizations.translate(context, this);
}

/// Drop-in localized replacement for Flutter's [material.Text].
///
/// Keeping the same constructor shape lets existing const UI widgets remain
/// const while translation is resolved when the widget is built.
class Text extends material.StatelessWidget {
  final String data;
  final bool localize;
  final material.TextStyle? style;
  final material.StrutStyle? strutStyle;
  final material.TextAlign? textAlign;
  final material.TextDirection? textDirection;
  final material.Locale? locale;
  final bool? softWrap;
  final material.TextOverflow? overflow;
  final double? textScaleFactor;
  final material.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final material.TextWidthBasis? textWidthBasis;
  final material.TextHeightBehavior? textHeightBehavior;
  final material.Color? selectionColor;

  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : localize = true;

  const Text.raw(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : localize = false;

  @override
  material.Widget build(material.BuildContext context) => material.Text(
        localize ? KuraudoLocalizations.translate(context, data) : data,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaleFactor: textScaleFactor,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
}

/// Kuraudo Google Drive 同期サービス
/// 
/// デスクトップ（Linux/Windows）: HTTPベースOAuth2認証（ブラウザ→localhostリダイレクト）
/// Android: google_sign_in パッケージ
/// Google Drive API v3 でファイルのアップロード/ダウンロード
/// App Data Folder を第一候補、通常フォルダをフォールバック
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google認証ヘッダーを付与するHTTPクライアント
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

/// 同期ステータス
enum SyncStatus {
  idle,           // 待機中
  syncing,        // 同期中
  success,        // 同期成功
  error,          // エラー
  offline,        // オフライン
  notSignedIn,    // 未ログイン
}

/// 同期結果
class SyncResult {
  final SyncStatus status;
  final String message;
  final SyncAction action;
  final DateTime? remoteModifiedAt;

  SyncResult({
    required this.status,
    required this.message,
    this.action = SyncAction.none,
    this.remoteModifiedAt,
  });
}

/// 同期で実行されたアクション
enum SyncAction {
  none,
  uploaded,       // ローカル → クラウドにアップロード
  downloaded,     // クラウド → ローカルにダウンロード
  conflict,       // 衝突（手動解決が必要）
}

/// Google Drive 同期サービス
class GoogleDriveService {
  static const String _mimeType = 'application/octet-stream';

  // OAuth2 設定（デスクトップ用）
  // クライアントIDは公開情報（Android/デスクトップ共通）
  static const String _clientId = '957494358901-uamng73fenel1anlsflmki3s0jdg56pd.apps.googleusercontent.com';
  // クライアントシークレットは環境変数から取得（ビルド時に --dart-define=GOOGLE_CLIENT_SECRET=xxx で注入）
  // デスクトップOAuthではシークレットが必要だが、モバイルでは不要
  static const String _clientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET', defaultValue: '');
  static const String _authEndpoint = 'https://accounts.google.com/o/oauth2/auth';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const int _redirectPort = 43823;

  // スコープ
  static const String _appDataScope = 'https://www.googleapis.com/auth/drive.appdata';
  static const String _fileScope = 'https://www.googleapis.com/auth/drive.file';

  // 暗号化トークンストレージ
  static const _secureStorage = FlutterSecureStorage();
  static const _tokenKeyPrefix = 'kuraudo_oauth_';

  drive.DriveApi? _driveApi;
  bool _useAppDataFolder;
  String? _accessToken;
  String? _refreshToken;
  String? _email;
  DateTime? _tokenExpiry;
  String _vaultName = 'Default'; // ActiveVault名

  SyncStatus _status = SyncStatus.notSignedIn;

  GoogleDriveService({
    bool useAppDataFolder = true,
  }) : _useAppDataFolder = useAppDataFolder;

  SyncStatus get status => _status;
  bool get isSignedIn => _accessToken != null && _driveApi != null;
  String? get accountEmail => _email;

  /// ActiveVault名を設定（同期対象ファイル名に使用）
  void setVaultName(String name) {
    _vaultName = name.replaceAll(RegExp(r'[^\w\-]'), '_'); // ファイル名安全化
  }

  /// 現在のVault名に対応するクラウドファイル名
  String get _fileName => 'kuraudo_$_vaultName.kuraudo';

  /// 現在のVault名に対応するバックアッププレフィックス
  String get _backupPrefix => 'kuraudo_backup_${_vaultName}_';

  // ── トークン永続化 ──

  Future<void> _saveToken() async {
    try {
      await _secureStorage.write(key: '${_tokenKeyPrefix}access_token', value: _accessToken);
      await _secureStorage.write(key: '${_tokenKeyPrefix}refresh_token', value: _refreshToken);
      await _secureStorage.write(key: '${_tokenKeyPrefix}email', value: _email);
      await _secureStorage.write(key: '${_tokenKeyPrefix}expiry', value: _tokenExpiry?.toIso8601String());
    } catch (_) {}
  }

  Future<bool> _loadToken() async {
    try {
      _accessToken = await _secureStorage.read(key: '${_tokenKeyPrefix}access_token');
      _refreshToken = await _secureStorage.read(key: '${_tokenKeyPrefix}refresh_token');
      _email = await _secureStorage.read(key: '${_tokenKeyPrefix}email');
      final expiryStr = await _secureStorage.read(key: '${_tokenKeyPrefix}expiry');
      if (expiryStr != null) _tokenExpiry = DateTime.parse(expiryStr);
      return _accessToken != null && _refreshToken != null;
    } catch (_) {
      return false;
    }
  }

  // ── トークンリフレッシュ ──

  Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;
    try {
      final response = await http.post(Uri.parse(_tokenEndpoint), body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'refresh_token': _refreshToken,
        'grant_type': 'refresh_token',
      });
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = json['access_token'] as String;
        final expiresIn = json['expires_in'] as int? ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
        await _saveToken();
        _setupDriveApi();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureValidToken() async {
    if (_accessToken == null) return false;
    if (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      return await _refreshAccessToken();
    }
    return true;
  }

  void _setupDriveApi() {
    if (_accessToken == null) return;
    final client = _GoogleAuthClient({'Authorization': 'Bearer $_accessToken'});
    _driveApi = drive.DriveApi(client);
  }

  // ── プラットフォーム判定 ──

  bool get _isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  // ── サインイン ──

  Future<bool> signIn() async {
    if (_isDesktop) {
      return _signInDesktop();
    } else {
      return _signInMobile();
    }
  }

  /// Android: google_sign_in パッケージを使用
  Future<bool> _signInMobile() async {
    try {
      final scope = _useAppDataFolder ? _appDataScope : _fileScope;
      final googleSignIn = GoogleSignIn(scopes: [scope]);
      final account = await googleSignIn.signIn();
      if (account == null) {
        _status = SyncStatus.notSignedIn;
        return false;
      }

      final authHeaders = await account.authHeaders;
      _accessToken = authHeaders['Authorization']?.replaceFirst('Bearer ', '');
      _email = account.email;
      _tokenExpiry = DateTime.now().add(const Duration(hours: 1));

      _setupDriveApi();
      await _saveToken();
      _status = SyncStatus.idle;
      return true;
    } catch (e) {
      if (_useAppDataFolder) {
        _useAppDataFolder = false;
        return _signInMobile();
      }
      _status = SyncStatus.error;
      return false;
    }
  }

  /// デスクトップ: HTTPベースOAuth2認証（ブラウザ→localhostリダイレクト）
  Future<bool> _signInDesktop() async {
    try {
      final scope = _useAppDataFolder ? _appDataScope : _fileScope;
      final redirectUri = 'http://localhost:$_redirectPort';

      // ローカルHTTPサーバー起動
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);

      // ブラウザで認証URLを開く
      final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
        'client_id': _clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': '$scope email',
        'access_type': 'offline',
        'prompt': 'consent',
      });

      await launchUrl(authUrl, mode: LaunchMode.externalApplication);

      // リダイレクト待ち（120秒タイムアウト）
      String? authCode;
      try {
        final request = await server.first.timeout(const Duration(seconds: 120));
        authCode = request.uri.queryParameters['code'];

        // ブラウザに成功画面を返す
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('<html><body style="font-family:sans-serif;text-align:center;padding:60px;background:#0a0a0b;color:#e4e4e7;">'
              '<h2 style="color:#22c55e;">&#x2705; 認証成功</h2>'
              '<p>Kuraudoに戻ってください。このタブは閉じて構いません。</p>'
              '</body></html>');
        await request.response.close();
      } catch (_) {
        // タイムアウト
      } finally {
        await server.close();
      }

      if (authCode == null) {
        _status = SyncStatus.notSignedIn;
        return false;
      }

      // 認証コード → アクセストークン交換
      final tokenResponse = await http.post(Uri.parse(_tokenEndpoint), body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'code': authCode,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      });

      if (tokenResponse.statusCode != 200) {
        _status = SyncStatus.error;
        return false;
      }

      final tokenJson = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      _accessToken = tokenJson['access_token'] as String;
      _refreshToken = tokenJson['refresh_token'] as String?;
      final expiresIn = tokenJson['expires_in'] as int? ?? 3600;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

      // メールアドレス取得
      try {
        final userInfoResponse = await http.get(
          Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
          headers: {'Authorization': 'Bearer $_accessToken'},
        );
        if (userInfoResponse.statusCode == 200) {
          final userInfo = jsonDecode(userInfoResponse.body) as Map<String, dynamic>;
          _email = userInfo['email'] as String?;
        }
      } catch (_) {}

      await _saveToken();
      _setupDriveApi();
      _status = SyncStatus.idle;
      return true;
    } catch (e) {
      if (_useAppDataFolder) {
        _useAppDataFolder = false;
        return _signInDesktop();
      }
      _status = SyncStatus.error;
      return false;
    }
  }

  // ── サインアウト ──

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _email = null;
    _tokenExpiry = null;
    _driveApi = null;
    _status = SyncStatus.notSignedIn;
    try {
      if (!_isDesktop) {
        await GoogleSignIn().signOut();
      }
      // secure storageからトークンを削除
      await _secureStorage.delete(key: '${_tokenKeyPrefix}access_token');
      await _secureStorage.delete(key: '${_tokenKeyPrefix}refresh_token');
      await _secureStorage.delete(key: '${_tokenKeyPrefix}email');
      await _secureStorage.delete(key: '${_tokenKeyPrefix}expiry');
      // 旧形式の平文トークンファイルも削除（マイグレーション）
      try {
        final dir = await getApplicationDocumentsDirectory();
        final oldFile = File('${dir.path}/kuraudo_google_token.json');
        if (await oldFile.exists()) await oldFile.delete();
      } catch (_) {}
    } catch (_) {}
  }

  // ── サイレントサインイン ──

  Future<bool> silentSignIn() async {
    if (_isDesktop) {
      return _silentSignInDesktop();
    } else {
      return _silentSignInMobile();
    }
  }

  Future<bool> _silentSignInMobile() async {
    try {
      final scope = _useAppDataFolder ? _appDataScope : _fileScope;
      final googleSignIn = GoogleSignIn(scopes: [scope]);
      final account = await googleSignIn.signInSilently();
      if (account == null) {
        _status = SyncStatus.notSignedIn;
        return false;
      }
      final authHeaders = await account.authHeaders;
      _accessToken = authHeaders['Authorization']?.replaceFirst('Bearer ', '');
      _email = account.email;
      _tokenExpiry = DateTime.now().add(const Duration(hours: 1));
      _setupDriveApi();
      _status = SyncStatus.idle;
      return true;
    } catch (_) {
      _status = SyncStatus.notSignedIn;
      return false;
    }
  }

  Future<bool> _silentSignInDesktop() async {
    try {
      if (!await _loadToken()) {
        _status = SyncStatus.notSignedIn;
        return false;
      }
      if (await _ensureValidToken()) {
        _setupDriveApi();
        _status = SyncStatus.idle;
        return true;
      }
      if (await _refreshAccessToken()) {
        _status = SyncStatus.idle;
        return true;
      }
      _status = SyncStatus.notSignedIn;
      return false;
    } catch (_) {
      _status = SyncStatus.notSignedIn;
      return false;
    }
  }

  // ── Drive操作 ──

  Future<drive.File?> _findRemoteFile() async {
    if (_driveApi == null) return null;
    if (!await _ensureValidToken()) return null;
    _setupDriveApi();
    try {
      final spaces = _useAppDataFolder ? 'appDataFolder' : 'drive';
      final query = "name = '$_fileName' and trashed = false";
      final result = await _driveApi!.files.list(q: query, spaces: spaces, $fields: 'files(id, name, modifiedTime, size)', orderBy: 'modifiedTime desc', pageSize: 1);
      if (result.files != null && result.files!.isNotEmpty) return result.files!.first;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<SyncResult> upload(Uint8List fileBytes) async {
    if (_driveApi == null) return SyncResult(status: SyncStatus.notSignedIn, message: 'Googleアカウントにサインインしてください');
    if (!await _ensureValidToken()) return SyncResult(status: SyncStatus.error, message: 'トークンの更新に失敗しました');
    _setupDriveApi();
    _status = SyncStatus.syncing;
    try {
      final existingFile = await _findRemoteFile();
      final media = drive.Media(Stream.value(fileBytes), fileBytes.length);
      if (existingFile != null && existingFile.id != null) {
        final updatedFile = drive.File()..modifiedTime = DateTime.now().toUtc();
        await _driveApi!.files.update(updatedFile, existingFile.id!, uploadMedia: media);
      } else {
        final newFile = drive.File()..name = _fileName..mimeType = _mimeType..modifiedTime = DateTime.now().toUtc();
        if (_useAppDataFolder) newFile.parents = ['appDataFolder'];
        await _driveApi!.files.create(newFile, uploadMedia: media);
      }
      _status = SyncStatus.success;
      return SyncResult(status: SyncStatus.success, message: 'クラウドにアップロードしました', action: SyncAction.uploaded);
    } catch (e) {
      _status = SyncStatus.error;
      return SyncResult(status: SyncStatus.error, message: 'アップロードに失敗しました: $e');
    }
  }

  Future<Uint8List?> download() async {
    if (_driveApi == null) return null;
    if (!await _ensureValidToken()) return null;
    _setupDriveApi();
    _status = SyncStatus.syncing;
    try {
      final remoteFile = await _findRemoteFile();
      if (remoteFile == null || remoteFile.id == null) { _status = SyncStatus.idle; return null; }
      final media = await _driveApi!.files.get(remoteFile.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) { bytes.addAll(chunk); }
      _status = SyncStatus.success;
      return Uint8List.fromList(bytes);
    } catch (_) {
      _status = SyncStatus.error;
      return null;
    }
  }

  Future<DateTime?> getRemoteModifiedTime() async {
    final remoteFile = await _findRemoteFile();
    return remoteFile?.modifiedTime;
  }

  // ── 最終同期時刻の管理 ──

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  Future<String> get _syncStatePath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/kuraudo_sync_state.json';
  }

  Future<void> _saveLastSyncTime() async {
    try {
      final file = File(await _syncStatePath);
      await file.writeAsString(jsonEncode({'lastSyncTime': _lastSyncTime?.toIso8601String()}));
    } catch (_) {}
  }

  Future<void> loadLastSyncTime() async {
    try {
      final file = File(await _syncStatePath);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final t = json['lastSyncTime'] as String?;
        if (t != null) _lastSyncTime = DateTime.parse(t);
      }
    } catch (_) {}
  }

  /// スマート同期: 最終同期時刻ベースで判定
  /// 
  /// - 前回同期以降にローカルが変更されていたらアップロード
  /// - 前回同期以降にリモートが変更されていたらダウンロード
  /// - 両方変更されていたらマージを推奨
  Future<SyncResult> smartSync({
    required Uint8List localFileBytes,
    required DateTime localModifiedAt,
  }) async {
    if (_driveApi == null) return SyncResult(status: SyncStatus.notSignedIn, message: 'Googleアカウントにサインインしてください');
    _status = SyncStatus.syncing;
    try {
      await loadLastSyncTime();
      final remoteModifiedAt = await getRemoteModifiedTime();

      // クラウドにファイルなし → アップロード
      if (remoteModifiedAt == null) {
        final result = await upload(localFileBytes);
        if (result.status == SyncStatus.success) { _lastSyncTime = DateTime.now(); await _saveLastSyncTime(); }
        return result;
      }

      final lastSync = _lastSyncTime ?? DateTime(2000);
      final localChanged = localModifiedAt.isAfter(lastSync.add(const Duration(seconds: 3)));
      final remoteChanged = remoteModifiedAt.isAfter(lastSync.add(const Duration(seconds: 3)));

      if (localChanged && !remoteChanged) {
        // ローカルのみ変更 → アップロード
        final result = await upload(localFileBytes);
        if (result.status == SyncStatus.success) { _lastSyncTime = DateTime.now(); await _saveLastSyncTime(); }
        return result;
      } else if (!localChanged && remoteChanged) {
        // リモートのみ変更 → ダウンロード可能を通知
        _status = SyncStatus.idle;
        return SyncResult(status: SyncStatus.success, message: 'クラウドに新しいデータがあります（マージ同期を推奨）', action: SyncAction.conflict, remoteModifiedAt: remoteModifiedAt);
      } else if (localChanged && remoteChanged) {
        // 両方変更 → マージ推奨
        _status = SyncStatus.idle;
        return SyncResult(status: SyncStatus.success, message: '双方に変更があります（マージ同期を推奨）', action: SyncAction.conflict, remoteModifiedAt: remoteModifiedAt);
      } else {
        // 両方変更なし → 同期済み
        _status = SyncStatus.success;
        _lastSyncTime = DateTime.now();
        await _saveLastSyncTime();
        return SyncResult(status: SyncStatus.success, message: '同期済み', action: SyncAction.none);
      }
    } catch (e) {
      _status = SyncStatus.error;
      return SyncResult(status: SyncStatus.error, message: '同期に失敗しました: $e');
    }
  }

  /// アップロード後に同期時刻を更新するラッパー
  Future<SyncResult> uploadAndRecord(Uint8List fileBytes) async {
    final result = await upload(fileBytes);
    if (result.status == SyncStatus.success) {
      _lastSyncTime = DateTime.now();
      await _saveLastSyncTime();
    }
    return result;
  }

  // ── バックアップ管理 ──

  static const int _maxBackups = 3;

  /// バックアップを作成（Drive上に世代管理）
  Future<SyncResult> createBackup(Uint8List fileBytes, {String label = 'manual'}) async {
    if (_driveApi == null) return SyncResult(status: SyncStatus.notSignedIn, message: 'サインインしてください');
    if (!await _ensureValidToken()) return SyncResult(status: SyncStatus.error, message: 'トークン更新失敗');
    _setupDriveApi();

    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final backupName = '$_backupPrefix${label}_$timestamp.kuraudo';

      final media = drive.Media(Stream.value(fileBytes), fileBytes.length);
      final newFile = drive.File()
        ..name = backupName
        ..mimeType = _mimeType
        ..modifiedTime = DateTime.now().toUtc();
      if (_useAppDataFolder) newFile.parents = ['appDataFolder'];

      await _driveApi!.files.create(newFile, uploadMedia: media);

      // 古いバックアップを削除（最大3世代保持）
      await _pruneBackups(label);

      return SyncResult(status: SyncStatus.success, message: 'バックアップを作成しました: $backupName', action: SyncAction.uploaded);
    } catch (e) {
      return SyncResult(status: SyncStatus.error, message: 'バックアップ作成に失敗: $e');
    }
  }

  /// 古いバックアップを削除（ラベル別に最大_maxBackups件保持）
  Future<void> _pruneBackups(String label) async {
    if (_driveApi == null) return;
    try {
      final spaces = _useAppDataFolder ? 'appDataFolder' : 'drive';
      final query = "name contains '$_backupPrefix${label}_' and trashed = false";
      final result = await _driveApi!.files.list(q: query, spaces: spaces, $fields: 'files(id, name, modifiedTime)', orderBy: 'modifiedTime desc', pageSize: 20);
      final files = result.files ?? [];
      if (files.length > _maxBackups) {
        for (int i = _maxBackups; i < files.length; i++) {
          if (files[i].id != null) await _driveApi!.files.delete(files[i].id!);
        }
      }
    } catch (_) {}
  }

  /// バックアップ一覧を取得
  Future<List<drive.File>> listBackups() async {
    if (_driveApi == null) return [];
    if (!await _ensureValidToken()) return [];
    _setupDriveApi();
    try {
      final spaces = _useAppDataFolder ? 'appDataFolder' : 'drive';
      final query = "name contains '$_backupPrefix' and trashed = false";
      final result = await _driveApi!.files.list(q: query, spaces: spaces, $fields: 'files(id, name, modifiedTime, size)', orderBy: 'modifiedTime desc', pageSize: 20);
      return result.files ?? [];
    } catch (_) {
      return [];
    }
  }

  /// 指定バックアップからリストア
  Future<Uint8List?> downloadBackup(String fileId) async {
    if (_driveApi == null) return null;
    if (!await _ensureValidToken()) return null;
    _setupDriveApi();
    try {
      final media = await _driveApi!.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) { bytes.addAll(chunk); }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  // ── 旧sync()は互換性のため残す ──

  Future<SyncResult> sync({required Uint8List localFileBytes, required DateTime localModifiedAt}) async {
    return smartSync(localFileBytes: localFileBytes, localModifiedAt: localModifiedAt);
  }

  Future<bool> deleteRemoteFile() async {
    if (_driveApi == null) return false;
    try {
      final remoteFile = await _findRemoteFile();
      if (remoteFile?.id != null) { await _driveApi!.files.delete(remoteFile!.id!); return true; }
      return false;
    } catch (_) {
      return false;
    }
  }
}

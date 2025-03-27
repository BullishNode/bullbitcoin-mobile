import 'dart:async';
import 'dart:convert';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:recoverbull/recoverbull.dart';

class GoogleDriveAppDatasource {
  static final _google = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/drive.appdata'],
  );

  drive.DriveApi? _driveApi;

  void _checkConnection() {
    if (_driveApi == null) throw 'unauthenticated';
  }

  Future<void> connect() async {
    try {
      GoogleSignInAccount? account = await _google.signInSilently();

      if (account == null) {
        debugPrint('Silent sign-in failed, attempting interactive sign-in...');
        account = await _google.signIn();
      }

      if (account == null) {
        throw 'Sign-in failed';
      }

      final client = await _google.authenticatedClient();
      if (client == null) throw 'Failed to get authenticated client';

      _driveApi = drive.DriveApi(client);
    } catch (e) {
      debugPrint('Google Sign-in error: $e');
      await disconnect();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _google.disconnect();
    _driveApi = null;
  }

  Future<List<drive.File>> fetchAll() async {
    _checkConnection();
    final response = await _driveApi!.files.list(
      spaces: 'appDataFolder',
      q: "mimeType='application/json' and trashed=false",
      $fields: 'files(id, name, createdTime)',
      orderBy: 'createdTime desc',
    );
    return response.files ?? [];
  }

  Future<List<int>> fetchContent(String fileId) async {
    _checkConnection();
    final media = await _driveApi!.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = await media.stream.fold<List<int>>(
      <int>[],
      (previous, element) => previous..addAll(element),
    );
    return bytes;
  }

  Future<void> trash(String path) async {
    _checkConnection();
    final files = await _driveApi!.files.list(
      spaces: 'appDataFolder',
      q: "name = '$path' and trashed = false",
      $fields: 'files(id)',
    );

    final fileId = files.files?.firstOrNull?.id;
    if (fileId == null) throw "Backup file not found";

    await _driveApi!.files.update(
      drive.File()..trashed = true,
      fileId,
    );
  }

  Future<void> store(String content) async {
    _checkConnection();
    final backup = BullBackup.fromJson(content);
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_${backup.id}.json';

    final file = drive.File()
      ..name = filename
      ..mimeType = 'application/json'
      ..parents = ['appDataFolder'];

    final jsonBackup = backup.toJson();

    await _driveApi!.files.create(
      file,
      uploadMedia: drive.Media(
        Stream.value(utf8.encode(jsonBackup)),
        jsonBackup.length,
      ),
    );
  }
}

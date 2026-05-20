import 'dart:convert';

import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_file_saver.dart';
import 'package:file_picker/file_picker.dart';

class FilePickerWalletManifestFileSaver implements WalletManifestFileSaver {
  @override
  Future<bool> save({required String content, required String filename}) async {
    final result = await FilePicker.platform.saveFile(
      bytes: utf8.encode(content),
      fileName: filename,
    );
    return result != null;
  }
}

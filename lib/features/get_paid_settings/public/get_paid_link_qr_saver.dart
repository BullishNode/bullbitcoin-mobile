import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:meta/meta.dart';

/// Outcome of a Get Paid link QR PNG download.
enum QrImageSaveOutcome {
  /// The user chose a destination and the file was written.
  saved,

  /// The user dismissed the system save dialog — a NEUTRAL result (no error).
  cancelled,

  /// Writing the file failed.
  failed,
}

/// Saves a rendered QR PNG through the system Files save dialog. No gallery or
/// broad-storage permission is requested (the picker owns the destination), and
/// the URL / QR contents / chosen path are never logged.
///
/// It lives beside `GetPaidLinkQr` because it exists only as that widget's
/// injected save seam.
abstract interface class GetPaidLinkQrSaver {
  Future<QrImageSaveOutcome> save({
    required Uint8List pngBytes,
    required String fileName,
  });
}

/// `file_picker`-backed saver (the same `saveFile(bytes:)` idiom the CSV export
/// uses). A null result means the user cancelled; a throw means the write
/// failed. Nothing here is logged.
class FilePickerGetPaidLinkQrSaver implements GetPaidLinkQrSaver {
  const FilePickerGetPaidLinkQrSaver();

  @override
  Future<QrImageSaveOutcome> save({
    required Uint8List pngBytes,
    required String fileName,
  }) {
    return mapSaveDialogResult(
      () => FilePicker.platform.saveFile(bytes: pngBytes, fileName: fileName),
    );
  }
}

/// Runs a system save-dialog call and maps its result to an outcome: a null
/// path is a NEUTRAL cancel, a throw is a failure. Extracted so the mapping is
/// unit-tested without a platform-channel mock. Never logs (no URL / bytes /
/// destination reaches here anyway).
@visibleForTesting
Future<QrImageSaveOutcome> mapSaveDialogResult(
  Future<String?> Function() saveFile,
) async {
  try {
    final result = await saveFile();
    return result == null
        ? QrImageSaveOutcome.cancelled
        : QrImageSaveOutcome.saved;
  } on Exception {
    return QrImageSaveOutcome.failed;
  }
}

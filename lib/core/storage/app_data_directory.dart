import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the directory that owns Bull's local application data.
///
/// Normal builds always use the platform documents directory. The integration
/// target supplies an absolute, disposable directory so destructive recovery
/// journeys cannot touch a developer's real profile.
abstract final class AppDataDirectory {
  static const _isolatedTestPath = String.fromEnvironment(
    'BULL_INTEGRATION_DATA_DIR',
  );

  static bool get isIsolatedTestProfile => _isolatedTestPath.isNotEmpty;

  static Future<Directory> resolve() async {
    if (!isIsolatedTestProfile) {
      return getApplicationDocumentsDirectory();
    }

    final directory = Directory(_isolatedTestPath);
    final lexicalTemp = p.normalize(Directory.systemTemp.absolute.path);
    final lexicalRequested = p.normalize(directory.absolute.path);
    if (!directory.isAbsolute || !p.isWithin(lexicalTemp, lexicalRequested)) {
      throw StateError(
        'BULL_INTEGRATION_DATA_DIR must be inside the system temp directory',
      );
    }

    final normalizedDirectory = Directory(lexicalRequested);
    await normalizedDirectory.create(recursive: true);
    final resolvedTemp = await Directory.systemTemp.resolveSymbolicLinks();
    final resolvedRequested = await normalizedDirectory.resolveSymbolicLinks();
    if (!p.isWithin(resolvedTemp, resolvedRequested)) {
      throw StateError(
        'BULL_INTEGRATION_DATA_DIR must not escape the system temp directory',
      );
    }
    return Directory(resolvedRequested);
  }
}

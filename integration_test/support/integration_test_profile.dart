import 'package:bb_mobile/core/storage/app_data_directory.dart';
import 'package:bb_mobile/main.dart';

/// Fails before application initialization unless the test process owns a
/// disposable profile.
///
/// This guard is shared by the generated aggregate runner and direct IDE/test
/// invocations. It prevents either path from opening a developer's production
/// database, native wallet files, or secure-storage namespace.
Future<void> initializeIntegrationTestApp({required bool isInitialized}) async {
  if (!AppDataDirectory.isIsolatedTestProfile) {
    throw StateError(
      'Integration tests require BULL_INTEGRATION_DATA_DIR; '
      'run `make integration-test`',
    );
  }
  if (!isInitialized) await Bull.init();
}

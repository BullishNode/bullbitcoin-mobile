import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:drift/drift.dart';

/// Adds the local-only wallet metadata backup activation and progress state.
class Schema17To18 {
  static Future<void> migrate(Migrator m, Schema18 schema18) async {
    await m.createTable(schema18.walletMetadataBackupStates);
  }
}

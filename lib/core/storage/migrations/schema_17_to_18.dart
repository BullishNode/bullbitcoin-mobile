import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:drift/drift.dart';

/// Collapses the historical metadata-backup state table into the unified
/// wallet-backup state and records incomplete recovery as a durable fence.
class Schema17To18 {
  static Future<void> migrate(Migrator m, Schema18 schema18) async {
    await m.deleteTable('wallet_metadata_backup_states');
    await m.addColumn(
      schema18.walletBackupStates,
      schema18.walletBackupStates.recoveryBlocked,
    );
  }
}

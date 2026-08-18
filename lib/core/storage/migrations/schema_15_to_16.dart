import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:drift/drift.dart';

/// Adds the durable fence that prevents backup writes while recovery is
/// incomplete. Metadata backup uses the unified wallet-backup state, so no
/// standalone metadata-backup table is created.
class Schema15To16 {
  static Future<void> migrate(Migrator m, Schema16 schema16) async {
    await m.addColumn(
      schema16.walletBackupStates,
      schema16.walletBackupStates.recoveryBlocked,
    );
  }
}

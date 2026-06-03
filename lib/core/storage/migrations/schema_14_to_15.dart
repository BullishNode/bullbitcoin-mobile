import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:drift/drift.dart';

/// Adds the persistence foundation shared by the keychain manifest, unified
/// remote backup, wallet visibility, and autosweep behavior.
class Schema14To15 {
  static Future<void> migrate(Migrator m, Schema15 schema15) async {
    await m.addColumn(
      schema15.walletMetadatas,
      schema15.walletMetadatas.hideOnHome,
    );
    await m.addColumn(
      schema15.walletMetadatas,
      schema15.walletMetadatas.autoSweepEnabled,
    );
    await m.createTable(schema15.keychainManifestEntries);
    await m.createTable(schema15.keychainManifestWalletBindings);
    await m.createTable(schema15.walletBackupStates);
  }
}

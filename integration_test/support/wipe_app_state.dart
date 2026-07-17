import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:get_it/get_it.dart';

/// Simulates a fresh install within one test process (HARNESS §2.6(c)): clears
/// the Get Paid / keychain-manifest / wallet-metadata-backup / wallet drift
/// tables and secure storage (seeds), WITHOUT restarting the process (the
/// Linux device allows exactly one app launch per `flutter test`). The
/// injected fakes intentionally survive so the Bullnym-backed backup
/// round-trip and registration lookups stay honest across the wipe.
///
/// Get Paid's own settings (automated-backup enabled/dirty/last-succeeded) are
/// NOT a dedicated table: `GetGetPaidSettingsUsecase` derives them from
/// `KeychainManifestBackupStates`, so clearing that table clears both.
Future<void> wipeAppState(GetIt locator) async {
  final db = locator<SqliteDatabase>();
  await db.transaction(() async {
    // Bindings reference entries — delete children first.
    await db.delete(db.keychainManifestWalletBindings).go();
    await db.delete(db.keychainManifestEntries).go();
    await db.delete(db.keychainManifestBackupStates).go();
    await db.delete(db.walletMetadataBackupStates).go();
    await db.delete(db.walletMetadatas).go();
  });

  final secureStorage = locator<KeyValueStorageDatasource<String>>(
    instanceName: LocatorInstanceNameConstants.secureStorageDatasource,
  );
  await secureStorage.deleteAll();
}

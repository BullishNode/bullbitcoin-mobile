import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:get_it/get_it.dart';

/// Simulates a fresh install within one test process (HARNESS §2.6(c)): clears
/// the Get Paid / keychain-manifest / wallet drift tables and secure storage
/// (seeds), WITHOUT restarting the process (the Linux device allows exactly one
/// app launch per `flutter test`). The injected fakes intentionally survive so
/// the relay round-trip and registration lookups stay honest across the wipe.
Future<void> wipeAppState(GetIt locator) async {
  final db = locator<SqliteDatabase>();
  await db.transaction(() async {
    // Bindings reference entries — delete children first.
    await db.delete(db.keychainManifestWalletBindings).go();
    await db.delete(db.keychainManifestEntries).go();
    await db.delete(db.getPaidSettings).go();
    await db.delete(db.paymentRecoveries).go();
    await db.delete(db.walletMetadatas).go();
  });

  final secureStorage = locator<KeyValueStorageDatasource<String>>(
    instanceName: LocatorInstanceNameConstants.secureStorageDatasource,
  );
  await secureStorage.deleteAll();
}

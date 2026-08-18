import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/core/storage/app_data_directory.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/core/wallet/data/datasources/wallet_metadata_datasource.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/invoices/application/usecases/create_invoice_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/watchers/wallet_backup_coordinator.dart';
import 'package:bb_mobile/locator.dart';

import 'fake_bullnym_client.dart';

/// Replaces the Bullnym transport after [Bull.init] without leaving any
/// long-lived consumer bound to the previous client.
///
/// In particular, the wallet-backup remote repository and the invoice-create
/// use case are lazy singletons. Resetting only [BullnymClientPort] would leave
/// those objects using the transport they captured when first constructed.
Future<void> installFakeBullnymClient(FakeBullnymClient fake) async {
  await locator.resetLazySingleton<WalletBackupCoordinator>();
  await locator.resetLazySingleton<WalletBackupRemoteRepository>();
  await locator.resetLazySingleton<CreateInvoiceUsecase>();

  await locator.unregister<BullnymClientPort>();
  locator.registerLazySingleton<BullnymClientPort>(() => fake);

  locator<WalletBackupCoordinator>().start();
}

/// Removes the local state owned by Get Paid recovery journeys while leaving
/// the fake Bullnym server untouched.
///
/// Child rows are removed before their manifest parents. Settings and network
/// configuration deliberately survive so the scenario keeps the environment
/// selected by the integration runner. The backup coordinator deliberately
/// remains stopped: restarting it here could race the caller's explicit
/// fresh-install bootstrap with automatic recovery from the preserved fake
/// remote backup.
Future<void> wipeGetPaidLocalState() async {
  if (!AppDataDirectory.isIsolatedTestProfile) {
    throw StateError(
      'Refusing destructive integration cleanup outside an isolated profile',
    );
  }

  await locator.resetLazySingleton<WalletBackupCoordinator>();

  final database = locator<SqliteDatabase>();
  final walletMetadata = locator<WalletMetadataDatasource>();
  final walletRepository = locator<WalletRepository>();
  final walletIds = (await walletMetadata.fetchAll())
      .map((wallet) => wallet.id)
      .toList(growable: false);

  await database.transaction(() async {
    await database.managers.keychainManifestNostrKeys.delete();
    await database.managers.keychainManifestWalletBindings.delete();
    await database.managers.keychainManifestEntries.delete();
    await database.managers.walletBackupStates.delete();
    await database.managers.transactions.delete();
    await database.managers.labels.delete();
    await database.managers.frozenUtxos.delete();
    await database.managers.bip85Derivations.delete();
  });

  // Removing only the Drift metadata leaves the native BDK/LWK wallet files
  // behind. A deterministic re-create can then collide with those files and
  // silently leave the next scenario without both default wallets. Exercise
  // the real repository deletion path so the database and native stores move
  // together.
  for (final walletId in walletIds) {
    await walletRepository.deleteWallet(walletId: walletId);
  }

  await locator<KeyValueStorageDatasource<String>>(
    instanceName: LocatorInstanceNameConstants.secureStorageDatasource,
  ).deleteAll();
}

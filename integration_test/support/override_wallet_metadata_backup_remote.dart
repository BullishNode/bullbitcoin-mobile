import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/bullnym_keychain_manifest_remote_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_remote_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/flush_keychain_manifest_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/bullnym_wallet_metadata_remote_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_remote_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/apply_wallet_metadata_recovery_plan_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/delete_wallet_metadata_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/fetch_current_wallet_metadata_recovery_plan_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/get_wallet_metadata_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/mark_wallet_metadata_backup_dirty_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/set_wallet_metadata_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_snapshot_cryptor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/watchers/wallet_metadata_backup_coordinator.dart';
import 'package:get_it/get_it.dart';

/// Rebinds the already-started metadata composition without replacing its
/// coordinator, contributors, cryptography, key material, or local state.
Future<void> overrideWalletMetadataBackupRemote(
  GetIt locator,
  BullnymClientPort client,
) async {
  await locator.unregister<BullnymClientPort>();
  locator.registerLazySingleton<BullnymClientPort>(() => client);

  await locator.unregister<KeychainManifestRemoteRepository>();
  locator.registerLazySingleton<KeychainManifestRemoteRepository>(
    () => BullnymKeychainManifestRemoteRepository(locator<BullnymFacade>()),
  );
  await locator.unregister<FlushKeychainManifestBackupUsecase>();
  locator.registerLazySingleton<FlushKeychainManifestBackupUsecase>(
    () => FlushKeychainManifestBackupUsecase(
      state: locator(),
      wallet: locator(),
      sync: locator(),
    ),
  );

  await locator.unregister<WalletMetadataRemoteRepository>();
  locator.registerLazySingleton<WalletMetadataRemoteRepository>(
    () => BullnymWalletMetadataRemoteRepository(
      bullnym: locator<BullnymFacade>(),
      snapshots: locator<WalletMetadataSnapshotCryptor>(),
      identity: locator<NostrIdentityFacade>(),
    ),
  );

  // The facade retains its delete use case, so rebuild that public composition
  // after replacing the remote repository. Publish and recovery already resolve
  // their factory use cases lazily through the existing coordinator/facade.
  await locator.unregister<WalletMetadataBackupFacade>();
  locator.registerLazySingleton<WalletMetadataBackupFacade>(
    () => WalletMetadataBackupFacade(
      locator<GetWalletMetadataBackupStateUsecase>(),
      locator<SetWalletMetadataBackupEnabledUsecase>(),
      locator<MarkWalletMetadataBackupDirtyUsecase>(),
      locator<DeleteWalletMetadataBackupUsecase>(),
      locator<WalletMetadataBackupCoordinator>(),
      () => locator<FetchCurrentWalletMetadataRecoveryPlanUsecase>().execute(),
      ({required plan, required createdWalletRefs}) =>
          locator<ApplyWalletMetadataRecoveryPlanUsecase>().execute(
            plan: plan,
            createdWalletRefs: createdWalletRefs,
          ),
    ),
  );
}

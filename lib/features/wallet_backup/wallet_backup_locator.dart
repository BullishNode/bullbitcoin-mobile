import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_electrum_sync_results_usecase.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_backup/data/bullnym_wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/data/default_wallet_backup_wallet_adapter.dart';
import 'package:bb_mobile/features/wallet_backup/data/drift_wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/data/recoverbull_wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/build_wallet_backup_envelope_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_encryption_key_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_signer_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/fetch_wallet_backup_manifest_import_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/get_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/mark_wallet_backup_dirty_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/sync_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/watch_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_wallet_port.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/features/wallet_backup/watchers/wallet_backup_coordinator.dart';
import 'package:get_it/get_it.dart';

class WalletBackupLocator {
  static void setup(GetIt locator) {
    locator.registerLazySingleton<WalletBackupEncryptionRepository>(
      RecoverBullWalletBackupEncryptionRepository.new,
    );
    locator.registerLazySingleton<WalletBackupRemoteRepository>(
      () => BullnymWalletBackupRemoteRepository(locator<BullnymFacade>()),
    );
    locator.registerLazySingleton<WalletBackupStateRepository>(
      () => DriftWalletBackupStateRepository(locator<SqliteDatabase>()),
    );
    locator.registerLazySingleton<WalletBackupWalletPort>(
      () => DefaultWalletBackupWalletAdapter(
        getSettings: locator<GetSettingsUsecase>(),
        wallets: locator<WalletRepository>(),
        seeds: locator<SeedRepository>(),
      ),
    );
    locator.registerFactory<DeriveWalletBackupEncryptionKeyUsecase>(
      () => DeriveWalletBackupEncryptionKeyUsecase(
        registry: locator<Bip85RegistryFacade>(),
      ),
    );
    locator.registerFactory<DeriveWalletBackupSignerUsecase>(
      () => DeriveWalletBackupSignerUsecase(locator<NostrIdentityFacade>()),
    );
    locator.registerFactory<BuildWalletBackupEnvelopeUsecase>(
      () => BuildWalletBackupEnvelopeUsecase(
        locator<KeychainManifestFacade>(),
        locator<Clock>(),
      ),
    );
    locator.registerFactory<SyncWalletBackupUsecase>(
      () => SyncWalletBackupUsecase(
        buildEnvelope: locator<BuildWalletBackupEnvelopeUsecase>(),
        deriveEncryptionKey: locator<DeriveWalletBackupEncryptionKeyUsecase>(),
        encryption: locator<WalletBackupEncryptionRepository>(),
        remote: locator<WalletBackupRemoteRepository>(),
        keychainManifest: locator<KeychainManifestFacade>(),
        deriveSigner: locator<DeriveWalletBackupSignerUsecase>(),
      ),
    );
    locator.registerFactory<GetWalletBackupStateUsecase>(
      () => GetWalletBackupStateUsecase(locator<WalletBackupStateRepository>()),
    );
    locator.registerFactory<WatchWalletBackupStateUsecase>(
      () =>
          WatchWalletBackupStateUsecase(locator<WalletBackupStateRepository>()),
    );
    locator.registerFactory<SetWalletBackupEnabledUsecase>(
      () =>
          SetWalletBackupEnabledUsecase(locator<WalletBackupStateRepository>()),
    );
    locator.registerFactory<BackupWalletNowUsecase>(
      () => BackupWalletNowUsecase(
        state: locator<WalletBackupStateRepository>(),
        wallet: locator<WalletBackupWalletPort>(),
        sync: locator<SyncWalletBackupUsecase>().execute,
        clock: locator<Clock>(),
      ),
    );
    locator.registerFactory<MarkWalletBackupDirtyUsecase>(
      () =>
          MarkWalletBackupDirtyUsecase(locator<WalletBackupStateRepository>()),
    );
    locator.registerLazySingleton<WalletBackupCoordinator>(
      () => WalletBackupCoordinator(
        manifestChanges: locator<KeychainManifestFacade>()
            .watchCommittedChanges(),
        syncResults: locator<WatchElectrumSyncResultsUsecase>().execute(),
        publishBackup: locator<BackupWalletNowUsecase>().execute,
        markDirty: locator<MarkWalletBackupDirtyUsecase>().execute,
      ),
      dispose: (coordinator) => coordinator.dispose(),
    );
    locator.registerFactory<DeleteWalletBackupUsecase>(
      () => DeleteWalletBackupUsecase(
        remote: locator<WalletBackupRemoteRepository>(),
        state: locator<WalletBackupStateRepository>(),
        wallet: locator<WalletBackupWalletPort>(),
        deriveSigner: locator<DeriveWalletBackupSignerUsecase>(),
      ),
    );
    locator.registerFactory<FetchWalletBackupManifestImportUsecase>(
      () => FetchWalletBackupManifestImportUsecase(
        wallet: locator<WalletBackupWalletPort>(),
        deriveSigner: locator<DeriveWalletBackupSignerUsecase>(),
        remote: locator<WalletBackupRemoteRepository>(),
        deriveEncryptionKey: locator<DeriveWalletBackupEncryptionKeyUsecase>(),
        encryption: locator<WalletBackupEncryptionRepository>(),
        keychainManifest: locator<KeychainManifestFacade>(),
        state: locator<WalletBackupStateRepository>(),
      ),
    );
    locator.registerFactory<WalletBackupFacade>(
      () => WalletBackupFacade(
        getState: locator<GetWalletBackupStateUsecase>(),
        watchState: locator<WatchWalletBackupStateUsecase>(),
        setEnabled: locator<SetWalletBackupEnabledUsecase>(),
        delete: locator<DeleteWalletBackupUsecase>(),
        fetchManifestImport: locator<FetchWalletBackupManifestImportUsecase>(),
        coordinator: locator<WalletBackupCoordinator>(),
      ),
    );
  }

  static void start(GetIt locator) {
    locator<WalletBackupCoordinator>().start();
  }
}

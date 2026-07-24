import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_backup/data/bullnym_wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/data/drift_wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/data/recoverbull_wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/build_wallet_backup_envelope_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_encryption_key_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/sync_wallet_backup_usecase.dart';
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
    locator.registerFactory<DeriveWalletBackupEncryptionKeyUsecase>(
      () => DeriveWalletBackupEncryptionKeyUsecase(
        registry: locator<Bip85RegistryFacade>(),
      ),
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
        identity: locator<NostrIdentityFacade>(),
      ),
    );
  }
}

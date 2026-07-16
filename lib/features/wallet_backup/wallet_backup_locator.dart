import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/wallet_backup/data/recoverbull_wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/build_wallet_backup_envelope_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_encryption_key_usecase.dart';
import 'package:get_it/get_it.dart';

class WalletBackupLocator {
  static void setup(GetIt locator) {
    locator.registerLazySingleton<WalletBackupEncryptionRepository>(
      RecoverBullWalletBackupEncryptionRepository.new,
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
  }
}

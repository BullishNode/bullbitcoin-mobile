import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/public/keychain_recovery_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/recover_remote_keychain_manifest_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/heal_recovered_products_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/data/remote_recovery_outcome_store.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/recover_remote_wallet_backups_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/get_last_remote_recovery_outcome_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:get_it/get_it.dart';

final class RemoteKeychainRecoveryLocator {
  static void setup(GetIt locator) {
    locator.registerFactory<HealRecoveredProductsUsecase>(
      () => HealRecoveredProductsUsecase(
        locator<LightningAddressFacade>(),
        locator<PaymentPageFacade>(),
        locator<PosFacade>(),
      ),
    );
    locator.registerFactory<RecoverRemoteKeychainManifestUsecase>(
      () => RecoverRemoteKeychainManifestUsecase(
        locator<WalletBackupFacade>(),
        locator<KeychainManifestFacade>(),
        locator<KeychainRecoveryFacade>(),
        locator<HealRecoveredProductsUsecase>(),
      ),
    );
    locator.registerFactory<RemoteRecoveryOutcomeStore>(
      () => RemoteRecoveryOutcomeStore(
        locator<KeyValueStorageDatasource<String>>(
          instanceName: LocatorInstanceNameConstants.secureStorageDatasource,
        ),
      ),
    );
    locator.registerFactory<GetLastRemoteRecoveryOutcomeUsecase>(
      () => GetLastRemoteRecoveryOutcomeUsecase(
        locator<RemoteRecoveryOutcomeStore>(),
      ),
    );
    locator.registerFactory<RecoverRemoteWalletBackupsUsecase>(
      () => RecoverRemoteWalletBackupsUsecase(
        (deadline) => locator<RecoverRemoteKeychainManifestUsecase>().execute(
          deadline: deadline,
        ),
        locator<WalletBackupFacade>(),
        locator<WalletMetadataBackupFacade>(),
        outcomeStore: locator<RemoteRecoveryOutcomeStore>(),
      ),
    );
    locator.registerFactory<RemoteKeychainRecoveryFacade>(
      () => RemoteKeychainRecoveryFacade(
        locator<RecoverRemoteWalletBackupsUsecase>(),
      ),
    );
  }
}

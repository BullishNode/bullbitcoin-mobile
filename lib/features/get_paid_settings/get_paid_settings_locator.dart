import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/data/drift_get_paid_settings_repository.dart';
import 'package:bb_mobile/features/get_paid_settings/data/get_paid_settings_default_wallet_xprv_adapter.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/repositories/get_paid_settings_repository.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/acknowledge_automated_backup_disclosure_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_settings_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/get_get_paid_wallet_behaviors_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/publish_automated_keychain_backup_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/set_automated_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_cubit.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:get_it/get_it.dart';

class GetPaidSettingsLocator {
  static void setup(GetIt locator) {
    // lazySingleton: the repository is stateless over the shared SqliteDatabase
    // singleton, so a single instance is safe and avoids re-allocating on every
    // resolution.
    locator.registerLazySingleton<GetPaidSettingsRepository>(
      () => DriftGetPaidSettingsRepository(database: locator<SqliteDatabase>()),
    );
    locator.registerFactory<GetPaidSettingsDefaultWalletXprvPort>(
      () => GetPaidSettingsDefaultWalletXprvAdapter(
        getSettings: locator<GetSettingsUsecase>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );
    locator.registerFactory<GetGetPaidSettingsUsecase>(
      () => GetGetPaidSettingsUsecase(
        repository: locator<GetPaidSettingsRepository>(),
      ),
    );
    // Read-only resolver for reserved product wallets (LA/PP/POS), consumed by
    // each product screen's cubit to drive its per-wallet behavior controls.
    locator.registerFactory<GetGetPaidWalletBehaviorsUsecase>(
      () => GetGetPaidWalletBehaviorsUsecase(
        getWallets: locator<GetWalletsUsecase>(),
      ),
    );
    locator.registerFactory<PublishAutomatedKeychainBackupUsecase>(
      () => PublishAutomatedKeychainBackupUsecase(
        repository: locator<GetPaidSettingsRepository>(),
        xprvPort: locator<GetPaidSettingsDefaultWalletXprvPort>(),
        keychainManifest: locator<KeychainManifestFacade>(),
        relayPolicy: const NostrRelayPolicyFacade(),
      ),
    );
    locator.registerFactory<SetAutomatedBackupEnabledUsecase>(
      () => SetAutomatedBackupEnabledUsecase(
        repository: locator<GetPaidSettingsRepository>(),
        publishBackup: locator<PublishAutomatedKeychainBackupUsecase>(),
      ),
    );
    locator.registerFactory<AcknowledgeAutomatedBackupDisclosureUsecase>(
      () => AcknowledgeAutomatedBackupDisclosureUsecase(
        repository: locator<GetPaidSettingsRepository>(),
      ),
    );
    locator.registerFactory<GetPaidSettingsFacade>(
      () => GetPaidSettingsFacade(
        getSettings: locator<GetGetPaidSettingsUsecase>(),
        setAutomatedBackupEnabled: locator<SetAutomatedBackupEnabledUsecase>(),
        acknowledgeDisclosure:
            locator<AcknowledgeAutomatedBackupDisclosureUsecase>(),
        publishBackup: locator<PublishAutomatedKeychainBackupUsecase>(),
      ),
    );
    locator.registerFactory<GetPaidSettingsCubit>(
      () => GetPaidSettingsCubit(
        getSettings: locator<GetGetPaidSettingsUsecase>(),
        setAutomatedBackupEnabled: locator<SetAutomatedBackupEnabledUsecase>(),
      ),
    );
  }
}

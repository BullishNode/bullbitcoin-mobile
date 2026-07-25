import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/watch_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_cubit.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:get_it/get_it.dart';

class BackupSettingsLocator {
  static void setup(GetIt locator) {
    // Blocs
    locator.registerFactory<BackupSettingsCubit>(
      () => BackupSettingsCubit(
        getWalletsUsecase: locator<GetWalletsUsecase>(),
        settingsRepository: locator<SettingsRepository>(),
      ),
    );
    locator.registerFactory<WatchWalletBackupUsecase>(
      () => WatchWalletBackupUsecase(locator<WalletBackupFacade>()),
    );
    locator.registerFactory<SetWalletBackupEnabledUsecase>(
      () => SetWalletBackupEnabledUsecase(locator<WalletBackupFacade>()),
    );
    locator.registerFactory<BackupWalletNowUsecase>(
      () => BackupWalletNowUsecase(locator<WalletBackupFacade>()),
    );
    locator.registerFactory<DeleteWalletBackupUsecase>(
      () => DeleteWalletBackupUsecase(locator<WalletBackupFacade>()),
    );
    locator.registerFactory<WalletBackupSettingsCubit>(
      () => WalletBackupSettingsCubit(
        locator<WatchWalletBackupUsecase>(),
        locator<SetWalletBackupEnabledUsecase>(),
        locator<BackupWalletNowUsecase>(),
        locator<DeleteWalletBackupUsecase>(),
      ),
    );
  }
}

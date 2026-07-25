import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/apply_recovered_wallet_preferences_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_frozen_wallet_outpoints_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_preferences_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/restore_frozen_wallet_outpoints_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_wallet_preference_changes_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_wallet_utxo_freeze_changes_usecase.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/labels_bip329_wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_composition_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_backup_section_provider.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_preferences_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_utxo_freeze_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_snapshot_composition_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_section_provider.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:get_it/get_it.dart';

final class WalletMetadataBackupLocator {
  const WalletMetadataBackupLocator._();

  static void setup(GetIt locator) {
    locator.registerLazySingleton<LabelsBip329WalletMetadataContributor>(
      () => LabelsBip329WalletMetadataContributor(locator<LabelsFacade>()),
    );
    locator.registerLazySingleton<WalletUtxoFreezeMetadataContributor>(
      () => WalletUtxoFreezeMetadataContributor(
        locator<GetFrozenWalletOutpointsUsecase>(),
        locator<RestoreFrozenWalletOutpointsUsecase>(),
        locator<WatchWalletUtxoFreezeChangesUsecase>(),
      ),
    );
    locator.registerLazySingleton<WalletPreferencesMetadataContributor>(
      () => WalletPreferencesMetadataContributor(
        locator<GetWalletPreferencesUsecase>(),
        locator<ApplyRecoveredWalletPreferencesUsecase>(),
        locator<WatchWalletPreferenceChangesUsecase>(),
      ),
    );
    locator.registerLazySingleton<WalletMetadataSnapshotCompositionRepository>(
      WalletMetadataSnapshotCompositionRepositoryImpl.new,
    );
    locator.registerLazySingleton<WalletMetadataBackupSectionProvider>(
      () => WalletMetadataBackupSectionProviderImpl(
        contributors: _contributors(locator),
        restoringContributors: _restoringContributors(locator),
        composition: locator<WalletMetadataSnapshotCompositionRepository>(),
        clock: locator<Clock>(),
      ),
      dispose: (provider) => provider.dispose(),
    );
    locator.registerLazySingleton<WalletMetadataBackupFacade>(
      () => WalletMetadataBackupFacade.unified(
        walletBackup: locator<WalletBackupFacade>(),
        sectionProvider: locator<WalletMetadataBackupSectionProvider>(),
      ),
    );
  }

  static List<WalletMetadataContributor> _contributors(GetIt locator) => [
    locator<LabelsBip329WalletMetadataContributor>(),
    locator<WalletUtxoFreezeMetadataContributor>(),
    locator<WalletPreferencesMetadataContributor>(),
  ];

  static List<WalletMetadataRestoringContributor> _restoringContributors(
    GetIt locator,
  ) => [
    locator<LabelsBip329WalletMetadataContributor>(),
    locator<WalletUtxoFreezeMetadataContributor>(),
    locator<WalletPreferencesMetadataContributor>(),
  ];
}

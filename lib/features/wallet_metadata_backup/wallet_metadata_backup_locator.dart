import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_utxo_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/apply_recovered_wallet_preferences_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_preferences_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_wallet_preference_changes_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_wallet_utxo_freeze_changes_usecase.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/drift_wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/labels_bip329_wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/local_wallet_metadata_backup_root_adapter.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_key_deriver.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_safe_head_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_composition_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/websocket_wallet_metadata_graph_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/websocket_wallet_metadata_relay_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_utxo_freeze_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_preferences_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_graph_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_relay_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_safe_head_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_snapshot_composition_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_snapshot_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/acknowledge_wallet_metadata_relay_disclosure_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/apply_wallet_metadata_recovery_plan_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/build_wallet_metadata_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/fetch_wallet_metadata_recovery_plan_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/get_wallet_metadata_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/mark_wallet_metadata_backup_dirty_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/publish_wallet_metadata_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/publish_current_wallet_metadata_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/set_wallet_metadata_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_root_port.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_publication_guard.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/watchers/wallet_metadata_backup_coordinator.dart';
import 'package:get_it/get_it.dart';

final class WalletMetadataBackupLocator {
  const WalletMetadataBackupLocator._();

  static void setup(GetIt locator) {
    locator.registerLazySingleton<LabelsBip329WalletMetadataContributor>(
      () => LabelsBip329WalletMetadataContributor(locator<LabelsFacade>()),
    );
    locator.registerLazySingleton<WalletUtxoFreezeMetadataContributor>(
      () => WalletUtxoFreezeMetadataContributor(
        locator<WalletUtxoRepository>(),
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
    locator.registerLazySingleton<WalletMetadataPublicationGuard>(
      WalletMetadataPublicationGuard.new,
    );
    locator.registerLazySingleton<WalletMetadataBackupRootPort>(
      () => LocalWalletMetadataBackupRootAdapter(
        getSettings: locator<GetSettingsUsecase>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );
    locator.registerLazySingleton<WalletMetadataBackupStateRepository>(
      () => DriftWalletMetadataBackupStateRepository(locator<SqliteDatabase>()),
    );
    locator.registerLazySingleton<WalletMetadataSnapshotRepository>(
      () => WalletMetadataSnapshotRepositoryImpl(
        nostrIdentity: locator<NostrIdentityFacade>(),
        keyDeriver: WalletMetadataKeyDeriver(
          registry: locator<Bip85RegistryFacade>(),
        ),
      ),
    );
    locator.registerLazySingleton<WalletMetadataSnapshotCompositionRepository>(
      WalletMetadataSnapshotCompositionRepositoryImpl.new,
    );
    locator.registerLazySingleton<WalletMetadataRelayRepository>(
      WebSocketWalletMetadataRelayRepository.new,
    );
    locator.registerLazySingleton<WalletMetadataGraphRepository>(
      () => WebSocketWalletMetadataGraphRepository(
        nostrIdentity: locator<NostrIdentityFacade>(),
        keyDeriver: WalletMetadataKeyDeriver(
          registry: locator<Bip85RegistryFacade>(),
        ),
      ),
    );
    locator.registerLazySingleton<WalletMetadataSafeHeadRepository>(
      () => WalletMetadataSafeHeadRepositoryImpl(
        graphRepository: locator<WalletMetadataGraphRepository>(),
        clock: locator<Clock>(),
      ),
    );
    locator.registerFactory<BuildWalletMetadataSnapshotUsecase>(
      () => BuildWalletMetadataSnapshotUsecase(
        locator<WalletMetadataSnapshotRepository>(),
      ),
    );
    locator.registerFactory<GetWalletMetadataBackupStateUsecase>(
      () => GetWalletMetadataBackupStateUsecase(
        locator<WalletMetadataBackupStateRepository>(),
      ),
    );
    locator.registerFactory<SetWalletMetadataBackupEnabledUsecase>(
      () => SetWalletMetadataBackupEnabledUsecase(
        locator<WalletMetadataBackupStateRepository>(),
      ),
    );
    locator.registerFactory<AcknowledgeWalletMetadataRelayDisclosureUsecase>(
      () => AcknowledgeWalletMetadataRelayDisclosureUsecase(
        locator<WalletMetadataBackupStateRepository>(),
      ),
    );
    locator.registerFactory<MarkWalletMetadataBackupDirtyUsecase>(
      () => MarkWalletMetadataBackupDirtyUsecase(
        locator<WalletMetadataBackupStateRepository>(),
      ),
    );
    locator.registerFactory<PublishWalletMetadataBackupUsecase>(
      () => PublishWalletMetadataBackupUsecase(
        stateRepository: locator<WalletMetadataBackupStateRepository>(),
        safeHeadRepository: locator<WalletMetadataSafeHeadRepository>(),
        compositionRepository:
            locator<WalletMetadataSnapshotCompositionRepository>(),
        snapshotRepository: locator<WalletMetadataSnapshotRepository>(),
        relayRepository: locator<WalletMetadataRelayRepository>(),
        contributors: _contributors(locator),
        clock: locator<Clock>(),
      ),
    );
    locator.registerFactory<PublishCurrentWalletMetadataBackupUsecase>(
      () => PublishCurrentWalletMetadataBackupUsecase(
        stateRepository: locator<WalletMetadataBackupStateRepository>(),
        rootPort: locator<WalletMetadataBackupRootPort>(),
        publish: locator<PublishWalletMetadataBackupUsecase>(),
      ),
    );
    locator.registerFactory<FetchWalletMetadataRecoveryPlanUsecase>(
      () => FetchWalletMetadataRecoveryPlanUsecase(
        stateRepository: locator<WalletMetadataBackupStateRepository>(),
        graphRepository: locator<WalletMetadataGraphRepository>(),
        contributors: _contributors(locator),
        clock: locator<Clock>(),
      ),
    );
    locator.registerFactory<ApplyWalletMetadataRecoveryPlanUsecase>(
      () => ApplyWalletMetadataRecoveryPlanUsecase(
        locator<WalletMetadataBackupRootPort>(),
        stateRepository: locator<WalletMetadataBackupStateRepository>(),
        contributors: _restoringContributors(locator),
        publicationGuard: locator<WalletMetadataPublicationGuard>(),
        clock: locator<Clock>(),
      ),
    );
    locator.registerLazySingleton<WalletMetadataBackupCoordinator>(
      () => WalletMetadataBackupCoordinator(
        markDirty: locator<MarkWalletMetadataBackupDirtyUsecase>(),
        publishCurrent: () =>
            locator<PublishCurrentWalletMetadataBackupUsecase>().execute(),
        guard: locator<WalletMetadataPublicationGuard>(),
        sources: () => _changeSources(locator),
      ),
      dispose: (coordinator) => coordinator.dispose(),
    );
    locator.registerLazySingleton<WalletMetadataBackupFacade>(
      () => WalletMetadataBackupFacade(
        locator<GetWalletMetadataBackupStateUsecase>(),
        locator<SetWalletMetadataBackupEnabledUsecase>(),
        locator<AcknowledgeWalletMetadataRelayDisclosureUsecase>(),
        locator<MarkWalletMetadataBackupDirtyUsecase>(),
        locator<WalletMetadataBackupCoordinator>(),
        ({required xprvBase58, required parentFingerprint}) =>
            locator<FetchWalletMetadataRecoveryPlanUsecase>().execute(
              xprvBase58: xprvBase58,
              parentFingerprint: parentFingerprint,
            ),
        ({required plan, required createdWalletRefs}) =>
            locator<ApplyWalletMetadataRecoveryPlanUsecase>().execute(
              plan: plan,
              createdWalletRefs: createdWalletRefs,
            ),
      ),
    );
  }

  static Future<void> start(GetIt locator) {
    return locator<WalletMetadataBackupCoordinator>().start();
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

  static List<WalletMetadataChangeSource> _changeSources(GetIt locator) => [
    locator<LabelsBip329WalletMetadataContributor>(),
    locator<WalletUtxoFreezeMetadataContributor>(),
    locator<WalletPreferencesMetadataContributor>(),
  ];
}

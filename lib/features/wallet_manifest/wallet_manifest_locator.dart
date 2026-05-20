import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/bip85/domain/fetch_all_derivations_usecase.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/repositories/settings_repository.dart'
    as settings;
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_nostr_snapshot_store.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_file_saver.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_origin_store.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_wallet_operations_port.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/audit_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/build_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/check_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/create_manual_bip85_wallets_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/delete_wallet_manifest_origin_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_nostr_handle_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_root_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_wallet_manifest_origins_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/get_wallet_manifest_public_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/publish_local_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/record_wallet_manifest_origin_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/save_wallet_manifest_payload_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/start_wallet_manifest_restore_after_seed_recovery_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/interface_adapters/file_picker_wallet_manifest_file_saver.dart';
import 'package:bb_mobile/features/wallet_manifest/interface_adapters/nostr_wallet_manifest_snapshot_store.dart';
import 'package:bb_mobile/features/wallet_manifest/interface_adapters/wallet_manifest_wallet_operations_adapter.dart';
import 'package:bb_mobile/features/wallet_manifest/interface_adapters/wallet_manifest_origin_datasource.dart';
import 'package:bb_mobile/features/wallet_manifest/presentation/wallet_manifest_settings_cubit.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';
import 'package:get_it/get_it.dart';

class WalletManifestLocator {
  static void setup(GetIt locator) {
    if (!locator.isRegistered<WalletManifestOriginStore>()) {
      locator.registerLazySingleton<WalletManifestOriginStore>(
        () => WalletManifestOriginDatasource(sqlite: locator<SqliteDatabase>()),
      );
    }

    if (!locator.isRegistered<WalletManifestNostrSnapshotStore>()) {
      locator.registerLazySingleton<WalletManifestNostrSnapshotStore>(
        () => NostrWalletManifestSnapshotStore(
          relayClient: locator<NostrRelayClient>(),
        ),
      );
    }

    if (!locator.isRegistered<WalletManifestWalletOperationsPort>()) {
      locator.registerLazySingleton<WalletManifestWalletOperationsPort>(
        () => WalletManifestWalletOperationsAdapter(
          bip85Repository: locator<Bip85Repository>(),
          seedRepository: locator<SeedRepository>(),
          walletRepository: locator<WalletRepository>(),
          getWallets: locator<GetWalletsUsecase>(),
        ),
      );
    }

    if (!locator.isRegistered<WalletManifestFileSaver>()) {
      locator.registerLazySingleton<WalletManifestFileSaver>(
        FilePickerWalletManifestFileSaver.new,
      );
    }

    if (!locator.isRegistered<RecordWalletManifestOriginUsecase>()) {
      locator.registerFactory<RecordWalletManifestOriginUsecase>(
        () => RecordWalletManifestOriginUsecase(
          originStore: locator<WalletManifestOriginStore>(),
        ),
      );
    }

    if (!locator.isRegistered<FetchWalletManifestOriginsUsecase>()) {
      locator.registerFactory<FetchWalletManifestOriginsUsecase>(
        () => FetchWalletManifestOriginsUsecase(
          originStore: locator<WalletManifestOriginStore>(),
        ),
      );
    }

    if (!locator.isRegistered<DeleteWalletManifestOriginUsecase>()) {
      locator.registerFactory<DeleteWalletManifestOriginUsecase>(
        () => DeleteWalletManifestOriginUsecase(
          originStore: locator<WalletManifestOriginStore>(),
        ),
      );
    }

    if (!locator.isRegistered<BuildWalletManifestSnapshotUsecase>()) {
      locator.registerFactory<BuildWalletManifestSnapshotUsecase>(
        () => BuildWalletManifestSnapshotUsecase(
          fetchOrigins: locator<FetchWalletManifestOriginsUsecase>(),
          getWallets: locator<GetWalletsUsecase>(),
        ),
      );
    }

    if (!locator.isRegistered<DeriveWalletManifestRootKeyUsecase>()) {
      locator.registerFactory<DeriveWalletManifestRootKeyUsecase>(
        () => DeriveWalletManifestRootKeyUsecase(
          walletOperations: locator<WalletManifestWalletOperationsPort>(),
        ),
      );
    }

    if (!locator.isRegistered<DeriveWalletManifestNostrHandleUsecase>()) {
      locator.registerFactory<DeriveWalletManifestNostrHandleUsecase>(
        () => DeriveWalletManifestNostrHandleUsecase(
          deriveRootKey: locator<DeriveWalletManifestRootKeyUsecase>(),
        ),
      );
    }

    if (!locator.isRegistered<PublishLocalWalletManifestUsecase>()) {
      locator.registerFactory<PublishLocalWalletManifestUsecase>(
        () => PublishLocalWalletManifestUsecase(
          buildSnapshot: locator<BuildWalletManifestSnapshotUsecase>(),
          deriveHandle: locator<DeriveWalletManifestNostrHandleUsecase>(),
          nostrSnapshotStore: locator<WalletManifestNostrSnapshotStore>(),
        ),
      );
    }

    if (!locator.isRegistered<FetchRemoteWalletManifestUsecase>()) {
      locator.registerFactory<FetchRemoteWalletManifestUsecase>(
        () => FetchRemoteWalletManifestUsecase(
          deriveHandle: locator<DeriveWalletManifestNostrHandleUsecase>(),
          nostrSnapshotStore: locator<WalletManifestNostrSnapshotStore>(),
        ),
      );
    }

    if (!locator.isRegistered<RestoreWalletManifestSnapshotUsecase>()) {
      locator.registerFactory<RestoreWalletManifestSnapshotUsecase>(
        () => RestoreWalletManifestSnapshotUsecase(
          walletOperations: locator<WalletManifestWalletOperationsPort>(),
          fetchOrigins: locator<FetchWalletManifestOriginsUsecase>(),
          recordOrigin: locator<RecordWalletManifestOriginUsecase>(),
          deriveRootKey: locator<DeriveWalletManifestRootKeyUsecase>(),
        ),
      );
    }

    if (!locator.isRegistered<RestoreRemoteWalletManifestUsecase>()) {
      locator.registerFactory<RestoreRemoteWalletManifestUsecase>(
        () => RestoreRemoteWalletManifestUsecase(
          fetchRemoteManifest: locator<FetchRemoteWalletManifestUsecase>(),
          restoreSnapshot: locator<RestoreWalletManifestSnapshotUsecase>(),
        ),
      );
    }

    if (!locator
        .isRegistered<StartWalletManifestRestoreAfterSeedRecoveryUsecase>()) {
      locator
          .registerFactory<StartWalletManifestRestoreAfterSeedRecoveryUsecase>(
            () => StartWalletManifestRestoreAfterSeedRecoveryUsecase(
              restoreRemoteManifest:
                  locator<RestoreRemoteWalletManifestUsecase>(),
            ),
          );
    }

    if (!locator.isRegistered<CheckRemoteWalletManifestUsecase>()) {
      locator.registerFactory<CheckRemoteWalletManifestUsecase>(
        () => CheckRemoteWalletManifestUsecase(
          fetchRemoteManifest: locator<FetchRemoteWalletManifestUsecase>(),
        ),
      );
    }

    if (!locator.isRegistered<AuditRemoteWalletManifestUsecase>()) {
      locator.registerFactory<AuditRemoteWalletManifestUsecase>(
        () => AuditRemoteWalletManifestUsecase(
          fetchRemoteManifest: locator<FetchRemoteWalletManifestUsecase>(),
          buildLocalSnapshot: locator<BuildWalletManifestSnapshotUsecase>(),
          deriveRootKey: locator<DeriveWalletManifestRootKeyUsecase>(),
        ),
      );
    }

    if (!locator.isRegistered<GetWalletManifestPublicKeyUsecase>()) {
      locator.registerFactory<GetWalletManifestPublicKeyUsecase>(
        () => GetWalletManifestPublicKeyUsecase(
          deriveHandle: locator<DeriveWalletManifestNostrHandleUsecase>(),
        ),
      );
    }

    if (!locator.isRegistered<SaveWalletManifestPayloadUsecase>()) {
      locator.registerFactory<SaveWalletManifestPayloadUsecase>(
        () => SaveWalletManifestPayloadUsecase(
          fileSaver: locator<WalletManifestFileSaver>(),
        ),
      );
    }

    if (!locator.isRegistered<CreateManualBip85WalletsUsecase>()) {
      locator.registerFactory<CreateManualBip85WalletsUsecase>(
        () => CreateManualBip85WalletsUsecase(
          deriveRootKey: locator<DeriveWalletManifestRootKeyUsecase>(),
          fetchOrigins: locator<FetchWalletManifestOriginsUsecase>(),
          restoreSnapshot: locator<RestoreWalletManifestSnapshotUsecase>(),
          publishLocalManifest: locator<PublishLocalWalletManifestUsecase>(),
          settingsRepository: locator<settings.SettingsRepository>(),
          fetchAllBip85Derivations: locator<FetchAllBip85DerivationsUsecase>(),
          walletLabelReservationPolicy: locator<WalletLabelReservationPolicy>(),
        ),
      );
    }

    if (!locator.isRegistered<WalletManifestFacade>()) {
      locator.registerFactory<WalletManifestFacade>(
        () => WalletManifestFacade(
          recordOrigin: locator<RecordWalletManifestOriginUsecase>(),
          deleteOrigin: locator<DeleteWalletManifestOriginUsecase>(),
          fetchOrigins: locator<FetchWalletManifestOriginsUsecase>(),
          publishLocalManifest: locator<PublishLocalWalletManifestUsecase>(),
          startRestoreAfterSeedRecovery:
              locator<StartWalletManifestRestoreAfterSeedRecoveryUsecase>()
                  .execute,
          createManualBip85Wallets: locator<CreateManualBip85WalletsUsecase>(),
        ),
      );
    }

    if (!locator.isRegistered<WalletManifestSettingsCubit>()) {
      locator.registerFactory<WalletManifestSettingsCubit>(
        () => WalletManifestSettingsCubit(
          getPublicKey: locator<GetWalletManifestPublicKeyUsecase>(),
          checkRemoteManifest: locator<CheckRemoteWalletManifestUsecase>(),
          publishLocalManifest: locator<PublishLocalWalletManifestUsecase>(),
          restoreRemoteManifest: locator<RestoreRemoteWalletManifestUsecase>(),
          saveWalletManifestPayload:
              locator<SaveWalletManifestPayloadUsecase>(),
          auditRemoteWalletManifest:
              locator<AuditRemoteWalletManifestUsecase>(),
        ),
      );
    }
  }
}

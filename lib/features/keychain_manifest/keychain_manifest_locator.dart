import 'package:bb_mobile/core/nostr/nostr_key_materialization_recorder.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/drift_keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/data/keychain_manifest_backup_wallet_adapter.dart';
import 'package:bb_mobile/features/keychain_manifest/data/keychain_manifest_nostr_key_recorder.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/create_keychain_manifest_nostr_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/get_keychain_manifest_nostr_keys_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/get_default_wallet_nostr_keys_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/merge_keychain_manifest_file_payloads_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/get_keychain_manifest_reservation_wallet_ids_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_nostr_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/reveal_keychain_manifest_nostr_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/update_keychain_manifest_nostr_key_purpose_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:get_it/get_it.dart';

class KeychainManifestLocator {
  static void setup(GetIt locator) {
    locator.registerLazySingleton<KeychainManifestEntryRepository>(
      () => DriftKeychainManifestEntryRepository(
        database: locator<SqliteDatabase>(),
      ),
    );
    locator.registerLazySingleton<KeychainManifestBackupWalletPort>(
      () => KeychainManifestBackupWalletAdapter(
        getSettings: locator<GetSettingsUsecase>(),
        wallets: locator<WalletRepository>(),
        seeds: locator<SeedRepository>(),
      ),
    );
    locator.registerFactory<RecordKeychainManifestEntryUsecase>(
      () => RecordKeychainManifestEntryUsecase(
        repository: locator<KeychainManifestEntryRepository>(),
        bip85Registry: locator<Bip85RegistryFacade>(),
        clock: locator<Clock>(),
      ),
    );
    locator.registerFactory<RecordKeychainManifestNostrKeyUsecase>(
      () => RecordKeychainManifestNostrKeyUsecase(
        repository: locator<KeychainManifestEntryRepository>(),
        registry: locator<Bip85RegistryFacade>(),
        clock: locator<Clock>(),
      ),
    );
    locator.registerFactory<CreateKeychainManifestNostrKeyUsecase>(
      () => CreateKeychainManifestNostrKeyUsecase(
        wallet: locator<KeychainManifestBackupWalletPort>(),
        repository: locator<KeychainManifestEntryRepository>(),
        record: locator<RecordKeychainManifestNostrKeyUsecase>(),
        registry: locator<Bip85RegistryFacade>(),
        clock: locator<Clock>(),
      ),
    );
    locator.registerFactory<GetKeychainManifestNostrKeysUsecase>(
      () => GetKeychainManifestNostrKeysUsecase(
        repository: locator<KeychainManifestEntryRepository>(),
      ),
    );
    locator.registerFactory<GetDefaultWalletNostrKeysUsecase>(
      () => GetDefaultWalletNostrKeysUsecase(
        wallet: locator<KeychainManifestBackupWalletPort>(),
        getKeys: locator<GetKeychainManifestNostrKeysUsecase>(),
        registry: locator<Bip85RegistryFacade>(),
      ),
    );
    locator.registerFactory<UpdateKeychainManifestNostrKeyPurposeUsecase>(
      () => UpdateKeychainManifestNostrKeyPurposeUsecase(
        repository: locator<KeychainManifestEntryRepository>(),
        registry: locator<Bip85RegistryFacade>(),
        clock: locator<Clock>(),
      ),
    );
    locator.registerFactory<RevealKeychainManifestNostrKeyUsecase>(
      () => RevealKeychainManifestNostrKeyUsecase(
        wallet: locator<KeychainManifestBackupWalletPort>(),
      ),
    );
    locator.registerFactory<NostrKeysCubit>(
      () => NostrKeysCubit(locator<KeychainManifestFacade>()),
    );
    locator.registerFactory<GetKeychainManifestReservationWalletIdsUsecase>(
      () => GetKeychainManifestReservationWalletIdsUsecase(
        repository: locator<KeychainManifestEntryRepository>(),
      ),
    );
    locator.registerFactory<BuildKeychainManifestFileUsecase>(
      () => BuildKeychainManifestFileUsecase(
        repository: locator<KeychainManifestEntryRepository>(),
        registry: locator<Bip85RegistryFacade>(),
        clock: locator<Clock>(),
      ),
    );
    locator.registerFactory<ParseKeychainManifestFileUsecase>(
      () => ParseKeychainManifestFileUsecase(
        codec: const KeychainManifestFileCodec(),
        bip85Registry: locator<Bip85RegistryFacade>(),
      ),
    );
    locator.registerFactory<MergeKeychainManifestFilePayloadsUsecase>(
      () => MergeKeychainManifestFilePayloadsUsecase(
        codec: const KeychainManifestFileCodec(),
        parseManifest: locator<ParseKeychainManifestFileUsecase>(),
      ),
    );
    locator.registerLazySingleton<KeychainManifestFacade>(
      () => KeychainManifestFacade(
        recordEntry: locator<RecordKeychainManifestEntryUsecase>(),
        recordNostrKey: locator<RecordKeychainManifestNostrKeyUsecase>(),
        getNostrKeys: locator<GetKeychainManifestNostrKeysUsecase>(),
        getDefaultNostrKeys: locator<GetDefaultWalletNostrKeysUsecase>(),
        updateNostrKeyPurpose:
            locator<UpdateKeychainManifestNostrKeyPurposeUsecase>(),
        buildManifestFile: locator<BuildKeychainManifestFileUsecase>(),
        mergeManifestFiles: locator<MergeKeychainManifestFilePayloadsUsecase>(),
        parseManifestFile: locator<ParseKeychainManifestFileUsecase>(),
        reservationWalletIds:
            locator<GetKeychainManifestReservationWalletIdsUsecase>(),
        createNostrKey: locator<CreateKeychainManifestNostrKeyUsecase>(),
        revealNostrKey: locator<RevealKeychainManifestNostrKeyUsecase>(),
      ),
      dispose: (facade) => facade.close(),
    );
    locator.registerLazySingleton<NostrKeyMaterializationRecorder>(
      () => KeychainManifestNostrKeyRecorder(
        registry: locator<Bip85RegistryFacade>(),
        record: locator<KeychainManifestFacade>().recordNostrKey,
      ),
    );
  }
}

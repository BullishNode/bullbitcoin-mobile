import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/drift_keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/data/recoverbull_keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/data/websocket_keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_nostr_encrypted_content_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_signed_keychain_manifest_nostr_event_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/publish_keychain_manifest_nostr_event_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:get_it/get_it.dart';

class KeychainManifestLocator {
  static void setup(GetIt locator) {
    locator.registerLazySingleton<KeychainManifestEntryRepository>(
      () => DriftKeychainManifestEntryRepository(
        database: locator<SqliteDatabase>(),
      ),
    );
    locator.registerLazySingleton<KeychainManifestNostrEncryptionRepository>(
      () => const RecoverBullKeychainManifestNostrEncryptionRepository(),
    );
    locator.registerLazySingleton<KeychainManifestNostrRelayRepository>(
      () => const WebSocketKeychainManifestNostrRelayRepository(),
    );
    locator.registerFactory<RecordKeychainManifestEntryUsecase>(
      () => RecordKeychainManifestEntryUsecase(
        repository: locator<KeychainManifestEntryRepository>(),
        bip85Registry: locator<Bip85RegistryFacade>(),
        clock: locator<Clock>(),
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
    locator.registerFactory<BuildKeychainManifestNostrEncryptedContentUsecase>(
      () => BuildKeychainManifestNostrEncryptedContentUsecase(
        buildManifestFile: locator<BuildKeychainManifestFileUsecase>(),
        encryptionRepository:
            locator<KeychainManifestNostrEncryptionRepository>(),
      ),
    );
    locator.registerFactory<BuildSignedKeychainManifestNostrEventUsecase>(
      () => BuildSignedKeychainManifestNostrEventUsecase(
        buildEncryptedContent:
            locator<BuildKeychainManifestNostrEncryptedContentUsecase>(),
        nostrIdentity: locator<NostrIdentityFacade>(),
      ),
    );
    locator.registerFactory<PublishKeychainManifestNostrEventUsecase>(
      () => PublishKeychainManifestNostrEventUsecase(
        buildSignedEvent:
            locator<BuildSignedKeychainManifestNostrEventUsecase>(),
        relayRepository: locator<KeychainManifestNostrRelayRepository>(),
      ),
    );
    locator.registerFactory<KeychainManifestFacade>(
      () => KeychainManifestFacade(
        recordEntry: locator<RecordKeychainManifestEntryUsecase>(),
        buildManifestFile: locator<BuildKeychainManifestFileUsecase>(),
        parseManifestFile: locator<ParseKeychainManifestFileUsecase>(),
        publishNostrEvent: locator<PublishKeychainManifestNostrEventUsecase>(),
      ),
    );
  }
}

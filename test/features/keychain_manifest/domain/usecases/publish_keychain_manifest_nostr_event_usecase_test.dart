import 'dart:typed_data';

import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/recoverbull_keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_nostr_encrypted_content_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_signed_keychain_manifest_nostr_event_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/publish_keychain_manifest_nostr_event_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _InMemoryKeychainManifestStore store;
  late _FakeKeychainManifestNostrRelayRepository relayRepository;
  late PublishKeychainManifestNostrEventUsecase usecase;

  setUp(() {
    store = _InMemoryKeychainManifestStore();
    relayRepository = _FakeKeychainManifestNostrRelayRepository();
    usecase = PublishKeychainManifestNostrEventUsecase(
      buildSignedEvent: BuildSignedKeychainManifestNostrEventUsecase(
        buildEncryptedContent:
            BuildKeychainManifestNostrEncryptedContentUsecase(
              buildManifestFile: BuildKeychainManifestFileUsecase(
                repository: store,
                registry: const Bip85RegistryFacade(),
              ),
              encryptionRepository:
                  const RecoverBullKeychainManifestNostrEncryptionRepository(),
            ),
        nostrIdentity: _FakeNostrIdentityFacade(),
      ),
      relayRepository: relayRepository,
    );
  });

  test('builds, signs, and publishes to configured relays', () async {
    await _recordInventory(store);

    await usecase.execute(
      parentFingerprint: _parentFingerprint,
      xprvBase58: _xprv,
      relayUrls: const ['wss://relay.example', 'wss://relay.example'],
      now: DateTime.fromMillisecondsSinceEpoch(20000, isUtc: true),
    );

    final published = relayRepository.published.single;
    expect(published.relayUrls.map((relayUrl) => relayUrl.value), [
      'wss://relay.example',
      'wss://relay.example',
    ]);
    expect(published.event.authorPublicKeyHex, _authorPublicKeyHex);
    expect(published.event.signatureHex, _signatureHex);
  });

  test('requires at least one configured relay', () async {
    await _recordInventory(store);

    await expectLater(
      usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const [],
      ),
      throwsA(
        isA<KeychainManifestException>().having(
          (error) => error.type,
          'type',
          KeychainManifestExceptionType.invalidEntry,
        ),
      ),
    );
  });

  test('does not publish empty remote manifests', () async {
    await expectLater(
      usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const ['wss://relay.example'],
      ),
      throwsA(
        isA<KeychainManifestException>().having(
          (error) => error.type,
          'type',
          KeychainManifestExceptionType.emptyInventory,
        ),
      ),
    );
    expect(relayRepository.published, isEmpty);
  });

  test('rejects plaintext relay URLs', () async {
    await _recordInventory(store);

    await expectLater(
      usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const ['ws://relay.example'],
      ),
      throwsA(
        isA<KeychainManifestException>().having(
          (error) => error.type,
          'type',
          KeychainManifestExceptionType.invalidEntry,
        ),
      ),
    );
  });

  test('rejects relay results that no relay accepted', () async {
    await _recordInventory(store);
    relayRepository.acceptedByAnyRelay = false;

    await expectLater(
      usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const ['wss://relay.example'],
      ),
      throwsA(
        isA<KeychainManifestNostrPublishException>().having(
          (error) => error.message,
          'message',
          'failed to publish keychain manifest Nostr event',
        ),
      ),
    );
  });

  test('maps relay failures into sanitized publish errors', () async {
    await _recordInventory(store);
    relayRepository.error = StateError('relay-secret-leak');

    await expectLater(
      usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const ['wss://relay.example'],
      ),
      throwsA(
        isA<KeychainManifestNostrPublishException>()
            .having(
              (error) => error.message,
              'message',
              'failed to publish keychain manifest Nostr event',
            )
            .having(
              (error) => error.toString(),
              'string',
              isNot(contains('relay-secret-leak')),
            ),
      ),
    );
  });
}

Future<void> _recordInventory(_InMemoryKeychainManifestStore store) async {
  await RecordKeychainManifestEntryUsecase(
    repository: store,
    bip85Registry: const Bip85RegistryFacade(),
  ).execute(
    KeychainManifestReservedDerivationRequest(
      reservationId: 'btcpay_wallet_seed',
      parentFingerprint: _parentFingerprint,
      derivationPath: "39'/0'/12'/100'",
      materializations: [
        KeychainManifestWalletMaterializationRequest(
          walletId: 'btc-wallet',
          childSeedFingerprint: '0123abcd',
          network: Network.bitcoinMainnet,
          scriptType: ScriptType.bip84,
        ),
      ],
    ),
    now: DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true),
  );
}

final _xprv = Bip32Derivation.getXprvFromSeed(
  Uint8List.fromList(
    Mnemonic.fromWords(
      words: List.generate(11, (index) => 'zoo') + ['wrong'],
    ).seed,
  ),
  Network.bitcoinMainnet,
);

final _parentFingerprint = bip32.Bip32Keys.fromBase58(_xprv).fingerprintHex;

const _authorPublicKeyHex =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _signatureHex =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _FakeNostrIdentityFacade implements NostrIdentityFacade {
  @override
  String deriveWalletManifestPublicKeyFromXprv(String xprvBase58) {
    return _authorPublicKeyHex;
  }

  @override
  String signWalletManifestHashFromXprv({
    required String xprvBase58,
    required String messageHashHex,
  }) {
    return _signatureHex;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeKeychainManifestNostrRelayRepository
    implements KeychainManifestNostrRelayRepository {
  final published = <_PublishedEvent>[];
  Object? error;
  bool acceptedByAnyRelay = true;

  @override
  Future<KeychainManifestNostrFetchResult> fetchManifestEvents({
    required String authorPublicKeyHex,
    required List<KeychainManifestNostrRelayUrl> relayUrls,
  }) async {
    return KeychainManifestNostrFetchResult(
      contactedAnyRelay: false,
      events: [],
    );
  }

  @override
  Future<bool> publish({
    required KeychainManifestNostrSignedEvent event,
    required List<KeychainManifestNostrRelayUrl> relayUrls,
  }) async {
    final error = this.error;
    if (error != null) throw error;
    published.add(_PublishedEvent(event, relayUrls));
    return acceptedByAnyRelay;
  }
}

class _PublishedEvent {
  final KeychainManifestNostrSignedEvent event;
  final List<KeychainManifestNostrRelayUrl> relayUrls;

  const _PublishedEvent(this.event, this.relayUrls);
}

class _InMemoryKeychainManifestStore
    implements KeychainManifestEntryRepository {
  final entries = <KeychainManifestEntry>[];
  final records = <KeychainManifestWalletMaterializationRecord>[];

  @override
  Future<List<KeychainManifestWalletMaterializationRecord>>
  fetchWalletMaterializationRecordsByParentFingerprint(
    String parentFingerprint,
  ) async {
    return records
        .where((record) => record.entry.parentFingerprint == parentFingerprint)
        .toList(growable: false);
  }

  @override
  Future<void> insertWalletMaterializationRecords(
    List<KeychainManifestWalletMaterializationRecord> records,
  ) async {
    final nextEntries = [...entries];
    final nextRecords = [...this.records];
    for (final record in records) {
      final existingRecord = nextRecords
          .cast<KeychainManifestWalletMaterializationRecord?>()
          .firstWhere(
            (stored) => stored!.walletId == record.walletId,
            orElse: () => null,
          );
      if (existingRecord != null) {
        if (existingRecord.entry.entryId == record.entry.entryId &&
            existingRecord.walletMaterialization ==
                record.walletMaterialization) {
          continue;
        }
        throw KeychainManifestEntryConflictException('conflict');
      }
      if (!nextEntries.any((entry) => entry.entryId == record.entry.entryId)) {
        nextEntries.add(record.entry);
      }
      nextRecords.add(record);
    }
    entries
      ..clear()
      ..addAll(nextEntries);
    this.records
      ..clear()
      ..addAll(nextRecords);
  }
}

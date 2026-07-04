import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_encryption_datasource.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/data/recoverbull_keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/derive_keychain_manifest_nostr_encryption_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/fetch_keychain_manifest_nostr_import_plan_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeRelayRepository relayRepository;
  late FetchKeychainManifestNostrImportPlanUsecase usecase;

  setUp(() {
    relayRepository = _FakeRelayRepository();
    usecase = FetchKeychainManifestNostrImportPlanUsecase(
      relayRepository: relayRepository,
      encryptionRepository:
          const RecoverBullKeychainManifestNostrEncryptionRepository(),
      parseManifestFile: const ParseKeychainManifestFileUsecase(
        codec: KeychainManifestFileCodec(),
        bip85Registry: Bip85RegistryFacade(),
      ),
      nostrIdentity: _FakeNostrIdentityFacade(),
    );
  });

  test('returns relaysUnavailable when no relay answers', () async {
    relayRepository.contactedAnyRelay = false;

    final result = await usecase.execute(
      parentFingerprint: _parentFingerprint,
      xprvBase58: _xprv,
      relayUrls: const ['wss://relay.example'],
    );

    expect(result.status, KeychainManifestNostrImportStatus.relaysUnavailable);
  });

  test('returns noManifestFound when relays answer without events', () async {
    final result = await usecase.execute(
      parentFingerprint: _parentFingerprint,
      xprvBase58: _xprv,
      relayUrls: const ['wss://relay.example'],
    );

    expect(result.status, KeychainManifestNostrImportStatus.noManifestFound);
  });

  test(
    'returns latestRecoverable for the newest decryptable manifest',
    () async {
      relayRepository.events = [
        _event(createdAt: 20, walletId: 'btc-wallet-latest'),
      ];

      final result = await usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const ['wss://relay.example'],
      );

      expect(
        result.status,
        KeychainManifestNostrImportStatus.latestRecoverable,
      );
      expect(
        result.importPlan?.walletMaterializations.single.walletId,
        'btc-wallet-latest',
      );
    },
  );

  test(
    'returns explicit older outcome when newest cannot be recovered',
    () async {
      relayRepository.events = [
        _invalidEvent(createdAt: 30),
        _event(createdAt: 20, walletId: 'btc-wallet-older'),
      ];

      final result = await usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const ['wss://relay.example'],
      );

      expect(
        result.status,
        KeychainManifestNostrImportStatus.newestFailedOlderRecoverable,
      );
      expect(result.newestEventCreatedAt, 30);
      expect(result.selectedEventCreatedAt, 20);
      expect(
        result.importPlan?.walletMaterializations.single.walletId,
        'btc-wallet-older',
      );
    },
  );

  test(
    'KC1: an empty newer manifest never masks a populated older one',
    () async {
      relayRepository.events = [
        _emptyEvent(createdAt: 30),
        _event(createdAt: 20, walletId: 'btc-wallet-populated'),
      ];

      final result = await usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const ['wss://relay.example'],
      );

      // The empty newest is non-recoverable and skipped - it must NOT raise a
      // "newest failed" alarm; the populated older is the latest recoverable.
      expect(
        result.status,
        KeychainManifestNostrImportStatus.latestRecoverable,
      );
      expect(
        result.importPlan?.walletMaterializations.single.walletId,
        'btc-wallet-populated',
      );
    },
  );

  test(
    'KC1: selection uses authenticated inventoryUpdatedAt, not the clock',
    () async {
      // The stale-clock event is newest by createdAt but its manifest is older by
      // inventoryUpdatedAt; the populated event with the newer inventory wins.
      relayRepository.events = [
        _event(
          createdAt: 99,
          walletId: 'btc-wallet-stale',
          inventoryUpdatedAt: 5,
        ),
        _event(
          createdAt: 20,
          walletId: 'btc-wallet-fresh',
          inventoryUpdatedAt: 50,
        ),
      ];

      final result = await usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const ['wss://relay.example'],
      );

      expect(
        result.status,
        KeychainManifestNostrImportStatus.latestRecoverable,
      );
      expect(
        result.importPlan?.walletMaterializations.single.walletId,
        'btc-wallet-fresh',
      );
    },
  );

  test('KC1: equal inventory falls back to the createdAt tiebreak', () async {
    relayRepository.events = [
      _event(
        createdAt: 20,
        walletId: 'btc-wallet-older',
        inventoryUpdatedAt: 10,
      ),
      _event(
        createdAt: 40,
        walletId: 'btc-wallet-newer',
        inventoryUpdatedAt: 10,
      ),
    ];

    final result = await usecase.execute(
      parentFingerprint: _parentFingerprint,
      xprvBase58: _xprv,
      relayUrls: const ['wss://relay.example'],
    );

    expect(result.status, KeychainManifestNostrImportStatus.latestRecoverable);
    expect(
      result.importPlan?.walletMaterializations.single.walletId,
      'btc-wallet-newer',
    );
  });

  test('KC2b: a newer inner-version manifest reports update-the-app', () async {
    relayRepository.events = [_unsupportedVersionEvent(createdAt: 30)];

    final result = await usecase.execute(
      parentFingerprint: _parentFingerprint,
      xprvBase58: _xprv,
      relayUrls: const ['wss://relay.example'],
    );

    expect(
      result.status,
      KeychainManifestNostrImportStatus.unsupportedNewerManifest,
    );
  });

  test(
    'KC2b: an authentic unreadable newest with no fallback is not "no backup"',
    () async {
      relayRepository.events = [_invalidEvent(createdAt: 30)];

      final result = await usecase.execute(
        parentFingerprint: _parentFingerprint,
        xprvBase58: _xprv,
        relayUrls: const ['wss://relay.example'],
      );

      expect(
        result.status,
        KeychainManifestNostrImportStatus.unsupportedNewerManifest,
      );
    },
  );
}

KeychainManifestNostrEncryptionKey get _encryptionKey =>
    const DeriveKeychainManifestNostrEncryptionKeyUsecase().execute(
      xprvBase58: _xprv,
      expectedParentFingerprint: _parentFingerprint,
    );

KeychainManifestNostrSignedEvent _eventWithContent({
  required int createdAt,
  required KeychainManifestNostrCiphertext content,
}) {
  return KeychainManifestNostrSignedEvent.fromDraft(
    draft: KeychainManifestNostrEventDraft(
      authorPublicKeyHex: _authorPublicKeyHex,
      encryptedContent: content,
      createdAt: createdAt,
    ),
    signatureHex: _signatureHex,
  );
}

KeychainManifestNostrSignedEvent _event({
  required int createdAt,
  required String walletId,
  int inventoryUpdatedAt = 10,
}) {
  final content = const RecoverBullKeychainManifestNostrEncryptionRepository()
      .encryptSnapshot(
        snapshot: KeychainManifestNostrSnapshot(
          manifestFile: _manifestFile(
            walletId: walletId,
            inventoryUpdatedAt: inventoryUpdatedAt,
          ),
        ),
        key: _encryptionKey,
      );
  return _eventWithContent(createdAt: createdAt, content: content);
}

/// An authentic event whose (populated) manifest is empty of entries -
/// decryptable but non-recoverable (must never trigger a "newest failed" alarm).
KeychainManifestNostrSignedEvent _emptyEvent({required int createdAt}) {
  final content = const RecoverBullKeychainManifestNostrEncryptionRepository()
      .encryptSnapshot(
        snapshot: KeychainManifestNostrSnapshot(manifestFile: _emptyManifest()),
        key: _encryptionKey,
      );
  return _eventWithContent(createdAt: createdAt, content: content);
}

/// An authentic event whose content is a well-shaped ciphertext that does not
/// decrypt under our key (wrong/newer format) - authentic-but-unreadable.
KeychainManifestNostrSignedEvent _invalidEvent({required int createdAt}) {
  final content = KeychainManifestNostrCiphertext(base64.encode(Uint8List(64)));
  return _eventWithContent(createdAt: createdAt, content: content);
}

/// An authentic event that decrypts cleanly but whose inner manifest file
/// declares a newer format version than this app understands (KC2b(a)).
KeychainManifestNostrSignedEvent _unsupportedVersionEvent({
  required int createdAt,
}) {
  const snapshotCodec = KeychainManifestNostrSnapshotCodec();
  final plaintext = snapshotCodec
      .encode(
        KeychainManifestNostrSnapshot(
          manifestFile: _manifestFile(walletId: 'btc-wallet'),
        ),
      )
      .replaceFirst(
        '"manifestFile":{"version":1',
        '"manifestFile":{"version":2',
      );
  final blob = const KeychainManifestNostrEncryptionDatasource().encrypt(
    plaintext: plaintext,
    key: _encryptionKey,
  );
  return _eventWithContent(
    createdAt: createdAt,
    content: KeychainManifestNostrCiphertext(blob),
  );
}

KeychainManifestFile _emptyManifest() {
  return KeychainManifestFile(
    parentFingerprint: _parentFingerprint,
    generatedAt: 20,
    entries: const [],
  );
}

KeychainManifestFile _manifestFile({
  required String walletId,
  int inventoryUpdatedAt = 10,
}) {
  final entryId = "$_parentFingerprint:39'/0'/12'/100'";
  return KeychainManifestFile(
    parentFingerprint: _parentFingerprint,
    generatedAt: 20,
    entries: [
      KeychainManifestFileEntry(
        parentFingerprint: _parentFingerprint,
        bip85DerivationPath: "39'/0'/12'/100'",
        reservationId: 'btcpay_wallet_seed',
        entryType: 'walletSeed',
        ownerFeature: 'btcpay',
        bip85Application: 39,
        bip85Index: 100,
        createdAt: 10,
        updatedAt: inventoryUpdatedAt,
        materializations: [
          KeychainManifestFileWalletMaterialization(
            walletId: walletId,
            entryId: entryId,
            childSeedFingerprint: '0123abcd',
            network: Network.bitcoinMainnet.name,
            scriptType: ScriptType.bip84.name,
            createdAt: 10,
            updatedAt: inventoryUpdatedAt,
          ),
        ],
      ),
    ],
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRelayRepository implements KeychainManifestNostrRelayRepository {
  bool contactedAnyRelay = true;
  List<KeychainManifestNostrSignedEvent> events = [];

  @override
  Future<KeychainManifestNostrFetchResult> fetchManifestEvents({
    required String authorPublicKeyHex,
    required List<KeychainManifestNostrRelayUrl> relayUrls,
  }) async {
    return KeychainManifestNostrFetchResult(
      contactedAnyRelay: contactedAnyRelay,
      events: events,
    );
  }

  @override
  Future<bool> publish({
    required KeychainManifestNostrSignedEvent event,
    required List<KeychainManifestNostrRelayUrl> relayUrls,
  }) async {
    throw UnimplementedError();
  }
}

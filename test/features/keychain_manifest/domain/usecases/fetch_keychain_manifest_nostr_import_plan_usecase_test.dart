import 'dart:typed_data';

import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/data/recoverbull_keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
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
}

KeychainManifestNostrSignedEvent _event({
  required int createdAt,
  required String walletId,
}) {
  final encryptionKey = const DeriveKeychainManifestNostrEncryptionKeyUsecase()
      .execute(
        xprvBase58: _xprv,
        expectedParentFingerprint: _parentFingerprint,
      );
  final encryptedContent =
      const RecoverBullKeychainManifestNostrEncryptionRepository()
          .encryptSnapshot(
            snapshot: KeychainManifestNostrSnapshot(
              manifestFile: _manifestFile(walletId: walletId),
            ),
            key: encryptionKey,
          );
  return KeychainManifestNostrSignedEvent.fromDraft(
    draft: KeychainManifestNostrEventDraft(
      authorPublicKeyHex: _authorPublicKeyHex,
      encryptedContent: encryptedContent,
      createdAt: createdAt,
    ),
    signatureHex: _signatureHex,
  );
}

KeychainManifestNostrSignedEvent _invalidEvent({required int createdAt}) {
  return KeychainManifestNostrSignedEvent.fromDraft(
    draft: KeychainManifestNostrEventDraft(
      authorPublicKeyHex: _authorPublicKeyHex,
      encryptedContent: '{"not":"decryptable"}',
      createdAt: createdAt,
    ),
    signatureHex: _signatureHex,
  );
}

KeychainManifestFile _manifestFile({required String walletId}) {
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
        updatedAt: 10,
        materializations: [
          KeychainManifestFileWalletMaterialization(
            walletId: walletId,
            entryId: entryId,
            childSeedFingerprint: '0123abcd',
            network: Network.bitcoinMainnet.name,
            scriptType: ScriptType.bip84.name,
            createdAt: 10,
            updatedAt: 10,
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

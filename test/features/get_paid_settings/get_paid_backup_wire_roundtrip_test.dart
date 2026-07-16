import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/nostr/nostr_relay_transport.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/drift_keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/data/recoverbull_keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/data/websocket_keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_nostr_encrypted_content_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_signed_keychain_manifest_nostr_event_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/fetch_keychain_manifest_nostr_import_plan_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/publish_keychain_manifest_nostr_event_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/core/utils/uint_8_list_x.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/fake_nostr_relay.dart';
import '../../../integration_test/support/get_paid_fixtures.dart';

// SPEC-RT-01 / WIRE-01 runs the real keychain-manifest encrypt/sign/codec path against the injectable relay transport's `connect` fake, with no app pump.
//
// The full-app L1 variant (integration_test/get_paid_backup_roundtrip_test.dart)
// is authored-but-CI-only — the live-startup timers make an app-process pump
// non-deterministic, so this domain-layer test is the money-path gate. The
// consent gate, republish suppression, and posture re-application are proven in
// the L0 suites (publish-usecase gating matrix, cubit T-NOCLOBBER, restore
// usecase posture).
void main() {
  const relayUrls = ['wss://relay.example.test'];

  late SqliteDatabase database;
  late FakeNostrRelay relay;
  late KeychainManifestFacade facade;
  late String xprv;
  // The manifest parent fingerprint must equal the publishing xprv's own
  // fingerprint (the facade enforces this), so derive both from the fixture
  // seed's master key.
  late String parentFingerprint;

  KeychainManifestWalletMaterializationRequest materialization({
    String walletId = 'btcpay-btc-wallet',
    Network network = Network.bitcoinMainnet,
  }) {
    return KeychainManifestWalletMaterializationRequest(
      walletId: walletId,
      childSeedFingerprint: '0123abcd',
      network: network,
      scriptType: ScriptType.bip84,
    );
  }

  setUp(() {
    database = SqliteDatabase(NativeDatabase.memory());
    relay = FakeNostrRelay();

    final store = DriftKeychainManifestEntryRepository(database: database);
    const registry = Bip85RegistryFacade();
    const encryption = RecoverBullKeychainManifestNostrEncryptionRepository();
    const parse = ParseKeychainManifestFileUsecase(
      codec: KeychainManifestFileCodec(),
      bip85Registry: registry,
    );
    final nostrIdentity = NostrIdentityFacade(
      deriveHandle: const DeriveNostrIdentityHandleUsecase(registry: registry),
    );
    final relayRepository = WebSocketKeychainManifestNostrRelayRepository(
      transport: NostrRelayTransport(connect: relay.connect),
    );

    facade = KeychainManifestFacade(
      recordEntry: RecordKeychainManifestEntryUsecase(
        repository: store,
        bip85Registry: registry,
      ),
      buildManifestFile: BuildKeychainManifestFileUsecase(
        repository: store,
        registry: registry,
      ),
      parseManifestFile: parse,
      publishNostrEvent: PublishKeychainManifestNostrEventUsecase(
        buildSignedEvent: BuildSignedKeychainManifestNostrEventUsecase(
          buildEncryptedContent:
              BuildKeychainManifestNostrEncryptedContentUsecase(
                buildManifestFile: BuildKeychainManifestFileUsecase(
                  repository: store,
                  registry: registry,
                ),
                encryptionRepository: encryption,
              ),
          nostrIdentity: nostrIdentity,
        ),
        relayRepository: relayRepository,
      ),
      fetchNostrImportPlan: FetchKeychainManifestNostrImportPlanUsecase(
        relayRepository: relayRepository,
        encryptionRepository: encryption,
        parseManifestFile: parse,
        nostrIdentity: nostrIdentity,
      ),
    );

    final mnemonic = bip39.Mnemonic.fromWords(
      words: getPaidFixtureMnemonicWords,
      language: bip39.Language.english,
    );
    final seedBytes = Uint8List.fromList(mnemonic.seed);
    parentFingerprint = bip32.Bip32Keys.fromSeed(
      seedBytes,
    ).fingerprint.toHexString();
    xprv = Bip32Derivation.getXprvFromSeed(seedBytes, Network.bitcoinMainnet);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> recordBtcpayEntry() {
    return facade.recordReservedDerivation(
      KeychainManifestReservedDerivationRequest(
        reservationId: 'btcpay_wallet_seed',
        derivationPath: "39'/0'/12'/100'",
        parentFingerprint: parentFingerprint,
        materializations: [materialization()],
      ),
      now: DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true),
    );
  }

  test(
    'publishes an opaque NIP-33 blob with no cleartext markers (WIRE-01)',
    () async {
      await recordBtcpayEntry();

      await facade.publishEncryptedNostrSnapshot(
        parentFingerprint: parentFingerprint,
        xprvBase58: xprv,
        relayUrls: relayUrls,
      );

      expect(relay.capturedEventFrames, isNotEmpty);
      expect(relay.storedEventCount, 1);

      for (final frame in relay.capturedEventFrames) {
        final lower = frame.toLowerCase();
        expect(lower.contains('bullbitcoin'), isFalse);
        expect(lower.contains('recoverbull'), isFalse);
        expect(lower.contains('satoshiportal'), isFalse);

        final decoded = jsonDecode(frame) as List;
        expect(decoded[0], 'EVENT');
        final event = decoded[1] as Map<String, dynamic>;
        expect(event['kind'], 30078);
        final tags = (event['tags'] as List).cast<List<dynamic>>();
        expect(tags.any((t) => t[0] == 'd' && t[1] == 'manifest'), isTrue);
        final content = event['content'] as String;
        // Opaque: bare base64, not a cleartext JSON envelope.
        expect(content.startsWith('{'), isFalse);
        expect(() => base64.decode(content), returnsNormally);
      }
    },
  );

  test('a published snapshot round-trips through fetch under the same author '
      'key (SPEC-RT-01 / KC-4 obligation 4)', () async {
    await recordBtcpayEntry();
    await facade.publishEncryptedNostrSnapshot(
      parentFingerprint: parentFingerprint,
      xprvBase58: xprv,
      relayUrls: relayUrls,
    );

    // Fetch derives the author key from the SAME xprv (KC-4 ob.4) and decrypts.
    final result = await facade.fetchEncryptedNostrImportPlan(
      parentFingerprint: parentFingerprint,
      xprvBase58: xprv,
      relayUrls: relayUrls,
      acceptedThirdPartyRelayDisclosure: true,
    );

    final plan = result.importPlan;
    expect(plan, isNotNull);
    expect(
      plan!.entries.map((entry) => entry.reservationId),
      contains('btcpay_wallet_seed'),
    );
  });

  test(
    'a newer publish replaces the older event (NIP-33), no accumulation',
    () async {
      await recordBtcpayEntry();
      await facade.publishEncryptedNostrSnapshot(
        parentFingerprint: parentFingerprint,
        xprvBase58: xprv,
        relayUrls: relayUrls,
      );
      await facade.publishEncryptedNostrSnapshot(
        parentFingerprint: parentFingerprint,
        xprvBase58: xprv,
        relayUrls: relayUrls,
      );

      // Two publishes, but the relay holds a single replaceable event.
      expect(relay.storedEventCount, 1);
    },
  );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/backup/authenticated_backup_cipher.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/get_keychain_manifest_reservation_wallet_ids_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/merge_keychain_manifest_file_payloads_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_backup/data/models/wallet_backup_envelope_model.dart';
import 'package:bb_mobile/features/wallet_backup/data/recoverbull_wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_encryption.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_envelope.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/build_wallet_backup_envelope_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_encryption_key_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_signer_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/sync_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores the first unified manifest backup', () async {
    final remote = _FakeRemoteRepository(
      heads: [WalletBackupRemoteHead.absent(generation: 0, etag: null)],
    );
    final fixture = _Fixture(remote);

    final result = await fixture.sync.execute(
      parentFingerprint: fixture.parentFingerprint,
      xprvBase58: fixture.xprv,
    );

    expect(result, isA<Ok<WalletBackupSyncResult, WalletBackupFailure>>());
    expect(remote.fetchCalls, 1);
    expect(remote.storeCalls, 1);
    expect(
      remote.signers.first.publicKeyHex,
      fixture.identity.deriveWalletBackupPublicKeyFromXprv(fixture.xprv),
    );
    final stored = fixture.decrypt(remote.storedCiphertexts.single);
    expect(stored.manifest.parentFingerprint, fixture.parentFingerprint);
    expect(
      const KeychainManifestFileCodec()
          .decode(stored.manifest.payload)
          .entryCount,
      1,
    );
  });

  test(
    'stores a canonical empty manifest for a newly enabled wallet',
    () async {
      final remote = _FakeRemoteRepository(
        heads: [WalletBackupRemoteHead.absent(generation: 0, etag: null)],
      );
      final fixture = _Fixture(remote, emptyManifest: true);

      final result = await fixture.sync.execute(
        parentFingerprint: fixture.parentFingerprint,
        xprvBase58: fixture.xprv,
      );

      expect(result, isA<Ok<WalletBackupSyncResult, WalletBackupFailure>>());
      expect(remote.storeCalls, 1);
      final stored = fixture.decrypt(remote.storedCiphertexts.single);
      expect(
        const KeychainManifestFileCodec()
            .decode(stored.manifest.payload)
            .entries,
        isEmpty,
      );
    },
  );

  test(
    'returns the existing checkpoint when merged content is unchanged',
    () async {
      final remote = _FakeRemoteRepository(heads: const []);
      final fixture = _Fixture(remote);
      final localPayload = await fixture.keychainManifest
          .buildManifestFilePayload(
            fixture.parentFingerprint,
            now: DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true),
          );
      final remoteEnvelope = WalletBackupEnvelope(
        parentFingerprint: fixture.parentFingerprint,
        createdAt: 15,
        manifest: WalletBackupManifestSection(
          payload: localPayload.payload,
          parentFingerprint: fixture.parentFingerprint,
        ),
      );
      final ciphertext = fixture.encrypt(remoteEnvelope);
      remote.heads.add(
        WalletBackupRemoteHead.present(
          generation: 4,
          etag: '44' * 32,
          ciphertext: ciphertext,
          ciphertextSha256: _ciphertextHash(ciphertext),
          updatedAtSecs: 20,
        ),
      );

      final result = await fixture.sync.execute(
        parentFingerprint: fixture.parentFingerprint,
        xprvBase58: fixture.xprv,
      );

      final value =
          (result as Ok<WalletBackupSyncResult, WalletBackupFailure>).value;
      expect(value.checkpoint.generation, 4);
      expect(value.checkpoint.etag, '44' * 32);
      expect(
        value.contentHash,
        (fixture.encryption.contentHash(remoteEnvelope)
                as Ok<String, WalletBackupFailure>)
            .value,
      );
      expect(remote.storeCalls, 0);
    },
  );

  test('refetches and recomposes both manifests after one conflict', () async {
    final remote = _FakeRemoteRepository(heads: const []);
    final fixture = _Fixture(remote);
    final remoteEnvelope = fixture.remoteEnvelopeWithLightningAddress();
    final remoteCiphertext = fixture.encrypt(remoteEnvelope);
    remote
      ..heads.add(WalletBackupRemoteHead.absent(generation: 0, etag: null))
      ..heads.add(
        WalletBackupRemoteHead.present(
          generation: 1,
          etag: '11' * 32,
          ciphertext: remoteCiphertext,
          ciphertextSha256: _ciphertextHash(remoteCiphertext),
          updatedAtSecs: 20,
        ),
      )
      ..storeFailures.add(const WalletBackupHeadConflictFailure());

    final result = await fixture.sync.execute(
      parentFingerprint: fixture.parentFingerprint,
      xprvBase58: fixture.xprv,
    );

    expect(result, isA<Ok<WalletBackupSyncResult, WalletBackupFailure>>());
    expect(remote.fetchCalls, 2);
    expect(remote.storeCalls, 2);
    final stored = fixture.decrypt(remote.storedCiphertexts.last);
    final manifest = const KeychainManifestFileCodec().decode(
      stored.manifest.payload,
    );
    expect(manifest.entries.map((entry) => entry.bip85Index), [100, 101]);
  });

  test('returns a typed failure after a second head conflict', () async {
    final remote = _FakeRemoteRepository(
      heads: [
        WalletBackupRemoteHead.absent(generation: 0, etag: null),
        WalletBackupRemoteHead.absent(generation: 0, etag: null),
      ],
      storeFailures: [
        const WalletBackupHeadConflictFailure(),
        const WalletBackupHeadConflictFailure(),
      ],
    );
    final fixture = _Fixture(remote);

    final result = await fixture.sync.execute(
      parentFingerprint: fixture.parentFingerprint,
      xprvBase58: fixture.xprv,
    );

    expect(
      result,
      isA<Err<WalletBackupSyncResult, WalletBackupFailure>>().having(
        (result) => result.failure,
        'failure',
        isA<WalletBackupHeadConflictFailure>(),
      ),
    );
    expect(remote.fetchCalls, 2);
    expect(remote.storeCalls, 2);
  });

  test('does not overwrite malformed authenticated ciphertext', () async {
    final malformed = WalletBackupCiphertext(
      base64.encode(List<int>.filled(64, 7)),
    );
    final remote = _FakeRemoteRepository(
      heads: [
        WalletBackupRemoteHead.present(
          generation: 1,
          etag: '11' * 32,
          ciphertext: malformed,
          ciphertextSha256: _ciphertextHash(malformed),
          updatedAtSecs: 20,
        ),
      ],
    );
    final fixture = _Fixture(remote);

    final result = await fixture.sync.execute(
      parentFingerprint: fixture.parentFingerprint,
      xprvBase58: fixture.xprv,
    );

    expect(
      result,
      isA<Err<WalletBackupSyncResult, WalletBackupFailure>>().having(
        (result) => result.failure,
        'failure',
        isA<WalletBackupEncryptionFailure>(),
      ),
    );
    expect(remote.storeCalls, 0);
  });

  test(
    'does not overwrite an authenticated envelope with a newer section',
    () async {
      final remote = _FakeRemoteRepository(heads: const []);
      final fixture = _Fixture(remote);
      final local = await fixture.buildLocalEnvelope();
      final plaintext = const WalletBackupEnvelopeCodec()
          .encode(local)
          .replaceFirst(
            '"keychain_manifest":',
            '"future_section":{"version":1,"payload":{}},'
                '"keychain_manifest":',
          );
      final ciphertext = fixture.encryptRaw(plaintext);
      remote.heads.add(
        WalletBackupRemoteHead.present(
          generation: 1,
          etag: '11' * 32,
          ciphertext: ciphertext,
          ciphertextSha256: _ciphertextHash(ciphertext),
          updatedAtSecs: 20,
        ),
      );

      final result = await fixture.sync.execute(
        parentFingerprint: fixture.parentFingerprint,
        xprvBase58: fixture.xprv,
      );

      expect(
        result,
        isA<Err<WalletBackupSyncResult, WalletBackupFailure>>().having(
          (result) => result.failure,
          'failure',
          isA<WalletBackupUnsupportedSectionFailure>(),
        ),
      );
      expect(remote.storeCalls, 0);
    },
  );

  test(
    'does not overwrite authenticated non-canonical manifest fields',
    () async {
      final remote = _FakeRemoteRepository(heads: const []);
      final fixture = _Fixture(remote);
      final local = await fixture.buildLocalEnvelope();
      final plaintext = const WalletBackupEnvelopeCodec()
          .encode(local)
          .replaceFirst(
            '"generatedAt":30',
            '"futureField":true,"generatedAt":30',
          );
      final ciphertext = fixture.encryptRaw(plaintext);
      remote.heads.add(
        WalletBackupRemoteHead.present(
          generation: 1,
          etag: '11' * 32,
          ciphertext: ciphertext,
          ciphertextSha256: _ciphertextHash(ciphertext),
          updatedAtSecs: 20,
        ),
      );

      final result = await fixture.sync.execute(
        parentFingerprint: fixture.parentFingerprint,
        xprvBase58: fixture.xprv,
      );

      expect(
        result,
        isA<Err<WalletBackupSyncResult, WalletBackupFailure>>().having(
          (result) => result.failure,
          'failure',
          isA<WalletBackupInvalidEnvelopeFailure>(),
        ),
      );
      expect(remote.storeCalls, 0);
    },
  );

  test('propagates remote size failures without attempting a write', () async {
    final remote = _FakeRemoteRepository(
      heads: const [],
      fetchFailure: const WalletBackupTooLargeFailure(),
    );
    final fixture = _Fixture(remote);

    final result = await fixture.sync.execute(
      parentFingerprint: fixture.parentFingerprint,
      xprvBase58: fixture.xprv,
    );

    expect(
      result,
      isA<Err<WalletBackupSyncResult, WalletBackupFailure>>().having(
        (result) => result.failure,
        'failure',
        isA<WalletBackupTooLargeFailure>(),
      ),
    );
    expect(remote.storeCalls, 0);
  });
}

final class _Fixture {
  static const registry = Bip85RegistryFacade();
  static const codec = KeychainManifestFileCodec();
  static const parser = ParseKeychainManifestFileUsecase(
    codec: codec,
    bip85Registry: registry,
  );

  final _FakeRemoteRepository remote;
  final bool emptyManifest;
  final String xprv = _xprv();
  final RecoverBullWalletBackupEncryptionRepository encryption =
      const RecoverBullWalletBackupEncryptionRepository();
  late final String parentFingerprint = bip32.Bip32Keys.fromBase58(
    xprv,
  ).fingerprintHex;
  late final KeychainManifestFacade keychainManifest = _keychainManifest();
  late final NostrIdentityFacade identity = const NostrIdentityFacade(
    DeriveNostrIdentityHandleUsecase(registry),
  );
  late final SyncWalletBackupUsecase sync = SyncWalletBackupUsecase(
    buildEnvelope: BuildWalletBackupEnvelopeUsecase(
      keychainManifest,
      const _FixedClock(),
    ),
    deriveEncryptionKey: const DeriveWalletBackupEncryptionKeyUsecase(
      registry: registry,
    ),
    encryption: encryption,
    remote: remote,
    keychainManifest: keychainManifest,
    deriveSigner: DeriveWalletBackupSignerUsecase(identity),
  );

  _Fixture(this.remote, {this.emptyManifest = false});

  WalletBackupCiphertext encrypt(WalletBackupEnvelope envelope) {
    final result = encryption.encrypt(
      envelope: envelope,
      key: _encryptionKey(),
    );
    return (result as Ok<WalletBackupCiphertext, WalletBackupFailure>).value;
  }

  WalletBackupCiphertext encryptRaw(String plaintext) {
    final ciphertext = const RecoverBullAuthenticatedBackupCipher().encrypt(
      plaintext: plaintext,
      key: AuthenticatedBackupCipherKey(_encryptionKey().hex),
    );
    return WalletBackupCiphertext(ciphertext.value);
  }

  WalletBackupEnvelope decrypt(WalletBackupCiphertext ciphertext) {
    final result = encryption.decrypt(
      ciphertext: ciphertext,
      key: _encryptionKey(),
      expectedParentFingerprint: parentFingerprint,
    );
    return (result as Ok<WalletBackupEnvelope, WalletBackupFailure>).value;
  }

  Future<WalletBackupEnvelope> buildLocalEnvelope() async {
    final result = await BuildWalletBackupEnvelopeUsecase(
      keychainManifest,
      const _FixedClock(),
    ).execute(parentFingerprint: parentFingerprint);
    return (result as Ok<WalletBackupEnvelope, WalletBackupFailure>).value;
  }

  WalletBackupEnvelope remoteEnvelopeWithLightningAddress() {
    final file = KeychainManifestFile(
      parentFingerprint: parentFingerprint,
      generatedAt: 15,
      entries: [
        _fileEntry(
          parentFingerprint: parentFingerprint,
          index: 101,
          reservationId: 'lightning_address_wallet_seed',
          ownerFeature: 'lightningAddress',
          walletId: 'lightning-wallet',
        ),
      ],
    );
    return WalletBackupEnvelope(
      parentFingerprint: parentFingerprint,
      createdAt: 15,
      manifest: WalletBackupManifestSection(
        payload: codec.encode(file),
        parentFingerprint: parentFingerprint,
      ),
    );
  }

  KeychainManifestFacade _keychainManifest() {
    final store = _StaticManifestStore(
      emptyManifest
          ? const []
          : [
              KeychainManifestWalletMaterializationRecord(
                entry: KeychainManifestEntry(
                  parentFingerprint: parentFingerprint,
                  bip85DerivationPath: "39'/0'/12'/100'",
                  reservationId: 'btcpay_wallet_seed',
                  entryType: 'walletSeed',
                  ownerFeature: 'btcpay',
                  bip85Application: 39,
                  bip85Index: 100,
                  createdAt: 10,
                  updatedAt: 10,
                ),
                walletMaterialization: KeychainManifestWalletMaterialization(
                  walletId: 'btcpay-wallet',
                  entryId: "$parentFingerprint:39'/0'/12'/100'",
                  childSeedFingerprint: '0123abcd',
                  network: 'bitcoinMainnet',
                  scriptType: 'bip84',
                  createdAt: 10,
                  updatedAt: 10,
                ),
              ),
            ],
    );
    return KeychainManifestFacade(
      recordEntry: RecordKeychainManifestEntryUsecase(
        repository: store,
        bip85Registry: registry,
      ),
      buildManifestFile: BuildKeychainManifestFileUsecase(
        repository: store,
        registry: registry,
      ),
      mergeManifestFiles: const MergeKeychainManifestFilePayloadsUsecase(
        codec: codec,
        parseManifest: parser,
      ),
      parseManifestFile: parser,
      reservationWalletIds: GetKeychainManifestReservationWalletIdsUsecase(
        repository: store,
      ),
    );
  }

  WalletBackupEncryptionKey _encryptionKey() {
    final result = const DeriveWalletBackupEncryptionKeyUsecase(
      registry: registry,
    ).execute(xprvBase58: xprv, expectedParentFingerprint: parentFingerprint);
    return (result as Ok<WalletBackupEncryptionKey, WalletBackupFailure>).value;
  }
}

final class _FakeRemoteRepository implements WalletBackupRemoteRepository {
  final List<WalletBackupRemoteHead> heads;
  final List<WalletBackupFailure> storeFailures;
  final WalletBackupFailure? fetchFailure;
  final signers = <WalletBackupSigner>[];
  final storedCiphertexts = <WalletBackupCiphertext>[];
  int fetchCalls = 0;
  int storeCalls = 0;

  _FakeRemoteRepository({
    required List<WalletBackupRemoteHead> heads,
    List<WalletBackupFailure> storeFailures = const [],
    this.fetchFailure,
  }) : heads = [...heads],
       storeFailures = [...storeFailures];

  @override
  Future<Result<WalletBackupRemoteHead, WalletBackupFailure>> fetch(
    WalletBackupSigner signer,
  ) async {
    fetchCalls++;
    signers.add(signer);
    final failure = fetchFailure;
    if (failure != null) return Err(failure);
    return Ok(heads.removeAt(0));
  }

  @override
  Future<Result<WalletBackupRemoteCheckpoint, WalletBackupFailure>> store({
    required WalletBackupSigner signer,
    required WalletBackupRemoteHead current,
    required WalletBackupCiphertext ciphertext,
  }) async {
    storeCalls++;
    signers.add(signer);
    storedCiphertexts.add(ciphertext);
    if (storeFailures.isNotEmpty) return Err(storeFailures.removeAt(0));
    return Ok(
      WalletBackupRemoteCheckpoint(
        generation: current.generation + 1,
        etag: storeCalls.toString().padLeft(2, '0') * 32,
      ),
    );
  }

  @override
  Future<Result<WalletBackupRemoteCheckpoint?, WalletBackupFailure>> delete({
    required WalletBackupSigner signer,
    required WalletBackupRemoteHead current,
  }) async => const Ok(null);
}

final class _StaticManifestStore implements KeychainManifestEntryRepository {
  final List<KeychainManifestWalletMaterializationRecord> records;

  const _StaticManifestStore(this.records);

  @override
  Future<List<KeychainManifestNostrKeyRecord>>
  fetchNostrKeyRecordsByParentFingerprint(String parentFingerprint) async =>
      const [];

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
  ) async {}

  @override
  Future<void> insertNostrKeyRecords(
    List<KeychainManifestNostrKeyRecord> records,
  ) async {}

  @override
  Future<void> updateNostrKeyPurpose({
    required String parentFingerprint,
    required String entryId,
    required String purpose,
    required int updatedAt,
  }) async {}
}

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.fromMillisecondsSinceEpoch(30000, isUtc: true);
}

KeychainManifestFileEntry _fileEntry({
  required String parentFingerprint,
  required int index,
  required String reservationId,
  required String ownerFeature,
  required String walletId,
}) {
  final path = "39'/0'/12'/$index'";
  return KeychainManifestFileEntry(
    parentFingerprint: parentFingerprint,
    bip85DerivationPath: path,
    reservationId: reservationId,
    entryType: 'walletSeed',
    ownerFeature: ownerFeature,
    bip85Application: 39,
    bip85Index: index,
    createdAt: 10,
    updatedAt: 10,
    materializations: [
      KeychainManifestFileWalletMaterialization(
        walletId: walletId,
        entryId: '$parentFingerprint:$path',
        childSeedFingerprint: '89abcdef',
        network: 'bitcoinMainnet',
        scriptType: 'bip84',
        createdAt: 10,
        updatedAt: 10,
      ),
    ],
  );
}

String _ciphertextHash(WalletBackupCiphertext ciphertext) =>
    sha256.convert(base64.decode(ciphertext.value)).toString();

String _xprv() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about',
    bip39.Language.english,
  );
  return bip32.Bip32Keys.fromSeed(Uint8List.fromList(mnemonic.seed)).toBase58();
}

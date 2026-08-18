import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_backup/data/recoverbull_wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_encryption.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_envelope.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_wallet.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_encryption_key_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_signer_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/fetch_wallet_backup_manifest_import_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_wallet_port.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decrypts one envelope and returns its validated manifest', () async {
    final fixture = _realFixture(_emptyManifestPayload);

    final result = await fixture.usecase.execute();

    final manifestImport = _value(result);
    expect(manifestImport, isNotNull);
    expect(manifestImport!.parentFingerprint, fixture.parentFingerprint);
    expect(manifestImport.payload, _emptyManifestPayload);
    expect(fixture.remote.fetchCalls, 1);
    expect(fixture.state.blockedVersions, isEmpty);
    expect(fixture.state.setEnabledCalls, 0);
  });

  test(
    'returns an absent result without deriving the encryption key',
    () async {
      final fixture = _Fixture(
        remoteResult: Ok(
          WalletBackupRemoteHead.absent(generation: 0, etag: null),
        ),
      );

      final result = await fixture.usecase.execute();

      expect(_value(result), isNull);
      expect(fixture.fakeEncryption!.decryptCalls, 0);
      expect(fixture.fakeKeychain!.parseCalls, 0);
      expect(fixture.state.blockedVersions, isEmpty);
    },
  );

  test('preserves distinct remote failure states', () async {
    for (final failure in <WalletBackupFailure>[
      const WalletBackupRemoteUnavailableFailure(),
      const WalletBackupInvalidRemoteFailure(),
      const WalletBackupTooLargeFailure(),
      const WalletBackupHeadConflictFailure(),
    ]) {
      final fixture = _Fixture(remoteResult: Err(failure));

      final result = await fixture.usecase.execute();

      expect(_failure(result).runtimeType, failure.runtimeType);
      expect(fixture.fakeEncryption!.decryptCalls, 0);
      expect(fixture.state.blockedVersions, isEmpty);
    }
  });

  test(
    'preserves invalid, oversized, and unsupported section failures',
    () async {
      for (final failure in <WalletBackupFailure>[
        const WalletBackupInvalidEnvelopeFailure(),
        const WalletBackupTooLargeFailure(),
        const WalletBackupUnsupportedSectionFailure(
          sectionId: 'keychain_manifest',
          version: 2,
        ),
      ]) {
        final fixture = _Fixture(decryptResult: Err(failure));

        final result = await fixture.usecase.execute();

        expect(_failure(result).runtimeType, failure.runtimeType);
        expect(fixture.fakeKeychain!.parseCalls, 0);
        expect(fixture.state.blockedVersions, isEmpty);
      }
    },
  );

  test('blocks future writes after observing a newer outer version', () async {
    final fixture = _Fixture(
      decryptResult: const Err(
        WalletBackupUnsupportedEnvelopeVersionFailure(2),
      ),
    );

    final result = await fixture.usecase.execute();

    expect(
      _failure(result),
      isA<WalletBackupUnsupportedEnvelopeVersionFailure>().having(
        (failure) => failure.version,
        'version',
        2,
      ),
    );
    expect(fixture.state.blockedVersions, [2]);
    expect(fixture.fakeKeychain!.parseCalls, 0);
    expect(fixture.state.setEnabledCalls, 0);
  });

  test(
    'returns a state failure when the outer-version block cannot persist',
    () async {
      final fixture = _Fixture(
        decryptResult: const Err(
          WalletBackupUnsupportedEnvelopeVersionFailure(2),
        ),
        blockResult: const Err(WalletBackupStorageFailure()),
      );

      final result = await fixture.usecase.execute();

      expect(_failure(result), isA<WalletBackupStorageFailure>());
      expect(fixture.state.blockedVersions, [2]);
    },
  );

  test('maps invalid manifest data to a manifest failure', () async {
    final invalid = _realFixture(_unknownReservationManifestPayload);

    expect(
      _failure(await invalid.usecase.execute()),
      isA<WalletBackupManifestFailure>(),
    );
  });
}

final class _Fixture {
  late final String xprv = _canonicalXprv();
  final String parentFingerprint = '73c5da0a';
  late final _FakeWalletPort wallet = _FakeWalletPort(
    WalletBackupWallet(xprvBase58: xprv, parentFingerprint: parentFingerprint),
  );
  late final _FakeRemoteRepository remote;
  late final WalletBackupEncryptionRepository encryption;
  late final _FakeEncryptionRepository? fakeEncryption;
  late final KeychainManifestFacade keychain;
  late final _FakeKeychainManifestFacade? fakeKeychain;
  late final _FakeStateRepository state;
  late final FetchWalletBackupManifestImportUsecase usecase;

  _Fixture({
    Result<WalletBackupRemoteHead, WalletBackupFailure>? remoteResult,
    Result<WalletBackupEnvelope, WalletBackupFailure>? decryptResult,
    WalletBackupEncryptionRepository? encryptionRepository,
    KeychainManifestFacade? keychainManifest,
    Result<void, WalletBackupFailure> blockResult = const Ok(null),
  }) {
    final registry = Bip85RegistryFacade();
    remote = _FakeRemoteRepository(remoteResult ?? Ok(_presentRemoteHead()));
    if (encryptionRepository case final repository?) {
      encryption = repository;
      fakeEncryption = null;
    } else {
      fakeEncryption = _FakeEncryptionRepository(
        decryptResult ??
            Ok(
              WalletBackupEnvelope(
                parentFingerprint: parentFingerprint,
                createdAt: 1,
                manifest: WalletBackupManifestSection(
                  payload: _emptyManifestPayload,
                  parentFingerprint: parentFingerprint,
                ),
              ),
            ),
      );
      encryption = fakeEncryption!;
    }
    if (keychainManifest case final facade?) {
      keychain = facade;
      fakeKeychain = null;
    } else {
      fakeKeychain = _FakeKeychainManifestFacade();
      keychain = fakeKeychain!;
    }
    state = _FakeStateRepository(blockResult);
    usecase = FetchWalletBackupManifestImportUsecase(
      wallet: wallet,
      deriveSigner: DeriveWalletBackupSignerUsecase(
        NostrIdentityFacade(DeriveNostrIdentityHandleUsecase(registry)),
      ),
      remote: remote,
      deriveEncryptionKey: DeriveWalletBackupEncryptionKeyUsecase(
        registry: registry,
      ),
      encryption: encryption,
      keychainManifest: keychain,
      state: state,
    );
  }
}

_Fixture _realFixture(String manifestPayload) {
  final registry = Bip85RegistryFacade();
  final xprv = _canonicalXprv();
  final encryption = const RecoverBullWalletBackupEncryptionRepository();
  final key = _value(
    DeriveWalletBackupEncryptionKeyUsecase(
      registry: registry,
    ).execute(xprvBase58: xprv, expectedParentFingerprint: '73c5da0a'),
  );
  final ciphertext = _value(
    encryption.encrypt(
      envelope: WalletBackupEnvelope(
        parentFingerprint: '73c5da0a',
        createdAt: 1,
        manifest: WalletBackupManifestSection(
          payload: manifestPayload,
          parentFingerprint: '73c5da0a',
        ),
      ),
      key: key,
    ),
  );
  return _Fixture(
    remoteResult: Ok(_presentRemoteHead(ciphertext)),
    encryptionRepository: encryption,
    keychainManifest: _realKeychainManifestFacade(registry),
  );
}

KeychainManifestFacade _realKeychainManifestFacade(
  Bip85RegistryFacade registry,
) {
  return _ParsingKeychainManifestFacade(
    ParseKeychainManifestFileUsecase(
      codec: const KeychainManifestFileCodec(),
      bip85Registry: registry,
    ),
  );
}

final class _ParsingKeychainManifestFacade implements KeychainManifestFacade {
  final ParseKeychainManifestFileUsecase parser;

  const _ParsingKeychainManifestFacade(this.parser);

  @override
  KeychainManifestImportPlan parseManifestFilePayload(
    String payload, {
    required String expectedParentFingerprint,
    bool allowEmpty = false,
  }) {
    return parser.execute(
      payload,
      expectedParentFingerprint: expectedParentFingerprint,
      allowEmpty: allowEmpty,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeWalletPort implements WalletBackupWalletPort {
  final WalletBackupWallet wallet;

  const _FakeWalletPort(this.wallet);

  @override
  Future<Result<WalletBackupWallet, WalletBackupFailure>>
  deriveDefaultWallet() async => Ok(wallet);
}

final class _FakeRemoteRepository implements WalletBackupRemoteRepository {
  final Result<WalletBackupRemoteHead, WalletBackupFailure> result;
  int fetchCalls = 0;

  _FakeRemoteRepository(this.result);

  @override
  Future<Result<WalletBackupRemoteHead, WalletBackupFailure>> fetch(
    WalletBackupSigner signer,
  ) async {
    fetchCalls++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeEncryptionRepository
    implements WalletBackupEncryptionRepository {
  final Result<WalletBackupEnvelope, WalletBackupFailure> result;
  int decryptCalls = 0;

  _FakeEncryptionRepository(this.result);

  @override
  Result<WalletBackupEnvelope, WalletBackupFailure> decrypt({
    required WalletBackupCiphertext ciphertext,
    required WalletBackupEncryptionKey key,
    required String expectedParentFingerprint,
  }) {
    decryptCalls++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeKeychainManifestFacade implements KeychainManifestFacade {
  int parseCalls = 0;
  String? expectedFingerprint;
  bool? allowEmpty;

  @override
  KeychainManifestImportPlan parseManifestFilePayload(
    String payload, {
    required String expectedParentFingerprint,
    bool allowEmpty = false,
  }) {
    parseCalls++;
    expectedFingerprint = expectedParentFingerprint;
    this.allowEmpty = allowEmpty;
    return KeychainManifestImportPlan(
      parentFingerprint: expectedParentFingerprint,
      entries: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeStateRepository implements WalletBackupStateRepository {
  final Result<void, WalletBackupFailure> blockResult;
  final blockedVersions = <int>[];
  int setEnabledCalls = 0;

  _FakeStateRepository(this.blockResult);

  @override
  Future<Result<void, WalletBackupFailure>> blockUnsupportedVersion(
    int version,
  ) async {
    blockedVersions.add(version);
    return blockResult;
  }

  @override
  Future<Result<void, WalletBackupFailure>> setEnabled(bool enabled) async {
    setEnabledCalls++;
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WalletBackupRemoteHead _presentRemoteHead([
  WalletBackupCiphertext? storedCiphertext,
]) {
  final ciphertext =
      storedCiphertext ??
      WalletBackupCiphertext(
        base64Encode(
          List<int>.filled(WalletBackupCiphertext.minimumByteLength, 0),
        ),
      );
  return WalletBackupRemoteHead.present(
    generation: 1,
    etag: '11' * 32,
    ciphertext: ciphertext,
    ciphertextSha256: '22' * 32,
    updatedAtSecs: 1,
  );
}

const _emptyManifestPayload =
    '{"version":1,"parentFingerprint":"73c5da0a","generatedAt":1,'
    '"inventoryUpdatedAt":0,"entryCount":0,"materializationCount":0,'
    '"entries":[]}';

const _unknownReservationManifestPayload =
    '{"version":1,"parentFingerprint":"73c5da0a","generatedAt":20,'
    '"inventoryUpdatedAt":12,"entryCount":1,"materializationCount":1,'
    '"entries":[{"entryId":"73c5da0a:39\'/0\'/12\'/100\'",'
    '"bip85DerivationPath":"39\'/0\'/12\'/100\'",'
    '"reservationId":"unknown_wallet_seed","entryType":"walletSeed",'
    '"ownerFeature":"btcpay","bip85Application":39,"bip85Index":100,'
    '"createdAt":10,"updatedAt":12,"materializations":[{"type":"wallet",'
    '"walletId":"btc-wallet","childSeedFingerprint":"0123abcd",'
    '"network":"bitcoinMainnet","scriptType":"bip84",'
    '"createdAt":10,"updatedAt":10}]}]}';

String _canonicalXprv() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about',
    bip39.Language.english,
  );
  return Bip32Derivation.getCanonicalRootXprvFromSeed(
    Uint8List.fromList(mnemonic.seed),
  );
}

T _value<T>(Result<T, WalletBackupFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Expected Ok, got ${failure.runtimeType}'),
};

WalletBackupFailure _failure<T>(Result<T, WalletBackupFailure> result) =>
    switch (result) {
      Ok() => fail('Expected Err'),
      Err(:final failure) => failure,
    };

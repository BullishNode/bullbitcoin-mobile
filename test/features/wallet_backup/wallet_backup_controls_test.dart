import 'dart:async';
import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_backup/data/default_wallet_backup_wallet_adapter.dart';
import 'package:bb_mobile/features/wallet_backup/data/recoverbull_wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_encryption.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_wallet.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_encryption_key_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_signer_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/fetch_wallet_backup_manifest_import_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/get_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/watch_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_wallet_port.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:test/test.dart';

void main() {
  group('DefaultWalletBackupWalletAdapter', () {
    test('derives one canonical BIP85 root in either environment', () async {
      final seed = _zeroMnemonicSeed();
      for (final (environment, network) in [
        (Environment.mainnet, Network.bitcoinMainnet),
        (Environment.testnet, Network.bitcoinTestnet),
      ]) {
        final wallets = _FakeWalletRepository([
          _wallet('default', network: network),
        ]);
        final seeds = _FakeSeedRepository(seed);
        final adapter = DefaultWalletBackupWalletAdapter(
          getSettings: _FakeGetSettingsUsecase(environment),
          wallets: wallets,
          seeds: seeds,
        );

        expect(seeds.fingerprints, isEmpty);
        final derived = _value(await adapter.deriveDefaultWallet());

        expect(wallets.environment, environment);
        expect(wallets.onlyDefaults, isTrue);
        expect(wallets.onlyBitcoin, isTrue);
        expect(seeds.fingerprints, ['73c5da0a']);
        expect(derived.parentFingerprint, '73c5da0a');
        expect(derived.xprvBase58, startsWith('xprv'));
        expect(
          const DeriveWalletBackupEncryptionKeyUsecase(
            registry: Bip85RegistryFacade(),
          ).execute(
            xprvBase58: derived.xprvBase58,
            expectedParentFingerprint: derived.parentFingerprint,
          ),
          isA<Ok<WalletBackupEncryptionKey, WalletBackupFailure>>(),
        );
        expect(
          DeriveWalletBackupSignerUsecase(
            const NostrIdentityFacade(
              DeriveNostrIdentityHandleUsecase(Bip85RegistryFacade()),
            ),
          ).execute(
            xprvBase58: derived.xprvBase58,
            expectedParentFingerprint: derived.parentFingerprint,
          ),
          isA<Ok<WalletBackupSigner, WalletBackupFailure>>(),
        );
      }
    });

    test('rejects an absent or ambiguous default wallet as a value', () async {
      for (final wallets in <List<Wallet>>[
        const [],
        [
          _wallet('first', masterFingerprint: '11111111'),
          _wallet('second', masterFingerprint: '22222222'),
        ],
      ]) {
        final result = await DefaultWalletBackupWalletAdapter(
          getSettings: _FakeGetSettingsUsecase(),
          wallets: _FakeWalletRepository(wallets),
          seeds: _FakeSeedRepository(_zeroMnemonicSeed()),
        ).deriveDefaultWallet();

        expect(
          result,
          isA<Err<WalletBackupWallet, WalletBackupFailure>>().having(
            (result) => result.failure,
            'failure',
            isA<WalletBackupWalletUnavailableFailure>(),
          ),
        );
      }
    });
  });

  group('BackupWalletNowUsecase', () {
    test('does not derive or publish while backup is disabled', () async {
      final state = _FakeStateRepository(_state(enabled: false, dirty: true));
      final wallet = _FakeWalletPort();
      var syncCalls = 0;
      final usecase = BackupWalletNowUsecase(
        state: state,
        wallet: wallet,
        sync: ({required parentFingerprint, required xprvBase58}) async {
          syncCalls++;
          return Ok(_syncResult());
        },
        clock: _SequenceClock([10]),
      );

      final result = await usecase.execute();

      expect(_failure(result), isA<WalletBackupDisabledFailure>());
      expect(state.attempts, isEmpty);
      expect(wallet.calls, 0);
      expect(syncCalls, 0);
    });

    test('publishes one captured dirty revision and records success', () async {
      final state = _FakeStateRepository(
        _state(enabled: true, dirty: true, dirtyRevision: 7),
      );
      final wallet = _FakeWalletPort();
      String? seenFingerprint;
      String? seenXprv;
      final usecase = BackupWalletNowUsecase(
        state: state,
        wallet: wallet,
        sync: ({required parentFingerprint, required xprvBase58}) async {
          seenFingerprint = parentFingerprint;
          seenXprv = xprvBase58;
          return Ok(_syncResult());
        },
        clock: _SequenceClock([10, 12]),
      );

      _expectOk(await usecase.execute());

      expect(state.attempts, [10]);
      expect(state.successRevisions, [7]);
      expect(state.successTimes, [12]);
      expect(wallet.calls, 1);
      expect(seenFingerprint, '73c5da0a');
      expect(seenXprv, _canonicalXprv());
    });

    test('clean state is a no-op and preserves key secrecy boundary', () async {
      final state = _FakeStateRepository(_state(enabled: true, dirty: false));
      final wallet = _FakeWalletPort();
      final usecase = BackupWalletNowUsecase(
        state: state,
        wallet: wallet,
        sync: ({required parentFingerprint, required xprvBase58}) async =>
            Ok(_syncResult()),
        clock: _SequenceClock([]),
      );

      _expectOk(await usecase.execute());

      expect(wallet.calls, 0);
      expect(state.attempts, isEmpty);
    });

    test('persists a newly observed unsupported outer version', () async {
      final state = _FakeStateRepository(_state(enabled: true, dirty: true));
      final usecase = BackupWalletNowUsecase(
        state: state,
        wallet: _FakeWalletPort(),
        sync: ({required parentFingerprint, required xprvBase58}) async =>
            const Err(WalletBackupUnsupportedEnvelopeVersionFailure(2)),
        clock: _SequenceClock([10]),
      );

      final result = await usecase.execute();

      expect(
        _failure(result),
        isA<WalletBackupUnsupportedEnvelopeVersionFailure>().having(
          (failure) => failure.version,
          'version',
          2,
        ),
      );
      expect(state.blockedVersions, [2]);
      expect(state.successRevisions, isEmpty);
    });

    test('an existing version block prevents any publication work', () async {
      final state = _FakeStateRepository(
        _state(enabled: true, dirty: true, unsupportedVersion: 2),
      );
      final wallet = _FakeWalletPort();
      var syncCalls = 0;
      final usecase = BackupWalletNowUsecase(
        state: state,
        wallet: wallet,
        sync: ({required parentFingerprint, required xprvBase58}) async {
          syncCalls++;
          return Ok(_syncResult());
        },
        clock: _SequenceClock([]),
      );

      final result = await usecase.execute();

      expect(
        _failure(result),
        isA<WalletBackupUnsupportedEnvelopeVersionFailure>(),
      );
      expect(wallet.calls, 0);
      expect(syncCalls, 0);
      expect(state.attempts, isEmpty);
    });
  });

  group('DeleteWalletBackupUsecase', () {
    test('requires confirmation before deriving wallet keys', () async {
      final wallet = _FakeWalletPort();
      final state = _FakeStateRepository(_state());
      final remote = _FakeRemoteRepository();
      final usecase = _deleteUsecase(
        wallet: wallet,
        state: state,
        remote: remote,
      );

      final result = await usecase.execute(confirmed: false);

      expect(_failure(result), isA<WalletBackupConfirmationRequiredFailure>());
      expect(wallet.calls, 0);
      expect(remote.fetchCalls, 0);
      expect(state.clearCalls, 0);
    });

    test('conditionally deletes and then clears only the checkpoint', () async {
      final wallet = _FakeWalletPort();
      final state = _FakeStateRepository(_state(enabled: true, dirty: true));
      final remote = _FakeRemoteRepository();
      final usecase = _deleteUsecase(
        wallet: wallet,
        state: state,
        remote: remote,
      );

      _expectOk(await usecase.execute(confirmed: true));

      expect(wallet.calls, 1);
      expect(remote.fetchCalls, 1);
      expect(remote.deleteCalls, 1);
      expect(remote.lastSigner?.publicKeyHex, '11' * 32);
      expect(state.clearCalls, 1);
      expect(state.current.enabled, isTrue);
      expect(state.current.dirty, isTrue);
    });

    test('does not clear local state after a remote conflict', () async {
      final state = _FakeStateRepository(_state());
      final remote = _FakeRemoteRepository(
        deleteFailure: const WalletBackupHeadConflictFailure(),
      );
      final usecase = _deleteUsecase(
        wallet: _FakeWalletPort(),
        state: state,
        remote: remote,
      );

      final result = await usecase.execute(confirmed: true);

      expect(_failure(result), isA<WalletBackupHeadConflictFailure>());
      expect(state.clearCalls, 0);
    });

    test(
      'mismatched stored seed cannot select a remote deletion key',
      () async {
        final actualSeed = _zeroMnemonicSeed();
        final remote = _FakeRemoteRepository();
        final usecase = _deleteUsecase(
          wallet: DefaultWalletBackupWalletAdapter(
            getSettings: _FakeGetSettingsUsecase(),
            wallets: _FakeWalletRepository([
              _wallet('default', masterFingerprint: '11111111'),
            ]),
            seeds: _FakeSeedRepository(
              Seed.bytes(
                bytes: actualSeed.bytes,
                masterFingerprint: '11111111',
              ),
            ),
          ),
          state: _FakeStateRepository(_state()),
          remote: remote,
        );

        final result = await usecase.execute(confirmed: true);

        expect(_failure(result), isA<WalletBackupWalletUnavailableFailure>());
        expect(remote.fetchCalls, 0);
        expect(remote.deleteCalls, 0);
      },
    );
  });

  test('WalletBackupFacade exposes the unified lifecycle only', () async {
    final state = _FakeStateRepository(_state());
    final wallet = _FakeWalletPort();
    final facade = WalletBackupFacade(
      getState: GetWalletBackupStateUsecase(state),
      watchState: WatchWalletBackupStateUsecase(state),
      setEnabled: SetWalletBackupEnabledUsecase(state),
      backupNow: BackupWalletNowUsecase(
        state: state,
        wallet: wallet,
        sync: ({required parentFingerprint, required xprvBase58}) async =>
            Ok(_syncResult()),
        clock: _SequenceClock([]),
      ),
      delete: _deleteUsecase(
        wallet: wallet,
        state: state,
        remote: _FakeRemoteRepository(),
      ),
      fetchManifestImport: _fetchManifestImportUsecase(
        wallet: wallet,
        state: state,
        remote: _FakeRemoteRepository(),
      ),
    );

    expect(_value(await facade.getState()).enabled, isFalse);
    _expectOk(await facade.setEnabled(true));
    expect(_value(await facade.getState()).enabled, isTrue);
    expect(
      await facade.watchState().first,
      isA<Ok<WalletBackupState, WalletBackupFailure>>(),
    );
    expect(_value(await facade.fetchManifestImport()), isNull);
  });
}

DeleteWalletBackupUsecase _deleteUsecase({
  required WalletBackupWalletPort wallet,
  required WalletBackupStateRepository state,
  required WalletBackupRemoteRepository remote,
}) {
  return DeleteWalletBackupUsecase(
    remote: remote,
    state: state,
    wallet: wallet,
    deriveSigner: DeriveWalletBackupSignerUsecase(_FakeNostrIdentityFacade()),
  );
}

FetchWalletBackupManifestImportUsecase _fetchManifestImportUsecase({
  required WalletBackupWalletPort wallet,
  required WalletBackupStateRepository state,
  required WalletBackupRemoteRepository remote,
}) {
  return FetchWalletBackupManifestImportUsecase(
    wallet: wallet,
    deriveSigner: DeriveWalletBackupSignerUsecase(_FakeNostrIdentityFacade()),
    remote: remote,
    deriveEncryptionKey: const DeriveWalletBackupEncryptionKeyUsecase(
      registry: Bip85RegistryFacade(),
    ),
    encryption: const RecoverBullWalletBackupEncryptionRepository(),
    keychainManifest: _FakeKeychainManifestFacade(),
    state: state,
  );
}

final class _FakeStateRepository implements WalletBackupStateRepository {
  WalletBackupState current;
  final attempts = <int>[];
  final successRevisions = <int>[];
  final successTimes = <int>[];
  final blockedVersions = <int>[];
  int clearCalls = 0;

  _FakeStateRepository(this.current);

  @override
  Future<Result<WalletBackupState, WalletBackupFailure>> get() async {
    return Ok(current);
  }

  @override
  Stream<Result<WalletBackupState, WalletBackupFailure>> watch() {
    return Stream.value(Ok(current));
  }

  @override
  Future<Result<void, WalletBackupFailure>> setEnabled(bool enabled) async {
    current = _state(
      enabled: enabled,
      dirty: enabled ? true : current.dirty,
      dirtyRevision: enabled && !current.enabled
          ? current.dirtyRevision + 1
          : current.dirtyRevision,
    );
    return const Ok(null);
  }

  @override
  Future<Result<void, WalletBackupFailure>> markDirty() async {
    return const Ok(null);
  }

  @override
  Future<Result<void, WalletBackupFailure>> recordAttempt(
    int attemptedAt,
  ) async {
    attempts.add(attemptedAt);
    return const Ok(null);
  }

  @override
  Future<Result<void, WalletBackupFailure>> recordSuccess({
    required int capturedDirtyRevision,
    required int succeededAt,
    required WalletBackupSyncResult syncResult,
  }) async {
    successRevisions.add(capturedDirtyRevision);
    successTimes.add(succeededAt);
    return const Ok(null);
  }

  @override
  Future<Result<void, WalletBackupFailure>> blockUnsupportedVersion(
    int version,
  ) async {
    blockedVersions.add(version);
    return const Ok(null);
  }

  @override
  Future<Result<void, WalletBackupFailure>> clearRemoteCheckpoint() async {
    clearCalls++;
    return const Ok(null);
  }
}

final class _FakeWalletPort implements WalletBackupWalletPort {
  int calls = 0;
  Result<WalletBackupWallet, WalletBackupFailure> result = Ok(
    WalletBackupWallet(
      xprvBase58: _canonicalXprv(),
      parentFingerprint: '73c5da0a',
    ),
  );

  @override
  Future<Result<WalletBackupWallet, WalletBackupFailure>>
  deriveDefaultWallet() async {
    calls++;
    return result;
  }
}

final class _FakeRemoteRepository implements WalletBackupRemoteRepository {
  final WalletBackupFailure? deleteFailure;
  int fetchCalls = 0;
  int deleteCalls = 0;
  WalletBackupSigner? lastSigner;

  _FakeRemoteRepository({this.deleteFailure});

  @override
  Future<Result<WalletBackupRemoteHead, WalletBackupFailure>> fetch(
    WalletBackupSigner signer,
  ) async {
    fetchCalls++;
    lastSigner = signer;
    return Ok(WalletBackupRemoteHead.absent(generation: 0, etag: null));
  }

  @override
  Future<Result<WalletBackupRemoteCheckpoint?, WalletBackupFailure>> delete({
    required WalletBackupSigner signer,
    required WalletBackupRemoteHead current,
  }) async {
    deleteCalls++;
    lastSigner = signer;
    final failure = deleteFailure;
    if (failure != null) return Err(failure);
    return const Ok(null);
  }

  @override
  Future<Result<WalletBackupRemoteCheckpoint, WalletBackupFailure>> store({
    required WalletBackupSigner signer,
    required WalletBackupRemoteHead current,
    required WalletBackupCiphertext ciphertext,
  }) {
    throw UnimplementedError();
  }
}

final class _FakeNostrIdentityFacade implements NostrIdentityFacade {
  @override
  String deriveWalletBackupPublicKeyFromXprv(String xprvBase58) => '11' * 32;

  @override
  String signWalletBackupHashFromXprv({
    required String xprvBase58,
    required String messageHashHex,
  }) => '22' * 32;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeKeychainManifestFacade implements KeychainManifestFacade {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SequenceClock implements Clock {
  final List<int> seconds;
  int _index = 0;

  _SequenceClock(this.seconds);

  @override
  DateTime nowUtc() {
    if (_index >= seconds.length) throw StateError('unexpected clock read');
    final value = seconds[_index++];
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }
}

final class _FakeWalletRepository implements WalletRepository {
  final List<Wallet> wallets;
  Environment? environment;
  bool? onlyDefaults;
  bool? onlyBitcoin;

  _FakeWalletRepository(this.wallets);

  @override
  Future<List<Wallet>> getWallets({
    Environment? environment,
    bool? onlyDefaults,
    bool? onlyBitcoin,
    bool? onlyLiquid,
    bool sync = false,
  }) async {
    this.environment = environment;
    this.onlyDefaults = onlyDefaults;
    this.onlyBitcoin = onlyBitcoin;
    return wallets
        .where((wallet) {
          if (environment == null) return true;
          return switch (environment) {
            Environment.mainnet => wallet.network == Network.bitcoinMainnet,
            Environment.testnet => wallet.network == Network.bitcoinTestnet,
          };
        })
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSeedRepository implements SeedRepository {
  final Seed seed;
  final fingerprints = <String>[];

  _FakeSeedRepository(this.seed);

  @override
  Future<Seed> get(String fingerprint) async {
    fingerprints.add(fingerprint);
    return seed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeGetSettingsUsecase implements GetSettingsUsecase {
  final Environment environment;

  _FakeGetSettingsUsecase([this.environment = Environment.mainnet]);

  @override
  Future<SettingsEntity> execute() async {
    return SettingsEntity(
      environment: environment,
      bitcoinUnit: BitcoinUnit.sats,
      currencyCode: 'USD',
    );
  }
}

WalletBackupState _state({
  bool enabled = false,
  bool dirty = false,
  int dirtyRevision = 0,
  int? unsupportedVersion,
}) {
  return WalletBackupState(
    enabled: enabled,
    dirty: dirty,
    dirtyRevision: dirtyRevision,
    lastAttemptedAt: null,
    lastSucceededAt: null,
    remoteGeneration: 0,
    remoteEtag: null,
    contentHash: null,
    unsupportedVersion: unsupportedVersion,
  );
}

WalletBackupSyncResult _syncResult() {
  return WalletBackupSyncResult(
    checkpoint: WalletBackupRemoteCheckpoint(generation: 1, etag: '33' * 32),
    contentHash: '44' * 32,
  );
}

Wallet _wallet(
  String id, {
  Network network = Network.bitcoinMainnet,
  String masterFingerprint = '73c5da0a',
}) {
  return Wallet(
    origin: id,
    network: network,
    masterFingerprint: masterFingerprint,
    xpubFingerprint: masterFingerprint,
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: 'external',
    internalPublicDescriptor: 'internal',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}

Seed _zeroMnemonicSeed() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about',
    bip39.Language.english,
  );
  return Seed.mnemonic(
    mnemonicWords: mnemonic.words,
    bytes: Uint8List.fromList(mnemonic.seed),
    masterFingerprint: '73c5da0a',
  );
}

String _canonicalXprv() {
  return Bip32Derivation.getCanonicalRootXprvFromSeed(
    _zeroMnemonicSeed().bytes,
  );
}

T _value<T>(Result<T, WalletBackupFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Expected Ok, got ${failure.runtimeType}'),
};

WalletBackupFailure _failure(Result<void, WalletBackupFailure> result) {
  return switch (result) {
    Ok() => fail('Expected Err'),
    Err(:final failure) => failure,
  };
}

void _expectOk(Result<void, WalletBackupFailure> result) {
  if (result case Err(:final failure)) {
    fail('Expected Ok, got ${failure.runtimeType}');
  }
}

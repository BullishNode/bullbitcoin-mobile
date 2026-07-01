import 'dart:typed_data';

import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/recoverbull_keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_nostr_encrypted_content_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_signed_keychain_manifest_nostr_event_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _InMemoryKeychainManifestStore store;
  late _FakeNostrIdentityFacade nostrIdentity;
  late BuildSignedKeychainManifestNostrEventUsecase usecase;

  setUp(() {
    store = _InMemoryKeychainManifestStore();
    nostrIdentity = _FakeNostrIdentityFacade();
    usecase = BuildSignedKeychainManifestNostrEventUsecase(
      buildEncryptedContent: BuildKeychainManifestNostrEncryptedContentUsecase(
        buildManifestFile: BuildKeychainManifestFileUsecase(
          repository: store,
          registry: const Bip85RegistryFacade(),
        ),
        encryptionRepository:
            const RecoverBullKeychainManifestNostrEncryptionRepository(),
      ),
      nostrIdentity: nostrIdentity,
    );
  });

  test('builds and signs an encrypted manifest event', () async {
    await _recordInventory(store);

    final event = await usecase.execute(
      parentFingerprint: _parentFingerprint,
      xprvBase58: _xprv,
      now: DateTime.fromMillisecondsSinceEpoch(20000, isUtc: true),
    );

    expect(event.authorPublicKeyHex, _authorPublicKeyHex);
    expect(event.createdAt, 20);
    expect(event.kind, keychainManifestNostrEventKind);
    expect(event.tags, [
      ['d', keychainManifestNostrDTag],
    ]);
    expect(event.encryptedContent, isNot(contains(_parentFingerprint)));
    expect(event.encryptedContent, isNot(contains('btc-wallet')));
    expect(event.signatureHex, _signatureHex);
    expect(nostrIdentity.publicKeyXprvs, [_xprv]);
    expect(nostrIdentity.signXprvs, [_xprv]);
    expect(nostrIdentity.signedHashes.single, event.id);
  });

  test('keeps empty inventory as an explicit caller decision', () async {
    await expectLater(
      usecase.execute(parentFingerprint: _parentFingerprint, xprvBase58: _xprv),
      throwsA(
        isA<KeychainManifestException>().having(
          (error) => error.type,
          'type',
          KeychainManifestExceptionType.emptyInventory,
        ),
      ),
    );

    final result = await usecase.execute(
      parentFingerprint: _parentFingerprint,
      xprvBase58: _xprv,
      allowEmpty: true,
    );

    expect(result.encryptedContent, isNotEmpty);
  });

  test('maps signing failures into sanitized signing errors', () async {
    await _recordInventory(store);
    nostrIdentity.signError = StateError('xprv-secret-leak');

    await expectLater(
      usecase.execute(parentFingerprint: _parentFingerprint, xprvBase58: _xprv),
      throwsA(
        isA<KeychainManifestNostrSigningException>()
            .having(
              (error) => error.message,
              'message',
              'failed to build signed keychain manifest Nostr event',
            )
            .having(
              (error) => error.toString(),
              'string',
              isNot(contains('xprv-secret-leak')),
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
  final publicKeyXprvs = <String>[];
  final signXprvs = <String>[];
  final signedHashes = <String>[];
  Object? signError;

  @override
  String deriveWalletManifestPublicKeyFromXprv(String xprvBase58) {
    publicKeyXprvs.add(xprvBase58);
    return _authorPublicKeyHex;
  }

  @override
  String signWalletManifestHashFromXprv({
    required String xprvBase58,
    required String messageHashHex,
  }) {
    final error = signError;
    if (error != null) throw error;
    signXprvs.add(xprvBase58);
    signedHashes.add(messageHashHex);
    return _signatureHex;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/merge_keychain_manifest_file_payloads_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = KeychainManifestFileCodec();
  const parser = ParseKeychainManifestFileUsecase(
    codec: codec,
    bip85Registry: Bip85RegistryFacade(),
  );
  const usecase = MergeKeychainManifestFilePayloadsUsecase(
    codec: codec,
    parseManifest: parser,
  );

  test('unions validated local and remote manifest inventory canonically', () {
    final remote = _file(
      generatedAt: 10,
      entries: [_entry(index: 100, updatedAt: 10)],
    );
    final local = _file(
      generatedAt: 20,
      entries: [_entry(index: 101, updatedAt: 20)],
    );

    final merged = usecase.execute(
      localPayload: codec.encode(local),
      remotePayload: codec.encode(remote),
      expectedParentFingerprint: 'fedcba98',
      generatedAt: 30,
    );

    expect(merged.generatedAt, 30);
    expect(merged.entries.map((entry) => entry.bip85Index), [100, 101]);
    final encoded = codec.encode(merged);
    expect(codec.encode(codec.decode(encoded)), encoded);
  });

  test('preserves the remote file when local inventory adds nothing', () {
    final remote = _file(
      generatedAt: 10,
      entries: [_entry(index: 100, updatedAt: 10)],
    );
    final local = _file(
      generatedAt: 20,
      entries: [_entry(index: 100, updatedAt: 10)],
    );

    final merged = usecase.execute(
      localPayload: codec.encode(local),
      remotePayload: codec.encode(remote),
      expectedParentFingerprint: 'fedcba98',
      generatedAt: 30,
    );

    expect(merged.generatedAt, remote.generatedAt);
    expect(codec.encode(merged), codec.encode(remote));
  });

  test('rejects one wallet id with conflicting derived fingerprints', () {
    final remote = _file(
      generatedAt: 10,
      entries: [_entry(index: 100, childSeedFingerprint: '0123abcd')],
    );
    final local = _file(
      generatedAt: 20,
      entries: [_entry(index: 100, childSeedFingerprint: '89abcdef')],
    );

    expect(
      () => usecase.execute(
        localPayload: codec.encode(local),
        remotePayload: codec.encode(remote),
        expectedParentFingerprint: 'fedcba98',
        generatedAt: 30,
      ),
      throwsA(isA<KeychainManifestEntryConflictException>()),
    );
  });

  test('validates the expected parent before returning merged inventory', () {
    final file = _file(entries: [_entry(index: 100)]);

    expect(
      () => usecase.execute(
        localPayload: codec.encode(file),
        remotePayload: codec.encode(file),
        expectedParentFingerprint: '01234567',
        generatedAt: 30,
      ),
      throwsA(isA<KeychainManifestFileParseException>()),
    );
  });
}

KeychainManifestFile _file({
  int generatedAt = 10,
  required List<KeychainManifestFileEntry> entries,
}) {
  return KeychainManifestFile(
    parentFingerprint: 'fedcba98',
    generatedAt: generatedAt,
    entries: entries,
  );
}

KeychainManifestFileEntry _entry({
  required int index,
  int updatedAt = 10,
  String childSeedFingerprint = '0123abcd',
}) {
  final path = "39'/0'/12'/$index'";
  final entryId = 'fedcba98:$path';
  final (reservationId, ownerFeature) = switch (index) {
    100 => ('btcpay_wallet_seed', 'btcpay'),
    101 => ('lightning_address_wallet_seed', 'lightningAddress'),
    _ => throw ArgumentError.value(index, 'index'),
  };
  return KeychainManifestFileEntry(
    parentFingerprint: 'fedcba98',
    bip85DerivationPath: path,
    reservationId: reservationId,
    entryType: 'walletSeed',
    ownerFeature: ownerFeature,
    bip85Application: 39,
    bip85Index: index,
    createdAt: 10,
    updatedAt: updatedAt,
    materializations: [
      KeychainManifestFileWalletMaterialization(
        walletId: 'wallet-$index',
        entryId: entryId,
        childSeedFingerprint: childSeedFingerprint,
        network: 'bitcoinMainnet',
        scriptType: 'bip84',
        createdAt: 10,
        updatedAt: updatedAt,
      ),
    ],
  );
}

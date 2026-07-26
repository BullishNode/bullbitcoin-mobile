import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:test/test.dart';

void main() {
  test('round trips a Nostr materialization without private key material', () {
    final entry = KeychainManifestEntry(
      parentFingerprint: '01234567',
      bip85DerivationPath: "128002'/1'/1'",
      reservationId: 'nostr_user_key',
      entryType: 'userGenerated',
      ownerFeature: 'nostr',
      bip85Application: 128002,
      bip85Index: 1,
      createdAt: 100,
      updatedAt: 100,
    );
    final record = KeychainManifestNostrKeyRecord(
      entry: entry,
      nostrKeyMaterialization: KeychainManifestNostrKeyMaterialization(
        entryId: entry.entryId,
        publicKeyHex: 'ab' * 32,
        keyKind: KeychainManifestNostrKeyKind.userGenerated,
        purpose: 'personal identity',
        createdAt: 100,
        updatedAt: 100,
      ),
    );
    final file = KeychainManifestFile(
      parentFingerprint: entry.parentFingerprint,
      generatedAt: 100,
      entries: [KeychainManifestFileEntry.fromNostrKeyRecord(record)],
    );

    const codec = KeychainManifestFileCodec();
    final payload = codec.encode(file);
    final decoded = codec.decode(payload);
    final materialization =
        decoded.entries.single.materializations.single
            as KeychainManifestFileNostrKeyMaterialization;

    expect(materialization.publicKeyHex, 'ab' * 32);
    expect(materialization.purpose, 'personal identity');
    expect(payload, isNot(contains('nsec')));
    expect(payload, isNot(contains('private')));
  });

  test('parses a user Nostr namespace entry without a static reservation', () {
    final entry = KeychainManifestFileEntry(
      parentFingerprint: '01234567',
      bip85DerivationPath: "128002'/7'/1'",
      reservationId: 'nostr_user_key',
      entryType: 'userGenerated',
      ownerFeature: 'nostr',
      bip85Application: 128002,
      bip85Index: 1,
      createdAt: 100,
      updatedAt: 100,
      materializations: [
        KeychainManifestFileNostrKeyMaterialization(
          entryId: KeychainManifestEntryId.fromIdentity(
            parentFingerprint: '01234567',
            bip85DerivationPath: "128002'/7'/1'",
          ),
          publicKeyHex: 'cd' * 32,
          keyKind: KeychainManifestNostrKeyKind.userGenerated.name,
          purpose: 'integration key',
          createdAt: 100,
          updatedAt: 100,
        ),
      ],
    );
    final file = KeychainManifestFile(
      parentFingerprint: '01234567',
      generatedAt: 100,
      entries: [entry],
    );

    final plan = ParseKeychainManifestFileUsecase(
      codec: const KeychainManifestFileCodec(),
      bip85Registry: const Bip85RegistryFacade(),
    ).executeFile(file, expectedParentFingerprint: '01234567');

    expect(plan.nostrKeyMaterializations.single.publicKeyHex, 'cd' * 32);
    expect(
      plan.nostrKeyMaterializations.single.bip85DerivationPath,
      "128002'/7'/1'",
    );
  });
}

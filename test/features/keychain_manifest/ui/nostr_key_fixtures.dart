import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';

const parentFingerprint = '73c5da0a';

/// The hex public keys the fixtures use. No screen may render either of these:
/// npub is the only public-key representation the UI is allowed to show.
const userPublicKeyHex =
    'abababababababababababababababababababababababababababababababab';
const systemPublicKeyHex =
    'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';

KeychainManifestNostrKeyRecord userKeyRecord({
  String purpose = 'personal identity',
  String? description,
  int identity = 1,
  String publicKeyHex = userPublicKeyHex,
}) {
  final entry = KeychainManifestEntry(
    parentFingerprint: parentFingerprint,
    bip85DerivationPath: "128002'/$identity'/1'",
    reservationId: 'nostr_user_key',
    entryType: 'userGenerated',
    ownerFeature: 'nostr',
    bip85Application: 128002,
    bip85Index: 1,
    createdAt: 1,
    updatedAt: 1,
  );
  return KeychainManifestNostrKeyRecord(
    entry: entry,
    nostrKeyMaterialization: KeychainManifestNostrKeyMaterialization(
      entryId: entry.entryId,
      publicKeyHex: publicKeyHex,
      keyKind: KeychainManifestNostrKeyKind.userGenerated,
      purpose: purpose,
      description: description,
      createdAt: 1,
      updatedAt: 1,
    ),
  );
}

KeychainManifestNostrKeyRecord systemKeyRecord({
  String path = "128002'/100'/1'",
  String reservationId = 'nostr_wallet_backup_key',
  String purpose = 'Nostr Wallet Backup',
  String publicKeyHex = systemPublicKeyHex,
}) {
  final segments = path.split('/');
  final entry = KeychainManifestEntry(
    parentFingerprint: parentFingerprint,
    bip85DerivationPath: path,
    reservationId: reservationId,
    entryType: 'nonWalletNostrKey',
    ownerFeature: 'nostr',
    bip85Application: int.parse(
      segments.first.substring(0, segments.first.length - 1),
    ),
    bip85Index: int.parse(segments.last.substring(0, segments.last.length - 1)),
    createdAt: 1,
    updatedAt: 1,
  );
  return KeychainManifestNostrKeyRecord(
    entry: entry,
    nostrKeyMaterialization: KeychainManifestNostrKeyMaterialization(
      entryId: entry.entryId,
      publicKeyHex: publicKeyHex,
      keyKind: KeychainManifestNostrKeyKind.reserved,
      purpose: purpose,
      createdAt: 1,
      updatedAt: 1,
    ),
  );
}

/// Records the calls the screens make, so a test can assert what reached the
/// domain rather than only what was painted.
final class FakeKeychainManifestFacade implements KeychainManifestFacade {
  FakeKeychainManifestFacade({
    List<KeychainManifestNostrKeyRecord> keys = const [],
    this.failing = false,
    this.nsec = 'nsec1fake',
  }) : keys = List.of(keys);

  final List<KeychainManifestNostrKeyRecord> keys;
  final bool failing;
  final String nsec;

  final createCalls = <(String, String?)>[];
  final updateCalls = <(String, String?, String?)>[];
  final revealCalls = <String>[];

  @override
  Future<List<KeychainManifestNostrKeyRecord>>
  getDefaultWalletNostrKeys() async {
    if (failing) throw StateError('listing failed');
    return List.unmodifiable(keys);
  }

  @override
  Future<CreatedKeychainManifestNostrKey> createUserNostrKey({
    required String purpose,
    String? description,
    DateTime? now,
  }) async {
    createCalls.add((purpose, description));
    if (failing) throw StateError('create failed');
    final created = userKeyRecord(
      purpose: purpose,
      description: description,
      identity: keys.length + 1,
    );
    keys.add(created);
    return CreatedKeychainManifestNostrKey(
      parentFingerprint: parentFingerprint,
      derivationPath: created.entry.bip85DerivationPath,
      publicKeyHex: created.nostrKeyMaterialization.publicKeyHex,
      purpose: created.nostrKeyMaterialization.purpose,
      description: created.nostrKeyMaterialization.description,
    );
  }

  @override
  Future<void> updateNostrKey({
    required String parentFingerprint,
    required String entryId,
    String? purpose,
    String? description,
    DateTime? now,
  }) async {
    updateCalls.add((entryId, purpose, description));
    if (failing) throw StateError('update failed');
    final index = keys.indexWhere((key) => key.entryId == entryId);
    if (index == -1) return;
    final stored = keys[index].nostrKeyMaterialization;
    keys[index] = KeychainManifestNostrKeyRecord(
      entry: keys[index].entry,
      nostrKeyMaterialization: KeychainManifestNostrKeyMaterialization(
        entryId: stored.entryId,
        publicKeyHex: stored.publicKeyHex,
        keyKind: stored.keyKind,
        purpose: purpose ?? stored.purpose,
        description: description ?? stored.description,
        createdAt: stored.createdAt,
        updatedAt: stored.updatedAt + 1,
      ),
    );
  }

  @override
  Future<String> revealNostrKeyNsec(
    KeychainManifestNostrKeyRecord record,
  ) async {
    revealCalls.add(record.entryId);
    if (failing) throw StateError('reveal failed');
    return nsec;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

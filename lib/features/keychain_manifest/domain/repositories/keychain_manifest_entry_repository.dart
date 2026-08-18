import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';

abstract interface class KeychainManifestEntryRepository {
  /// Returns the records sorted by BIP85 derivation path, entry id, network,
  /// then wallet id, matching the manifest file's canonical ordering.
  Future<List<KeychainManifestWalletMaterializationRecord>>
  fetchWalletMaterializationRecordsByParentFingerprint(
    String parentFingerprint,
  );

  Future<void> insertWalletMaterializationRecords(
    List<KeychainManifestWalletMaterializationRecord> records,
  );

  Future<List<KeychainManifestNostrKeyRecord>>
  fetchNostrKeyRecordsByParentFingerprint(String parentFingerprint);

  Future<void> insertNostrKeyRecords(
    List<KeychainManifestNostrKeyRecord> records,
  );

  /// Writes a Nostr key's editable metadata as one row state.
  ///
  /// Both fields are always written, so callers that only change one of them
  /// pass the stored value for the other. Deciding what "unchanged" means
  /// belongs to the use case that already holds the record, not here.
  Future<void> updateNostrKeyMetadata({
    required String parentFingerprint,
    required String entryId,
    required String purpose,
    required String? description,
    required int updatedAt,
  });
}

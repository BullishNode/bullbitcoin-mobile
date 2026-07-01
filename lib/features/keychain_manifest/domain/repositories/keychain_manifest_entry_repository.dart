import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';

abstract interface class KeychainManifestEntryRepository {
  Future<List<KeychainManifestWalletMaterializationRecord>>
  fetchWalletMaterializationRecordsByParentFingerprint(
    String parentFingerprint,
  );

  Future<void> insertWalletMaterializationRecords(
    List<KeychainManifestWalletMaterializationRecord> records,
  );
}

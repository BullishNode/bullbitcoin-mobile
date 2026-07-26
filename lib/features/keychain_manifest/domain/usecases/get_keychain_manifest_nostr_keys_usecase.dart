// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';

class GetKeychainManifestNostrKeysUsecase {
  final KeychainManifestEntryRepository _repository;

  const GetKeychainManifestNostrKeysUsecase({
    required KeychainManifestEntryRepository repository,
  }) : _repository = repository;

  Future<List<KeychainManifestNostrKeyRecord>> execute(
    String parentFingerprint,
  ) => _repository.fetchNostrKeyRecordsByParentFingerprint(parentFingerprint);
}

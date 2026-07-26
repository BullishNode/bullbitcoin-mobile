// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';

class UpdateKeychainManifestNostrKeyPurposeUsecase {
  final KeychainManifestEntryRepository _repository;
  final Clock _clock;

  const UpdateKeychainManifestNostrKeyPurposeUsecase({
    required KeychainManifestEntryRepository repository,
    Clock clock = const SystemClock(),
  }) : _repository = repository,
       _clock = clock;

  Future<void> execute({
    required String parentFingerprint,
    required String entryId,
    required String purpose,
    DateTime? now,
  }) => _repository.updateNostrKeyPurpose(
    parentFingerprint: parentFingerprint,
    entryId: entryId,
    purpose: purpose,
    updatedAt: (now ?? _clock.nowUtc()).millisecondsSinceEpoch ~/ 1000,
  );
}

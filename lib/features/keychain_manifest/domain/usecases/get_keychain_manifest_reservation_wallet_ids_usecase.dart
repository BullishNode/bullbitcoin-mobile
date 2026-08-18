// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';

/// Reads the local manifest (wallet truth) for the wallet ids materialized under
/// [parentFingerprint] for a given [reservationId]. Lets callers resolve a
/// reserved wallet by its STABLE BIP85 reservation instead of a mutable label.
class GetKeychainManifestReservationWalletIdsUsecase {
  final KeychainManifestEntryRepository _repository;

  const GetKeychainManifestReservationWalletIdsUsecase({
    required KeychainManifestEntryRepository repository,
  }) : _repository = repository;

  Future<List<String>> execute({
    required String parentFingerprint,
    required String reservationId,
  }) async {
    final records = await _repository
        .fetchWalletMaterializationRecordsByParentFingerprint(
          parentFingerprint,
        );
    return records
        .where((record) => record.entry.reservationId == reservationId)
        .map((record) => record.walletId)
        .toList(growable: false);
  }
}

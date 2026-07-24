import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_file_decoder.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';

final class MergeKeychainManifestFilePayloadsUsecase {
  final KeychainManifestFileDecoder _codec;
  final ParseKeychainManifestFileUsecase _parseManifest;

  const MergeKeychainManifestFilePayloadsUsecase({
    required this._codec,
    required this._parseManifest,
  });

  KeychainManifestFile execute({
    required String localPayload,
    required String remotePayload,
    required String expectedParentFingerprint,
    required int generatedAt,
  }) {
    final local = _codec.decode(localPayload);
    final remote = _codec.decode(remotePayload);
    _parseManifest.executeFile(
      local,
      expectedParentFingerprint: expectedParentFingerprint,
      allowEmpty: true,
    );
    _parseManifest.executeFile(
      remote,
      expectedParentFingerprint: expectedParentFingerprint,
      allowEmpty: true,
    );

    final entries = <String, KeychainManifestFileEntry>{
      for (final entry in remote.entries) entry.entryId: entry,
    };
    for (final entry in local.entries) {
      final existing = entries[entry.entryId];
      entries[entry.entryId] = existing == null
          ? entry
          : _mergeEntry(existing, entry);
    }
    if (_sameEntries(remote.entries, entries.values)) return remote;

    final sortedEntries = entries.values.toList(growable: false)
      ..sort((left, right) {
        final path = left.bip85DerivationPath.compareTo(
          right.bip85DerivationPath,
        );
        return path != 0 ? path : left.entryId.compareTo(right.entryId);
      });
    return KeychainManifestFile(
      parentFingerprint: expectedParentFingerprint,
      generatedAt: generatedAt,
      entries: sortedEntries,
    );
  }

  KeychainManifestFileEntry _mergeEntry(
    KeychainManifestFileEntry first,
    KeychainManifestFileEntry second,
  ) {
    if (first.parentFingerprint != second.parentFingerprint ||
        first.bip85DerivationPath != second.bip85DerivationPath ||
        first.reservationId != second.reservationId ||
        first.entryType != second.entryType ||
        first.ownerFeature != second.ownerFeature ||
        first.bip85Application != second.bip85Application ||
        first.bip85Index != second.bip85Index) {
      throw KeychainManifestEntryConflictException(
        'remote manifest entry conflicts with local inventory',
      );
    }

    final materializations =
        <String, KeychainManifestFileWalletMaterialization>{
          for (final item in first.materializations) item.walletId: item,
        };
    for (final item in second.materializations) {
      final existing = materializations[item.walletId];
      if (existing != null &&
          (existing.entryId != item.entryId ||
              existing.childSeedFingerprint != item.childSeedFingerprint ||
              existing.network != item.network ||
              existing.scriptType != item.scriptType)) {
        throw KeychainManifestEntryConflictException(
          'remote wallet materialization conflicts with local inventory',
        );
      }
      materializations[item.walletId] = existing == null
          ? item
          : KeychainManifestFileWalletMaterialization(
              walletId: existing.walletId,
              entryId: existing.entryId,
              childSeedFingerprint: existing.childSeedFingerprint,
              network: existing.network,
              scriptType: existing.scriptType,
              createdAt: _earlier(existing.createdAt, item.createdAt),
              updatedAt: _later(existing.updatedAt, item.updatedAt),
            );
    }
    final sortedMaterializations =
        materializations.values.toList(growable: false)..sort((left, right) {
          final network = left.network.compareTo(right.network);
          return network != 0
              ? network
              : left.walletId.compareTo(right.walletId);
        });
    return KeychainManifestFileEntry(
      parentFingerprint: first.parentFingerprint,
      bip85DerivationPath: first.bip85DerivationPath,
      reservationId: first.reservationId,
      entryType: first.entryType,
      ownerFeature: first.ownerFeature,
      bip85Application: first.bip85Application,
      bip85Index: first.bip85Index,
      createdAt: _earlier(first.createdAt, second.createdAt),
      updatedAt: _later(first.updatedAt, second.updatedAt),
      materializations: sortedMaterializations,
    );
  }

  bool _sameEntries(
    List<KeychainManifestFileEntry> current,
    Iterable<KeychainManifestFileEntry> merged,
  ) {
    final mergedById = {for (final entry in merged) entry.entryId: entry};
    if (current.length != mergedById.length) return false;
    return current.every(
      (entry) => _sameEntry(entry, mergedById[entry.entryId]),
    );
  }

  bool _sameEntry(
    KeychainManifestFileEntry current,
    KeychainManifestFileEntry? merged,
  ) {
    if (merged == null ||
        current.entryId != merged.entryId ||
        current.parentFingerprint != merged.parentFingerprint ||
        current.bip85DerivationPath != merged.bip85DerivationPath ||
        current.reservationId != merged.reservationId ||
        current.entryType != merged.entryType ||
        current.ownerFeature != merged.ownerFeature ||
        current.bip85Application != merged.bip85Application ||
        current.bip85Index != merged.bip85Index ||
        current.createdAt != merged.createdAt ||
        current.updatedAt != merged.updatedAt ||
        current.materializations.length != merged.materializations.length) {
      return false;
    }
    final mergedByWallet = {
      for (final item in merged.materializations) item.walletId: item,
    };
    return current.materializations.every((item) {
      final other = mergedByWallet[item.walletId];
      return other != null &&
          item.entryId == other.entryId &&
          item.childSeedFingerprint == other.childSeedFingerprint &&
          item.network == other.network &&
          item.scriptType == other.scriptType &&
          item.createdAt == other.createdAt &&
          item.updatedAt == other.updatedAt;
    });
  }

  int _earlier(int first, int second) => first < second ? first : second;

  int _later(int first, int second) => first > second ? first : second;
}

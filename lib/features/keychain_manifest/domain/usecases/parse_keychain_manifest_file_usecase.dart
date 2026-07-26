import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_file_decoder.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_reservation_support.dart';

class ParseKeychainManifestFileUsecase {
  final KeychainManifestFileDecoder _codec;
  final Bip85RegistryFacade _bip85Registry;

  const ParseKeychainManifestFileUsecase({
    required this._codec,
    required this._bip85Registry,
  });

  KeychainManifestImportPlan execute(
    String payload, {
    required String expectedParentFingerprint,
    bool allowEmpty = false,
  }) {
    final manifestFile = _codec.decode(payload);
    return executeFile(
      manifestFile,
      expectedParentFingerprint: expectedParentFingerprint,
      allowEmpty: allowEmpty,
    );
  }

  KeychainManifestImportPlan executeFile(
    KeychainManifestFile manifestFile, {
    required String expectedParentFingerprint,
    bool allowEmpty = false,
  }) {
    // The fingerprint gate runs before any registry validation: a manifest
    // for another parent seed must be refused regardless of its contents.
    final normalizedExpectedParentFingerprint =
        KeychainManifestFingerprint.normalize(expectedParentFingerprint);
    if (manifestFile.parentFingerprint != normalizedExpectedParentFingerprint) {
      throw KeychainManifestFileParseException(
        reason: KeychainManifestFileParseFailureReason.wrongParentFingerprint,
      );
    }
    // Mirrors the export gate: an empty plan carries no recoverable
    // inventory, so returning one silently must be an explicit caller
    // decision.
    if (manifestFile.entries.isEmpty && !allowEmpty) {
      throw KeychainManifestEmptyInventoryException();
    }
    final entries = manifestFile.entries
        .map(_entryIntent)
        .toList(growable: false);
    return KeychainManifestImportPlan(
      parentFingerprint: manifestFile.parentFingerprint,
      entries: entries,
    );
  }

  KeychainManifestImportEntryIntent _entryIntent(
    KeychainManifestFileEntry entry,
  ) {
    final reservation = _bip85Registry.reservationById(entry.reservationId);
    final isDynamicNostr =
        entry.reservationId == _bip85Registry.nostrUserKeyReservationId &&
        _bip85Registry.isNostrUserKeyPath(entry.bip85DerivationPath);
    if (reservation == null && !isDynamicNostr) {
      throw KeychainManifestFileParseException(
        reason: KeychainManifestFileParseFailureReason.unknownReservation,
      );
    }
    if (!isDynamicNostr &&
        !reservation!.scope.matchesExactPath(entry.bip85DerivationPath)) {
      throw KeychainManifestFileParseException(
        reason: KeychainManifestFileParseFailureReason.invalidMetadata,
      );
    }
    final isWalletEntry = reservation is Bip85WalletSeedReservation;
    final isNostrEntry = reservation is Bip85KeyReservation || isDynamicNostr;
    if ((!isWalletEntry && !isNostrEntry) ||
        (isWalletEntry &&
            (!_supportsWalletManifestImport(reservation) ||
                entry.materializations.any(
                  (materialization) =>
                      materialization
                          is! KeychainManifestFileWalletMaterialization,
                ))) ||
        (isNostrEntry &&
            entry.materializations.any(
              (materialization) =>
                  materialization
                      is! KeychainManifestFileNostrKeyMaterialization,
            ))) {
      throw KeychainManifestFileParseException(
        reason: KeychainManifestFileParseFailureReason.invalidMetadata,
      );
    }
    final metadataMatches = isDynamicNostr
        ? entry.ownerFeature == 'nostr' &&
              entry.entryType == 'userGenerated' &&
              entry.bip85Application ==
                  _bip85Registry.nostrUserKeyApplication &&
              entry.bip85Index == _bip85Registry.nostrUserAccount
        : reservation!.owner.name == entry.ownerFeature &&
              reservation.purpose.name == entry.entryType &&
              reservation.application.number == entry.bip85Application &&
              (reservation is! Bip85WalletSeedReservation ||
                  reservation.walletIndex == entry.bip85Index);
    if (!metadataMatches) {
      throw KeychainManifestFileParseException(
        reason: KeychainManifestFileParseFailureReason.invalidMetadata,
      );
    }
    return KeychainManifestImportEntryIntent.fromFileEntry(
      entry,
      walletMaterializations: _walletMaterializations(entry),
      nostrKeyMaterializations: _nostrKeyMaterializations(entry),
    );
  }

  bool _supportsWalletManifestImport(Bip85Reservation reservation) {
    // Import plans cover every EXPORTABLE product (100/101/102) so the frozen
    // v1 format can round-trip all of them; recovery separately decides which
    // are materialized (R2-KC3/F1b, ruling A/B).
    return KeychainManifestReservationSupport.supportsV1Export(reservation);
  }

  List<KeychainManifestWalletMaterializationIntent> _walletMaterializations(
    KeychainManifestFileEntry entry,
  ) {
    // Duplicate entry ids and wallet ids are rejected by the
    // KeychainManifestFile entity when the payload is decoded, so every
    // materialization reaching this point is unique.
    return entry.materializations
        .whereType<KeychainManifestFileWalletMaterialization>()
        .map(
          (materialization) =>
              KeychainManifestWalletMaterializationIntent.fromFileMaterialization(
                entry: entry,
                materialization: materialization,
              ),
        )
        .toList(growable: false);
  }

  List<KeychainManifestNostrKeyMaterializationIntent> _nostrKeyMaterializations(
    KeychainManifestFileEntry entry,
  ) {
    return entry.materializations
        .whereType<KeychainManifestFileNostrKeyMaterialization>()
        .map(
          (materialization) =>
              KeychainManifestNostrKeyMaterializationIntent.fromFileMaterialization(
                entry: entry,
                materialization: materialization,
              ),
        )
        .toList(growable: false);
  }
}

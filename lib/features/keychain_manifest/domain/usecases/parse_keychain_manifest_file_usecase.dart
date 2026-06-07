import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_reservation_support.dart';

class ParseKeychainManifestFileUsecase {
  final Bip85RegistryFacade registry;

  const ParseKeychainManifestFileUsecase({
    this.registry = const Bip85RegistryFacade(),
  });

  KeychainManifestImportPlan execute(KeychainManifestFile manifestFile) {
    final entries = _entryIntents(manifestFile.entries);
    return KeychainManifestImportPlan(
      parentFingerprint: manifestFile.parentFingerprint,
      entries: entries,
    );
  }

  List<KeychainManifestImportEntryIntent> _entryIntents(
    List<KeychainManifestFileEntry> entries,
  ) {
    final entryIds = <String>{};
    final walletIds = <String>{};
    final intents = <KeychainManifestImportEntryIntent>[];
    for (final entry in entries) {
      if (!entryIds.add(entry.entryId)) {
        throw KeychainManifestFileParseException(
          reason: KeychainManifestFileParseFailureReason.duplicateEntry,
        );
      }
      final intent = _entryIntent(entry);
      for (final materialization in intent.walletMaterializations) {
        if (!walletIds.add(materialization.walletId)) {
          throw KeychainManifestFileParseException(
            reason: KeychainManifestFileParseFailureReason
                .duplicateWalletMaterialization,
          );
        }
      }
      intents.add(intent);
    }
    return intents;
  }

  KeychainManifestImportEntryIntent _entryIntent(
    KeychainManifestFileEntry entry,
  ) {
    final reservation = registry.reservationById(entry.reservationId);
    if (reservation == null) {
      throw KeychainManifestFileParseException(
        reason: KeychainManifestFileParseFailureReason.unknownReservation,
      );
    }
    if (!reservation.scope.matchesExactPath(entry.bip85DerivationPath)) {
      throw KeychainManifestFileParseException(
        reason: KeychainManifestFileParseFailureReason.invalidMetadata,
      );
    }
    if (!_supportsWalletManifestImport(reservation)) {
      throw KeychainManifestFileParseException(
        reason: KeychainManifestFileParseFailureReason.invalidMetadata,
      );
    }
    if (reservation.owner.name != entry.ownerFeature ||
        reservation.purpose.name != entry.entryType ||
        reservation.application.number != entry.bip85Application ||
        reservation.scope.segmentValue('index') != entry.bip85Index) {
      throw KeychainManifestFileParseException(
        reason: KeychainManifestFileParseFailureReason.invalidMetadata,
      );
    }
    return KeychainManifestImportEntryIntent.fromFileEntry(
      entry,
      walletMaterializations: _walletMaterializations(entry),
    );
  }

  bool _supportsWalletManifestImport(Bip85Reservation reservation) {
    return KeychainManifestReservationSupport.supportsV1WalletManifestFile(
      reservation,
    );
  }

  List<KeychainManifestWalletMaterializationIntent> _walletMaterializations(
    KeychainManifestFileEntry entry,
  ) {
    final materializations =
        <String, KeychainManifestWalletMaterializationIntent>{};
    for (final materialization in entry.materializations) {
      final intent =
          KeychainManifestWalletMaterializationIntent.fromFileMaterialization(
            entry: entry,
            materialization: materialization,
          );
      final materializationKey = _materializationKey(intent);
      final existing = materializations[materializationKey];
      if (existing == null) {
        materializations[materializationKey] = intent;
      } else {
        throw KeychainManifestFileParseException(
          reason: KeychainManifestFileParseFailureReason
              .duplicateWalletMaterialization,
        );
      }
    }
    return materializations.values.toList(growable: false);
  }

  String _materializationKey(
    KeychainManifestWalletMaterializationIntent intent,
  ) {
    return '${intent.entryId}:${intent.walletId}';
  }
}

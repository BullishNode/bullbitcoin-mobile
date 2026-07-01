export 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart'
    show
        KeychainManifestException,
        KeychainManifestExceptionType,
        KeychainManifestFileParseException,
        KeychainManifestFileParseFailureReason;
export 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart'
    show
        KeychainManifestImportPlan,
        KeychainManifestImportEntryIntent,
        KeychainManifestWalletMaterializationIntent;
export 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_import.dart'
    show KeychainManifestNostrImportResult, KeychainManifestNostrImportStatus;
export 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_reservation_support.dart'
    show
        KeychainManifestReservationSupport,
        KeychainManifestWalletMaterializationShape;
export 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart'
    show
        KeychainManifestReservedDerivationRequest,
        KeychainManifestWalletMaterializationRequest;

import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/fetch_keychain_manifest_nostr_import_plan_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/publish_keychain_manifest_nostr_event_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';

class KeychainManifestFacade {
  static const _manifestFileCodec = KeychainManifestFileCodec();

  final RecordKeychainManifestEntryUsecase _recordEntry;
  final BuildKeychainManifestFileUsecase _buildManifestFile;
  final ParseKeychainManifestFileUsecase _parseManifestFile;
  final PublishKeychainManifestNostrEventUsecase _publishNostrEvent;
  final FetchKeychainManifestNostrImportPlanUsecase _fetchNostrImportPlan;

  KeychainManifestFacade({
    required this._recordEntry,
    required this._buildManifestFile,
    required this._parseManifestFile,
    required PublishKeychainManifestNostrEventUsecase publishNostrEvent,
    required this._fetchNostrImportPlan,
    // ignore: prefer_initializing_formals
  }) : _publishNostrEvent = publishNostrEvent;

  Future<void> recordReservedDerivation(
    KeychainManifestReservedDerivationRequest request, {
    DateTime? now,
  }) async {
    try {
      await _recordEntry.execute(request, now: now);
    } catch (e) {
      throw KeychainManifestException.fromInternal(e);
    }
  }

  Future<KeychainManifestFilePayload> buildManifestFilePayload(
    String parentFingerprint, {
    bool allowEmpty = false,
    DateTime? now,
  }) async {
    try {
      final manifestFile = await _buildManifestFile.execute(
        parentFingerprint,
        now: now,
      );
      if (manifestFile.entries.isEmpty && !allowEmpty) {
        throw KeychainManifestEmptyInventoryException();
      }
      return KeychainManifestFilePayload._(
        payload: _manifestFileCodec.encode(manifestFile),
        entryCount: manifestFile.entries.length,
        materializationCount: manifestFile.entries.fold<int>(
          0,
          (count, entry) => count + entry.materializations.length,
        ),
        generatedAt: manifestFile.generatedAt,
        inventoryUpdatedAt: manifestFile.inventoryUpdatedAt,
      );
    } catch (e) {
      throw KeychainManifestException.fromInternal(e);
    }
  }

  KeychainManifestImportPlan parseManifestFilePayload(
    String payload, {
    required String expectedParentFingerprint,
  }) {
    try {
      final manifestFile = _manifestFileCodec.decode(payload);
      final normalizedExpectedParentFingerprint =
          KeychainManifestFingerprint.normalize(expectedParentFingerprint);
      if (manifestFile.parentFingerprint !=
          normalizedExpectedParentFingerprint) {
        throw KeychainManifestFileParseException(
          reason: KeychainManifestFileParseFailureReason.wrongParentFingerprint,
        );
      }
      return _parseManifestFile.execute(manifestFile);
    } catch (e) {
      throw KeychainManifestException.fromInternal(e);
    }
  }

  Future<void> publishEncryptedNostrSnapshot({
    required String parentFingerprint,
    required String xprvBase58,
    required List<String> relayUrls,
    DateTime? now,
  }) async {
    try {
      await _publishNostrEvent.execute(
        parentFingerprint: parentFingerprint,
        xprvBase58: xprvBase58,
        relayUrls: relayUrls,
        now: now,
      );
    } catch (e) {
      throw KeychainManifestException.fromInternal(e);
    }
  }

  Future<KeychainManifestNostrImportResult> fetchEncryptedNostrImportPlan({
    required String parentFingerprint,
    required String xprvBase58,
    required List<String> relayUrls,
  }) async {
    try {
      return await _fetchNostrImportPlan.execute(
        parentFingerprint: parentFingerprint,
        xprvBase58: xprvBase58,
        relayUrls: relayUrls,
      );
    } catch (e) {
      throw KeychainManifestException.fromInternal(e);
    }
  }
}

class KeychainManifestFilePayload {
  final String payload;
  final int entryCount;
  final int materializationCount;
  final int generatedAt;
  final int inventoryUpdatedAt;

  bool get isEmpty => entryCount == 0;

  const KeychainManifestFilePayload._({
    required this.payload,
    required this.entryCount,
    required this.materializationCount,
    required this.generatedAt,
    required this.inventoryUpdatedAt,
  });
}

import 'dart:async';

export 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart'
    show
        KeychainManifestDuplicateException,
        KeychainManifestEntryConflictException,
        KeychainManifestException,
        KeychainManifestExceptionType,
        KeychainManifestFileParseException,
        KeychainManifestFileParseFailureReason,
        KeychainManifestGenericException,
        KeychainManifestInvalidEntryException,
        KeychainManifestReservationMismatchException,
        KeychainManifestUnsupportedVersionException;
export 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart'
    show
        KeychainManifestImportPlan,
        KeychainManifestImportEntryIntent,
        KeychainManifestWalletMaterializationIntent;
export 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_reservation_support.dart'
    show KeychainManifestReservationSupport;
export 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart'
    show
        KeychainManifestReservedDerivationRequest,
        KeychainManifestWalletMaterializationRequest;

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/merge_keychain_manifest_file_payloads_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';

class KeychainManifestFacade {
  static const _manifestFileCodec = KeychainManifestFileCodec();

  final RecordKeychainManifestEntryUsecase _recordEntry;
  final BuildKeychainManifestFileUsecase _buildManifestFile;
  final MergeKeychainManifestFilePayloadsUsecase _mergeManifestFiles;
  final ParseKeychainManifestFileUsecase _parseManifestFile;
  final StreamController<void> _committedChanges =
      StreamController<void>.broadcast();

  KeychainManifestFacade({
    required this._recordEntry,
    required this._buildManifestFile,
    required this._mergeManifestFiles,
    required this._parseManifestFile,
  });

  Future<void> recordReservedDerivation(
    KeychainManifestReservedDerivationRequest request, {
    DateTime? now,
  }) async {
    await _recordDerivation(request, now: now);
    _committedChanges.add(null);
  }

  /// Records inventory reconstructed from an authenticated remote backup.
  ///
  /// This semantic boundary lets the later backup coordinator exclude recovery
  /// writes from automatic publication. Recovery must never turn a remote read
  /// into a remote write.
  Future<void> recordRecoveredDerivation(
    KeychainManifestReservedDerivationRequest request, {
    DateTime? now,
  }) => _recordDerivation(request, now: now);

  /// Emits after a normal local inventory transaction commits.
  ///
  /// Recovery-originated records are deliberately excluded so restoring a
  /// remote backup can never schedule a publication as a side effect.
  Stream<void> watchCommittedChanges() => _committedChanges.stream;

  Future<void> close() => _committedChanges.close();

  Future<void> _recordDerivation(
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
      return _toPayload(manifestFile);
    } catch (e, stack) {
      if (e is! KeychainManifestException) {
        log.warning(
          'Keychain manifest file build failed',
          error: e,
          trace: stack,
        );
      }
      throw KeychainManifestException.fromInternal(e);
    }
  }

  KeychainManifestFilePayload mergeManifestFilePayloads({
    required String localPayload,
    required String remotePayload,
    required String expectedParentFingerprint,
    required int generatedAt,
  }) {
    try {
      return _toPayload(
        _mergeManifestFiles.execute(
          localPayload: localPayload,
          remotePayload: remotePayload,
          expectedParentFingerprint: expectedParentFingerprint,
          generatedAt: generatedAt,
        ),
      );
    } on Exception catch (e, stack) {
      if (e is! KeychainManifestException) {
        log.warning('Keychain manifest merge failed', error: e, trace: stack);
      }
      throw KeychainManifestException.fromInternal(e);
    }
  }

  /// Validates a manifest payload and returns its canonical wire encoding.
  ///
  /// Cross-feature containers use this to reject reordered or unknown
  /// manifest fields rather than hashing or overwriting non-canonical content.
  static String canonicalizeManifestFilePayload(String payload) {
    try {
      return _manifestFileCodec.encode(_manifestFileCodec.decode(payload));
    } catch (e, stack) {
      if (e is! KeychainManifestException) {
        log.warning(
          'Keychain manifest canonicalization failed',
          error: e,
          trace: stack,
        );
      }
      throw KeychainManifestException.fromInternal(e);
    }
  }

  /// Parses a serialized manifest file into an import plan.
  ///
  /// Throws a [KeychainManifestException]. Consumers MUST distinguish the
  /// unsupported-version case: [KeychainManifestExceptionType.unsupportedFileVersion]
  /// means the backup exists but was written by a newer app version and MUST be
  /// shown as "update the app", never as "no backup found" (KC-2). Use
  /// `toTranslated` for the user-facing copy.
  KeychainManifestImportPlan parseManifestFilePayload(
    String payload, {
    required String expectedParentFingerprint,
    bool allowEmpty = false,
  }) {
    try {
      return _parseManifestFile.execute(
        payload,
        expectedParentFingerprint: expectedParentFingerprint,
        allowEmpty: allowEmpty,
      );
    } catch (e, stack) {
      if (e is! KeychainManifestException) {
        log.warning(
          'Keychain manifest file parse failed',
          error: e,
          trace: stack,
        );
      }
      throw KeychainManifestException.fromInternal(e);
    }
  }

  KeychainManifestFilePayload _toPayload(KeychainManifestFile manifestFile) {
    return KeychainManifestFilePayload._(
      payload: _manifestFileCodec.encode(manifestFile),
      parentFingerprint: manifestFile.parentFingerprint,
      entryCount: manifestFile.entryCount,
      materializationCount: manifestFile.materializationCount,
      generatedAt: manifestFile.generatedAt,
      inventoryUpdatedAt: manifestFile.inventoryUpdatedAt,
    );
  }
}

class KeychainManifestFilePayload {
  final String payload;
  final String parentFingerprint;
  final int entryCount;
  final int materializationCount;
  final int generatedAt;
  final int inventoryUpdatedAt;

  bool get isEmpty => entryCount == 0;

  const KeychainManifestFilePayload._({
    required this.payload,
    required this.parentFingerprint,
    required this.entryCount,
    required this.materializationCount,
    required this.generatedAt,
    required this.inventoryUpdatedAt,
  });
}

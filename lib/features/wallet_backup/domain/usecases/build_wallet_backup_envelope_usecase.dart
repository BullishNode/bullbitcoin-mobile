// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_envelope.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_section_provider.dart';
import 'package:meta/meta.dart';

final class BuildWalletBackupEnvelopeUsecase {
  final KeychainManifestFacade _keychainManifest;
  final Clock _clock;
  final WalletMetadataBackupSectionProvider? _metadata;

  const BuildWalletBackupEnvelopeUsecase(
    this._keychainManifest,
    this._clock, {
    WalletMetadataBackupSectionProvider? metadata,
  }) : _metadata = metadata;

  @useResult
  Future<Result<WalletBackupEnvelope, WalletBackupFailure>> execute({
    required String parentFingerprint,
    String? remoteMetadataPayload,
    bool allowEmpty = false,
  }) async {
    final now = _clock.nowUtc();
    try {
      final manifest = await _keychainManifest.buildManifestFilePayload(
        parentFingerprint,
        allowEmpty: allowEmpty,
        now: now,
      );
      final section = WalletBackupManifestSection(
        payload: manifest.payload,
        parentFingerprint: manifest.parentFingerprint,
      );
      final metadataResult = _metadata == null
          ? null
          : await _metadata.composeSection(
              parentFingerprint: parentFingerprint,
              remotePayload: remoteMetadataPayload,
            );
      if (metadataResult case Err(:final failure)) {
        return Err(WalletBackupManifestFailure(failure.runtimeType.toString()));
      }
      final metadataPayload = switch (metadataResult) {
        null => null,
        Ok(:final value) => value,
        Err() => null,
      };
      return Ok(
        WalletBackupEnvelope(
          parentFingerprint: parentFingerprint,
          createdAt: now.millisecondsSinceEpoch ~/ 1000,
          manifest: section,
          metadata: metadataPayload == null
              ? null
              : WalletBackupMetadataSection(
                  payload: metadataPayload,
                  parentFingerprint: parentFingerprint,
                ),
        ),
      );
    } on KeychainManifestException catch (error) {
      return Err(WalletBackupManifestFailure(error.runtimeType.toString()));
    } on Exception catch (error) {
      return Err(WalletBackupUnexpectedFailure(error.runtimeType.toString()));
    }
  }
}

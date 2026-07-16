import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_envelope.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:meta/meta.dart';

final class BuildWalletBackupEnvelopeUsecase {
  final KeychainManifestFacade _keychainManifest;
  final Clock _clock;

  const BuildWalletBackupEnvelopeUsecase(this._keychainManifest, this._clock);

  @useResult
  Future<Result<WalletBackupEnvelope, WalletBackupFailure>> execute({
    required String parentFingerprint,
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
      return Ok(
        WalletBackupEnvelope(
          parentFingerprint: parentFingerprint,
          createdAt: now.millisecondsSinceEpoch ~/ 1000,
          manifest: section,
        ),
      );
    } on KeychainManifestException catch (error) {
      return Err(WalletBackupManifestFailure(error.runtimeType.toString()));
    } on Exception catch (error) {
      return Err(WalletBackupUnexpectedFailure(error.runtimeType.toString()));
    }
  }
}

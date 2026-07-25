import 'package:bb_mobile/core/utils/result.dart';
// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_encryption.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_envelope.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_encryption_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/build_wallet_backup_envelope_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_encryption_key_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/derive_wallet_backup_signer_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_section_provider.dart';
import 'package:meta/meta.dart';

final class SyncWalletBackupUsecase {
  final BuildWalletBackupEnvelopeUsecase _buildEnvelope;
  final DeriveWalletBackupEncryptionKeyUsecase _deriveEncryptionKey;
  final WalletBackupEncryptionRepository _encryption;
  final WalletBackupRemoteRepository _remote;
  final KeychainManifestFacade _keychainManifest;
  final DeriveWalletBackupSignerUsecase _deriveSigner;
  final WalletMetadataBackupSectionProvider? _metadata;

  const SyncWalletBackupUsecase({
    required this._buildEnvelope,
    required this._deriveEncryptionKey,
    required this._encryption,
    required this._remote,
    required this._keychainManifest,
    required this._deriveSigner,
    WalletMetadataBackupSectionProvider? metadata,
  }) : _metadata = metadata;

  @useResult
  Future<Result<WalletBackupSyncResult, WalletBackupFailure>> execute({
    required String parentFingerprint,
    required String xprvBase58,
  }) async {
    final keyResult = _deriveEncryptionKey.execute(
      xprvBase58: xprvBase58,
      expectedParentFingerprint: parentFingerprint,
    );
    final WalletBackupEncryptionKey key;
    switch (keyResult) {
      case Ok(:final value):
        key = value;
      case Err(:final failure):
        return Err(failure);
    }

    final localResult = await _buildEnvelope.execute(
      parentFingerprint: parentFingerprint,
      allowEmpty: true,
    );
    final WalletBackupEnvelope local;
    switch (localResult) {
      case Ok(:final value):
        local = value;
      case Err(:final failure):
        return Err(failure);
    }

    final signerResult = _deriveSigner.execute(
      xprvBase58: xprvBase58,
      expectedParentFingerprint: parentFingerprint,
    );
    final WalletBackupSigner signer;
    switch (signerResult) {
      case Ok(:final value):
        signer = value;
      case Err(:final failure):
        return Err(failure);
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final fetchResult = await _remote.fetch(signer);
      final WalletBackupRemoteHead current;
      switch (fetchResult) {
        case Ok(:final value):
          current = value;
        case Err(:final failure):
          return Err(failure);
      }

      final candidateResult = await _composeCandidate(
        local: local,
        current: current,
        key: key,
        parentFingerprint: parentFingerprint,
      );
      final _ComposedBackup composed;
      switch (candidateResult) {
        case Ok(:final value):
          composed = value;
        case Err(:final failure):
          return Err(failure);
      }

      if (composed.matchesRemote) {
        final hashResult = _encryption.contentHash(composed.envelope);
        return hashResult.map(
          (hash) => WalletBackupSyncResult(
            checkpoint: WalletBackupRemoteCheckpoint(
              generation: current.generation,
              etag: current.etag!,
            ),
            contentHash: hash,
          ),
        );
      }

      final hashResult = _encryption.contentHash(composed.envelope);
      final String contentHash;
      switch (hashResult) {
        case Ok(:final value):
          contentHash = value;
        case Err(:final failure):
          return Err(failure);
      }
      final encryptionResult = _encryption.encrypt(
        envelope: composed.envelope,
        key: key,
      );
      final WalletBackupCiphertext ciphertext;
      switch (encryptionResult) {
        case Ok(:final value):
          ciphertext = value;
        case Err(:final failure):
          return Err(failure);
      }

      final storeResult = await _remote.store(
        signer: signer,
        current: current,
        ciphertext: ciphertext,
      );
      switch (storeResult) {
        case Ok(:final value):
          return Ok(
            WalletBackupSyncResult(checkpoint: value, contentHash: contentHash),
          );
        case Err(failure: WalletBackupHeadConflictFailure()) when attempt == 0:
          continue;
        case Err(:final failure):
          return Err(failure);
      }
    }
    return const Err(WalletBackupUnexpectedFailure('sync attempts exhausted'));
  }

  Future<Result<_ComposedBackup, WalletBackupFailure>> _composeCandidate({
    required WalletBackupEnvelope local,
    required WalletBackupRemoteHead current,
    required WalletBackupEncryptionKey key,
    required String parentFingerprint,
  }) async {
    final ciphertext = current.ciphertext;
    if (ciphertext == null) {
      return Ok(_ComposedBackup(envelope: local, matchesRemote: false));
    }

    final decrypted = _encryption.decrypt(
      ciphertext: ciphertext,
      key: key,
      expectedParentFingerprint: parentFingerprint,
    );
    final WalletBackupEnvelope remoteEnvelope;
    switch (decrypted) {
      case Ok(:final value):
        remoteEnvelope = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (!remoteEnvelope.manifest.isCanonical) {
      return const Err(
        WalletBackupInvalidEnvelopeFailure(
          'remote keychain manifest section is not canonical',
        ),
      );
    }

    try {
      final merged = _keychainManifest.mergeManifestFilePayloads(
        localPayload: local.manifest.payload,
        remotePayload: remoteEnvelope.manifest.payload,
        expectedParentFingerprint: parentFingerprint,
        generatedAt: local.createdAt,
      );
      final metadataResult = _metadata == null
          ? null
          : await _metadata.composeSection(
              parentFingerprint: parentFingerprint,
              remotePayload: remoteEnvelope.metadata?.payload,
            );
      if (metadataResult case Err(:final failure)) {
        return Err(WalletBackupManifestFailure(failure.runtimeType.toString()));
      }
      final metadataPayload = switch (metadataResult) {
        null => remoteEnvelope.metadata?.payload,
        Ok(:final value) => value,
        Err() => null,
      };
      if (merged.payload == remoteEnvelope.manifest.payload &&
          metadataPayload == remoteEnvelope.metadata?.payload) {
        return Ok(
          _ComposedBackup(envelope: remoteEnvelope, matchesRemote: true),
        );
      }
      return Ok(
        _ComposedBackup(
          envelope: WalletBackupEnvelope(
            parentFingerprint: parentFingerprint,
            createdAt: local.createdAt,
            manifest: WalletBackupManifestSection(
              payload: merged.payload,
              parentFingerprint: merged.parentFingerprint,
            ),
            metadata: metadataPayload == null
                ? null
                : WalletBackupMetadataSection(
                    payload: metadataPayload,
                    parentFingerprint: parentFingerprint,
                  ),
          ),
          matchesRemote: false,
        ),
      );
    } on KeychainManifestException catch (error) {
      return Err(WalletBackupManifestFailure(error.runtimeType.toString()));
    } on Exception catch (error) {
      return Err(WalletBackupUnexpectedFailure(error.runtimeType.toString()));
    }
  }
}

final class _ComposedBackup {
  final WalletBackupEnvelope envelope;
  final bool matchesRemote;

  const _ComposedBackup({required this.envelope, required this.matchesRemote});
}

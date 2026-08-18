// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/core/nostr/nostr_key_materialization_recorder.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:convert/convert.dart';

class NostrIdentityFacade {
  final DeriveNostrIdentityHandleUsecase _deriveHandle;
  final NostrKeyMaterializationRecorder? _recorder;

  const NostrIdentityFacade(
    this._deriveHandle, {
    NostrKeyMaterializationRecorder? recorder,
  }) : _recorder = recorder;

  String deriveWalletBackupPublicKeyFromXprv(String xprvBase58) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.walletBackup,
    );
    _record(
      xprvBase58: xprvBase58,
      reservationId: 'nostr_wallet_backup_key',
      publicKeyHex: handle.publicKeyHex,
    );
    return handle.publicKeyHex;
  }

  String deriveBullnymServerAuthPublicKeyFromXprv(String xprvBase58) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.bullnymServerAuth,
    );
    _record(
      xprvBase58: xprvBase58,
      reservationId: 'nostr_bullnym_server_auth_key',
      publicKeyHex: handle.publicKeyHex,
    );
    return handle.publicKeyHex;
  }

  String deriveBullnymNip05VerificationPublicKeyFromXprv(String xprvBase58) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.bullnymNip05Verification,
    );
    _record(
      xprvBase58: xprvBase58,
      reservationId: 'nostr_nip05_public_nym_verification_key',
      publicKeyHex: handle.publicKeyHex,
    );
    return handle.publicKeyHex;
  }

  String signWalletBackupHashFromXprv({
    required String xprvBase58,
    required String messageHashHex,
  }) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.walletBackup,
    );
    final signature = handle.signHashHex(messageHashHex);
    _record(
      xprvBase58: xprvBase58,
      reservationId: 'nostr_wallet_backup_key',
      publicKeyHex: handle.publicKeyHex,
    );
    return signature;
  }

  String signBullnymServerAuthHashFromXprv({
    required String xprvBase58,
    required String messageHashHex,
  }) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.bullnymServerAuth,
    );
    final signature = handle.signHashHex(messageHashHex);
    _record(
      xprvBase58: xprvBase58,
      reservationId: 'nostr_bullnym_server_auth_key',
      publicKeyHex: handle.publicKeyHex,
    );
    return signature;
  }

  void _record({
    required String xprvBase58,
    required String reservationId,
    required String publicKeyHex,
  }) {
    final recorder = _recorder;
    if (recorder == null) return;
    final reservation = _deriveHandle.registry.reservationById(reservationId);
    if (reservation == null) return;
    final parentFingerprint = hex.encode(
      bip32.Bip32Keys.fromBase58(xprvBase58).fingerprint,
    );
    unawaited(
      recorder
          .record(
            reservationId: reservationId,
            derivationPath: reservation.scope.exactPath,
            publicKeyHex: publicKeyHex,
            parentFingerprint: parentFingerprint,
          )
          .catchError((Object error, StackTrace stackTrace) {
            log.warning(
              'Nostr key materialization recording failed',
              error: error.runtimeType,
              trace: stackTrace,
            );
          }),
    );
  }
}

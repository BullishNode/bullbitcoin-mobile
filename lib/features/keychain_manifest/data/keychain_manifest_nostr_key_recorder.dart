// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/nostr/nostr_key_materialization_recorder.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';

final class KeychainManifestNostrKeyRecorder
    implements NostrKeyMaterializationRecorder {
  final Bip85RegistryFacade _registry;
  final Future<void> Function(KeychainManifestNostrKeyRequest request) _record;

  const KeychainManifestNostrKeyRecorder({
    required Bip85RegistryFacade registry,
    required Future<void> Function(KeychainManifestNostrKeyRequest request)
    record,
  }) : _registry = registry,
       _record = record;

  @override
  Future<void> record({
    required String reservationId,
    required String derivationPath,
    required String publicKeyHex,
    required String parentFingerprint,
  }) async {
    final reservation = _registry.reservationById(reservationId);
    if (reservation is! Bip85KeyReservation) return;
    await _record(
      KeychainManifestNostrKeyRequest(
        reservationId: reservationId,
        parentFingerprint: parentFingerprint,
        derivationPath: derivationPath,
        publicKeyHex: publicKeyHex,
        keyKind: KeychainManifestNostrKeyKind.reserved,
        purpose: reservation.deterministicAlias,
      ),
    );
  }
}

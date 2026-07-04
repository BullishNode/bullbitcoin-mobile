import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/derive_keychain_manifest_nostr_encryption_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';

class FetchKeychainManifestNostrImportPlanUsecase {
  static const _manifestFileCodec = KeychainManifestFileCodec();

  final KeychainManifestNostrRelayRepository relayRepository;
  final KeychainManifestNostrEncryptionRepository encryptionRepository;
  final ParseKeychainManifestFileUsecase parseManifestFile;
  final DeriveKeychainManifestNostrEncryptionKeyUsecase deriveEncryptionKey;
  final NostrIdentityFacade nostrIdentity;

  const FetchKeychainManifestNostrImportPlanUsecase({
    required this.relayRepository,
    required this.encryptionRepository,
    required this.parseManifestFile,
    required this.nostrIdentity,
    this.deriveEncryptionKey =
        const DeriveKeychainManifestNostrEncryptionKeyUsecase(),
  });

  Future<KeychainManifestNostrImportResult> execute({
    required String parentFingerprint,
    required String xprvBase58,
    required List<String> relayUrls,
  }) async {
    try {
      final normalizedParentFingerprint = KeychainManifestFingerprint.normalize(
        parentFingerprint,
      );
      final normalizedRelayUrls = relayUrls
          .map(KeychainManifestNostrRelayUrl.new)
          .toList(growable: false);
      if (normalizedRelayUrls.isEmpty) {
        throw KeychainManifestInvalidEntryException(
          'at least one keychain manifest Nostr relay URL is required',
        );
      }
      final authorPublicKeyHex = nostrIdentity
          .deriveWalletManifestPublicKeyFromXprv(xprvBase58);
      final fetchResult = await relayRepository.fetchManifestEvents(
        authorPublicKeyHex: authorPublicKeyHex,
        relayUrls: normalizedRelayUrls,
      );
      if (!fetchResult.contactedAnyRelay) {
        return const KeychainManifestNostrImportResult.relaysUnavailable();
      }
      if (fetchResult.events.isEmpty) {
        return const KeychainManifestNostrImportResult.noManifestFound();
      }
      final encryptionKey = deriveEncryptionKey.execute(
        xprvBase58: xprvBase58,
        expectedParentFingerprint: normalizedParentFingerprint,
      );

      // Decrypt/parse every authenticated candidate. An empty or wrong-owner
      // manifest is non-recoverable and simply skipped (it can never outrank a
      // populated one); a decryptable-newer or authentic-but-unreadable payload
      // is a "failed" candidate that must fail loud, not masquerade as absence.
      final recoverable = <_RecoverableCandidate>[];
      int? newestFailedEventCreatedAt;
      for (final event in fetchResult.events) {
        final candidate = _classifyCandidate(
          event: event,
          encryptionKey: encryptionKey,
          expectedParentFingerprint: normalizedParentFingerprint,
        );
        switch (candidate) {
          case _BuiltCandidate(:final importPlan, :final inventoryUpdatedAt):
            recoverable.add(
              _RecoverableCandidate(
                importPlan: importPlan,
                inventoryUpdatedAt: inventoryUpdatedAt,
                eventCreatedAt: event.createdAt,
              ),
            );
          case _FailedCandidate():
            newestFailedEventCreatedAt =
                (newestFailedEventCreatedAt == null ||
                    event.createdAt > newestFailedEventCreatedAt)
                ? event.createdAt
                : newestFailedEventCreatedAt;
          case _NonRecoverableCandidate():
            break;
        }
      }

      if (recoverable.isEmpty) {
        // KC2b: an authentic event that failed to decrypt/parse under our own
        // key is overwhelmingly a format newer than this app - "update the app",
        // never "no backup". Only an all-empty/wrong-owner set is genuinely
        // non-recoverable.
        return newestFailedEventCreatedAt != null
            ? const KeychainManifestNostrImportResult.unsupportedNewerManifest()
            : const KeychainManifestNostrImportResult.noRecoverableManifest();
      }

      // KC1: select the best plan by authenticated recency
      // (inventoryUpdatedAt desc, event.createdAt desc) - inventoryUpdatedAt is
      // inside the encrypted+signed payload, so the selection key is
      // tamper-authenticated ([F]).
      recoverable.sort((a, b) {
        final byInventory = b.inventoryUpdatedAt.compareTo(
          a.inventoryUpdatedAt,
        );
        if (byInventory != 0) return byInventory;
        return b.eventCreatedAt.compareTo(a.eventCreatedAt);
      });
      final best = recoverable.first;

      if (newestFailedEventCreatedAt != null &&
          newestFailedEventCreatedAt > best.eventCreatedAt) {
        return KeychainManifestNostrImportResult.newestFailedOlderRecoverable(
          importPlan: best.importPlan,
          selectedEventCreatedAt: best.eventCreatedAt,
          newestEventCreatedAt: newestFailedEventCreatedAt,
        );
      }
      return KeychainManifestNostrImportResult.latestRecoverable(
        importPlan: best.importPlan,
        eventCreatedAt: best.eventCreatedAt,
      );
    } on KeychainManifestException {
      rethrow;
    } catch (e) {
      throw KeychainManifestGenericException(cause: e);
    }
  }

  _CandidateOutcome _classifyCandidate({
    required KeychainManifestNostrSignedEvent event,
    required KeychainManifestNostrEncryptionKey encryptionKey,
    required String expectedParentFingerprint,
  }) {
    final KeychainManifestNostrSnapshot snapshot;
    try {
      snapshot = encryptionRepository.decryptSnapshot(
        ciphertext: KeychainManifestNostrCiphertext(event.encryptedContent),
        key: encryptionKey,
      );
    } on KeychainManifestException {
      // Undecryptable, non-ciphertext, or a newer inner version under our own
      // key: a "failed" (authentic-but-unreadable) candidate, not a skip.
      return const _FailedCandidate();
    }

    if (snapshot.manifestFile.parentFingerprint != expectedParentFingerprint) {
      return const _NonRecoverableCandidate();
    }
    if (snapshot.manifestFile.entries.isEmpty) {
      return const _NonRecoverableCandidate();
    }

    final KeychainManifestImportPlan importPlan;
    try {
      importPlan = parseManifestFile.execute(
        _manifestFileCodec.encode(snapshot.manifestFile),
        expectedParentFingerprint: expectedParentFingerprint,
        allowEmpty: false,
      );
    } on KeychainManifestException {
      return const _FailedCandidate();
    }
    return _BuiltCandidate(
      importPlan: importPlan,
      inventoryUpdatedAt: snapshot.manifestFile.inventoryUpdatedAt,
    );
  }
}

class _RecoverableCandidate {
  final KeychainManifestImportPlan importPlan;
  final int inventoryUpdatedAt;
  final int eventCreatedAt;

  const _RecoverableCandidate({
    required this.importPlan,
    required this.inventoryUpdatedAt,
    required this.eventCreatedAt,
  });
}

sealed class _CandidateOutcome {
  const _CandidateOutcome();
}

class _BuiltCandidate extends _CandidateOutcome {
  final KeychainManifestImportPlan importPlan;
  final int inventoryUpdatedAt;

  const _BuiltCandidate({
    required this.importPlan,
    required this.inventoryUpdatedAt,
  });
}

/// Authentic event that failed to decrypt/parse (newer version or unreadable).
class _FailedCandidate extends _CandidateOutcome {
  const _FailedCandidate();
}

/// Decrypted cleanly but carries nothing recoverable (empty or wrong owner).
class _NonRecoverableCandidate extends _CandidateOutcome {
  const _NonRecoverableCandidate();
}

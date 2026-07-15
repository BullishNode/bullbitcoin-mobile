import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart';

enum KeychainManifestNostrImportStatus {
  latestRecoverable,
  newestFailedOlderRecoverable,
  noManifestFound,
  relaysUnavailable,
  noRecoverableManifest,
  unsupportedNewerManifest,
}

class KeychainManifestNostrImportResult {
  final KeychainManifestNostrImportStatus status;
  final KeychainManifestImportPlan? importPlan;
  final int? selectedEventCreatedAt;
  final int? newestEventCreatedAt;

  const KeychainManifestNostrImportResult._({
    required this.status,
    this.importPlan,
    this.selectedEventCreatedAt,
    this.newestEventCreatedAt,
  });

  factory KeychainManifestNostrImportResult.latestRecoverable({
    required KeychainManifestImportPlan importPlan,
    required int eventCreatedAt,
  }) {
    return KeychainManifestNostrImportResult._(
      status: KeychainManifestNostrImportStatus.latestRecoverable,
      importPlan: importPlan,
      selectedEventCreatedAt: eventCreatedAt,
      newestEventCreatedAt: eventCreatedAt,
    );
  }

  factory KeychainManifestNostrImportResult.newestFailedOlderRecoverable({
    required KeychainManifestImportPlan importPlan,
    required int selectedEventCreatedAt,
    required int newestEventCreatedAt,
  }) {
    return KeychainManifestNostrImportResult._(
      status: KeychainManifestNostrImportStatus.newestFailedOlderRecoverable,
      importPlan: importPlan,
      selectedEventCreatedAt: selectedEventCreatedAt,
      newestEventCreatedAt: newestEventCreatedAt,
    );
  }

  const KeychainManifestNostrImportResult.noManifestFound()
    : this._(status: KeychainManifestNostrImportStatus.noManifestFound);

  const KeychainManifestNostrImportResult.relaysUnavailable()
    : this._(status: KeychainManifestNostrImportStatus.relaysUnavailable);

  const KeychainManifestNostrImportResult.noRecoverableManifest()
    : this._(status: KeychainManifestNostrImportStatus.noRecoverableManifest);

  /// An authentic event (author-filtered, Schnorr-verified) exists but is a
  /// decryptable-newer-version or authentic-but-unreadable manifest, with no
  /// older candidate recovering. Under our own seed-derived key an authentic
  /// unreadable payload is overwhelmingly a format newer than this app, so this
  /// maps to "update the app" (KC2b), never "no backup found".
  const KeychainManifestNostrImportResult.unsupportedNewerManifest()
    : this._(
        status: KeychainManifestNostrImportStatus.unsupportedNewerManifest,
      );
}

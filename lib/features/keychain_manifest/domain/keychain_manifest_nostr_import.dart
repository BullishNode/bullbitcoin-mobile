import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart';

enum KeychainManifestNostrImportStatus {
  latestRecoverable,
  newestFailedOlderRecoverable,
  noManifestFound,
  relaysUnavailable,
  noRecoverableManifest,
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
}

enum WalletMetadataBackupNowStatus {
  saved,
  unchanged,
  acceptedUnverified,
  notReady,
}

final class WalletMetadataBackupSettingsSnapshot {
  final bool enabled;
  final bool relayDisclosureAcknowledged;
  final bool dirty;
  final bool blocked;

  const WalletMetadataBackupSettingsSnapshot({
    required this.enabled,
    required this.relayDisclosureAcknowledged,
    required this.dirty,
    required this.blocked,
  });
}

final class BackupSettingsSnapshot {
  final bool isDefaultPhysicalBackupTested;
  final DateTime? lastPhysicalBackup;
  final bool isDefaultEncryptedBackupTested;
  final DateTime? lastEncryptedBackup;
  final WalletMetadataBackupSettingsSnapshot walletMetadata;

  const BackupSettingsSnapshot({
    required this.isDefaultPhysicalBackupTested,
    required this.lastPhysicalBackup,
    required this.isDefaultEncryptedBackupTested,
    required this.lastEncryptedBackup,
    required this.walletMetadata,
  });
}

final class WalletMetadataBackupNowResult {
  final WalletMetadataBackupNowStatus status;
  final WalletMetadataBackupSettingsSnapshot settings;

  const WalletMetadataBackupNowResult({
    required this.status,
    required this.settings,
  });
}

final class BackupSettingsSnapshot {
  final bool isDefaultPhysicalBackupTested;
  final DateTime? lastPhysicalBackup;
  final bool isDefaultEncryptedBackupTested;
  final DateTime? lastEncryptedBackup;

  const BackupSettingsSnapshot({
    required this.isDefaultPhysicalBackupTested,
    required this.lastPhysicalBackup,
    required this.isDefaultEncryptedBackupTested,
    required this.lastEncryptedBackup,
  });
}

/// Persisted Get Paid automated-backup preference (PR23, decisions [3]/[A]).
///
/// Semantics:
/// - [automatedBackupEnabled] gates the NETWORK PUBLISH only. Wallet creation
///   and the local manifest record stay unconditional, so file-based recovery
///   still works while the toggle is off. Defaults on.
/// - [backupDisclosureAcknowledged] records the one-time consent shown at the
///   first BIP85-derived wallet creation. It gates any third-party-relay
///   contact — publish AND fetch (recovery reads the same value). Defaults
///   false: the consent has not been shown/accepted yet.
class GetPaidSettings {
  final bool automatedBackupEnabled;
  final bool backupDisclosureAcknowledged;

  const GetPaidSettings({
    required this.automatedBackupEnabled,
    required this.backupDisclosureAcknowledged,
  });

  GetPaidSettings copyWith({
    bool? automatedBackupEnabled,
    bool? backupDisclosureAcknowledged,
  }) {
    return GetPaidSettings(
      automatedBackupEnabled:
          automatedBackupEnabled ?? this.automatedBackupEnabled,
      backupDisclosureAcknowledged:
          backupDisclosureAcknowledged ?? this.backupDisclosureAcknowledged,
    );
  }
}

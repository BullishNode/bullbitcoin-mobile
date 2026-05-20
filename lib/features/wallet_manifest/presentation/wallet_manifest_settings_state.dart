enum WalletManifestRemoteCheckStatus { idle, loading, missing, failed, loaded }

enum WalletManifestPublishStatus { idle, loading, failed, succeeded }

enum WalletManifestSaveStatus { idle, loading, cancelled, failed, succeeded }

enum WalletManifestAuditStatus {
  idle,
  loading,
  missing,
  failed,
  matches,
  differs,
}

enum WalletManifestManualRestoreStatus {
  idle,
  loading,
  missing,
  failed,
  completed,
  needsAttention,
}

class WalletManifestSettingsState {
  final bool loading;
  final bool failed;
  final String? npub;
  final WalletManifestRemoteCheckStatus remoteCheckStatus;
  final String? remoteManifestJson;
  final int? remoteManifestAccountCount;
  final WalletManifestPublishStatus publishStatus;
  final int? publishedManifestAccountCount;
  final WalletManifestSaveStatus saveStatus;
  final WalletManifestManualRestoreStatus manualRestoreStatus;
  final int? manualRestoreRestoredCount;
  final int? manualRestoreAlreadyPresentCount;
  final int? manualRestoreSkippedCount;
  final int? manualRestoreFailedCount;
  final bool manualRestoreWalletStateMayHaveChanged;
  final WalletManifestAuditStatus auditStatus;
  final int? auditMatchingCount;
  final int? auditMissingLocalCount;
  final int? auditMissingRemoteCount;

  const WalletManifestSettingsState({
    this.loading = false,
    this.failed = false,
    this.npub,
    this.remoteCheckStatus = WalletManifestRemoteCheckStatus.idle,
    this.remoteManifestJson,
    this.remoteManifestAccountCount,
    this.publishStatus = WalletManifestPublishStatus.idle,
    this.publishedManifestAccountCount,
    this.saveStatus = WalletManifestSaveStatus.idle,
    this.manualRestoreStatus = WalletManifestManualRestoreStatus.idle,
    this.manualRestoreRestoredCount,
    this.manualRestoreAlreadyPresentCount,
    this.manualRestoreSkippedCount,
    this.manualRestoreFailedCount,
    this.manualRestoreWalletStateMayHaveChanged = false,
    this.auditStatus = WalletManifestAuditStatus.idle,
    this.auditMatchingCount,
    this.auditMissingLocalCount,
    this.auditMissingRemoteCount,
  });

  bool get checkingRemote =>
      remoteCheckStatus == WalletManifestRemoteCheckStatus.loading;

  bool get publishing => publishStatus == WalletManifestPublishStatus.loading;

  bool get saving => saveStatus == WalletManifestSaveStatus.loading;

  bool get auditing => auditStatus == WalletManifestAuditStatus.loading;

  bool get restoring =>
      manualRestoreStatus == WalletManifestManualRestoreStatus.loading;

  bool get manifestOperationInProgress =>
      checkingRemote || publishing || restoring || saving || auditing;

  WalletManifestSettingsState copyWith({
    bool? loading,
    bool? failed,
    String? npub,
    bool clearNpub = false,
    WalletManifestRemoteCheckStatus? remoteCheckStatus,
    String? remoteManifestJson,
    int? remoteManifestAccountCount,
    bool clearRemoteManifest = false,
    WalletManifestPublishStatus? publishStatus,
    int? publishedManifestAccountCount,
    bool clearPublishedManifest = false,
    WalletManifestSaveStatus? saveStatus,
    WalletManifestManualRestoreStatus? manualRestoreStatus,
    int? manualRestoreRestoredCount,
    int? manualRestoreAlreadyPresentCount,
    int? manualRestoreSkippedCount,
    int? manualRestoreFailedCount,
    bool? manualRestoreWalletStateMayHaveChanged,
    bool clearManualRestore = false,
    WalletManifestAuditStatus? auditStatus,
    int? auditMatchingCount,
    int? auditMissingLocalCount,
    int? auditMissingRemoteCount,
    bool clearAudit = false,
  }) {
    return WalletManifestSettingsState(
      loading: loading ?? this.loading,
      failed: failed ?? this.failed,
      npub: clearNpub ? null : npub ?? this.npub,
      remoteCheckStatus: remoteCheckStatus ?? this.remoteCheckStatus,
      remoteManifestJson: clearRemoteManifest
          ? null
          : remoteManifestJson ?? this.remoteManifestJson,
      remoteManifestAccountCount: clearRemoteManifest
          ? null
          : remoteManifestAccountCount ?? this.remoteManifestAccountCount,
      publishStatus: publishStatus ?? this.publishStatus,
      publishedManifestAccountCount: clearPublishedManifest
          ? null
          : publishedManifestAccountCount ?? this.publishedManifestAccountCount,
      saveStatus: saveStatus ?? this.saveStatus,
      manualRestoreStatus: manualRestoreStatus ?? this.manualRestoreStatus,
      manualRestoreRestoredCount: clearManualRestore
          ? null
          : manualRestoreRestoredCount ?? this.manualRestoreRestoredCount,
      manualRestoreAlreadyPresentCount: clearManualRestore
          ? null
          : manualRestoreAlreadyPresentCount ??
                this.manualRestoreAlreadyPresentCount,
      manualRestoreSkippedCount: clearManualRestore
          ? null
          : manualRestoreSkippedCount ?? this.manualRestoreSkippedCount,
      manualRestoreFailedCount: clearManualRestore
          ? null
          : manualRestoreFailedCount ?? this.manualRestoreFailedCount,
      manualRestoreWalletStateMayHaveChanged: clearManualRestore
          ? false
          : manualRestoreWalletStateMayHaveChanged ??
                this.manualRestoreWalletStateMayHaveChanged,
      auditStatus: auditStatus ?? this.auditStatus,
      auditMatchingCount: clearAudit
          ? null
          : auditMatchingCount ?? this.auditMatchingCount,
      auditMissingLocalCount: clearAudit
          ? null
          : auditMissingLocalCount ?? this.auditMissingLocalCount,
      auditMissingRemoteCount: clearAudit
          ? null
          : auditMissingRemoteCount ?? this.auditMissingRemoteCount,
    );
  }
}

/// RecoverBull's narrow capability for recording that an encrypted vault
/// backup completed for one wallet.
abstract interface class EncryptedVaultBackupCompletionPort {
  Future<void> markCompleted({
    required String walletId,
    required DateTime completedAt,
  });
}

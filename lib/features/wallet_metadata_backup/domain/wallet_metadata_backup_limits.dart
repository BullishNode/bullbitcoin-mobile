abstract final class WalletMetadataBackupLimits {
  static const int maxEventFrameBytes = 131000;
  static const int maxRelayResponseFrameAllowance = 512;
  static const int maxRelays = 32;
  static const int maxRootCandidatesPerRelay = 20;
  static const int maxGraphCandidates = 20;
  static const int maxChunks = 128;
  static const int maxLogicalRecords = 50000;
  static const int maxRecordCanonicalBytes = 64 * 1024;
  static const int maxDecryptedSnapshotBytes = 12 * 1024 * 1024;
  static const int maxJsonDepth = 32;
  static const int maxJsonCollectionLength = maxLogicalRecords;
  static const int maxStringBytes = maxRecordCanonicalBytes;
  static const int maxSignedInt64 = 0x7fffffffffffffff;
  static const int minSignedInt64 = -0x8000000000000000;

  const WalletMetadataBackupLimits._();
}

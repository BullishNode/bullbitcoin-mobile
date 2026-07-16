import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_root.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes the parent fingerprint for wire comparisons', () {
    final root = WalletMetadataBackupRoot(
      xprvBase58: 'test-xprv',
      parentFingerprint: 'A1B2C3D4',
    );

    expect(root.parentFingerprint, 'a1b2c3d4');
  });

  test('rejects malformed recovery roots', () {
    expect(
      () => WalletMetadataBackupRoot(
        xprvBase58: '',
        parentFingerprint: 'a1b2c3d4',
      ),
      throwsArgumentError,
    );
    expect(
      () => WalletMetadataBackupRoot(
        xprvBase58: 'test-xprv',
        parentFingerprint: 'not-a-fingerprint',
      ),
      throwsArgumentError,
    );
  });
}

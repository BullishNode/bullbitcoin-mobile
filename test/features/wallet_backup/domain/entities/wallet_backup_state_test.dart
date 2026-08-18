import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts one complete verified remote checkpoint', () {
    final state = WalletBackupState(
      enabled: true,
      dirty: false,
      dirtyRevision: 3,
      lastAttemptedAt: 10,
      lastSucceededAt: 11,
      remoteGeneration: 2,
      remoteEtag: 'AA' * 32,
      contentHash: 'BB' * 32,
      unsupportedVersion: null,
    );

    expect(state.remoteEtag, 'aa' * 32);
    expect(state.contentHash, 'bb' * 32);
  });

  test('rejects partial or generation-zero remote checkpoints', () {
    expect(
      () => WalletBackupState(
        enabled: false,
        dirty: false,
        dirtyRevision: 0,
        lastAttemptedAt: null,
        lastSucceededAt: 1,
        remoteGeneration: 0,
        remoteEtag: null,
        contentHash: null,
        unsupportedVersion: null,
      ),
      throwsArgumentError,
    );
    expect(
      () => WalletBackupState(
        enabled: false,
        dirty: false,
        dirtyRevision: 0,
        lastAttemptedAt: null,
        lastSucceededAt: 1,
        remoteGeneration: 1,
        remoteEtag: 'aa' * 32,
        contentHash: null,
        unsupportedVersion: null,
      ),
      throwsArgumentError,
    );
  });

  test('accepts only newer unsupported envelope versions', () {
    expect(
      () => WalletBackupState(
        enabled: false,
        dirty: true,
        dirtyRevision: 1,
        lastAttemptedAt: null,
        lastSucceededAt: null,
        remoteGeneration: 0,
        remoteEtag: null,
        contentHash: null,
        unsupportedVersion: 1,
      ),
      throwsArgumentError,
    );

    final state = WalletBackupState(
      enabled: false,
      dirty: true,
      dirtyRevision: 1,
      lastAttemptedAt: null,
      lastSucceededAt: null,
      remoteGeneration: 0,
      remoteEtag: null,
      contentHash: null,
      unsupportedVersion: 2,
    );
    expect(state.unsupportedVersion, 2);
  });
}

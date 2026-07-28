import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_state.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:flutter_test/flutter_test.dart';

WalletBackupState _backup({
  bool enabled = true,
  bool dirty = false,
  int? lastAttemptedAt,
  int? lastSucceededAt,
  bool recoveryBlocked = false,
  int? unsupportedVersion,
}) {
  final hasCheckpoint = lastSucceededAt != null;
  return WalletBackupState(
    enabled: enabled,
    dirty: dirty,
    dirtyRevision: dirty ? 1 : 0,
    lastAttemptedAt: lastAttemptedAt,
    lastSucceededAt: lastSucceededAt,
    remoteGeneration: hasCheckpoint ? 1 : 0,
    remoteEtag: hasCheckpoint
        ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        : null,
    contentHash: hasCheckpoint
        ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        : null,
    unsupportedVersion: unsupportedVersion,
    recoveryBlocked: recoveryBlocked,
  );
}

WalletBackupSettingsState _state(WalletBackupState? backup) =>
    WalletBackupSettingsState(backup: backup);

void main() {
  group('metadataWriteRejected', () {
    test('is false while nothing has been read', () {
      expect(_state(null).metadataWriteRejected, isFalse);
    });

    test('is false when the backup is clean', () {
      expect(
        _state(
          _backup(lastAttemptedAt: 2000, lastSucceededAt: 1000),
        ).metadataWriteRejected,
        isFalse,
      );
    });

    // Dirty with no attempt is a write that has not happened yet, not one that
    // was refused. Calling this a failure would nag about nothing.
    test('is false when a dirty backup has never been attempted', () {
      expect(
        _state(
          _backup(dirty: true, lastSucceededAt: 1000),
        ).metadataWriteRejected,
        isFalse,
      );
    });

    test('is false when the last attempt is the one that succeeded', () {
      expect(
        _state(
          _backup(dirty: true, lastAttemptedAt: 1000, lastSucceededAt: 1000),
        ).metadataWriteRejected,
        isFalse,
      );
    });

    test('is true once an attempt after the last success left it dirty', () {
      expect(
        _state(
          _backup(dirty: true, lastAttemptedAt: 1001, lastSucceededAt: 1000),
        ).metadataWriteRejected,
        isTrue,
      );
    });

    test('is true when the only attempt ever made never succeeded', () {
      expect(
        _state(_backup(dirty: true, lastAttemptedAt: 5)).metadataWriteRejected,
        isTrue,
      );
    });
  });

  group('metadataAttentionNeeded', () {
    test('is false for a healthy backup', () {
      expect(
        _state(_backup(lastSucceededAt: 1000)).metadataAttentionNeeded,
        isFalse,
      );
    });

    test('is false while nothing has been read', () {
      expect(_state(null).metadataAttentionNeeded, isFalse);
    });

    test('covers a rejected write', () {
      expect(
        _state(
          _backup(dirty: true, lastAttemptedAt: 2000, lastSucceededAt: 1000),
        ).metadataAttentionNeeded,
        isTrue,
      );
    });

    test('covers blocked recovery', () {
      expect(
        _state(
          _backup(recoveryBlocked: true, lastSucceededAt: 1000),
        ).metadataAttentionNeeded,
        isTrue,
      );
    });

    test('covers a backup written by a newer app version', () {
      expect(
        _state(
          _backup(unsupportedVersion: 2, lastSucceededAt: 1000),
        ).metadataAttentionNeeded,
        isTrue,
      );
    });
  });

  group('metadataLastBackedUpAt', () {
    test('is null until a write has actually landed', () {
      expect(
        _state(_backup(lastAttemptedAt: 1000)).metadataLastBackedUpAt,
        isNull,
      );
      expect(_state(null).metadataLastBackedUpAt, isNull);
    });

    test('reads the recorded success, converted from epoch seconds', () {
      expect(
        _state(_backup(lastSucceededAt: 1700000000)).metadataLastBackedUpAt,
        DateTime.fromMillisecondsSinceEpoch(
          1700000000 * 1000,
          isUtc: true,
        ).toLocal(),
      );
    });
  });
}

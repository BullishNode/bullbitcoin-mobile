import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_backup/data/drift_wallet_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_state.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDatabase database;
  late DriftWalletBackupStateRepository repository;

  setUp(() {
    database = SqliteDatabase(NativeDatabase.memory());
    repository = DriftWalletBackupStateRepository(database);
  });

  tearDown(() => database.close());

  test('starts as one disabled clean state', () async {
    final state = _value(await repository.get());

    expect(state.enabled, isFalse);
    expect(state.dirty, isFalse);
    expect(state.dirtyRevision, 0);
    expect(state.remoteGeneration, 0);
    expect(state.remoteEtag, isNull);
    expect(state.contentHash, isNull);
    expect(state.unsupportedVersion, isNull);
    expect(
      await database.select(database.walletBackupStates).get(),
      hasLength(1),
    );
  });

  test('first activation marks existing content dirty once', () async {
    _expectOk(await repository.setEnabled(true));
    final activated = _value(await repository.get());
    expect(activated.enabled, isTrue);
    expect(activated.dirty, isTrue);
    expect(activated.dirtyRevision, 1);

    _expectOk(await repository.setEnabled(true));
    expect(_value(await repository.get()).dirtyRevision, 1);

    _expectOk(await repository.setEnabled(false));
    final disabled = _value(await repository.get());
    expect(disabled.enabled, isFalse);
    expect(disabled.dirty, isTrue);
    expect(disabled.dirtyRevision, 1);
  });

  test('marking dirty is monotonic even while disabled', () async {
    final results = await Future.wait([
      repository.markDirty(),
      repository.markDirty(),
    ]);
    results.forEach(_expectOk);

    final state = _value(await repository.get());
    expect(state.enabled, isFalse);
    expect(state.dirty, isTrue);
    expect(state.dirtyRevision, 2);
  });

  test('records the latest publication attempt timestamp', () async {
    _expectOk(await repository.recordAttempt(17));

    expect(_value(await repository.get()).lastAttemptedAt, 17);
  });

  test('preserves newer dirty work when an older upload succeeds', () async {
    _expectOk(await repository.setEnabled(true));
    _expectOk(await repository.markDirty());

    _expectOk(
      await repository.recordSuccess(
        capturedDirtyRevision: 1,
        succeededAt: 20,
        syncResult: _syncResult(generation: 3),
      ),
    );

    final state = _value(await repository.get());
    expect(state.dirty, isTrue);
    expect(state.dirtyRevision, 2);
    expect(state.remoteGeneration, 3);
    expect(state.remoteEtag, '33' * 32);
    expect(state.contentHash, '44' * 32);
    expect(state.lastSucceededAt, 20);
  });

  test('matching success clears dirty state and a version block', () async {
    _expectOk(await repository.setEnabled(true));
    _expectOk(await repository.blockUnsupportedVersion(2));
    _expectOk(
      await repository.recordSuccess(
        capturedDirtyRevision: 1,
        succeededAt: 20,
        syncResult: _syncResult(),
      ),
    );

    final state = _value(await repository.get());
    expect(state.dirty, isFalse);
    expect(state.unsupportedVersion, isNull);
    expect(state.remoteGeneration, 1);
  });

  test(
    'confirmed deletion clears remote checkpoint and recovery block',
    () async {
      _expectOk(await repository.setEnabled(true));
      _expectOk(
        await repository.recordSuccess(
          capturedDirtyRevision: 1,
          succeededAt: 20,
          syncResult: _syncResult(),
        ),
      );
      _expectOk(await repository.blockUnsupportedVersion(2));
      _expectOk(await repository.setRecoveryBlocked(true));
      _expectOk(await repository.clearRemoteCheckpoint());

      final state = _value(await repository.get());
      expect(state.enabled, isTrue);
      expect(state.dirty, isFalse);
      expect(state.lastSucceededAt, isNull);
      expect(state.remoteGeneration, 0);
      expect(state.remoteEtag, isNull);
      expect(state.contentHash, isNull);
      expect(state.unsupportedVersion, isNull);
      expect(state.recoveryBlocked, isFalse);
    },
  );

  test('watch emits the singleton and later state changes', () async {
    final expectation = expectLater(
      repository.watch().map(_value).take(2),
      emitsInOrder([
        isA<WalletBackupState>().having(
          (state) => state.enabled,
          'enabled',
          isFalse,
        ),
        isA<WalletBackupState>()
            .having((state) => state.enabled, 'enabled', isTrue)
            .having((state) => state.dirtyRevision, 'dirty revision', 1),
      ]),
    );

    await Future<void>.delayed(Duration.zero);
    _expectOk(await repository.setEnabled(true));
    await expectation;
  });

  test('does not hide impossible captured revisions', () async {
    await expectLater(
      repository.recordSuccess(
        capturedDirtyRevision: 1,
        succeededAt: 20,
        syncResult: _syncResult(),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

WalletBackupSyncResult _syncResult({int generation = 1}) {
  return WalletBackupSyncResult(
    checkpoint: WalletBackupRemoteCheckpoint(
      generation: generation,
      etag: (generation % 10).toString() * 64,
    ),
    contentHash: '44' * 32,
  );
}

T _value<T>(Result<T, WalletBackupFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Expected Ok, got ${failure.runtimeType}'),
};

void _expectOk(Result<void, WalletBackupFailure> result) {
  if (result case Err(:final failure)) {
    fail('Expected Ok, got ${failure.runtimeType}');
  }
}

import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/drift_wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _eventId =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _blockedEventId =
    '2222222222222222222222222222222222222222222222222222222222222222';
const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late SqliteDatabase database;
  late DriftWalletMetadataBackupStateRepository repository;

  setUp(() {
    database = SqliteDatabase(NativeDatabase.memory());
    repository = DriftWalletMetadataBackupStateRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('an absent row returns the privacy-preserving defaults', () async {
    final state = _requireOk(await repository.fetch());

    expect(state.enabled, isFalse);
    expect(state.relayDisclosureAcknowledged, isFalse);
    expect(state.dirty, isFalse);
    expect(state.verifiedHead, isNull);
    expect(state.unsupportedNewerEnvelope, isNull);
    expect(state.recoveryBlock, isNull);
  });

  test(
    'round trips publication progress, verified head, and blocked head',
    () async {
      final expected = WalletMetadataBackupState(
        enabled: true,
        relayDisclosureAcknowledged: true,
        dirty: true,
        dirtyRevision: 12,
        lastAttemptedAt: 100,
        lastAcceptedAt: 101,
        verifiedHead: WalletMetadataBackupVerifiedHead(
          rootEventId: _eventId,
          snapshotRevision: 9,
          canonicalContentHash: _contentHash,
          verifiedAt: 102,
        ),
        unsupportedNewerEnvelope: WalletMetadataBackupUnsupportedEnvelope(
          rootEventId: _blockedEventId,
          envelopeVersion: 2,
          eventCreatedAt: 103,
          observedAt: 104,
        ),
        recoveryBlock: WalletMetadataBackupRecoveryBlock(
          reason: WalletMetadataRecoveryBlockReason.olderSnapshot,
          rootEventId: '3' * 64,
          snapshotRevision: 8,
          eventCreatedAt: 99,
          observedAt: 105,
        ),
      );

      _requireOk(await repository.update((_) => expected));
      final actual = _requireOk(await repository.fetch());

      expect(actual.enabled, expected.enabled);
      expect(
        actual.relayDisclosureAcknowledged,
        expected.relayDisclosureAcknowledged,
      );
      expect(actual.dirty, expected.dirty);
      expect(actual.dirtyRevision, 12);
      expect(actual.lastAttemptedAt, expected.lastAttemptedAt);
      expect(actual.lastAcceptedAt, expected.lastAcceptedAt);
      expect(actual.verifiedHead?.rootEventId, _eventId);
      expect(actual.verifiedHead?.snapshotRevision, 9);
      expect(actual.verifiedHead?.canonicalContentHash, _contentHash);
      expect(actual.verifiedHead?.verifiedAt, 102);
      expect(actual.unsupportedNewerEnvelope?.rootEventId, _blockedEventId);
      expect(actual.unsupportedNewerEnvelope?.envelopeVersion, 2);
      expect(actual.unsupportedNewerEnvelope?.eventCreatedAt, 103);
      expect(actual.unsupportedNewerEnvelope?.observedAt, 104);
      expect(
        actual.recoveryBlock?.reason,
        WalletMetadataRecoveryBlockReason.olderSnapshot,
      );
      expect(actual.recoveryBlock?.rootEventId, '3' * 64);
      expect(actual.recoveryBlock?.snapshotRevision, 8);
    },
  );

  test(
    'metadata activation is independent from GET PAID backup consent',
    () async {
      await database
          .into(database.getPaidSettings)
          .insert(
            const GetPaidSettingsRow(
              id: 1,
              automatedBackupEnabled: true,
              backupDisclosureAcknowledged: true,
            ),
          );

      final metadata = _requireOk(await repository.fetch());

      expect(metadata.enabled, isFalse);
      expect(metadata.relayDisclosureAcknowledged, isFalse);

      _requireOk(
        await repository.update(
          (state) => state.withEnabled(true).acknowledgeRelayDisclosure(),
        ),
      );
      final getPaid = await database
          .select(database.getPaidSettings)
          .getSingle();
      expect(getPaid.automatedBackupEnabled, isTrue);
      expect(getPaid.backupDisclosureAcknowledged, isTrue);
    },
  );

  test('concurrent updates retain activation and acknowledgement', () async {
    final results = await Future.wait([
      repository.update((state) => state.withEnabled(true)),
      repository.update((state) => state.acknowledgeRelayDisclosure()),
    ]);

    for (final result in results) {
      _requireOk(result);
    }
    final state = _requireOk(await repository.fetch());
    expect(state.enabled, isTrue);
    expect(state.relayDisclosureAcknowledged, isTrue);
    expect(state.dirty, isTrue);
  });

  test(
    'rejects a partially persisted verified head as storage failure',
    () async {
      await database
          .into(database.walletMetadataBackupStates)
          .insert(
            const WalletMetadataBackupStateRow(
              id: 1,
              enabled: false,
              relayDisclosureAcknowledged: false,
              dirty: false,
              dirtyRevision: 0,
              lastVerifiedRootEventId: _eventId,
            ),
          );

      final result = await repository.fetch();

      expect(
        result,
        isA<Err<WalletMetadataBackupState, WalletMetadataBackupFailure>>(),
      );
    },
  );
}

WalletMetadataBackupState _requireOk(
  Result<WalletMetadataBackupState, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}

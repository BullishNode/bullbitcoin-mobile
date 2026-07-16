import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _eventId =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('defaults off without relay consent or pending work', () {
    const state = WalletMetadataBackupState.initial;

    expect(state.enabled, isFalse);
    expect(state.relayDisclosureAcknowledged, isFalse);
    expect(state.dirty, isFalse);
    expect(state.dirtyRevision, 0);
    expect(state.canContactRelays, isFalse);
    expect(state.canAttemptPublication, isFalse);
    expect(state.lastAttemptedAt, isNull);
    expect(state.lastAcceptedAt, isNull);
    expect(state.verifiedHead, isNull);
    expect(state.unsupportedNewerEnvelope, isNull);
    expect(state.recoveryBlock, isNull);
  });

  test('off-to-on marks catch-up work without granting relay consent', () {
    const initial = WalletMetadataBackupState.initial;

    final enabled = initial.withEnabled(true);

    expect(enabled.enabled, isTrue);
    expect(enabled.dirty, isTrue);
    expect(enabled.dirtyRevision, 1);
    expect(enabled.relayDisclosureAcknowledged, isFalse);
    expect(enabled.canContactRelays, isFalse);
    expect(enabled.canAttemptPublication, isFalse);
  });

  test('setting an already-enabled clean state is an idempotent no-op', () {
    final clean = WalletMetadataBackupState.initial
        .withEnabled(true)
        .recordVerifiedHead(
          head: WalletMetadataBackupVerifiedHead(
            rootEventId: _eventId,
            snapshotRevision: 1,
            canonicalContentHash: _contentHash,
            verifiedAt: 10,
          ),
          expectedDirtyRevision: 1,
        );

    final enabledAgain = clean.withEnabled(true);

    expect(identical(enabledAgain, clean), isTrue);
    expect(enabledAgain.dirty, isFalse);
  });

  test('relay access requires this feature enabled and acknowledged', () {
    final enabled = WalletMetadataBackupState.initial.withEnabled(true);
    final acknowledged = WalletMetadataBackupState.initial
        .acknowledgeRelayDisclosure();
    final activated = enabled.acknowledgeRelayDisclosure();

    expect(enabled.canContactRelays, isFalse);
    expect(acknowledged.enabled, isFalse);
    expect(acknowledged.canContactRelays, isFalse);
    expect(activated.canContactRelays, isTrue);
    expect(activated.canAttemptPublication, isTrue);
  });

  test(
    'disabling preserves local progress and never creates deletion work',
    () {
      final head = WalletMetadataBackupVerifiedHead(
        rootEventId: _eventId,
        snapshotRevision: 7,
        canonicalContentHash: _contentHash,
        verifiedAt: 30,
      );
      final blocked = WalletMetadataBackupUnsupportedEnvelope(
        rootEventId:
            '2222222222222222222222222222222222222222222222222222222222222222',
        envelopeVersion: 2,
        eventCreatedAt: 40,
        observedAt: 41,
      );
      final active = WalletMetadataBackupState.initial
          .withEnabled(true)
          .acknowledgeRelayDisclosure()
          .recordPublicationAttempted(20)
          .recordPublicationAccepted(25)
          .recordVerifiedHead(head: head, expectedDirtyRevision: 0)
          .recordUnsupportedNewerEnvelope(blocked);

      final disabled = active.withEnabled(false);

      expect(disabled.enabled, isFalse);
      expect(disabled.relayDisclosureAcknowledged, isTrue);
      expect(disabled.dirty, isTrue);
      expect(disabled.lastAttemptedAt, 20);
      expect(disabled.lastAcceptedAt, 25);
      expect(identical(disabled.verifiedHead, head), isTrue);
      expect(identical(disabled.unsupportedNewerEnvelope, blocked), isTrue);
      expect(disabled.canContactRelays, isFalse);
    },
  );

  test(
    'unsupported newer envelopes block publication without clearing dirty',
    () {
      final state = WalletMetadataBackupState.initial
          .withEnabled(true)
          .acknowledgeRelayDisclosure()
          .recordUnsupportedNewerEnvelope(
            WalletMetadataBackupUnsupportedEnvelope(
              rootEventId: _eventId,
              envelopeVersion: 2,
              eventCreatedAt: 10,
              observedAt: 11,
            ),
          );

      expect(state.dirty, isTrue);
      expect(state.canContactRelays, isTrue);
      expect(state.canAttemptPublication, isFalse);
    },
  );

  test('publication timestamps never regress', () {
    final state = WalletMetadataBackupState.initial
        .recordPublicationAttempted(20)
        .recordPublicationAttempted(10)
        .recordPublicationAccepted(30)
        .recordPublicationAccepted(25);

    expect(state.lastAttemptedAt, 20);
    expect(state.lastAcceptedAt, 30);
  });

  test(
    'recovery apply blocks publication until an exact latest completion',
    () {
      final block = WalletMetadataBackupRecoveryBlock(
        reason: WalletMetadataRecoveryBlockReason.applyInProgress,
        rootEventId: _eventId,
        snapshotRevision: 3,
        eventCreatedAt: 10,
        observedAt: 11,
      );
      final applying = WalletMetadataBackupState.initial
          .withEnabled(true)
          .acknowledgeRelayDisclosure()
          .recordRecoveryApplyStarted(block);

      expect(applying.dirty, isTrue);
      expect(applying.canAttemptPublication, isFalse);
      expect(
        applying.recoveryBlock?.reason,
        WalletMetadataRecoveryBlockReason.applyInProgress,
      );

      final clean = applying.recordRecoveryAppliedClean(
        head: WalletMetadataBackupVerifiedHead(
          rootEventId: _eventId,
          snapshotRevision: 3,
          canonicalContentHash: _contentHash,
          verifiedAt: 12,
        ),
      );

      expect(clean.dirty, isFalse);
      expect(clean.recoveryBlock, isNull);
      expect(clean.verifiedHead?.snapshotRevision, 3);
    },
  );

  test('a newer dirty revision survives stale publication verification', () {
    final publishing = WalletMetadataBackupState.initial.withEnabled(true);
    final changedDuringPublish = publishing.markDirty();
    final verified = changedDuringPublish.recordVerifiedHead(
      head: WalletMetadataBackupVerifiedHead(
        rootEventId: _eventId,
        snapshotRevision: 1,
        canonicalContentHash: _contentHash,
        verifiedAt: 20,
      ),
      expectedDirtyRevision: publishing.dirtyRevision,
    );

    expect(publishing.dirtyRevision, 1);
    expect(changedDuringPublish.dirtyRevision, 2);
    expect(verified.dirty, isTrue);
    expect(verified.dirtyRevision, 2);
    expect(verified.verifiedHead?.rootEventId, _eventId);
  });

  test('an initial empty no-op clears only the captured dirty revision', () {
    final publishing = WalletMetadataBackupState.initial.withEnabled(true);
    final clean = publishing.recordNoPublicationNeeded(
      expectedDirtyRevision: publishing.dirtyRevision,
    );
    final changedDuringPublish = publishing
        .markDirty()
        .recordNoPublicationNeeded(
          expectedDirtyRevision: publishing.dirtyRevision,
        );

    expect(clean.dirty, isFalse);
    expect(changedDuringPublish.dirty, isTrue);
    expect(changedDuringPublish.dirtyRevision, 2);
  });

  test(
    'verified heads cannot regress or overwrite a same-revision conflict',
    () {
      final current = WalletMetadataBackupState.initial
          .withEnabled(true)
          .recordVerifiedHead(
            head: WalletMetadataBackupVerifiedHead(
              rootEventId: _eventId,
              snapshotRevision: 7,
              canonicalContentHash: _contentHash,
              verifiedAt: 20,
            ),
            expectedDirtyRevision: 1,
          )
          .markDirty();
      final older = current.recordVerifiedHead(
        head: WalletMetadataBackupVerifiedHead(
          rootEventId: '2' * 64,
          snapshotRevision: 6,
          canonicalContentHash: 'b' * 64,
          verifiedAt: 30,
        ),
        expectedDirtyRevision: current.dirtyRevision,
      );
      final conflicting = current.recordVerifiedHead(
        head: WalletMetadataBackupVerifiedHead(
          rootEventId: '3' * 64,
          snapshotRevision: 7,
          canonicalContentHash: 'c' * 64,
          verifiedAt: 30,
        ),
        expectedDirtyRevision: current.dirtyRevision,
      );

      expect(identical(older, current), isTrue);
      expect(identical(conflicting, current), isTrue);
      expect(older.dirty, isTrue);
      expect(conflicting.dirty, isTrue);
    },
  );

  test('same revision and content may clear work without changing root', () {
    final current = WalletMetadataBackupState.initial
        .withEnabled(true)
        .recordVerifiedHead(
          head: WalletMetadataBackupVerifiedHead(
            rootEventId: _eventId,
            snapshotRevision: 7,
            canonicalContentHash: _contentHash,
            verifiedAt: 20,
          ),
          expectedDirtyRevision: 1,
        )
        .markDirty();

    final verified = current.recordVerifiedHead(
      head: WalletMetadataBackupVerifiedHead(
        rootEventId: '4' * 64,
        snapshotRevision: 7,
        canonicalContentHash: _contentHash,
        verifiedAt: 30,
      ),
      expectedDirtyRevision: current.dirtyRevision,
    );

    expect(verified.dirty, isFalse);
    expect(verified.verifiedHead?.rootEventId, _eventId);
    expect(verified.verifiedHead?.verifiedAt, 30);
  });

  test('rejects malformed heads, blocks, and timestamps', () {
    expect(
      () => WalletMetadataBackupVerifiedHead(
        rootEventId: 'AA',
        snapshotRevision: 0,
        canonicalContentHash: _contentHash,
        verifiedAt: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => WalletMetadataBackupUnsupportedEnvelope(
        rootEventId: _eventId,
        envelopeVersion: 1,
        eventCreatedAt: 0,
        observedAt: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => WalletMetadataBackupState.initial.recordPublicationAttempted(-1),
      throwsArgumentError,
    );
  });
}

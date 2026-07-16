import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_wallet_metadata_recovery_failure.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/check_remote_keychain_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/check_remote_wallet_metadata_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/apply_remote_wallet_metadata_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/begin_wallet_metadata_recovery_session_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/recovered_products_heal_outcome.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/heal_recovered_products_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/load_automated_backup_consent_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/publish_restored_keychain_backup_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/restore_remote_keychain_manifest_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_cubit.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_publication_guard.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeCheckUsecase checkRecovery;
  late _FakeRestoreUsecase restoreManifest;
  late _FakeLoadConsent loadConsent;
  late _FakeHeal heal;
  late _FakePublishRestored publishRestored;
  late _FakeCheckMetadataRecovery checkMetadataRecovery;
  late _FakeApplyMetadataRecovery applyMetadataRecovery;
  late _FakeBeginMetadataSession beginMetadataSession;
  late RemoteKeychainRecoveryCubit cubit;

  setUp(() {
    checkRecovery = _FakeCheckUsecase();
    restoreManifest = _FakeRestoreUsecase();
    loadConsent = _FakeLoadConsent();
    heal = _FakeHeal();
    publishRestored = _FakePublishRestored();
    checkMetadataRecovery = _FakeCheckMetadataRecovery();
    applyMetadataRecovery = _FakeApplyMetadataRecovery();
    beginMetadataSession = _FakeBeginMetadataSession();
    cubit = RemoteKeychainRecoveryCubit(
      checkRecovery: checkRecovery,
      restoreManifest: restoreManifest,
      loadConsent: loadConsent,
      healRecoveredProducts: heal,
      publishRestoredBackup: publishRestored,
      checkMetadataRecovery: checkMetadataRecovery,
      applyMetadataRecovery: applyMetadataRecovery,
      beginMetadataSession: beginMetadataSession,
    );
  });

  tearDown(() async {
    await cubit.close();
  });

  test('requires relay disclosure before default relay fetch', () async {
    checkRecovery.result =
        const RemoteKeychainRecoveryCheckResult.requiresRelayDisclosure();

    await cubit.start();

    expect(checkRecovery.acceptedDisclosureValues, [false]);
    expect(
      cubit.state.status,
      RemoteKeychainRecoveryStatus.requiresRelayDisclosure,
    );
    expect(restoreManifest.restoreCount, 0);
  });

  test('surfaces no manifest without restoring wallets', () async {
    checkRecovery.result =
        const RemoteKeychainRecoveryCheckResult.noManifestFound();

    await cubit.acceptRelayDisclosure();

    expect(checkRecovery.acceptedDisclosureValues, [true]);
    expect(cubit.state.status, RemoteKeychainRecoveryStatus.noManifestFound);
    expect(restoreManifest.restoreCount, 0);
  });

  test('restores latest manifest automatically', () async {
    checkRecovery.result =
        RemoteKeychainRecoveryCheckResult.latestManifestReady(
          manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
            importPlan: _importPlan,
            eventCreatedAt: _manifestEvent.createdAt,
          ),
        );
    restoreManifest.summary = const RemoteKeychainRecoveryRestoreSummary(
      restoredCount: 2,
      failedCount: 0,
      hasProductReactivationRequired: true,
    );

    await cubit.acceptRelayDisclosure();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.restored);
    expect(cubit.state.restoredCount, 2);
    expect(cubit.state.hasProductReactivationRequired, isTrue);
  });

  test('reports partial restores distinctly', () async {
    checkRecovery.result =
        RemoteKeychainRecoveryCheckResult.latestManifestReady(
          manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
            importPlan: _importPlan,
            eventCreatedAt: _manifestEvent.createdAt,
          ),
        );
    restoreManifest.summary = const RemoteKeychainRecoveryRestoreSummary(
      restoredCount: 1,
      failedCount: 1,
      hasProductReactivationRequired: false,
    );

    await cubit.acceptRelayDisclosure();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.partiallyRestored);
    expect(cubit.state.restoredCount, 1);
    expect(cubit.state.failedCount, 1);
    expect(checkMetadataRecovery.calls, 1);
  });

  test('reports all-failed restore distinctly', () async {
    checkRecovery.result =
        RemoteKeychainRecoveryCheckResult.latestManifestReady(
          manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
            importPlan: _importPlan,
            eventCreatedAt: _manifestEvent.createdAt,
          ),
        );
    restoreManifest.summary = const RemoteKeychainRecoveryRestoreSummary(
      restoredCount: 0,
      failedCount: 2,
      hasProductReactivationRequired: false,
    );

    await cubit.acceptRelayDisclosure();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.restoreFailed);
    expect(cubit.state.restoredCount, 0);
    expect(cubit.state.failedCount, 2);
    expect(checkMetadataRecovery.calls, 0);
  });

  test('waits for explicit approval before restoring older manifest', () async {
    checkRecovery.result =
        RemoteKeychainRecoveryCheckResult.olderManifestAvailable(
          manifestResult:
              KeychainManifestNostrImportResult.newestFailedOlderRecoverable(
                importPlan: _importPlan,
                selectedEventCreatedAt: _manifestEvent.createdAt,
                newestEventCreatedAt: _newerManifestEvent.createdAt,
              ),
        );

    await cubit.acceptRelayDisclosure();

    expect(
      cubit.state.status,
      RemoteKeychainRecoveryStatus.olderManifestAvailable,
    );
    expect(restoreManifest.restoreCount, 0);

    await cubit.restoreOlderManifest();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.restored);
    expect(restoreManifest.restoreCount, 1);
  });

  test('maps a zero-outcome restore to nothingToRestore (P22a)', () async {
    checkRecovery.result =
        RemoteKeychainRecoveryCheckResult.latestManifestReady(
          manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
            importPlan: _importPlan,
            eventCreatedAt: _manifestEvent.createdAt,
          ),
        );
    restoreManifest.summary = const RemoteKeychainRecoveryRestoreSummary(
      restoredCount: 0,
      failedCount: 0,
      hasProductReactivationRequired: false,
    );

    await cubit.acceptRelayDisclosure();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.nothingToRestore);
  });

  test('maps unsupportedNewerManifest to a dedicated state (P22c)', () async {
    checkRecovery.result =
        const RemoteKeychainRecoveryCheckResult.unsupportedNewerManifest();

    await cubit.acceptRelayDisclosure();

    expect(
      cubit.state.status,
      RemoteKeychainRecoveryStatus.unsupportedNewerManifest,
    );
    expect(restoreManifest.restoreCount, 0);
  });

  test('maps relaysUnavailable and noRecoverableManifest checks', () async {
    checkRecovery.result =
        const RemoteKeychainRecoveryCheckResult.relaysUnavailable();
    await cubit.acceptRelayDisclosure();
    expect(cubit.state.status, RemoteKeychainRecoveryStatus.relaysUnavailable);

    checkRecovery.result =
        const RemoteKeychainRecoveryCheckResult.noRecoverableManifest();
    await cubit.acceptRelayDisclosure();
    expect(
      cubit.state.status,
      RemoteKeychainRecoveryStatus.noRecoverableManifest,
    );
  });

  test('carries staleness markers onto an older restore (P22d)', () async {
    checkRecovery.result =
        RemoteKeychainRecoveryCheckResult.olderManifestAvailable(
          manifestResult:
              KeychainManifestNostrImportResult.newestFailedOlderRecoverable(
                importPlan: _importPlan,
                selectedEventCreatedAt: 20,
                newestEventCreatedAt: 30,
              ),
        );

    await cubit.acceptRelayDisclosure();
    await cubit.restoreOlderManifest();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.restored);
    expect(cubit.state.isOlderRestore, isTrue);
    expect(cubit.state.selectedEventCreatedAt, 20);
    expect(cubit.state.newestEventCreatedAt, 30);
  });

  test('surfaces the typed failure without a raw error (P22b)', () async {
    checkRecovery.error = DefaultWalletUnavailableRecoveryException();

    await cubit.acceptRelayDisclosure();

    expect(
      cubit.state.failure,
      isA<DefaultWalletUnavailableRecoveryException>(),
    );
  });

  test('maps missing default wallet to unavailable state', () async {
    checkRecovery.error = DefaultWalletUnavailableRecoveryException();

    await cubit.acceptRelayDisclosure();

    expect(
      cubit.state.status,
      RemoteKeychainRecoveryStatus.defaultWalletUnavailable,
    );
    expect(restoreManifest.restoreCount, 0);
  });

  test('skip prevents stale check completion from overwriting state', () async {
    final pending = Completer<RemoteKeychainRecoveryCheckResult>();
    checkRecovery.pendingResult = pending;

    final start = cubit.acceptRelayDisclosure();
    final skip = cubit.skip();
    pending.complete(
      RemoteKeychainRecoveryCheckResult.latestManifestReady(
        manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
          importPlan: _importPlan,
          eventCreatedAt: _manifestEvent.createdAt,
        ),
      ),
    );
    await Future.wait([start, skip]);

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.skipped);
    expect(restoreManifest.restoreCount, 0);
    expect(checkMetadataRecovery.calls, 1);
  });

  test('skipping keychain disclosure still restores metadata', () async {
    checkRecovery.result =
        const RemoteKeychainRecoveryCheckResult.requiresRelayDisclosure();
    checkMetadataRecovery.result = Ok(
      WalletMetadataRecoveryResult.ready(_metadataPlan),
    );

    await cubit.start();
    await cubit.skip();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.metadataRestored);
    expect(restoreManifest.restoreCount, 0);
    expect(checkMetadataRecovery.calls, 1);
    expect(applyMetadataRecovery.calls, 1);
  });

  test(
    'a persisted disclosure ack short-circuits the relay-disclosure gate',
    () async {
      loadConsent.acked = true;
      checkRecovery.result =
          RemoteKeychainRecoveryCheckResult.latestManifestReady(
            manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
              importPlan: _importPlan,
              eventCreatedAt: _manifestEvent.createdAt,
            ),
          );

      // start() with no explicit accept, yet the persisted ack drives the fetch.
      await cubit.start();

      expect(loadConsent.calls, 1);
      expect(checkRecovery.acceptedDisclosureValues, [true]);
      expect(cubit.state.status, RemoteKeychainRecoveryStatus.restored);
    },
  );

  test(
    'without a persisted ack the relay-disclosure gate is preserved',
    () async {
      loadConsent.acked = false;
      checkRecovery.result =
          const RemoteKeychainRecoveryCheckResult.requiresRelayDisclosure();

      await cubit.start();

      expect(checkRecovery.acceptedDisclosureValues, [false]);
      expect(
        cubit.state.status,
        RemoteKeychainRecoveryStatus.requiresRelayDisclosure,
      );
    },
  );

  test(
    'a latest restore heals with the summary ids and republishes once',
    () async {
      checkRecovery.result =
          RemoteKeychainRecoveryCheckResult.latestManifestReady(
            manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
              importPlan: _importPlan,
              eventCreatedAt: _manifestEvent.createdAt,
            ),
          );
      restoreManifest.summary = const RemoteKeychainRecoveryRestoreSummary(
        restoredCount: 1,
        failedCount: 0,
        hasProductReactivationRequired: true,
        reactivationReservationIds: {'lightning_address_wallet_seed'},
      );
      heal.outcome = const RecoveredProductsHealOutcome(
        lightningAddress: LightningAddressHealOutcome(
          liveness: LightningAddressRegistrationLiveness.reregistered,
        ),
      );

      await cubit.acceptRelayDisclosure();

      expect(heal.calls, 1);
      expect(heal.receivedIds, {'lightning_address_wallet_seed'});
      expect(
        cubit.state.healOutcome?.liveness,
        LightningAddressRegistrationLiveness.reregistered,
      );
      expect(publishRestored.calls, 1);
      // Terminal state emitted regardless of the (decoupled) republish.
      expect(cubit.state.status, RemoteKeychainRecoveryStatus.restored);
    },
  );

  test('a post-restore republish failure does not undo recovery', () async {
    checkRecovery.result =
        RemoteKeychainRecoveryCheckResult.latestManifestReady(
          manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
            importPlan: _importPlan,
            eventCreatedAt: _manifestEvent.createdAt,
          ),
        );
    restoreManifest.summary = const RemoteKeychainRecoveryRestoreSummary(
      restoredCount: 1,
      failedCount: 0,
      hasProductReactivationRequired: false,
    );
    publishRestored.error = Exception('relay failed');

    await cubit.acceptRelayDisclosure();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.restored);
    expect(beginMetadataSession.guard.isPublicationSuppressed, isFalse);
    expect(publishRestored.calls, 1);
  });

  test(
    'an older-approved restore heals but never republishes (T-NOCLOBBER)',
    () async {
      checkRecovery.result =
          RemoteKeychainRecoveryCheckResult.olderManifestAvailable(
            manifestResult:
                KeychainManifestNostrImportResult.newestFailedOlderRecoverable(
                  importPlan: _importPlan,
                  selectedEventCreatedAt: 20,
                  newestEventCreatedAt: 30,
                ),
          );
      restoreManifest.summary = const RemoteKeychainRecoveryRestoreSummary(
        restoredCount: 1,
        failedCount: 0,
        hasProductReactivationRequired: false,
      );

      await cubit.acceptRelayDisclosure();
      await cubit.restoreOlderManifest();

      expect(cubit.state.status, RemoteKeychainRecoveryStatus.restored);
      expect(cubit.state.isOlderRestore, isTrue);
      // The newer (unreadable) relay event must not be clobbered by a republish.
      expect(publishRestored.calls, 0);
    },
  );

  test('nothingToRestore runs no heal and no republish', () async {
    checkRecovery.result =
        RemoteKeychainRecoveryCheckResult.latestManifestReady(
          manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
            importPlan: _importPlan,
            eventCreatedAt: _manifestEvent.createdAt,
          ),
        );
    restoreManifest.summary = const RemoteKeychainRecoveryRestoreSummary(
      restoredCount: 0,
      failedCount: 0,
      hasProductReactivationRequired: false,
    );

    await cubit.acceptRelayDisclosure();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.nothingToRestore);
    expect(heal.calls, 0);
    expect(publishRestored.calls, 0);
  });

  test(
    'metadata recovery checks immediately without separate consent',
    () async {
      await cubit.startMetadataRecovery();

      expect(checkMetadataRecovery.calls, 1);
      expect(
        cubit.state.status,
        RemoteKeychainRecoveryStatus.metadataNoSnapshot,
      );
      expect(beginMetadataSession.guard.isPublicationSuppressed, isFalse);
    },
  );

  test('an unexpected metadata check failure releases suppression', () async {
    checkMetadataRecovery.error = Exception('private transport detail');

    await cubit.startMetadataRecovery();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.metadataFailed);
    expect(beginMetadataSession.guard.isPublicationSuppressed, isFalse);
  });

  test(
    'keychain materialization holds metadata publication suppression',
    () async {
      checkRecovery.result =
          RemoteKeychainRecoveryCheckResult.latestManifestReady(
            manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
              importPlan: _importPlan,
              eventCreatedAt: _manifestEvent.createdAt,
            ),
          );
      restoreManifest.isMetadataPublicationSuppressed = () =>
          beginMetadataSession.guard.isPublicationSuppressed;

      await cubit.acceptRelayDisclosure();

      expect(restoreManifest.wasMetadataPublicationSuppressed, isTrue);
      expect(beginMetadataSession.calls, 1);
      expect(checkMetadataRecovery.calls, 1);
      expect(beginMetadataSession.guard.isPublicationSuppressed, isFalse);
    },
  );

  test('metadata plan is applied automatically', () async {
    checkMetadataRecovery.result = Ok(
      WalletMetadataRecoveryResult.ready(_metadataPlan),
    );

    await cubit.startMetadataRecovery();

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.metadataRestored);
    expect(applyMetadataRecovery.calls, 1);
    expect(beginMetadataSession.guard.isPublicationSuppressed, isFalse);
  });

  test(
    'passes only wallets created in this keychain recovery to metadata',
    () async {
      checkRecovery.result =
          RemoteKeychainRecoveryCheckResult.latestManifestReady(
            manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
              importPlan: _importPlan,
              eventCreatedAt: _manifestEvent.createdAt,
            ),
          );
      restoreManifest.summary = const RemoteKeychainRecoveryRestoreSummary(
        restoredCount: 2,
        failedCount: 0,
        hasProductReactivationRequired: false,
        createdWalletRefs: {'created-wallet'},
      );
      checkMetadataRecovery.result = Ok(
        WalletMetadataRecoveryResult.ready(_metadataPlan),
      );

      await cubit.acceptRelayDisclosure();

      expect(applyMetadataRecovery.createdWalletRefs, {'created-wallet'});
      expect(cubit.state.status, RemoteKeychainRecoveryStatus.metadataRestored);
      expect(cubit.state.restoredCount, 2);
      expect(cubit.state.failedCount, 0);
    },
  );

  test(
    'a metadata no-snapshot outcome releases publication suppression',
    () async {
      await cubit.startMetadataRecovery();

      expect(
        cubit.state.status,
        RemoteKeychainRecoveryStatus.metadataNoSnapshot,
      );
      expect(beginMetadataSession.guard.isPublicationSuppressed, isFalse);
    },
  );
}

final _wellShapedCiphertext = base64.encode(
  Uint8List(KeychainManifestNostrCiphertext.minimumByteLength),
);

final _importPlan = KeychainManifestImportPlan(
  parentFingerprint: 'fedcba98',
  entries: [],
);

const _metadataPlan = _FakeWalletMetadataRecoveryPlan();

final class _FakeWalletMetadataRecoveryPlan
    implements WalletMetadataRecoveryPlan {
  const _FakeWalletMetadataRecoveryPlan();

  @override
  int get plannedRecordCount => 0;

  @override
  int get unsupportedCount => 0;

  @override
  int get invalidRecordCount => 0;

  @override
  bool get isOlderRestore => false;
}

final _manifestEvent = KeychainManifestNostrSignedEvent.fromDraft(
  draft: KeychainManifestNostrEventDraft(
    authorPublicKeyHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    encryptedContent: KeychainManifestNostrCiphertext(_wellShapedCiphertext),
    createdAt: 20,
  ),
  signatureHex:
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
);

final _newerManifestEvent = KeychainManifestNostrSignedEvent.fromDraft(
  draft: KeychainManifestNostrEventDraft(
    authorPublicKeyHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    encryptedContent: KeychainManifestNostrCiphertext(_wellShapedCiphertext),
    createdAt: 30,
  ),
  signatureHex:
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
);

class _FakeCheckUsecase implements CheckRemoteKeychainRecoveryUsecase {
  RemoteKeychainRecoveryCheckResult result =
      const RemoteKeychainRecoveryCheckResult.noManifestFound();
  Completer<RemoteKeychainRecoveryCheckResult>? pendingResult;
  Object? error;
  final acceptedDisclosureValues = <bool>[];

  @override
  Future<RemoteKeychainRecoveryCheckResult> execute({
    required bool acceptedThirdPartyRelayDisclosure,
  }) async {
    acceptedDisclosureValues.add(acceptedThirdPartyRelayDisclosure);
    final error = this.error;
    if (error != null) throw error;
    final pendingResult = this.pendingResult;
    if (pendingResult != null) return pendingResult.future;
    return result;
  }
}

class _FakeRestoreUsecase implements RestoreRemoteKeychainManifestUsecase {
  RemoteKeychainRecoveryRestoreSummary summary =
      const RemoteKeychainRecoveryRestoreSummary(
        restoredCount: 1,
        failedCount: 0,
        hasProductReactivationRequired: false,
      );
  int restoreCount = 0;
  bool Function()? isMetadataPublicationSuppressed;
  bool? wasMetadataPublicationSuppressed;

  @override
  Future<RemoteKeychainRecoveryRestoreSummary> execute(
    KeychainManifestImportPlan importPlan,
  ) async {
    restoreCount++;
    wasMetadataPublicationSuppressed = isMetadataPublicationSuppressed?.call();
    return summary;
  }
}

class _FakeLoadConsent implements LoadAutomatedBackupConsentUsecase {
  bool acked = false;
  int calls = 0;

  @override
  Future<bool> execute() async {
    calls++;
    return acked;
  }
}

class _FakeHeal implements HealRecoveredProductsUsecase {
  Set<String>? receivedIds;
  int calls = 0;
  RecoveredProductsHealOutcome outcome = const RecoveredProductsHealOutcome();

  @override
  Future<RecoveredProductsHealOutcome> execute(
    Set<String> reactivationReservationIds,
  ) async {
    calls++;
    receivedIds = reactivationReservationIds;
    return outcome;
  }
}

class _FakePublishRestored implements PublishRestoredKeychainBackupUsecase {
  int calls = 0;
  Object? error;

  @override
  Future<void> execute() async {
    calls++;
    final error = this.error;
    if (error != null) throw error;
  }
}

class _FakeCheckMetadataRecovery
    implements CheckRemoteWalletMetadataRecoveryUsecase {
  Result<WalletMetadataRecoveryResult, RemoteWalletMetadataRecoveryFailure>
  result = const Ok(WalletMetadataRecoveryResult.noSnapshotFound());
  int calls = 0;
  Object? error;

  @override
  Future<
    Result<WalletMetadataRecoveryResult, RemoteWalletMetadataRecoveryFailure>
  >
  execute() async {
    calls++;
    final error = this.error;
    if (error != null) throw error;
    return result;
  }
}

class _FakeApplyMetadataRecovery
    implements ApplyRemoteWalletMetadataRecoveryUsecase {
  int calls = 0;
  Set<String>? createdWalletRefs;
  Completer<
    Result<
      WalletMetadataRecoveryApplyResult,
      RemoteWalletMetadataRecoveryFailure
    >
  >?
  pending;

  @override
  Future<
    Result<
      WalletMetadataRecoveryApplyResult,
      RemoteWalletMetadataRecoveryFailure
    >
  >
  execute({
    required WalletMetadataRecoveryPlan plan,
    required Set<String> createdWalletRefs,
  }) async {
    calls++;
    this.createdWalletRefs = createdWalletRefs;
    final pending = this.pending;
    if (pending != null) return pending.future;
    return Ok(_successfulMetadataApply());
  }
}

WalletMetadataRecoveryApplyResult _successfulMetadataApply() {
  return WalletMetadataRecoveryApplyResult(
    status: WalletMetadataRecoveryApplyStatus.latestComplete,
    contributorOutcomes: const [],
    unsupportedRecordCount: 0,
    unsupportedSectionCount: 0,
    invalidRecordCount: 0,
  );
}

class _FakeBeginMetadataSession
    implements BeginWalletMetadataRecoverySessionUsecase {
  final guard = WalletMetadataPublicationGuard();
  int calls = 0;

  @override
  Future<WalletMetadataPublicationSuppression> execute() async {
    calls++;
    return guard.beginPublicationSuppression();
  }
}

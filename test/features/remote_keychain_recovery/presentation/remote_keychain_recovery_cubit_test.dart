import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/check_remote_keychain_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/restore_remote_keychain_manifest_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_cubit.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeCheckUsecase checkRecovery;
  late _FakeRestoreUsecase restoreManifest;
  late RemoteKeychainRecoveryCubit cubit;

  setUp(() {
    checkRecovery = _FakeCheckUsecase();
    restoreManifest = _FakeRestoreUsecase();
    cubit = RemoteKeychainRecoveryCubit(
      checkRecovery: checkRecovery,
      restoreManifest: restoreManifest,
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
    cubit.skip();
    pending.complete(
      RemoteKeychainRecoveryCheckResult.latestManifestReady(
        manifestResult: KeychainManifestNostrImportResult.latestRecoverable(
          importPlan: _importPlan,
          eventCreatedAt: _manifestEvent.createdAt,
        ),
      ),
    );
    await start;

    expect(cubit.state.status, RemoteKeychainRecoveryStatus.skipped);
    expect(restoreManifest.restoreCount, 0);
  });
}

final _wellShapedCiphertext = base64.encode(
  Uint8List(KeychainManifestNostrCiphertext.minimumByteLength),
);

final _importPlan = KeychainManifestImportPlan(
  parentFingerprint: 'fedcba98',
  entries: [],
);

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

  @override
  Future<RemoteKeychainRecoveryRestoreSummary> execute(
    KeychainManifestImportPlan importPlan,
  ) async {
    restoreCount++;
    return summary;
  }
}

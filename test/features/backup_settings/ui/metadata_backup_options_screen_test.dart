import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/get_last_wallet_backup_recovery_outcome_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/retry_wallet_backup_recovery_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/watch_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/ui/screens/metadata_backup_options_screen.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The options screen owns every metadata-backup action. The Backup Settings
/// status row only summarises, so these tests are the ones that must prove the
/// toggle, the immediate write, and deletion still work after the move.
void main() {
  late AppLocalizations loc;

  setUpAll(
    () async => loc = await AppLocalizations.delegate.load(const Locale('en')),
  );

  tearDown(() async {
    await locator.reset();
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    _FakeWalletBackupFacade facade, {
    _FakeRemoteRecovery? remoteRecovery,
  }) async {
    final recovery = remoteRecovery ?? _FakeRemoteRecovery();
    locator.registerFactory<WalletBackupSettingsCubit>(
      () => WalletBackupSettingsCubit(
        WatchWalletBackupUsecase(facade),
        SetWalletBackupEnabledUsecase(facade),
        BackupWalletNowUsecase(facade),
        DeleteWalletBackupUsecase(facade),
        GetLastWalletBackupRecoveryOutcomeUsecase(recovery).execute,
        RetryWalletBackupRecoveryUsecase(recovery).execute,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const MetadataBackupOptionsScreen(),
      ),
    );
    await tester.pump();
  }

  testWidgets('is titled after the row that opens it', (tester) async {
    await pumpScreen(tester, _FakeWalletBackupFacade(_offState));

    expect(find.text(loc.backupSettingsMetadataBackup), findsOneWidget);
  });

  testWidgets('shows one unified Bull backup lifecycle', (tester) async {
    await pumpScreen(tester, _FakeWalletBackupFacade(_offState));

    expect(find.text(loc.walletBackupSettingsTitle), findsOneWidget);
    expect(find.text(loc.walletBackupSettingsEnabled), findsOneWidget);
    expect(find.text('Wallet metadata backup'), findsNothing);
    expect(find.text('Delete wallet metadata backup'), findsNothing);
  });

  testWidgets('states on/off the way the Backup Settings rows do', (
    tester,
  ) async {
    await pumpScreen(tester, _FakeWalletBackupFacade(_offState));

    // The status line, not a transplanted card: a value beside the label and the
    // one fact that matters under it.
    expect(find.text(loc.backupSettingsMetadataTurnedOff), findsOneWidget);
    expect(find.text(loc.walletBackupSettingsOff), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('keeps manual backup disabled while automatic backup is off', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      _FakeWalletBackupFacade(
        WalletBackupState(
          enabled: false,
          dirty: true,
          dirtyRevision: 1,
          lastAttemptedAt: null,
          lastSucceededAt: null,
          remoteGeneration: 0,
          remoteEtag: null,
          contentHash: null,
          unsupportedVersion: null,
        ),
      ),
    );

    expect(find.text(loc.walletBackupSettingsOff), findsOneWidget);
    final button = tester.widget<BBButton>(
      find.widgetWithText(BBButton, loc.walletBackupSettingsBackupNow),
    );
    expect(button.disabled, isTrue);
  });

  testWidgets('turns automatic backup on through the toggle', (tester) async {
    final facade = _FakeWalletBackupFacade(_offState);
    await pumpScreen(tester, facade);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(facade.enabledCalls, [true]);
  });

  testWidgets('backs up now when automatic backup is on', (tester) async {
    final facade = _FakeWalletBackupFacade(_enabledState);
    await pumpScreen(tester, facade);

    await tester.tap(
      find.widgetWithText(BBButton, loc.walletBackupSettingsBackupNow),
    );
    await tester.pumpAndSettle();

    expect(facade.backupNowCalls, 1);
  });

  testWidgets('shows successful manual recovery counts', (tester) async {
    final recovery = _FakeRemoteRecovery(
      retryResult: const RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.restored,
        restoredCount: 3,
        failedCount: 0,
      ),
    );
    await pumpScreen(
      tester,
      _FakeWalletBackupFacade(_recoveryBlockedState),
      remoteRecovery: recovery,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(loc.metadataBackupRetryRecovery));
    await tester.pumpAndSettle();

    expect(recovery.recoverCalls, 1);
    expect(find.text(loc.metadataBackupRecoveryRetryResult), findsOneWidget);
    expect(find.text(loc.metadataBackupRecoveryRetryComplete), findsOneWidget);
    expect(
      find.text(loc.metadataBackupRecoveryRetryCounts(3, 0)),
      findsOneWidget,
    );
  });

  testWidgets('shows a failed manual recovery status and counts', (
    tester,
  ) async {
    final recovery = _FakeRemoteRecovery(
      retryResult: const RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.unavailable,
        restoredCount: 1,
        failedCount: 2,
      ),
    );
    await pumpScreen(
      tester,
      _FakeWalletBackupFacade(_recoveryBlockedState),
      remoteRecovery: recovery,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(loc.metadataBackupRetryRecovery));
    await tester.pumpAndSettle();

    expect(find.text(loc.metadataBackupRecoveryRetryFailed), findsOneWidget);
    expect(
      find.text(loc.metadataBackupRecoveryRetryCounts(1, 2)),
      findsOneWidget,
    );
  });

  testWidgets('confirms deletion before removing the remote copy', (
    tester,
  ) async {
    final facade = _FakeWalletBackupFacade(
      WalletBackupState(
        enabled: false,
        dirty: false,
        dirtyRevision: 0,
        lastAttemptedAt: null,
        lastSucceededAt: 100,
        remoteGeneration: 1,
        remoteEtag:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        contentHash:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        unsupportedVersion: null,
      ),
    );
    await pumpScreen(tester, facade);

    await tester.tap(find.text(loc.walletBackupSettingsDelete));
    await tester.pumpAndSettle();
    expect(find.text(loc.walletBackupSettingsDeleteTitle), findsOneWidget);
    expect(facade.deleteCalls, 0);

    await tester.tap(find.text(loc.walletBackupSettingsDeleteConfirm).last);
    await tester.pumpAndSettle();
    expect(facade.deleteCalls, 1);
  });

  testWidgets('dismissing the confirmation deletes nothing', (tester) async {
    final facade = _FakeWalletBackupFacade(
      WalletBackupState(
        enabled: false,
        dirty: false,
        dirtyRevision: 0,
        lastAttemptedAt: null,
        lastSucceededAt: 100,
        remoteGeneration: 1,
        remoteEtag:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        contentHash:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        unsupportedVersion: null,
      ),
    );
    await pumpScreen(tester, facade);

    await tester.tap(find.text(loc.walletBackupSettingsDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(loc.walletBackupSettingsCancel));
    await tester.pumpAndSettle();

    expect(facade.deleteCalls, 0);
  });
}

final WalletBackupState _offState = WalletBackupState(
  enabled: false,
  dirty: false,
  dirtyRevision: 0,
  lastAttemptedAt: null,
  lastSucceededAt: null,
  remoteGeneration: 0,
  remoteEtag: null,
  contentHash: null,
  unsupportedVersion: null,
);

final WalletBackupState _enabledState = WalletBackupState(
  enabled: true,
  dirty: false,
  dirtyRevision: 0,
  lastAttemptedAt: null,
  lastSucceededAt: null,
  remoteGeneration: 0,
  remoteEtag: null,
  contentHash: null,
  unsupportedVersion: null,
);

final WalletBackupState _recoveryBlockedState = WalletBackupState(
  enabled: true,
  dirty: false,
  dirtyRevision: 0,
  lastAttemptedAt: null,
  lastSucceededAt: null,
  remoteGeneration: 0,
  remoteEtag: null,
  contentHash: null,
  unsupportedVersion: null,
  recoveryBlocked: true,
);

final class _FakeWalletBackupFacade implements WalletBackupFacade {
  _FakeWalletBackupFacade(this._state);

  final WalletBackupState _state;
  final List<bool> enabledCalls = [];
  int backupNowCalls = 0;
  int deleteCalls = 0;

  @override
  Future<Result<WalletBackupState, WalletBackupFailure>> getState() async =>
      Ok(_state);

  @override
  Stream<Result<WalletBackupState, WalletBackupFailure>> watchState() =>
      Stream.value(Ok(_state));

  @override
  Future<Result<void, WalletBackupFailure>> setEnabled(bool enabled) async {
    enabledCalls.add(enabled);
    return const Ok(null);
  }

  @override
  Future<Result<void, WalletBackupFailure>> backupNow() async {
    backupNowCalls++;
    return const Ok(null);
  }

  @override
  Future<Result<void, WalletBackupFailure>> deleteRemoteBackup({
    required bool confirmed,
  }) async {
    if (confirmed) deleteCalls++;
    return const Ok(null);
  }

  @override
  Future<Result<WalletBackupManifestImport?, WalletBackupFailure>>
  fetchManifestImport() async => const Ok(null);

  @override
  Future<WalletBackupLifecycleLease> beginRecoveryLease({
    Duration? timeout,
  }) async {
    timeout;
    return _Fence();
  }

  @override
  Future<Result<WalletBackupRemoteIdentity, WalletBackupFailure>>
  fetchRemoteIdentity() async => Ok(
    WalletBackupRemoteIdentity(
      found: false,
      generation: 0,
      etag: null,
      ciphertextSha256: null,
    ),
  );

  @override
  Future<Result<void, WalletBackupFailure>> setRecoveryBlocked(
    bool blocked,
  ) async => const Ok(null);
}

final class _FakeRemoteRecovery implements RemoteKeychainRecoveryFacade {
  final RemoteRecoveryOutcome? lastOutcome;
  final RemoteKeychainRecoveryResult retryResult;
  int recoverCalls = 0;

  _FakeRemoteRecovery({
    this.retryResult = const RemoteKeychainRecoveryResult(
      status: RemoteKeychainRecoveryStatus.noBackup,
    ),
  }) : lastOutcome = null;

  @override
  Future<RemoteRecoveryOutcome?> getLastOutcome() async => lastOutcome;

  @override
  Future<RemoteKeychainRecoveryResult> recover({
    Set<String> defaultCreatedWalletIds = const {},
  }) async {
    recoverCalls += 1;
    return retryResult;
  }
}

final class _Fence implements WalletBackupLifecycleLease {
  @override
  void close() {}
}

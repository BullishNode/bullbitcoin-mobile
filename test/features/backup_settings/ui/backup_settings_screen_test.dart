import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/watch_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/ui/screens/backup_settings_screen.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubBackupSettingsCubit extends Cubit<BackupSettingsState>
    implements BackupSettingsCubit {
  _StubBackupSettingsCubit(super.initialState);

  @override
  Future<void> checkBackupStatus() async {}
}

void main() {
  tearDown(() async {
    await locator.reset();
  });

  testWidgets('shows one unified Bull backup lifecycle', (tester) async {
    await _pump(tester, _StubBackupSettingsCubit(BackupSettingsState()));

    expect(find.text('Bull backup'), findsOneWidget);
    expect(find.text('Automatic Bull backup'), findsOneWidget);
    expect(find.text('Wallet metadata backup'), findsNothing);
    expect(find.text('Delete wallet metadata backup'), findsNothing);
  });

  testWidgets('shows pending state and keeps manual backup disabled when off', (
    tester,
  ) async {
    final facade = _FakeWalletBackupFacade(
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
    );
    await _pump(
      tester,
      _StubBackupSettingsCubit(BackupSettingsState()),
      facade: facade,
    );

    expect(find.text('Automatic backup is off'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Back up now'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('confirms deletion through the unified backup control', (
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
    await _pump(
      tester,
      _StubBackupSettingsCubit(BackupSettingsState()),
      facade: facade,
    );

    await tester.tap(find.text('Delete backup'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bull backup?'), findsOneWidget);
    expect(facade.deleteCalls, 0);

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(facade.deleteCalls, 1);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _StubBackupSettingsCubit cubit, {
  _FakeWalletBackupFacade? facade,
}) async {
  locator.registerFactory<BackupSettingsCubit>(() => cubit);
  final walletBackup = facade ?? _FakeWalletBackupFacade(_offState);
  locator.registerFactory<WalletBackupSettingsCubit>(
    () => WalletBackupSettingsCubit(
      WatchWalletBackupUsecase(walletBackup),
      SetWalletBackupEnabledUsecase(walletBackup),
      BackupWalletNowUsecase(walletBackup),
      DeleteWalletBackupUsecase(walletBackup),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const BackupSettingsScreen(),
    ),
  );
  await tester.pump();
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

final class _FakeWalletBackupFacade implements WalletBackupFacade {
  _FakeWalletBackupFacade(this._state);

  final WalletBackupState _state;
  int deleteCalls = 0;

  @override
  Future<Result<WalletBackupState, WalletBackupFailure>> getState() async =>
      Ok(_state);

  @override
  Stream<Result<WalletBackupState, WalletBackupFailure>> watchState() =>
      Stream.value(Ok(_state));

  @override
  Future<Result<void, WalletBackupFailure>> setEnabled(bool enabled) async =>
      const Ok(null);

  @override
  Future<Result<void, WalletBackupFailure>> backupNow() async => const Ok(null);

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
  }) async => _Fence();

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

final class _Fence implements WalletBackupLifecycleLease {
  @override
  void close() {}
}

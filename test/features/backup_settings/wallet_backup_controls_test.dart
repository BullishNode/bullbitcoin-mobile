import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/watch_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/ui/widgets/wallet_backup_controls.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders and drives the one global Bull backup lifecycle', (
    tester,
  ) async {
    final backup = _FakeWalletBackupFacade();
    final cubit = WalletBackupSettingsCubit(
      WatchWalletBackupUsecase(backup),
      SetWalletBackupEnabledUsecase(backup),
      BackupWalletNowUsecase(backup),
      DeleteWalletBackupUsecase(backup),
    );
    addTearDown(cubit.close);
    addTearDown(backup.close);
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: const WalletBackupControls(),
          ),
        ),
      ),
    );

    backup.states.add(Ok(_state(enabled: false, dirty: true)));
    await tester.pump();

    expect(find.text('Bull backup'), findsOneWidget);
    expect(find.text('Automatic backup is off'), findsOneWidget);
    expect(find.text('Back up now'), findsOneWidget);
    expect(find.text('Delete backup'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(backup.enabledValues, [true]);

    backup.states.add(Ok(_state(enabled: true, dirty: true)));
    await tester.pumpAndSettle();
    expect(find.text('Backup pending'), findsOneWidget);
    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();
    expect(backup.backupNowCalls, 1);

    backup.states.add(Ok(_state(enabled: false, dirty: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete backup'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bull backup?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(backup.deleteConfirmedValues, [true]);
  });
}

WalletBackupState _state({required bool enabled, required bool dirty}) {
  return WalletBackupState(
    enabled: enabled,
    dirty: dirty,
    dirtyRevision: dirty ? 1 : 0,
    lastAttemptedAt: null,
    lastSucceededAt: null,
    remoteGeneration: 0,
    remoteEtag: null,
    contentHash: null,
    unsupportedVersion: null,
  );
}

final class _FakeWalletBackupFacade implements WalletBackupFacade {
  final states =
      StreamController<
        Result<WalletBackupState, WalletBackupFailure>
      >.broadcast();
  final enabledValues = <bool>[];
  final deleteConfirmedValues = <bool>[];
  int backupNowCalls = 0;

  @override
  Stream<Result<WalletBackupState, WalletBackupFailure>> watchState() {
    return states.stream;
  }

  @override
  Future<Result<void, WalletBackupFailure>> setEnabled(bool enabled) async {
    enabledValues.add(enabled);
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
    deleteConfirmedValues.add(confirmed);
    return const Ok(null);
  }

  Future<void> close() => states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

/// Stands in for the real cubit so each posture can be pumped directly. The
/// screen resolves it from the locator, so registering the fake is enough.
class _FakeBackupSettingsCubit extends Cubit<BackupSettingsState>
    implements BackupSettingsCubit {
  _FakeBackupSettingsCubit(super.initialState);

  @override
  Future<void> checkBackupStatus() async {}
}

void main() {
  late AppLocalizations loc;

  setUpAll(
    () async => loc = await AppLocalizations.delegate.load(const Locale('en')),
  );

  tearDown(() async {
    await locator.reset();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required bool physicalTested,
    required bool vaultTested,
    DateTime? lastPhysicalBackup,
    DateTime? lastEncryptedBackup,
    BackupSettingsStatus status = BackupSettingsStatus.success,
    _FakeWalletBackupFacade? walletBackup,
  }) async {
    final state = BackupSettingsState(
      isDefaultPhysicalBackupTested: physicalTested,
      isDefaultEncryptedBackupTested: vaultTested,
      lastPhysicalBackup: lastPhysicalBackup,
      lastEncryptedBackup: lastEncryptedBackup,
      status: status,
    );
    locator.registerFactory<BackupSettingsCubit>(
      () => _FakeBackupSettingsCubit(state),
    );
    final facade = walletBackup ?? _FakeWalletBackupFacade(_offState);
    locator.registerFactory<WalletBackupSettingsCubit>(
      () => WalletBackupSettingsCubit(
        WatchWalletBackupUsecase(facade),
        SetWalletBackupEnabledUsecase(facade),
        BackupWalletNowUsecase(facade),
        DeleteWalletBackupUsecase(facade),
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

  testWidgets('urges a backup, and only that, when nothing is backed up', (
    tester,
  ) async {
    await pumpScreen(tester, physicalTested: false, vaultTested: false);

    expect(find.text(loc.backupSettingsHeroBackUpTitle), findsOneWidget);
    expect(find.text(loc.backupSettingsStartBackupAction), findsOneWidget);
    expect(find.text(loc.backupHealthReminderTitle), findsNothing);
    // Nothing to test yet, so no test-backup row.
    expect(find.text(loc.backupSettingsTestBackup), findsNothing);
  });

  testWidgets('asks a vault-only wallet for a physical backup', (tester) async {
    await pumpScreen(
      tester,
      physicalTested: false,
      vaultTested: true,
      lastEncryptedBackup: DateTime.now(),
    );

    expect(find.text(loc.backupHealthReminderTitle), findsOneWidget);
    expect(find.text(loc.backupHealthAddPhysicalBackupAction), findsOneWidget);
    expect(find.text(loc.backupSettingsHeroBackUpTitle), findsNothing);
  });

  testWidgets('says nothing extra when the physical backup is fresh', (
    tester,
  ) async {
    final testedAt = DateTime.now().subtract(const Duration(days: 30));
    await pumpScreen(
      tester,
      physicalTested: true,
      vaultTested: true,
      lastPhysicalBackup: testedAt,
      lastEncryptedBackup: testedAt,
    );

    expect(find.text(loc.backupHealthReminderTitle), findsNothing);
    expect(find.text(loc.backupSettingsHeroBackUpTitle), findsNothing);
    expect(find.text(loc.backupHealthTestBackupAction), findsNothing);
    // The rows still carry the facts.
    expect(find.text(loc.backupSettingsTested), findsNWidgets(2));
  });

  testWidgets('asks for a test when the physical backup has gone stale', (
    tester,
  ) async {
    final testedAt = DateTime.now().subtract(const Duration(days: 400));
    await pumpScreen(
      tester,
      physicalTested: true,
      vaultTested: true,
      lastPhysicalBackup: testedAt,
      lastEncryptedBackup: DateTime.now(),
    );

    expect(find.text(loc.backupHealthReminderTitle), findsOneWidget);
    expect(find.text(loc.backupHealthTestBackupAction), findsOneWidget);
  });

  testWidgets('a fresh vault does not excuse a stale physical backup', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      physicalTested: true,
      vaultTested: true,
      lastPhysicalBackup: DateTime.now().subtract(const Duration(days: 730)),
      lastEncryptedBackup: DateTime.now(),
    );

    expect(find.text(loc.backupHealthTestBackupAction), findsOneWidget);
  });

  testWidgets('states when the physical backup was last tested', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      physicalTested: true,
      vaultTested: false,
      lastPhysicalBackup: DateTime.now().subtract(const Duration(days: 60)),
    );

    expect(find.textContaining('Last tested'), findsWidgets);
  });

  testWidgets('renders no hero before the first load resolves', (tester) async {
    await pumpScreen(
      tester,
      physicalTested: false,
      vaultTested: false,
      status: BackupSettingsStatus.loading,
    );

    expect(find.text(loc.backupSettingsHeroBackUpTitle), findsNothing);
    expect(find.text(loc.backupSettingsStartBackupAction), findsNothing);
  });

  // Availability is not encouragement: the hero goes quiet once a physical
  // backup is fresh, but adding another backup must never stop being possible.
  group('the backup action is always available', () {
    final now = DateTime.now();
    // The zero-backup state is deliberately absent: there the hero itself
    // renders START BACKUP, so the menu row would be a second identical entry
    // a few pixels below it. Covered by its own test after this group.
    final postures = <String, Map<String, Object?>>{
      'vault only': {'physical': false, 'vault': true, 'vaultAt': now},
      'physical fresh': {
        'physical': true,
        'vault': false,
        'physicalAt': now.subtract(const Duration(days: 30)),
      },
      'physical stale': {
        'physical': true,
        'vault': false,
        'physicalAt': now.subtract(const Duration(days: 400)),
      },
      'both': {
        'physical': true,
        'vault': true,
        'physicalAt': now.subtract(const Duration(days: 30)),
        'vaultAt': now,
      },
    };

    for (final entry in postures.entries) {
      testWidgets(entry.key, (tester) async {
        final p = entry.value;
        await pumpScreen(
          tester,
          physicalTested: p['physical']! as bool,
          vaultTested: p['vault']! as bool,
          lastPhysicalBackup: p['physicalAt'] as DateTime?,
          lastEncryptedBackup: p['vaultAt'] as DateTime?,
        );

        expect(find.text(loc.backupSettingsStartBackup), findsOneWidget);
      });
    }
  });

  testWidgets(
    'the zero-backup hero offers START BACKUP without a duplicate menu row',
    (tester) async {
      await pumpScreen(tester, physicalTested: false, vaultTested: false);

      // The hero's own CTA is present…
      expect(find.text(loc.backupSettingsStartBackupAction), findsOneWidget);
      // …and the menu row offering the same action is suppressed here only.
      expect(find.text(loc.backupSettingsStartBackup), findsNothing);
    },
  );

  testWidgets('names the encrypted vault menu row after the status row', (
    tester,
  ) async {
    await pumpScreen(tester, physicalTested: false, vaultTested: false);

    expect(find.text(loc.backupSettingsEncryptedVaultSettings), findsOneWidget);
  });

  group('the fork metadata backup controls', () {
    testWidgets('show one unified Bull backup lifecycle', (tester) async {
      await pumpScreen(tester, physicalTested: false, vaultTested: false);

      expect(find.text('Bull backup'), findsOneWidget);
      expect(find.text('Automatic Bull backup'), findsOneWidget);
      expect(find.text('Wallet metadata backup'), findsNothing);
      expect(find.text('Delete wallet metadata backup'), findsNothing);
    });

    testWidgets('keep manual backup disabled while automatic backup is off', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        physicalTested: false,
        vaultTested: false,
        walletBackup: _FakeWalletBackupFacade(
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

      expect(find.text('Automatic backup is off'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Back up now'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('confirm deletion through the unified backup control', (
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
      await pumpScreen(
        tester,
        physicalTested: false,
        vaultTested: false,
        walletBackup: facade,
      );

      await tester.tap(find.text('Delete backup'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Bull backup?'), findsOneWidget);
      expect(facade.deleteCalls, 0);

      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(facade.deleteCalls, 1);
    });
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

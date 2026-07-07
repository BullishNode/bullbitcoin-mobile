import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_cubit.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_state.dart';
import 'package:bb_mobile/features/get_paid_settings/ui/screens/get_paid_settings_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bull_ui/bull_ui.dart'
    show BullInfoCard, BullSettingsEntryItem, BullSwitch, BullTopBar;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

// The locked off-warning copy, as a literal (not an arb reference) so a reword
// is caught.
const _lockedOffWarning =
    'You will need to manually re-enable the Get Paid feature you are '
    'activating now to recover funds you received with this feature.';

class _StubCubit extends Cubit<GetPaidSettingsState>
    implements GetPaidSettingsCubit {
  _StubCubit(super.initialState);

  @override
  Future<void> load() async {}

  @override
  Future<void> toggleAutomatedBackup(bool enabled) async {}
}

Future<void> _pump(WidgetTester tester, GetPaidSettingsState state) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<GetPaidSettingsCubit>.value(
        value: _StubCubit(state),
        child: const GetPaidSettingsScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders the bull_ui chrome, backup switch and recover row', (
    tester,
  ) async {
    await _pump(
      tester,
      const GetPaidSettingsState(
        status: GetPaidSettingsStatus.loaded,
        automatedBackupEnabled: true,
      ),
    );

    expect(find.byType(BullTopBar), findsOneWidget);
    expect(find.byType(BullSwitch), findsOneWidget);
    // Two entry rows: the backup toggle and the recover action.
    expect(find.byType(BullSettingsEntryItem), findsNWidgets(2));
    // Backup on → no warning.
    expect(find.byType(BullInfoCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backup off shows the locked warning in a BullInfoCard', (
    tester,
  ) async {
    await _pump(
      tester,
      const GetPaidSettingsState(
        status: GetPaidSettingsStatus.loaded,
        automatedBackupEnabled: false,
      ),
    );

    expect(find.byType(BullInfoCard), findsOneWidget);
    expect(find.text(_lockedOffWarning), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

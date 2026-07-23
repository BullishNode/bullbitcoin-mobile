import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/qr_display_widget.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/pos/presentation/pos_cubit.dart';
import 'package:bb_mobile/features/pos/presentation/pos_state.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/features/pos/ui/screens/pos_provisioning_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

const _terminalUrl = 'https://pay2.bull-wallet.com/pos/alice?ref=Shop%20One';

GetPaidWalletBehavior _behavior() => const GetPaidWalletBehavior(
  product: GetPaidWalletProduct.pos,
  walletId: 'w-103',
  hideOnHome: false,
  autoSweepEnabled: false,
);

PosState _editState({bool archived = false, GetPaidWalletBehavior? behavior}) {
  return PosState(
    status: archived ? PosStatus.archived : PosStatus.edit,
    permanentAlias: 'alice',
    terminal: const PosTerminal(
      nym: 'alice',
      label: 'Shop One',
      displayCurrency: 'CAD',
      enabled: true,
      isArchived: false,
      alias: 'alice',
      terminalUrl: _terminalUrl,
    ),
    label: 'Shop One',
    displayCurrency: 'CAD',
    walletBehavior: behavior,
  );
}

void main() {
  testWidgets(
    'an existing POS collapses the form, shows the exact-URL QR and staff '
    'instructions',
    (tester) async {
      await _pump(tester, _editState(behavior: _behavior()));

      expect(find.byKey(const Key('pos_edit_button')), findsOneWidget);
      expect(find.text('Save changes'), findsNothing);

      // The QR encodes the exact server-returned terminal URL, no
      // normalization.
      final qr = tester.widget<QrDisplayWidget>(find.byType(QrDisplayWidget));
      expect(qr.data, _terminalUrl);

      // Instructions for staff sit between the Fiat tile and Edit.
      expect(find.text('Instructions for staff'), findsOneWidget);
      expect(
        find.byKey(const Key('pos_advanced_settings_button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping Edit reveals the form and Cancel collapses it', (
    tester,
  ) async {
    await _pump(tester, _editState(behavior: _behavior()));

    await tester.tap(find.byKey(const Key('pos_edit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pos_cancel_edit')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('pos_edit_button')), findsOneWidget);
  });

  testWidgets('a dirty cancel confirms before discarding', (tester) async {
    final cubit = await _pump(tester, _editState(behavior: _behavior()));

    await tester.tap(find.byKey(const Key('pos_edit_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Changed label');
    await tester.pump();

    await tester.tap(find.byKey(const Key('pos_cancel_edit')));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(cubit.loadCalls, 2); // initial load + discard reload
    expect(find.byKey(const Key('pos_edit_button')), findsOneWidget);
  });

  testWidgets('a failed provision keeps the editor open', (tester) async {
    final cubit = await _pump(tester, _editState(behavior: _behavior()));
    cubit.failOnProvision = true;

    await tester.tap(find.byKey(const Key('pos_edit_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(cubit.provisionCalls, 1);
    expect(find.text('Save changes'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('a successful provision collapses the editor', (tester) async {
    final cubit = await _pump(tester, _editState(behavior: _behavior()));

    await tester.tap(find.byKey(const Key('pos_edit_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(cubit.provisionCalls, 1);
    expect(find.byKey(const Key('pos_edit_button')), findsOneWidget);
  });

  testWidgets('advanced settings opens the shared sheet with all controls', (
    tester,
  ) async {
    final cubit = await _pump(tester, _editState(behavior: _behavior()));

    await tester.tap(find.byKey(const Key('pos_advanced_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pos_online_switch')), findsOneWidget);
    expect(find.text('Auto-sweep'), findsOneWidget);
    expect(find.text('Hide on home'), findsOneWidget);

    await tester.ensureVisible(find.text('Auto-sweep'));
    await tester.tap(find.text('Auto-sweep'));
    await tester.pumpAndSettle();
    expect(cubit.behaviorWrites, [
      (walletId: 'w-103', hideOnHome: null, autoSweepEnabled: true),
    ]);
  });

  testWidgets('an archived POS reactivates through the advanced sheet', (
    tester,
  ) async {
    final cubit = await _pump(
      tester,
      _editState(archived: true, behavior: _behavior()),
    );

    expect(find.text('Point of Sale deactivated'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos_advanced_settings_button')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('pos_online_switch')));
    await tester.tap(find.byKey(const Key('pos_online_switch')));
    await tester.pumpAndSettle();
    expect(cubit.provisionCalls, 1);
  });

  testWidgets('the staff instructions expand to the owner-verbatim copy', (
    tester,
  ) async {
    await _pump(tester, _editState(behavior: _behavior()));

    expect(
      find.text('Two ways for your staff to accept Bitcoin payments'),
      findsNothing,
    );
    await tester.tap(find.text('Instructions for staff'));
    await tester.pumpAndSettle();
    expect(
      find.text('Two ways for your staff to accept Bitcoin payments'),
      findsOneWidget,
    );
  });
}

Future<_StubPosCubit> _pump(WidgetTester tester, PosState state) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final cubit = _StubPosCubit(state);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<PosCubit>.value(
        value: cubit,
        child: const PosProvisioningScreen(),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

class _StubPosCubit extends Cubit<PosState> implements PosCubit {
  _StubPosCubit(super.initialState);

  int loadCalls = 0;
  int provisionCalls = 0;
  bool failOnProvision = false;
  final List<({String walletId, bool? hideOnHome, bool? autoSweepEnabled})>
  behaviorWrites = [];

  @override
  Future<void> load() async {
    loadCalls += 1;
  }

  @override
  Future<void> provision() async {
    provisionCalls += 1;
    if (failOnProvision) {
      emit(state.copyWith(failure: const PosException.network()));
    }
  }

  @override
  Future<void> setOnline(bool online) async {}

  @override
  Future<void> archive() async {}

  @override
  Future<void> retryCurrencies() async {}

  @override
  void aliasDraftChanged(String value) =>
      emit(state.copyWith(aliasDraft: value));

  @override
  void labelChanged(String value) => emit(state.copyWith(label: value));

  @override
  void displayCurrencyChanged(String value) =>
      emit(state.copyWith(displayCurrency: value));

  @override
  Future<void> updateWalletBehavior({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {
    behaviorWrites.add((
      walletId: walletId,
      hideOnHome: hideOnHome,
      autoSweepEnabled: autoSweepEnabled,
    ));
  }
}

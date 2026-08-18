import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_state.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/payment_page/ui/screens/payment_page_editor_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

GetPaidWalletBehavior _behavior() => const GetPaidWalletBehavior(
  product: GetPaidWalletProduct.paymentPage,
  walletId: 'w-102',
  hideOnHome: false,
  autoSweepEnabled: false,
);

PaymentPageState _editState({
  bool archived = false,
  GetPaidWalletBehavior? behavior,
  bool walletBehaviorUnavailable = false,
}) {
  return PaymentPageState(
    status: archived ? PaymentPageStatus.archived : PaymentPageStatus.edit,
    permanentAlias: 'alice',
    page: const PaymentPage(
      nym: 'alice',
      header: 'Header',
      description: 'Description',
      displayCurrency: 'CAD',
      enabled: true,
      isArchived: false,
      alias: 'alice',
      publicUrl: 'https://pay2.bull-wallet.com/alice',
    ),
    header: 'Header',
    description: 'Description',
    displayCurrency: 'CAD',
    walletBehavior: behavior,
    walletBehaviorUnavailable: walletBehaviorUnavailable,
  );
}

PaymentPageState _createState({
  PaymentPageField? invalidField,
  PaymentPageException? failure,
  String aliasDraft = 'taken-alias',
}) {
  return PaymentPageState(
    status: PaymentPageStatus.create,
    nym: 'alice',
    aliasDraft: aliasDraft,
    displayCurrency: 'CAD',
    invalidField: invalidField,
    failure: failure,
  );
}

void main() {
  testWidgets('keeps wallet settings unavailability visibly stated', (
    tester,
  ) async {
    final cubit = await _pump(
      tester,
      _editState(walletBehaviorUnavailable: true),
    );

    expect(
      find.byKey(const Key('get_paid_wallet_behavior_unavailable_warning')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Wallet settings are temporarily unavailable. '
        'Try again.',
      ),
      findsOneWidget,
    );
    final priorLoads = cubit.loadCalls;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(cubit.loadCalls, priorLoads);
    expect(cubit.retryWalletBehaviorCalls, 1);
  });

  testWidgets('creation collects no display currency (payer picks on the '
      'hosted page)', (tester) async {
    await _pump(tester, _createState());

    // The alias claim and page fields are present, but no currency selector.
    expect(find.byKey(const Key('payment_page_alias_field')), findsOneWidget);
    expect(find.text('Display currency'), findsNothing);
    expect(find.text('Choose a currency'), findsNothing);
  });

  testWidgets('an alias-taken rejection shows the taken copy on the field, not '
      'the format rule', (tester) async {
    await _pump(
      tester,
      _createState(
        invalidField: PaymentPageField.alias,
        failure: const PaymentPageException.aliasTaken(),
      ),
    );

    expect(
      find.text('That alias is already claimed. Choose another.'),
      findsOneWidget,
    );
    expect(
      find.text('Use 1–32 lowercase letters, numbers, or internal hyphens'),
      findsNothing,
    );
  });

  testWidgets('a format failure still shows the format rule on the field', (
    tester,
  ) async {
    await _pump(
      tester,
      _createState(
        invalidField: PaymentPageField.alias,
        failure: const PaymentPageException.invalidInput(code: 'alias'),
      ),
    );

    expect(
      find.text('Use 1–32 lowercase letters, numbers, or internal hyphens'),
      findsOneWidget,
    );
    expect(
      find.text('That alias is already claimed. Choose another.'),
      findsNothing,
    );
  });

  testWidgets('no nym yet shows the shared claim step in the Page flow', (
    tester,
  ) async {
    final cubit = await _pump(
      tester,
      const PaymentPageState(status: PaymentPageStatus.needsNym),
    );

    expect(find.text('Claim your Bull Nym'), findsOneWidget);
    expect(
      find.text(
        'This is a permanent anonymous identity linked to your Bitcoin wallet '
        'and will become your public Lightning Address.',
      ),
      findsOneWidget,
    );
    // One field, and no instruction to go claim it in Lightning Address.
    expect(find.byKey(const Key('get_paid_nym_claim_field')), findsOneWidget);
    expect(
      find.textContaining('Claim your permanent name in Lightning Address'),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const Key('get_paid_nym_claim_field')),
      'alice',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('get_paid_nym_claim_submit')));
    await tester.pumpAndSettle();

    expect(cubit.claimNymCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a rejected nym is stated on the claim step, not swallowed', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentPageState(
        status: PaymentPageStatus.needsNym,
        nymDraft: 'alice',
        invalidField: PaymentPageField.nym,
        failure: PaymentPageException.nymTaken(),
      ),
    );

    expect(
      find.text('That name is already owned. Choose another available name.'),
      findsOneWidget,
    );
    // Drain the failure snackbar's timer.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('the nym is the default: stated, with only the alias opt-out', (
    tester,
  ) async {
    await _pump(tester, _createState(aliasDraft: ''));

    expect(find.text('Your nym is alice'), findsOneWidget);
    expect(
      find.text(
        'You can reuse this nym for your Donation Page and it will be publicly '
        'visible. You can optionally choose another Alias, separate from your '
        'Lightning Address, for the Point of Sale and Donation Page.',
      ),
      findsOneWidget,
    );
    // Keeping the nym takes no action, so there is nothing to press for it.
    expect(find.text('Use my nym'), findsNothing);
    expect(find.byKey(const Key('get_paid_choose_an_alias')), findsOneWidget);
    // The alias field stays hidden until the alias branch is chosen.
    expect(find.byKey(const Key('payment_page_alias_field')), findsNothing);
  });

  testWidgets('creating without choosing an alias uses the nym', (
    tester,
  ) async {
    final cubit = await _pump(tester, _createState(aliasDraft: ''));

    await tester.tap(find.text('Create Donation Page'));
    await tester.pumpAndSettle();

    expect(cubit.saveCalls, 1);
    expect(cubit.state.command.aliasClaim, isNull);
  });

  testWidgets('Choose an alias reveals the field with one permanence line', (
    tester,
  ) async {
    await _pump(tester, _createState(aliasDraft: ''));

    await tester.tap(find.byKey(const Key('get_paid_choose_an_alias')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment_page_alias_field')), findsOneWidget);
    expect(
      find.text(
        'One shared alias for Donation Page and Point of Sale. Once claimed, '
        'it cannot be changed, cleared, or replaced.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a created page shows no naming UI at all', (tester) async {
    await _pump(tester, _editState(behavior: _behavior()));

    expect(find.byKey(const Key('get_paid_choose_an_alias')), findsNothing);
    expect(find.byKey(const Key('payment_page_alias_field')), findsNothing);
    expect(find.textContaining('Your nym is'), findsNothing);
    expect(find.textContaining('Permanent alias shared'), findsNothing);
  });

  testWidgets('a created page leads with its link and a QR', (tester) async {
    await _pump(tester, _editState(behavior: _behavior()));

    // Presented exactly like the POS terminal link: the shared QR block.
    expect(find.byType(GetPaidLinkQr), findsOneWidget);
    expect(find.text('https://pay2.bull-wallet.com/alice'), findsOneWidget);
    final linkY = tester.getTopLeft(find.text('Your Donation Page link')).dy;
    final noticeY = tester
        .getTopLeft(find.textContaining('has its own link and its own wallet'))
        .dy;
    expect(linkY, lessThan(noticeY));
  });

  testWidgets('an existing page keeps the edit form collapsed behind Edit', (
    tester,
  ) async {
    await _pump(tester, _editState(behavior: _behavior()));

    expect(find.byKey(const Key('payment_page_edit_button')), findsOneWidget);
    // The form fields and Save action are hidden until Edit is tapped.
    expect(find.text('Save changes'), findsNothing);
    expect(find.text('Header'), findsNothing);
    expect(
      find.byKey(const Key('payment_page_advanced_settings_button')),
      findsOneWidget,
    );
  });

  testWidgets('tapping Edit reveals the form and Cancel collapses it', (
    tester,
  ) async {
    await _pump(tester, _editState(behavior: _behavior()));

    await tester.tap(find.byKey(const Key('payment_page_edit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Header'), findsOneWidget);

    // No unsaved changes → cancelling collapses without a confirm dialog.
    await tester.tap(find.byKey(const Key('payment_page_cancel_edit')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('payment_page_edit_button')), findsOneWidget);
  });

  testWidgets('a dirty cancel confirms before discarding', (tester) async {
    final cubit = await _pump(tester, _editState(behavior: _behavior()));

    await tester.tap(find.byKey(const Key('payment_page_edit_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Changed header');
    await tester.pump();

    await tester.tap(find.byKey(const Key('payment_page_cancel_edit')));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    // Keeping editing dismisses the dialog and leaves the form open.
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsOneWidget);
    expect(cubit.loadCalls, 1); // only the initial load; no discard reload yet

    // Discarding reloads the persisted values and collapses the form.
    await tester.tap(find.byKey(const Key('payment_page_cancel_edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(cubit.loadCalls, 2);
    expect(find.byKey(const Key('payment_page_edit_button')), findsOneWidget);
  });

  testWidgets('a failed save keeps the editor open', (tester) async {
    final cubit = await _pump(tester, _editState(behavior: _behavior()));
    cubit.failOnSave = true;

    await tester.tap(find.byKey(const Key('payment_page_edit_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(cubit.saveCalls, 1);
    expect(find.text('Save changes'), findsOneWidget); // still open to retry
    // Drain the failure snackbar's timer.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('a successful save collapses the editor', (tester) async {
    final cubit = await _pump(tester, _editState(behavior: _behavior()));

    await tester.tap(find.byKey(const Key('payment_page_edit_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(cubit.saveCalls, 1);
    expect(find.byKey(const Key('payment_page_edit_button')), findsOneWidget);
  });

  testWidgets('advanced settings opens the shared sheet with all controls', (
    tester,
  ) async {
    final cubit = await _pump(tester, _editState(behavior: _behavior()));

    await tester.tap(
      find.byKey(const Key('payment_page_advanced_settings_button')),
    );
    await tester.pumpAndSettle();

    // The shared sheet is open: its three controls are present.
    expect(find.byKey(const Key('payment_page_online_switch')), findsOneWidget);
    expect(find.text('Auto-sweep'), findsOneWidget);
    expect(find.text('Hide on home'), findsOneWidget);

    await tester.ensureVisible(find.text('Auto-sweep'));
    await tester.tap(find.text('Auto-sweep'));
    await tester.pumpAndSettle();
    expect(cubit.behaviorWrites, [
      (walletId: 'w-102', hideOnHome: null, autoSweepEnabled: true),
    ]);
  });

  testWidgets('an archived page reactivates through the advanced sheet', (
    tester,
  ) async {
    final cubit = await _pump(
      tester,
      _editState(archived: true, behavior: _behavior()),
    );

    expect(find.text('Donation Page deactivated'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('payment_page_advanced_settings_button')),
    );
    await tester.pumpAndSettle();

    // The online switch reflects the archived (off) state; turning it on saves.
    await tester.ensureVisible(
      find.byKey(const Key('payment_page_online_switch')),
    );
    await tester.tap(find.byKey(const Key('payment_page_online_switch')));
    await tester.pumpAndSettle();
    expect(cubit.saveCalls, 1);
  });
}

Future<_StubPageCubit> _pump(
  WidgetTester tester,
  PaymentPageState state,
) async {
  // A tall surface so the whole (lazily-built) ListView is laid out and every
  // section is findable/tappable without scroll juggling.
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final cubit = _StubPageCubit(state);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<PaymentPageCubit>.value(
        value: cubit,
        child: const PaymentPageEditorScreen(),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

class _StubPageCubit extends Cubit<PaymentPageState>
    implements PaymentPageCubit {
  _StubPageCubit(super.initialState);

  int loadCalls = 0;
  int retryWalletBehaviorCalls = 0;
  int saveCalls = 0;
  int claimNymCalls = 0;
  bool failOnSave = false;
  final List<({String walletId, bool? hideOnHome, bool? autoSweepEnabled})>
  behaviorWrites = [];

  @override
  Future<void> load() async {
    loadCalls += 1;
  }

  @override
  Future<void> retryWalletBehavior() async {
    retryWalletBehaviorCalls += 1;
  }

  @override
  Future<void> save() async {
    saveCalls += 1;
    if (failOnSave) {
      emit(state.copyWith(failure: const PaymentPageException.network()));
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
  void nymDraftChanged(String value) => emit(state.copyWith(nymDraft: value));

  @override
  Future<void> claimNym() async {
    claimNymCalls += 1;
  }

  @override
  void headerChanged(String value) => emit(state.copyWith(header: value));

  @override
  void descriptionChanged(String value) =>
      emit(state.copyWith(description: value));

  @override
  void displayCurrencyChanged(String value) =>
      emit(state.copyWith(displayCurrency: value));

  @override
  void websiteChanged(String value) => emit(state.copyWith(website: value));

  @override
  void twitterChanged(String value) => emit(state.copyWith(twitter: value));

  @override
  void instagramChanged(String value) => emit(state.copyWith(instagram: value));

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

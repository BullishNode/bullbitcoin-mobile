import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/invoices/domain/usecases/get_invoice_settlement_constraints_usecase.dart';
import 'package:bb_mobile/features/invoices/presentation/invoice_create_cubit.dart';
import 'package:bb_mobile/features/invoices/ui/screens/invoice_create_screen.dart';
import 'package:bb_mobile/features/invoices/ui/widgets/invoice_amount_card.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFacade extends Mock implements InvoicesFacade {}

class _MockSettlementConstraints extends Mock
    implements GetInvoiceSettlementConstraintsUsecase {}

class _MockGetSettings extends Mock implements GetSettingsUsecase {}

void main() {
  late _MockFacade facade;
  late InvoiceCreateCubit cubit;

  setUp(() async {
    facade = _MockFacade();
    when(() => facade.resumeCreate()).thenAnswer(
      (_) async => const Ok<CreateInvoiceResult?, InvoicesFailure>(null),
    );
    when(() => facade.supportedCurrencies()).thenAnswer(
      (_) async => const Ok<BullnymSupportedCurrencies, InvoicesFailure>(
        BullnymSupportedCurrencies(currencies: []),
      ),
    );
    cubit = InvoiceCreateCubit(facade: facade);
    await cubit.initialize();
  });

  tearDown(() => cubit.close());

  testWidgets('optional private details are collapsed and preserve values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<InvoiceCreateCubit>.value(
          value: cubit,
          child: const InvoiceCreateScreen(),
        ),
      ),
    );

    expect(find.text('Add invoice details (optional)'), findsOneWidget);
    expect(find.text('Payer'), findsNothing);
    expect(find.text('Invoice'), findsNothing);
    expect(find.text('Payee'), findsNothing);
    expect(find.text('Private note (only you)'), findsNothing);
    expect(find.textContaining('Expires in'), findsNothing);

    await tester.tap(find.text('Add invoice details (optional)'));
    await tester.pump();
    expect(find.text('Payer'), findsOneWidget);
    expect(find.text('Invoice'), findsOneWidget);
    expect(find.text('Payee'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Name').first,
      'Jane',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Corporate name').first,
      'Example Corp',
    );
    await tester.pump();
    expect(find.text('Invoice details · 2 fields added'), findsOneWidget);

    final detailsLabel = find.text('Invoice details · 2 fields added');
    await tester.ensureVisible(detailsLabel);
    await tester.pump();
    await tester.tap(
      find.ancestor(of: detailsLabel, matching: find.byType(ListTile)),
    );
    await tester.pump();
    expect(find.text('Payer'), findsNothing);

    await tester.tap(
      find.ancestor(of: detailsLabel, matching: find.byType(ListTile)),
    );
    await tester.pump();
    expect(find.text('Jane'), findsOneWidget);
    expect(find.text('Example Corp'), findsOneWidget);
  });

  testWidgets('mixed settlement explains and disables direct Liquid', (
    tester,
  ) async {
    await cubit.close();
    final constraints = _MockSettlementConstraints();
    when(() => constraints.execute()).thenAnswer(
      (_) async =>
          const InvoiceSettlementConstraints(directLiquidAvailable: false),
    );
    cubit = InvoiceCreateCubit(
      facade: facade,
      settlementConstraints: constraints,
    );
    await cubit.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<InvoiceCreateCubit>.value(
          value: cubit,
          child: const InvoiceCreateScreen(),
        ),
      ),
    );

    // The rails are collapsed by default; reveal them before inspecting.
    await tester.tap(find.byKey(const Key('invoice_edit_rails_button')));
    await tester.pump();

    final liquid = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Liquid'),
    );
    expect(liquid.value, isFalse);
    expect(liquid.onChanged, isNull);
    expect(
      find.text(
        'Direct Liquid payments are unavailable when this invoice is split between Bitcoin and fiat.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'amount card defaults to fiat, toggles denomination, and has no Max',
    (tester) async {
      await cubit.close();
      cubit = await _fiatSeededCubit(facade);

      await _pumpScreen(tester, cubit);

      // Default entry denomination is the user's fiat, with no balance Max.
      expect(find.byType(InvoiceAmountCard), findsOneWidget);
      expect(find.text('Max'), findsNothing);
      expect(find.text('MAX'), findsNothing);
      final card = tester.widget<InvoiceAmountCard>(
        find.byType(InvoiceAmountCard),
      );
      expect(card.fiatCurrency, 'CAD');

      await tester.tap(find.byKey(const Key('invoice_amount_toggle')));
      await tester.pump();
      expect(find.text('sats'), findsWidgets);
    },
  );

  testWidgets('payer and payee sections carry the owner descriptions', (
    tester,
  ) async {
    await cubit.close();
    cubit = await _fiatSeededCubit(facade);

    await _pumpScreen(tester, cubit);
    await tester.tap(find.text('Add invoice details (optional)'));
    await tester.pumpAndSettle();

    expect(find.text('Information about who is paying you.'), findsOneWidget);
    expect(find.text('Information about you.'), findsOneWidget);
  });

  testWidgets('the last enabled rail is locked on with a hint', (tester) async {
    await cubit.close();
    cubit = await _fiatSeededCubit(facade);

    await _pumpScreen(tester, cubit);

    // The rails are collapsed by default; reveal them first.
    await tester.tap(find.byKey(const Key('invoice_edit_rails_button')));
    await tester.pump();

    // Turn off two of the three rails; the third must stay locked on.
    await tester.tap(find.widgetWithText(SwitchListTile, 'On-chain Bitcoin'));
    await tester.pump();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Liquid'));
    await tester.pump();

    final lightning = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Lightning'),
    );
    expect(lightning.value, isTrue);
    expect(lightning.onChanged, isNull);
    expect(
      find.text('At least one payment method is required.'),
      findsOneWidget,
    );
  });

  testWidgets('accepted payment methods are collapsed behind an Edit button '
      'and stay respected on submit', (tester) async {
    await cubit.close();
    cubit = await _fiatSeededCubit(facade);

    await _pumpScreen(tester, cubit);

    // Collapsed by default: the Edit button shows; no toggles, no section label.
    expect(find.byKey(const Key('invoice_edit_rails_button')), findsOneWidget);
    expect(find.text('Accepted payment methods'), findsNothing);
    expect(find.widgetWithText(SwitchListTile, 'Lightning'), findsNothing);
    expect(
      find.widgetWithText(SwitchListTile, 'On-chain Bitcoin'),
      findsNothing,
    );

    // Tapping reveals the toggles and the section label.
    await tester.tap(find.byKey(const Key('invoice_edit_rails_button')));
    await tester.pump();
    expect(find.text('Accepted payment methods'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Lightning'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Liquid'), findsOneWidget);
    expect(
      find.widgetWithText(SwitchListTile, 'On-chain Bitcoin'),
      findsOneWidget,
    );

    // A toggle change is still carried in state (what submit uses).
    expect(cubit.state.acceptBtc, isTrue);
    await tester.tap(find.widgetWithText(SwitchListTile, 'On-chain Bitcoin'));
    await tester.pump();
    expect(cubit.state.acceptBtc, isFalse);
  });
}

Future<InvoiceCreateCubit> _fiatSeededCubit(_MockFacade facade) async {
  when(() => facade.supportedCurrencies()).thenAnswer(
    (_) async => const Ok<BullnymSupportedCurrencies, InvoicesFailure>(
      BullnymSupportedCurrencies(
        currencies: [BullnymSupportedCurrency(code: 'CAD', precision: 2)],
      ),
    ),
  );
  final getSettings = _MockGetSettings();
  when(() => getSettings.execute()).thenAnswer(
    (_) async => SettingsEntity(
      environment: Environment.mainnet,
      bitcoinUnit: BitcoinUnit.sats,
      currencyCode: 'CAD',
    ),
  );
  final cubit = InvoiceCreateCubit(facade: facade, getSettings: getSettings);
  await cubit.initialize();
  return cubit;
}

Future<void> _pumpScreen(WidgetTester tester, InvoiceCreateCubit cubit) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<InvoiceCreateCubit>.value(
        value: cubit,
        child: const InvoiceCreateScreen(),
      ),
    ),
  );
  await tester.pump();
}

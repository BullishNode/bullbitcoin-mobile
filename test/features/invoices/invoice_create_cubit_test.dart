import 'package:bb_mobile/core/exchange/domain/usecases/convert_currency_to_sats_amount_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/convert_sats_to_currency_amount_usecase.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/invoices/domain/entities/private_invoice_presentation.dart';
import 'package:bb_mobile/features/invoices/domain/usecases/get_invoice_settlement_constraints_usecase.dart';
import 'package:bb_mobile/features/invoices/presentation/invoice_create_cubit.dart';
import 'package:bb_mobile/features/invoices/presentation/invoice_create_state.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFacade extends Mock implements InvoicesFacade {}

class _MockSettlementConstraints extends Mock
    implements GetInvoiceSettlementConstraintsUsecase {}

class _MockGetSettings extends Mock implements GetSettingsUsecase {}

class _MockConvertToSats extends Mock
    implements ConvertCurrencyToSatsAmountUsecase {}

class _MockConvertToFiat extends Mock
    implements ConvertSatsToCurrencyAmountUsecase {}

SettingsEntity _settings({
  BitcoinUnit bitcoinUnit = BitcoinUnit.sats,
  String currencyCode = 'CAD',
}) => SettingsEntity(
  environment: Environment.mainnet,
  bitcoinUnit: bitcoinUnit,
  currencyCode: currencyCode,
);

void main() {
  final invoiceId = InvoiceId('inv-1');
  final result = CreateInvoiceResult(
    invoiceId: invoiceId,
    privateLink: PrivateInvoiceLink.fromServer(
      invoiceUrl: 'https://pay2.bull-wallet.com/invoice/inv-1',
      expectedInvoiceId: invoiceId,
      viewingKey: 'A' * 43,
      expectedOrigin: Uri.parse('https://pay2.bull-wallet.com'),
      expectedNym: null,
    ),
  );

  setUpAll(() {
    registerFallbackValue(
      CreateInvoiceCommand(
        amountSat: 1,
        presentation: PrivateInvoicePresentation(),
        acceptBtc: false,
        acceptLn: false,
        acceptLiquid: true,
      ),
    );
  });

  late _MockFacade facade;

  setUp(() {
    facade = _MockFacade();
    when(() => facade.resumeCreate()).thenAnswer(
      (_) async => const Ok<CreateInvoiceResult?, InvoicesFailure>(null),
    );
    when(() => facade.supportedCurrencies()).thenAnswer(
      (_) async => const Ok(
        BullnymSupportedCurrencies(
          currencies: [
            BullnymSupportedCurrency(code: 'CAD', precision: 2),
            BullnymSupportedCurrency(code: 'COP', precision: 0),
          ],
        ),
      ),
    );
  });

  Future<InvoiceCreateCubit> initialized() async {
    final cubit = InvoiceCreateCubit(facade: facade);
    await cubit.initialize();
    return cubit;
  }

  test(
    'bitcoin (sats) submit builds encrypted presentation domain data',
    () async {
      when(() => facade.create(any())).thenAnswer((_) async => Ok(result));
      final cubit = await initialized();
      cubit.amountModeChanged(InvoiceAmountMode.bitcoin);
      cubit.amountChanged('25000');
      cubit.detailChanged(InvoiceCreateField.payerName, ' Jane ');
      cubit.detailChanged(InvoiceCreateField.description, ' Design work ');
      cubit.detailChanged(InvoiceCreateField.invoiceDate, '2026-07-18');

      await cubit.submit();

      expect(cubit.state.result?.privateLink.value, contains('#v1.'));
      final sent =
          verify(() => facade.create(captureAny())).captured.single
              as CreateInvoiceCommand;
      expect(sent.amountSat, 25000);
      expect(sent.fiatAmountMinor, isNull);
      expect(sent.presentation.payer?.name, 'Jane');
      expect(sent.presentation.invoice?.description, 'Design work');
      expect(sent.presentation.invoice?.invoiceDate, '2026-07-18');
      await cubit.close();
    },
  );

  test('fiat submit converts to minor units by currency precision', () async {
    when(() => facade.create(any())).thenAnswer((_) async => Ok(result));
    final cubit = await initialized();
    cubit.amountModeChanged(InvoiceAmountMode.fiat);
    cubit.fiatCurrencyChanged('CAD');
    cubit.amountChanged('12.34');

    await cubit.submit();

    final sent =
        verify(() => facade.create(captureAny())).captured.single
            as CreateInvoiceCommand;
    expect(sent.fiatAmountMinor, 1234);
    expect(sent.fiatCurrency, 'CAD');
    expect(sent.amountSat, isNull);
    await cubit.close();
  });

  test('invalid private date identifies the exact form field', () async {
    final cubit = await initialized();
    cubit.amountChanged('1000');
    cubit.detailChanged(InvoiceCreateField.paymentDeadline, '2025-02-29');

    await cubit.submit();

    expect(cubit.state.invalidField, InvoiceCreateField.paymentDeadline);
    expect(cubit.state.failure?.kind, InvoicesFailureKind.invalidInput);
    verifyNever(() => facade.create(any()));
    await cubit.close();
  });

  test('the last enabled rail cannot be turned off (Q19)', () async {
    final cubit = await initialized();
    // Without a verified settlement constraint, direct Liquid fails closed.
    expect(cubit.state.acceptBtc, isTrue);
    expect(cubit.state.acceptLn, isTrue);
    expect(cubit.state.acceptLiquid, isFalse);

    cubit.acceptBtcChanged(false);
    // Only Lightning remains; the guard refuses to empty the last rail.
    cubit.acceptLnChanged(false);

    expect(cubit.state.acceptLn, isTrue);
    expect(cubit.state.enabledRailCount, 1);
    expect(cubit.state.hasAnyRail, isTrue);
    await cubit.close();
  });

  test('uncertain create locks the form into exact-operation retry', () async {
    when(
      () => facade.create(any()),
    ).thenAnswer((_) async => const Err(InvoicesFailure.outcomeUnknown()));
    var resumeCalls = 0;
    when(() => facade.resumeCreate()).thenAnswer((_) async {
      resumeCalls++;
      return resumeCalls == 1
          ? const Ok<CreateInvoiceResult?, InvoicesFailure>(null)
          : Ok<CreateInvoiceResult?, InvoicesFailure>(result);
    });
    final cubit = InvoiceCreateCubit(facade: facade);
    await cubit.initialize();
    cubit.amountChanged('1000');

    await cubit.submit();
    expect(cubit.state.pendingRetry, isTrue);
    await cubit.retryPending();

    expect(cubit.state.result, result);
    verify(() => facade.resumeCreate()).called(2);
    await cubit.close();
  });

  test(
    'startup resumes a pending operation before loading currencies',
    () async {
      when(() => facade.resumeCreate()).thenAnswer(
        (_) async => Ok<CreateInvoiceResult?, InvoicesFailure>(result),
      );
      final cubit = InvoiceCreateCubit(facade: facade);

      await cubit.initialize();

      expect(cubit.state.result, result);
      verifyNever(() => facade.supportedCurrencies());
      await cubit.close();
    },
  );

  test('double submit is inert after success', () async {
    when(() => facade.create(any())).thenAnswer((_) async => Ok(result));
    final cubit = await initialized();
    cubit.amountChanged('1000');

    await cubit.submit();
    await cubit.submit();

    verify(() => facade.create(any())).called(1);
    await cubit.close();
  });

  test('mixed invoice settlement disables direct Liquid', () async {
    final settlementConstraints = _MockSettlementConstraints();
    when(() => settlementConstraints.execute()).thenAnswer(
      (_) async =>
          const InvoiceSettlementConstraints(directLiquidAvailable: false),
    );
    final cubit = InvoiceCreateCubit(
      facade: facade,
      settlementConstraints: settlementConstraints,
    );

    await cubit.initialize();

    expect(cubit.state.directLiquidAvailable, isFalse);
    expect(cubit.state.acceptLiquid, isFalse);
    cubit.acceptLiquidChanged(true);
    expect(cubit.state.acceptLiquid, isFalse);
    await cubit.close();
  });

  test('fiat-only invoice settlement keeps direct Liquid available', () async {
    final settlementConstraints = _MockSettlementConstraints();
    when(() => settlementConstraints.execute()).thenAnswer(
      (_) async =>
          const InvoiceSettlementConstraints(directLiquidAvailable: true),
    );
    final cubit = InvoiceCreateCubit(
      facade: facade,
      settlementConstraints: settlementConstraints,
    );

    await cubit.initialize();

    expect(cubit.state.directLiquidAvailable, isTrue);
    expect(cubit.state.acceptLiquid, isTrue);
    await cubit.close();
  });

  test('defaults to fiat entry in the user\'s currency (Q16)', () async {
    final getSettings = _MockGetSettings();
    when(
      () => getSettings.execute(),
    ).thenAnswer((_) async => _settings(currencyCode: 'USD'));
    final cubit = InvoiceCreateCubit(facade: facade, getSettings: getSettings);

    await cubit.initialize();

    expect(cubit.state.amountMode, InvoiceAmountMode.fiat);
    expect(cubit.state.fiatCurrency, 'USD');
    await cubit.close();
  });

  test(
    'an unwired settlement constraint fails closed for direct Liquid',
    () async {
      final cubit = await initialized();
      expect(cubit.state.acceptBtc, isTrue);
      expect(cubit.state.acceptLn, isTrue);
      expect(cubit.state.acceptLiquid, isFalse);
      expect(cubit.state.directLiquidAvailable, isFalse);
      await cubit.close();
    },
  );

  test(
    'BTC-unit entry converts to exact satoshis (submitted command)',
    () async {
      when(() => facade.create(any())).thenAnswer((_) async => Ok(result));
      final getSettings = _MockGetSettings();
      when(
        () => getSettings.execute(),
      ).thenAnswer((_) async => _settings(bitcoinUnit: BitcoinUnit.btc));
      final cubit = InvoiceCreateCubit(
        facade: facade,
        getSettings: getSettings,
      );
      await cubit.initialize();

      cubit.amountModeChanged(InvoiceAmountMode.bitcoin);
      cubit.amountChanged('0.00012345');
      await cubit.submit();

      final sent =
          verify(() => facade.create(captureAny())).captured.single
              as CreateInvoiceCommand;
      expect(sent.amountSat, 12345);
      expect(sent.fiatAmountMinor, isNull);
      await cubit.close();
    },
  );

  test('toggling denomination clears the amount input', () async {
    final cubit = await initialized();
    cubit.amountChanged('123');
    expect(cubit.state.amountInput, '123');

    cubit.amountModeChanged(InvoiceAmountMode.bitcoin);
    expect(cubit.state.amountInput, '');
    await cubit.close();
  });

  test('a fiat entry publishes a live sats equivalent', () async {
    final getSettings = _MockGetSettings();
    when(
      () => getSettings.execute(),
    ).thenAnswer((_) async => _settings(currencyCode: 'CAD'));
    final convertToSats = _MockConvertToSats();
    when(
      () => convertToSats.execute(
        amountFiat: any(named: 'amountFiat'),
        currencyCode: any(named: 'currencyCode'),
      ),
    ).thenAnswer((_) async => BigInt.from(54321));
    final cubit = InvoiceCreateCubit(
      facade: facade,
      getSettings: getSettings,
      convertToSats: convertToSats,
    );
    await cubit.initialize();

    cubit.amountChanged('10');
    // Let the async equivalent computation settle.
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.equivalentLabel, contains('54,321'));
    await cubit.close();
  });

  test('a bitcoin entry publishes a live fiat equivalent', () async {
    final getSettings = _MockGetSettings();
    when(
      () => getSettings.execute(),
    ).thenAnswer((_) async => _settings(currencyCode: 'CAD'));
    final convertToFiat = _MockConvertToFiat();
    when(
      () => convertToFiat.execute(
        amountSat: any(named: 'amountSat'),
        currencyCode: any(named: 'currencyCode'),
      ),
    ).thenAnswer((_) async => 12.34);
    final cubit = InvoiceCreateCubit(
      facade: facade,
      getSettings: getSettings,
      convertToFiat: convertToFiat,
    );
    await cubit.initialize();

    cubit.amountModeChanged(InvoiceAmountMode.bitcoin);
    cubit.amountChanged('50000');
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.equivalentLabel, contains('12.34'));
    await cubit.close();
  });

  test(
    'initialize derives no invoice (addresses are a submit-only concern)',
    () async {
      final cubit = await initialized();
      // Nothing that could derive an address runs on screen open.
      verifyNever(() => facade.create(any()));

      when(() => facade.create(any())).thenAnswer((_) async => Ok(result));
      cubit.amountModeChanged(InvoiceAmountMode.bitcoin);
      cubit.amountChanged('1000');
      await cubit.submit();
      verify(() => facade.create(any())).called(1);
      await cubit.close();
    },
  );

  test('payer and payee ride only the encrypted presentation', () async {
    when(() => facade.create(any())).thenAnswer((_) async => Ok(result));
    final cubit = await initialized();
    cubit.amountModeChanged(InvoiceAmountMode.bitcoin);
    cubit.amountChanged('1000');
    cubit.detailChanged(InvoiceCreateField.payerName, 'Alice Payer');
    cubit.detailChanged(InvoiceCreateField.payeeName, 'Bob Payee');

    await cubit.submit();

    final sent =
        verify(() => facade.create(captureAny())).captured.single
            as CreateInvoiceCommand;
    // The command's only text channel is the client-encrypted presentation;
    // there is no plaintext note/memo field for the free text to leak into.
    expect(sent.presentation.payer?.name, 'Alice Payer');
    expect(sent.presentation.payee?.name, 'Bob Payee');
    expect(sent.amountSat, 1000);
    expect(sent.fiatAmountMinor, isNull);
    expect(sent.fiatCurrency, isNull);
    await cubit.close();
  });

  test('a mixed merchant never renders Liquid on before it is disabled', () async {
    final settlementConstraints = _MockSettlementConstraints();
    when(() => settlementConstraints.execute()).thenAnswer(
      (_) async =>
          const InvoiceSettlementConstraints(directLiquidAvailable: false),
    );
    final cubit = InvoiceCreateCubit(
      facade: facade,
      settlementConstraints: settlementConstraints,
    );
    final seen = <InvoiceCreateState>[];
    final sub = cubit.stream.listen(seen.add);

    await cubit.initialize();
    await pumpEventQueue();

    // Every state the form is ever shown in (initializing == false) already has
    // Liquid disabled — the toggles never render Liquid on-then-off (no flicker).
    final visible = seen.where((s) => !s.initializing).toList();
    expect(visible, isNotEmpty);
    expect(visible.every((s) => !s.acceptLiquid), isTrue);
    expect(visible.every((s) => !s.directLiquidAvailable), isTrue);
    await sub.cancel();
    await cubit.close();
  });
}

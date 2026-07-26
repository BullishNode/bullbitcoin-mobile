import 'dart:async';

import 'package:bb_mobile/core/exchange/domain/usecases/convert_currency_to_sats_amount_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/convert_sats_to_currency_amount_usecase.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/amount_formatting.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/invoices/domain/entities/private_invoice_presentation.dart';
import 'package:bb_mobile/features/invoices/domain/usecases/get_invoice_settlement_constraints_usecase.dart';
import 'package:bb_mobile/features/invoices/presentation/invoice_create_state.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class InvoiceCreateCubit extends Cubit<InvoiceCreateState> {
  final InvoicesFacade _facade;
  final GetInvoiceSettlementConstraintsUsecase? _settlementConstraints;
  final GetSettingsUsecase? _getSettings;
  final ConvertCurrencyToSatsAmountUsecase? _convertToSats;
  final ConvertSatsToCurrencyAmountUsecase? _convertToFiat;
  int _operationId = 0;
  int _equivalentOp = 0;

  /// The user's default fiat currency, captured at init. The cross-denomination
  /// equivalent is only computed against it (the conversion services resolve
  /// the rate for the user's default currency), so a non-default invoice
  /// currency simply hides the approximate line rather than showing a wrong one.
  String _defaultCurrency = '';

  InvoiceCreateCubit({
    required InvoicesFacade facade,
    GetInvoiceSettlementConstraintsUsecase? settlementConstraints,
    GetSettingsUsecase? getSettings,
    ConvertCurrencyToSatsAmountUsecase? convertToSats,
    ConvertSatsToCurrencyAmountUsecase? convertToFiat,
  }) : this._(
         facade,
         settlementConstraints,
         getSettings,
         convertToSats,
         convertToFiat,
       );

  InvoiceCreateCubit._(
    this._facade,
    this._settlementConstraints,
    this._getSettings,
    this._convertToSats,
    this._convertToFiat,
  ) : super(const InvoiceCreateState());

  Future<void> initialize() async {
    final result = await _facade.resumeCreate();
    if (isClosed) return;
    switch (result) {
      case Ok(:final value):
        if (value != null) {
          emit(state.copyWith(initializing: false, result: value));
          return;
        }
      case Err(:final failure):
        emit(
          state.copyWith(
            initializing: false,
            pendingRetry: true,
            failure: failure,
          ),
        );
        return;
    }
    // Seed the fiat-first defaults and load currencies + the settlement
    // constraints BEFORE clearing `initializing`, so the rail toggles render
    // once with the correct Liquid state (a mixed merchant never sees Liquid
    // flip on-then-off) and the amount card opens in the user's fiat.
    await _seedDefaults();
    await _loadCurrencies();
    await refreshFiatSettlement();
    if (isClosed) return;
    emit(state.copyWith(initializing: false));
    await _recomputeEquivalent();
  }

  Future<void> _seedDefaults() async {
    final getSettings = _getSettings;
    if (getSettings == null) return;
    try {
      final settings = await getSettings.execute();
      if (isClosed) return;
      _defaultCurrency = settings.currencyCode;
      emit(
        state.copyWith(
          bitcoinUnit: settings.bitcoinUnit,
          fiatCurrency: state.fiatCurrency.isEmpty
              ? settings.currencyCode
              : state.fiatCurrency,
        ),
      );
    } on Exception {
      log.warning('Invoice default-currency lookup failed');
    }
  }

  Future<void> retryPending() async {
    if (state.submitting || !state.pendingRetry) return;
    final op = ++_operationId;
    emit(state.copyWith(submitting: true, clearFailure: true));
    final result = await _facade.resumeCreate();
    if (isClosed || op != _operationId) return;
    switch (result) {
      case Ok(:final value):
        if (value == null) {
          emit(
            state.copyWith(
              submitting: false,
              pendingRetry: false,
              clearFailure: true,
            ),
          );
          await _loadCurrencies();
          await refreshFiatSettlement();
        } else {
          emit(state.copyWith(submitting: false, result: value));
        }
      case Err(:final failure):
        emit(state.copyWith(submitting: false, failure: failure));
    }
  }

  Future<void> _loadCurrencies() async {
    final result = await _facade.supportedCurrencies();
    if (isClosed) return;
    switch (result) {
      case Ok(:final value):
        final currencies = value.currencies;
        emit(
          state.copyWith(
            currencies: currencies,
            currenciesUnavailable: false,
            fiatCurrency: state.fiatCurrency.isEmpty && currencies.isNotEmpty
                ? currencies.first.code
                : state.fiatCurrency,
          ),
        );
      case Err(:final failure):
        log.warning(
          'Invoice currency fetch failed',
          error: failure.logMessage ?? failure.code,
        );
        emit(state.copyWith(currenciesUnavailable: true));
    }
  }

  void amountModeChanged(InvoiceAmountMode value) {
    // Switching denomination clears the input: the formatters and unit differ,
    // and carrying a stale number across would misrepresent the new mode.
    _emit(
      state.copyWith(
        amountMode: value,
        amountInput: '',
        clearInvalidField: state.invalidField == InvoiceCreateField.amount,
      ),
    );
    unawaited(_recomputeEquivalent());
  }

  void amountChanged(String value) {
    _emit(
      state.copyWith(
        amountInput: value,
        clearInvalidField: state.invalidField == InvoiceCreateField.amount,
      ),
    );
    unawaited(_recomputeEquivalent());
  }

  void fiatCurrencyChanged(String value) {
    _emit(
      state.copyWith(
        fiatCurrency: value,
        clearInvalidField: state.invalidField == InvoiceCreateField.currency,
      ),
    );
    unawaited(_recomputeEquivalent());
  }

  // Rail toggles never permit disabling the last enabled rail (Q19): the UI
  // locks that toggle on, and this guard keeps the invariant if reached anyway.
  void acceptBtcChanged(bool value) {
    if (!value && state.isLastEnabledRail(state.acceptBtc)) return;
    _emit(state.copyWith(acceptBtc: value));
  }

  void acceptLnChanged(bool value) {
    if (!value && state.isLastEnabledRail(state.acceptLn)) return;
    _emit(state.copyWith(acceptLn: value));
  }

  void acceptLiquidChanged(bool value) {
    if (!state.directLiquidAvailable) return;
    if (!value && state.isLastEnabledRail(state.acceptLiquid)) return;
    _emit(state.copyWith(acceptLiquid: value));
  }

  Future<void> refreshFiatSettlement() async {
    final usecase = _settlementConstraints;
    if (usecase == null) return;
    final constraints = await usecase.execute();
    if (isClosed) return;
    emit(
      state.copyWith(
        directLiquidAvailable: constraints.directLiquidAvailable,
        acceptLiquid: constraints.directLiquidAvailable
            ? (state.initializing ? true : state.acceptLiquid)
            : false,
      ),
    );
  }

  void detailChanged(InvoiceCreateField field, String value) {
    final next = switch (field) {
      InvoiceCreateField.payerName => state.copyWith(payerName: value),
      InvoiceCreateField.payerCorporateName => state.copyWith(
        payerCorporateName: value,
      ),
      InvoiceCreateField.payerAddress => state.copyWith(payerAddress: value),
      InvoiceCreateField.payerEmail => state.copyWith(payerEmail: value),
      InvoiceCreateField.payerPhone => state.copyWith(payerPhone: value),
      InvoiceCreateField.description => state.copyWith(description: value),
      InvoiceCreateField.invoiceNumber => state.copyWith(invoiceNumber: value),
      InvoiceCreateField.purchaseOrderReference => state.copyWith(
        purchaseOrderReference: value,
      ),
      InvoiceCreateField.invoiceDate => state.copyWith(invoiceDate: value),
      InvoiceCreateField.paymentDeadline => state.copyWith(
        paymentDeadline: value,
      ),
      InvoiceCreateField.payeeName => state.copyWith(payeeName: value),
      InvoiceCreateField.payeeCorporateName => state.copyWith(
        payeeCorporateName: value,
      ),
      InvoiceCreateField.payeeAddress => state.copyWith(payeeAddress: value),
      InvoiceCreateField.payeeEmail => state.copyWith(payeeEmail: value),
      InvoiceCreateField.payeePhone => state.copyWith(payeePhone: value),
      _ => state,
    };
    _emit(
      next.copyWith(
        clearInvalidField:
            state.invalidField == field ||
            state.invalidField == InvoiceCreateField.details,
      ),
    );
  }

  Future<void> submit() async {
    if (state.initializing ||
        state.submitting ||
        state.isSubmitted ||
        state.pendingRetry) {
      return;
    }
    if (!state.hasAnyRail) {
      emit(
        state.copyWith(
          failure: const InvoicesFailure.invalidInput(code: 'NoRailSelected'),
        ),
      );
      return;
    }
    final amount = _parseAmount();
    if (amount == null) return;

    final PrivateInvoicePresentation presentation;
    try {
      presentation = PrivateInvoicePresentation(
        payer: _contact(
          section: 'payer',
          name: state.payerName,
          corporateName: state.payerCorporateName,
          address: state.payerAddress,
          email: state.payerEmail,
          phone: state.payerPhone,
        ),
        invoice: _invoiceDetails(),
        payee: _contact(
          section: 'payee',
          name: state.payeeName,
          corporateName: state.payeeCorporateName,
          address: state.payeeAddress,
          email: state.payeeEmail,
          phone: state.payeePhone,
        ),
      );
    } on PrivateInvoicePresentationException catch (error) {
      emit(
        state.copyWith(
          failure: InvoicesFailure.invalidInput(
            code: '${error.field}:${error.code}',
          ),
          invalidField: _fieldFor(error.field),
        ),
      );
      return;
    }

    final op = ++_operationId;
    emit(
      state.copyWith(
        submitting: true,
        clearFailure: true,
        clearInvalidField: true,
      ),
    );
    final result = await _facade.create(
      CreateInvoiceCommand(
        amountSat: amount.$1,
        fiatAmountMinor: amount.$2,
        fiatCurrency: amount.$3,
        presentation: presentation,
        acceptBtc: state.acceptBtc,
        acceptLn: state.acceptLn,
        acceptLiquid: state.directLiquidAvailable && state.acceptLiquid,
      ),
    );
    if (isClosed || op != _operationId) return;
    switch (result) {
      case Ok(:final value):
        emit(state.copyWith(submitting: false, result: value));
      case Err(:final failure):
        emit(
          state.copyWith(
            submitting: false,
            pendingRetry:
                failure.kind == InvoicesFailureKind.outcomeUnknown ||
                failure.kind == InvoicesFailureKind.privateStorage ||
                failure.kind == InvoicesFailureKind.createConflict,
            failure: failure,
          ),
        );
    }
  }

  (int?, int?, String?)? _parseAmount() {
    if (state.amountMode == InvoiceAmountMode.bitcoin) {
      final sats = _bitcoinInputToSats(state.amountInput.trim());
      if (sats == null || sats <= 0) {
        _emitInvalid(InvoiceCreateField.amount, 'AmountInvalid');
        return null;
      }
      return (sats, null, null);
    }
    if (state.fiatCurrency.isEmpty) {
      _emitInvalid(InvoiceCreateField.currency, 'CurrencyRequired');
      return null;
    }
    final value = double.tryParse(state.amountInput.trim());
    if (value == null || value <= 0) {
      _emitInvalid(InvoiceCreateField.amount, 'AmountInvalid');
      return null;
    }
    final factor = _pow10(_precisionFor(state.fiatCurrency));
    return (null, (value * factor).round(), state.fiatCurrency);
  }

  /// Exact bitcoin-entry → satoshis. Integer sats parse directly; a BTC decimal
  /// string is converted digit-by-digit (never through a binary double) so the
  /// satoshi value is preserved precisely.
  int? _bitcoinInputToSats(String input) {
    if (input.isEmpty) return null;
    if (state.bitcoinUnit == BitcoinUnit.sats) {
      return int.tryParse(input);
    }
    final match = RegExp(r'^(\d+)(?:\.(\d{1,8}))?$').firstMatch(input);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(8, '0');
    return whole * 100000000 + int.parse('0$fraction');
  }

  Future<void> _recomputeEquivalent() async {
    final op = ++_equivalentOp;
    final input = state.amountInput.trim();
    if (input.isEmpty) {
      _emitEquivalent(op, null);
      return;
    }
    try {
      if (state.amountMode == InvoiceAmountMode.fiat) {
        final convert = _convertToSats;
        // The conversion resolves the rate for the user's default currency, so
        // a non-default invoice currency hides the line rather than misstating.
        if (convert == null ||
            state.fiatCurrency.isEmpty ||
            state.fiatCurrency != _defaultCurrency) {
          _emitEquivalent(op, null);
          return;
        }
        final value = double.tryParse(input);
        if (value == null || value <= 0) {
          _emitEquivalent(op, null);
          return;
        }
        final sats = await convert.execute(
          amountFiat: value,
          currencyCode: state.fiatCurrency,
        );
        _emitEquivalent(op, '≈ ${FormatAmount.sats(sats.toInt())}');
      } else {
        final convert = _convertToFiat;
        final sats = _bitcoinInputToSats(input);
        if (convert == null ||
            sats == null ||
            sats <= 0 ||
            _defaultCurrency.isEmpty) {
          _emitEquivalent(op, null);
          return;
        }
        final fiat = await convert.execute(
          amountSat: BigInt.from(sats),
          currencyCode: _defaultCurrency,
        );
        _emitEquivalent(op, '≈ ${FormatAmount.fiat(fiat, _defaultCurrency)}');
      }
    } on Exception {
      _emitEquivalent(op, null);
    }
  }

  void _emitEquivalent(int op, String? label) {
    if (isClosed || op != _equivalentOp) return;
    emit(
      label == null
          ? state.copyWith(clearEquivalent: true)
          : state.copyWith(equivalentLabel: label),
    );
  }

  PrivateInvoiceContact _contact({
    required String section,
    required String name,
    required String corporateName,
    required String address,
    required String email,
    required String phone,
  }) {
    try {
      return PrivateInvoiceContact(
        name: name,
        corporateName: corporateName,
        address: address,
        email: email,
        phone: phone,
      );
    } on PrivateInvoicePresentationException catch (error) {
      throw PrivateInvoicePresentationException(
        field: '$section.${error.field}',
        code: error.code,
      );
    }
  }

  PrivateInvoiceDetails _invoiceDetails() {
    try {
      return PrivateInvoiceDetails(
        description: state.description,
        number: state.invoiceNumber,
        purchaseOrderReference: state.purchaseOrderReference,
        invoiceDate: state.invoiceDate,
        paymentDeadline: state.paymentDeadline,
      );
    } on PrivateInvoicePresentationException catch (error) {
      throw PrivateInvoicePresentationException(
        field: 'invoice.${error.field}',
        code: error.code,
      );
    }
  }

  InvoiceCreateField _fieldFor(String field) => switch (field) {
    'payer.name' => InvoiceCreateField.payerName,
    'payer.corporate_name' => InvoiceCreateField.payerCorporateName,
    'payer.address' => InvoiceCreateField.payerAddress,
    'payer.email' => InvoiceCreateField.payerEmail,
    'payer.phone' => InvoiceCreateField.payerPhone,
    'invoice.description' => InvoiceCreateField.description,
    'invoice.number' => InvoiceCreateField.invoiceNumber,
    'invoice.purchase_order_reference' =>
      InvoiceCreateField.purchaseOrderReference,
    'invoice.invoice_date' => InvoiceCreateField.invoiceDate,
    'invoice.payment_deadline' => InvoiceCreateField.paymentDeadline,
    'payee.name' => InvoiceCreateField.payeeName,
    'payee.corporate_name' => InvoiceCreateField.payeeCorporateName,
    'payee.address' => InvoiceCreateField.payeeAddress,
    'payee.email' => InvoiceCreateField.payeeEmail,
    'payee.phone' => InvoiceCreateField.payeePhone,
    _ => InvoiceCreateField.details,
  };

  void _emitInvalid(InvoiceCreateField field, String code) {
    emit(
      state.copyWith(
        failure: InvoicesFailure.invalidInput(code: code),
        invalidField: field,
      ),
    );
  }

  int _precisionFor(String currency) {
    for (final item in state.currencies) {
      if (item.code == currency) return item.precision;
    }
    return 2;
  }

  int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  void _emit(InvoiceCreateState next) {
    emit(next.copyWith(clearFailure: true));
  }
}

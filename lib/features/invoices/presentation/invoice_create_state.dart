import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';

/// The amount entry denomination, which also fixes the invoice pricing (Q17):
/// [fiat] creates a fiat-fixed invoice, [bitcoin] a sat-fixed one. The bitcoin
/// display unit (sats vs BTC) follows the user's setting; the pricing stays
/// sat-fixed either way.
enum InvoiceAmountMode { bitcoin, fiat }

enum InvoiceCreateField {
  amount,
  currency,
  payerName,
  payerCorporateName,
  payerAddress,
  payerEmail,
  payerPhone,
  description,
  invoiceNumber,
  purchaseOrderReference,
  invoiceDate,
  paymentDeadline,
  payeeName,
  payeeCorporateName,
  payeeAddress,
  payeeEmail,
  payeePhone,
  details,
}

class InvoiceCreateState {
  final bool initializing;
  final bool submitting;
  final bool pendingRetry;
  final CreateInvoiceResult? result;
  final InvoicesFailure? failure;
  final InvoiceAmountMode amountMode;
  final String amountInput;
  final String fiatCurrency;

  /// The user's bitcoin display unit (sats or BTC), used only for the bitcoin
  /// entry denomination and its formatting. Pricing is always sat-fixed.
  final BitcoinUnit bitcoinUnit;

  /// The live approximate cross-denomination equivalent (e.g. "≈ 12,345 sats"
  /// when entering fiat, or the fiat value when entering bitcoin). Null when it
  /// cannot be computed (no rate, empty/invalid amount) — the line is hidden.
  final String? equivalentLabel;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final bool directLiquidAvailable;
  final String payerName;
  final String payerCorporateName;
  final String payerAddress;
  final String payerEmail;
  final String payerPhone;
  final String description;
  final String invoiceNumber;
  final String purchaseOrderReference;
  final String invoiceDate;
  final String paymentDeadline;
  final String payeeName;
  final String payeeCorporateName;
  final String payeeAddress;
  final String payeeEmail;
  final String payeePhone;
  final List<BullnymSupportedCurrency> currencies;
  final bool currenciesUnavailable;
  final InvoiceCreateField? invalidField;

  const InvoiceCreateState({
    this.initializing = true,
    this.submitting = false,
    this.pendingRetry = false,
    this.result,
    this.failure,
    this.amountMode = InvoiceAmountMode.fiat,
    this.amountInput = '',
    this.fiatCurrency = '',
    this.bitcoinUnit = BitcoinUnit.sats,
    this.equivalentLabel,
    this.acceptBtc = true,
    this.acceptLn = true,
    this.acceptLiquid = false,
    this.directLiquidAvailable = false,
    this.payerName = '',
    this.payerCorporateName = '',
    this.payerAddress = '',
    this.payerEmail = '',
    this.payerPhone = '',
    this.description = '',
    this.invoiceNumber = '',
    this.purchaseOrderReference = '',
    this.invoiceDate = '',
    this.paymentDeadline = '',
    this.payeeName = '',
    this.payeeCorporateName = '',
    this.payeeAddress = '',
    this.payeeEmail = '',
    this.payeePhone = '',
    this.currencies = const [],
    this.currenciesUnavailable = false,
    this.invalidField,
  });

  bool get isSubmitted => result != null;
  bool get hasAnyRail => acceptBtc || acceptLn || acceptLiquid;

  /// The number of currently-enabled rails. At least one is always required
  /// (Q19): the last enabled rail's toggle is disabled so the invalid empty
  /// state is unrepresentable rather than a submit-time error.
  int get enabledRailCount =>
      (acceptBtc ? 1 : 0) + (acceptLn ? 1 : 0) + (acceptLiquid ? 1 : 0);

  /// True when [railOn] is the only enabled rail — its toggle must be locked on.
  bool isLastEnabledRail(bool railOn) => railOn && enabledRailCount == 1;

  int get populatedFieldCount => [
    payerName,
    payerCorporateName,
    payerAddress,
    payerEmail,
    payerPhone,
    description,
    invoiceNumber,
    purchaseOrderReference,
    invoiceDate,
    paymentDeadline,
    payeeName,
    payeeCorporateName,
    payeeAddress,
    payeeEmail,
    payeePhone,
  ].where((value) => value.trim().isNotEmpty).length;

  InvoiceCreateState copyWith({
    bool? initializing,
    bool? submitting,
    bool? pendingRetry,
    CreateInvoiceResult? result,
    InvoicesFailure? failure,
    InvoiceAmountMode? amountMode,
    String? amountInput,
    String? fiatCurrency,
    BitcoinUnit? bitcoinUnit,
    String? equivalentLabel,
    bool? acceptBtc,
    bool? acceptLn,
    bool? acceptLiquid,
    bool? directLiquidAvailable,
    String? payerName,
    String? payerCorporateName,
    String? payerAddress,
    String? payerEmail,
    String? payerPhone,
    String? description,
    String? invoiceNumber,
    String? purchaseOrderReference,
    String? invoiceDate,
    String? paymentDeadline,
    String? payeeName,
    String? payeeCorporateName,
    String? payeeAddress,
    String? payeeEmail,
    String? payeePhone,
    List<BullnymSupportedCurrency>? currencies,
    bool? currenciesUnavailable,
    InvoiceCreateField? invalidField,
    bool clearFailure = false,
    bool clearInvalidField = false,
    bool clearEquivalent = false,
  }) {
    return InvoiceCreateState(
      initializing: initializing ?? this.initializing,
      submitting: submitting ?? this.submitting,
      pendingRetry: pendingRetry ?? this.pendingRetry,
      result: result ?? this.result,
      failure: clearFailure ? null : failure ?? this.failure,
      amountMode: amountMode ?? this.amountMode,
      amountInput: amountInput ?? this.amountInput,
      fiatCurrency: fiatCurrency ?? this.fiatCurrency,
      bitcoinUnit: bitcoinUnit ?? this.bitcoinUnit,
      equivalentLabel: clearEquivalent
          ? null
          : equivalentLabel ?? this.equivalentLabel,
      acceptBtc: acceptBtc ?? this.acceptBtc,
      acceptLn: acceptLn ?? this.acceptLn,
      acceptLiquid: acceptLiquid ?? this.acceptLiquid,
      directLiquidAvailable:
          directLiquidAvailable ?? this.directLiquidAvailable,
      payerName: payerName ?? this.payerName,
      payerCorporateName: payerCorporateName ?? this.payerCorporateName,
      payerAddress: payerAddress ?? this.payerAddress,
      payerEmail: payerEmail ?? this.payerEmail,
      payerPhone: payerPhone ?? this.payerPhone,
      description: description ?? this.description,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      purchaseOrderReference:
          purchaseOrderReference ?? this.purchaseOrderReference,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      paymentDeadline: paymentDeadline ?? this.paymentDeadline,
      payeeName: payeeName ?? this.payeeName,
      payeeCorporateName: payeeCorporateName ?? this.payeeCorporateName,
      payeeAddress: payeeAddress ?? this.payeeAddress,
      payeeEmail: payeeEmail ?? this.payeeEmail,
      payeePhone: payeePhone ?? this.payeePhone,
      currencies: currencies ?? this.currencies,
      currenciesUnavailable:
          currenciesUnavailable ?? this.currenciesUnavailable,
      invalidField: clearInvalidField
          ? null
          : invalidField ?? this.invalidField,
    );
  }
}

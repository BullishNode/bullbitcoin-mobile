import 'package:bb_mobile/core/utils/amount_formatting.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:flutter/widgets.dart';

/// Shared merchant-facing invoice copy: the localized wording for an invoice's
/// own facts, used by the invoices list/detail screens AND by the Get Paid
/// transaction card, which renders the same invoice facts for a received
/// payment. It lives on the public boundary so the wording is written once.

/// Localized label for an invoice status (shared by the list chips + detail).
String invoiceStatusText(BuildContext context, InvoiceStatus status) {
  return switch (status) {
    InvoiceStatus.unpaid => context.loc.invoiceStatusUnpaid,
    InvoiceStatus.inProgress => context.loc.invoiceStatusInProgress,
    InvoiceStatus.partiallyPaid => context.loc.invoiceStatusPartiallyPaid,
    InvoiceStatus.paid => context.loc.invoiceStatusPaid,
    InvoiceStatus.underpaid => context.loc.invoiceStatusUnderpaid,
    InvoiceStatus.overpaid => context.loc.invoiceStatusOverpaid,
    InvoiceStatus.expired => context.loc.invoiceStatusExpired,
    InvoiceStatus.cancelled => context.loc.invoiceStatusCancelled,
    InvoiceStatus.unsupported => context.loc.invoiceStatusUnsupported,
  };
}

String invoiceFallbackStateText(
  BuildContext context,
  InvoiceFallbackState state,
) {
  return switch (state) {
    InvoiceFallbackState.delayed => context.loc.invoiceFallbackDelayed,
    InvoiceFallbackState.inProgress => context.loc.invoiceFallbackInProgress,
    InvoiceFallbackState.confirming => context.loc.invoiceFallbackConfirming,
    InvoiceFallbackState.settled => context.loc.invoiceFallbackSettled,
    InvoiceFallbackState.integrityHold =>
      context.loc.invoiceFallbackIntegrityHold,
  };
}

String? invoiceSettlementSupportingText(
  BuildContext context,
  InvoiceSettlementState settlementState,
) {
  return switch (settlementState) {
    InvoiceSettlementState.none => null,
    InvoiceSettlementState.pending => context.loc.invoiceSettlementPending,
    InvoiceSettlementState.settled => context.loc.invoiceSettlementComplete,
    InvoiceSettlementState.problem => context.loc.invoiceSettlementProblem,
  };
}

/// The invoice face amount. Fiat-priced invoices headline their fiat face
/// value (the locked sat target is 0 on the row, so it must never render as
/// "0 sats"); sat-priced invoices headline the sat target.
String invoiceFaceAmountText(
  BuildContext context,
  InvoiceStatusSnapshot snapshot,
) {
  if (snapshot.hasFiatFace) {
    return FormatAmount.fiatMinor(
      snapshot.fiatAmountMinor!,
      snapshot.fiatCurrency!,
    );
  }
  if (snapshot.amountSat > 0) {
    return context.loc.invoiceAmountSats(snapshot.amountSat);
  }
  return context.loc.invoiceAmountUnavailable;
}

String invoicePaymentRailTitle(BuildContext context, PaymentMethod rail) {
  return switch (rail) {
    PaymentMethod.btc => context.loc.invoicePaymentEventBitcoinTitle,
    PaymentMethod.lightning => context.loc.invoicePaymentEventLightningTitle,
    PaymentMethod.liquid => context.loc.invoicePaymentEventLiquidTitle,
  };
}

/// The rail name on its own, as used for an accepted-rail list or a `paid_via`
/// value (distinct from [invoicePaymentRailTitle], which titles an event).
String invoiceRailName(BuildContext context, PaymentMethod rail) {
  return switch (rail) {
    PaymentMethod.btc => context.loc.invoiceAcceptBtc,
    PaymentMethod.lightning => context.loc.invoiceAcceptLn,
    PaymentMethod.liquid => context.loc.invoiceAcceptLiquid,
  };
}

String invoicePaymentEventStateText(
  BuildContext context,
  InvoicePaymentEvent payment,
) {
  if (payment.state == InvoicePaymentEventState.problem) {
    return switch (payment.problem) {
      InvoicePaymentProblem.evicted => context.loc.invoicePaymentProblemEvicted,
      InvoicePaymentProblem.reorged => context.loc.invoicePaymentProblemReorged,
      InvoicePaymentProblem.conflicted =>
        context.loc.invoicePaymentProblemConflicted,
      InvoicePaymentProblem.replaced =>
        context.loc.invoicePaymentProblemReplaced,
      InvoicePaymentProblem.unknown ||
      null => context.loc.invoicePaymentProblemUnknown,
    };
  }
  return switch (payment.state) {
    InvoicePaymentEventState.pending =>
      payment.rail == PaymentMethod.btc
          ? context.loc.invoicePaymentSeenMempool
          : context.loc.invoiceSettlementPending,
    InvoicePaymentEventState.confirming =>
      context.loc.invoicePaymentConfirmations(payment.confirmations),
    InvoicePaymentEventState.settled => context.loc.invoiceSettlementComplete,
    InvoicePaymentEventState.problem =>
      context.loc.invoicePaymentProblemUnknown,
  };
}

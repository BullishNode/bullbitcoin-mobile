import 'package:bb_mobile/core/utils/amount_formatting.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_creation_rate.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';

/// Local (client-side) CSV formatter for the merchant Get Paid accounting
/// export. Mirrors the wallet exporter's conventions: a header row, RFC-4180
/// escaping, UTC ISO-8601 timestamps, and numbers rendered unlocalized (dot
/// decimal). It never reformats through the device locale.
///
/// The exact-vs-estimate discipline of the accounting model is carried in the
/// column NAMES, not in flags: the fiat leg (`fiat_credited`,
/// `execution_rate_leg_ccy`) is exact; the bitcoin leg's fiat worth
/// (`btc_leg_value_est_face_ccy`) is an estimate at the creation rate and is
/// left EMPTY whenever R1 or its face currency is unknown. The face currency and
/// the leg currency are kept in separate, clearly named columns and never mixed.
/// The private comment text is never exported — only whether one is present.
class GetPaidCsvExportFormatter {
  const GetPaidCsvExportFormatter();

  static const List<String> headers = [
    'received_at',
    'source',
    'invoice_id',
    'order_id',
    'face_amount',
    'face_currency',
    'total_sats',
    'creation_rate_face_ccy',
    'split_pct',
    'btc_leg_sats',
    'btc_leg_value_est_face_ccy',
    'fiat_credited',
    'fiat_credited_currency',
    'execution_rate_leg_ccy',
    'btc_leg_status',
    'fiat_leg_status',
    'settlement_kind',
    'payment_status',
    'comment_present',
  ];

  String format(List<GetPaidTransaction> transactions) {
    final buffer = StringBuffer()..writeln(headers.join(','));
    for (final tx in transactions) {
      buffer.writeln(_fields(tx).map(_escape).join(','));
    }
    return buffer.toString();
  }

  List<String> _fields(GetPaidTransaction tx) {
    final settlement = tx.settlement;
    // The face currency travels with R1 on the settlement (the invoice face
    // currency is not otherwise carried on a history row); it may differ from a
    // fiat leg's own currency.
    final faceCurrency = settlement?.creationRateCurrency;
    final creationRate = settlement?.creationRateMinorPerBtc;

    final firstFiatLeg = _firstFiatLeg(settlement);
    final firstBitcoinLeg = _firstBitcoinLeg(settlement);
    final totalBitcoinLegSats = _totalBitcoinLegSats(settlement);

    // The estimate is only defined when R1 AND its face currency are both known
    // and there is a bitcoin leg — otherwise the column stays empty (never a
    // fabricated value, never guessed at a denomination).
    final String btcLegValueEst;
    if (creationRate != null &&
        faceCurrency != null &&
        totalBitcoinLegSats != null) {
      btcLegValueEst = _major(
        getPaidBitcoinLegValueMinorAtCreationRate(
          totalBitcoinLegSats,
          creationRate,
        ),
        faceCurrency,
      );
    } else {
      btcLegValueEst = '';
    }

    final creditedMinor =
        firstFiatLeg?.status == GetPaidSettlementLegStatus.settled
        ? firstFiatLeg?.amountMinor
        : null;

    return [
      tx.receivedAt.toUtc().toIso8601String(),
      _sourceWire(tx.source),
      tx.invoiceId ?? '',
      firstFiatLeg?.orderId ?? '',
      // The invoice face AMOUNT is not carried on a history row today; only its
      // currency (via R1). Left empty rather than derived from the sat leg.
      '',
      // Only trustworthy when the face currency is actually known (R1 present).
      faceCurrency ?? '',
      '${tx.amountSat}',
      (creationRate != null && faceCurrency != null)
          ? _major(creationRate, faceCurrency)
          : '',
      settlement?.fiatPercentage?.toString() ?? '',
      totalBitcoinLegSats?.toString() ?? '',
      btcLegValueEst,
      creditedMinor != null
          ? _major(creditedMinor, firstFiatLeg!.currency)
          : '',
      firstFiatLeg?.currency ?? '',
      firstFiatLeg?.executionRateMinorPerBtc != null
          ? _major(
              firstFiatLeg!.executionRateMinorPerBtc!,
              firstFiatLeg.currency,
            )
          : '',
      firstBitcoinLeg != null ? _legStatusWire(firstBitcoinLeg.status) : '',
      firstFiatLeg != null ? _legStatusWire(firstFiatLeg.status) : '',
      settlement != null ? _kindWire(settlement.kind) : '',
      _paymentStatusWire(tx.settlementState),
      (tx.comment != null).toString(),
    ];
  }

  GetPaidFiatSettlementLeg? _firstFiatLeg(GetPaidSettlement? settlement) {
    final fiat = settlement?.fiat;
    if (fiat == null || fiat.isEmpty) return null;
    return fiat.first;
  }

  GetPaidBitcoinSettlementLeg? _firstBitcoinLeg(GetPaidSettlement? settlement) {
    final bitcoin = settlement?.bitcoin;
    if (bitcoin == null || bitcoin.isEmpty) return null;
    return bitcoin.first;
  }

  int? _totalBitcoinLegSats(GetPaidSettlement? settlement) {
    final bitcoin = settlement?.bitcoin;
    if (bitcoin == null || bitcoin.isEmpty) return null;
    var total = 0;
    for (final leg in bitcoin) {
      total += leg.amountSat;
    }
    return total;
  }

  String _major(int minor, String currency) =>
      FormatAmount.fiatMinorValue(minor, currency);

  String _sourceWire(GetPaidTransactionSource source) => switch (source) {
    GetPaidTransactionSource.lightningAddress => 'lightning_address',
    GetPaidTransactionSource.invoice => 'invoice',
    GetPaidTransactionSource.paymentPage => 'payment_page',
    GetPaidTransactionSource.pointOfSale => 'point_of_sale',
  };

  String _kindWire(GetPaidSettlementKind kind) => switch (kind) {
    GetPaidSettlementKind.bitcoin => 'bitcoin',
    GetPaidSettlementKind.fiat => 'fiat',
    GetPaidSettlementKind.mixed => 'mixed',
    GetPaidSettlementKind.unavailable => 'unavailable',
  };

  String _legStatusWire(GetPaidSettlementLegStatus status) => switch (status) {
    GetPaidSettlementLegStatus.pending => 'pending',
    GetPaidSettlementLegStatus.settled => 'settled',
    GetPaidSettlementLegStatus.problem => 'problem',
    GetPaidSettlementLegStatus.unavailable => 'unavailable',
  };

  String _paymentStatusWire(GetPaidSettlementState state) => switch (state) {
    GetPaidSettlementState.pending => 'pending',
    GetPaidSettlementState.settled => 'settled',
    GetPaidSettlementState.problem => 'problem',
  };

  String _escape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

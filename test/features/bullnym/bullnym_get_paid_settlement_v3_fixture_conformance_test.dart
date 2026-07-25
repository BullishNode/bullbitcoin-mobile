import 'dart:convert';
import 'dart:io';

import 'package:bb_mobile/features/bullnym/data/bullnym_get_paid_transaction_mapper.dart';
import 'package:bb_mobile/features/bullnym/data/bullnym_get_paid_transaction_model.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_fiat_settlement.dart';
import 'package:flutter_test/flutter_test.dart';

// v3 contract conformance: this is the canonical Bullnym merchant-accounting
// fixture. It adds R1
// (settlement_details.creation_rate_minor_per_btc + creation_rate_currency, in
// the invoice FACE currency) and R2 (per-fiat-leg execution_rate_minor_per_btc,
// in the LEG currency). The parser must read the fields where present, keep
// legacy/bitcoin rows unchanged, and never conflate the face currency with the
// leg currency.
void main() {
  test('parses the canonical v3 accounting fixture through the real model', () {
    final raw = File(
      'test/features/bullnym/fixtures/get-paid-transactions-settlement-v3.json',
    ).readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final page = BullnymGetPaidTransactionPageModel.fromJson(json);
    final domain = page.transactions.map((m) => m.toDomain()).toList();

    expect(domain.length, 7);
    expect(page.nextCursor, isNull);

    // tx1 / tx2 / tx7 — bitcoin / overridden / unavailable: no accounting fields.
    expect(domain[0].settlement!.creationRateMinorPerBtc, isNull);
    expect(domain[1].settlement!.creationRateMinorPerBtc, isNull);

    // tx3 — fiat pending EUR: R1 present (in EUR), leg still pending ⇒ no R2.
    final pending = domain[2].settlement!;
    expect(pending.kind, BullnymSettlementKind.fiat);
    expect(pending.creationRateMinorPerBtc, 6416000);
    expect(pending.creationRateCurrency, 'EUR');
    expect(pending.fiat.single.executionRateMinorPerBtc, isNull);

    // tx4 — fiat settled CAD: R1 (CAD) and R2 on the settled leg (CAD).
    final settled = domain[3].settlement!;
    expect(settled.creationRateMinorPerBtc, 6400000);
    expect(settled.creationRateCurrency, 'CAD');
    expect(settled.fiat.single.executionRateMinorPerBtc, 6390000);

    // tx5 — mixed, FACE currency USD, fiat LEG currency CAD (the real
    // face≠leg case). R1 in USD; R2 on the CAD leg in CAD.
    final mixed = domain[4].settlement!;
    expect(mixed.kind, BullnymSettlementKind.mixed);
    expect(mixed.creationRateMinorPerBtc, 6416000);
    expect(mixed.creationRateCurrency, 'USD');
    expect(mixed.bitcoin.single.amountSat, 60000);
    expect(mixed.fiat.single.currency, 'CAD');
    expect(mixed.fiat.single.executionRateMinorPerBtc, 6390000);

    // tx6 — legacy fiat row: no R1/R2 at all, still parses (tolerance).
    final legacy = domain[5].settlement!;
    expect(legacy.kind, BullnymSettlementKind.fiat);
    expect(legacy.creationRateMinorPerBtc, isNull);
    expect(legacy.creationRateCurrency, isNull);
    expect(legacy.fiat.single.executionRateMinorPerBtc, isNull);
  });
}

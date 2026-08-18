import 'dart:convert';
import 'dart:io';

import 'package:bb_mobile/features/bullnym/data/bullnym_get_paid_transaction_mapper.dart';
import 'package:bb_mobile/features/bullnym/data/bullnym_get_paid_transaction_model.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_fiat_settlement.dart';
import 'package:flutter_test/flutter_test.dart';

// v2 contract conformance: the canonical version-two fixture shipped by the
// server (Bullnym) must parse through the REAL mobile model + settlement parser
// without any field name, enum string, null, or array shape being rewritten in
// the test. The fixture file is copied byte-for-byte from the server repo. v2
// adds the locked quote (quoted_amount_minor) on every fiat leg and the
// captured split (fiat_percentage) on settlement_details.
void main() {
  test('parses the canonical v2 settlement fixture through the real model', () {
    final raw = File(
      'test/features/bullnym/fixtures/get-paid-transactions-settlement-v2.json',
    ).readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final page = BullnymGetPaidTransactionPageModel.fromJson(json);
    final domain = page.transactions.map((m) => m.toDomain()).toList();

    expect(domain.length, 7);
    expect(page.nextCursor, isNull);

    // tx1 — explicit Bitcoin, no details, no override, no split.
    final btc = domain[0].settlement!;
    expect(btc.kind, BullnymSettlementKind.bitcoin);
    expect(btc.overrideReason, isNull);
    expect(btc.fiatPercentage, isNull);
    expect(btc.fiat, isEmpty);

    // tx2 — Bitcoin with a below-minimum conversion override.
    final overridden = domain[1].settlement!;
    expect(overridden.kind, BullnymSettlementKind.bitcoin);
    expect(
      overridden.overrideReason,
      BullnymFiatConversionOverrideReason.belowMinimum,
    );

    // tx3 — fiat pending WITH a locked quote. amount_minor (credited) is null;
    // the quote is exposed while pending so the merchant sees a fiat value.
    final pending = domain[2].settlement!;
    expect(pending.kind, BullnymSettlementKind.fiat);
    expect(pending.fiatPercentage, 100);
    final pendingLeg = pending.fiat.single;
    expect(pendingLeg.status, BullnymSettlementLegStatus.pending);
    expect(pendingLeg.amountMinor, isNull);
    expect(pendingLeg.quotedAmountMinor, 5000);
    expect(pendingLeg.currency, 'EUR');

    // tx4 — repriced late settle: the credited amount_minor differs from the
    // originally locked quote (12345 credited vs 12000 quoted).
    final repriced = domain[3].settlement!;
    expect(repriced.kind, BullnymSettlementKind.fiat);
    expect(repriced.fiatPercentage, 100);
    final settledLeg = repriced.fiat.single;
    expect(settledLeg.status, BullnymSettlementLegStatus.settled);
    expect(settledLeg.amountMinor, 12345);
    expect(settledLeg.quotedAmountMinor, 12000);
    expect(settledLeg.amountMinor == settledLeg.quotedAmountMinor, isFalse);

    // tx5 — mixed with a captured 40% fiat split and a settled leg on each side.
    final mixed = domain[4].settlement!;
    expect(mixed.kind, BullnymSettlementKind.mixed);
    expect(mixed.fiatPercentage, 40);
    expect(mixed.bitcoin.single.amountSat, 60000);
    expect(mixed.fiat.single.amountMinor, 12345);
    expect(mixed.fiat.single.quotedAmountMinor, 12345);

    // tx6 — legacy fiat row: no captured split and no quote (both null), but a
    // credited settled amount. v1-tolerance within a v2 payload.
    final legacy = domain[5].settlement!;
    expect(legacy.kind, BullnymSettlementKind.fiat);
    expect(legacy.fiatPercentage, isNull);
    final legacyLeg = legacy.fiat.single;
    expect(legacyLeg.status, BullnymSettlementLegStatus.settled);
    expect(legacyLeg.amountMinor, 12345);
    expect(legacyLeg.quotedAmountMinor, isNull);

    // tx7 — server-sent unavailable, carrying no details, split, or override.
    final unavailable = domain[6].settlement!;
    expect(unavailable.kind, BullnymSettlementKind.unavailable);
    expect(unavailable.fiatPercentage, isNull);
    expect(unavailable.fiat, isEmpty);
  });
}

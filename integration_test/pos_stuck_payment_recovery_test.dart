import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart'
    show BullnymRecoverableSwap;
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:bb_mobile/features/payment_recovery/domain/repositories/payment_recovery_repository.dart';
import 'package:bb_mobile/features/payment_recovery/public/payment_recovery_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/fake_nostr_relay.dart';
import 'support/get_paid_fixtures.dart';
import 'support/test_locator_overrides.dart';
import 'support/wipe_app_state.dart';

// SPEC-RECOVER-01 — the fake-backed one-tap chain-swap recovery round-trip.
//
// AUTHORED-BUT-CI-ONLY (same rationale as SPEC-POS-01 / SPEC-PP-01): excluded
// from the aggregated L1 suite (tool/gen_all_test.dart skip set) because live
// app-startup timers/blocs make a full app-process run non-deterministic. The
// deterministic gates for this feature are the L0 usecase/cubit suites; this
// file is retained for a dedicated CI job with a per-test relay-only harness.

const _nym = 'alice';
const _invoiceId = '3f6f0f6e-0000-0000-0000-000000000001';

BullnymRecoverableSwap _refundDueSwap({
  String? refundAddress,
  String? refundTxid,
  String status = 'refund_due',
}) {
  return BullnymRecoverableSwap(
    invoiceId: _invoiceId,
    nym: _nym,
    recoveryStatus: status,
    userLockAmountSat: 105000,
    serverLockAmountSat: 100000,
    lockupAddress: 'bc1qlockup',
    refundAddress: refundAddress,
    refundTxid: refundTxid,
    swapCreatedAtUnix: 1767000000,
    swapUpdatedAtUnix: 1767003600,
    invoiceStatus: 'expired',
    invoiceAmountSat: 100000,
    fiatAmountMinor: 5000,
    fiatCurrency: 'CAD',
    publicDescription: 'Order 123',
    invoiceNumber: 'INV-42',
    invoiceCreatedAtUnix: 1766990000,
  );
}

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  test('detect a stuck POS payment, one-tap recover it, then adopt the '
      'server echo after a reinstall', () async {
    final relay = FakeNostrRelay();
    final bullnym = FakeBullnymClient();
    await wipeAppState(locator);
    await overrideBoundariesForTest(locator, relay: relay, bullnym: bullnym);
    await overrideClockForTest(locator);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );

    final facade = locator<PaymentRecoveryFacade>();
    final repo = locator<PaymentRecoveryRepository>();

    // --- Detect --------------------------------------------------------------
    bullnym.recoverEnabled = true;
    bullnym.recoveryMode = FakeRecoveryMode.available;
    bullnym.recoverableSwaps = [_refundDueSwap()];

    final scan = await facade.scan();
    expect(scan.recoveryEnabled, isTrue);
    expect(scan.needsAttentionCount, 1);
    final detected = await repo.fetch(_invoiceId);
    expect(detected, isNotNull);
    expect(detected!.state, RecoveryState.detected);
    expect(detected.nym, _nym);
    expect(detected.refundAddress, isNull);

    // --- One-tap recover -----------------------------------------------------
    await facade.recover(_invoiceId);

    expect(bullnym.recoverCalls, hasLength(1));
    final call = bullnym.recoverCalls.single;
    expect(call.nym, _nym);
    expect(call.invoiceId, _invoiceId);
    // The refund address was freshly derived from the merchant's own default
    // Bitcoin wallet (mainnet), not supplied by the server.
    expect(call.btcAddress, isNotEmpty);

    final recovered = await repo.fetch(_invoiceId);
    expect(recovered!.state, RecoveryState.recovered);
    expect(recovered.refundTxid, bullnym.recoveredTxid);
    // Commit-before-send: the committed address equals what was POSTed.
    expect(recovered.refundAddress, call.btcAddress);

    // --- Simulate reinstall: wipe only the local recovery row ----------------
    await repo.delete(_invoiceId);
    expect(await repo.fetch(_invoiceId), isNull);

    // The server now echoes the committed address + txid on the recoverable
    // row (terminal). A fresh scan must ADOPT them without a second POST.
    bullnym.recoverableSwaps = [
      _refundDueSwap(
        status: 'refunded',
        refundAddress: call.btcAddress,
        refundTxid: bullnym.recoveredTxid,
      ),
    ];
    await facade.scan();

    final reconciled = await repo.fetch(_invoiceId);
    expect(reconciled!.state, RecoveryState.recovered);
    expect(reconciled.refundAddress, call.btcAddress);
    expect(reconciled.refundTxid, bullnym.recoveredTxid);
    // No new recover POST was issued during reconciliation.
    expect(bullnym.recoverCalls, hasLength(1));
  });

  test('when the server recover flag is off, detection is read-only (no POST)',
      () async {
    final relay = FakeNostrRelay();
    final bullnym = FakeBullnymClient();
    await wipeAppState(locator);
    await overrideBoundariesForTest(locator, relay: relay, bullnym: bullnym);
    await overrideClockForTest(locator);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );

    final facade = locator<PaymentRecoveryFacade>();
    final repo = locator<PaymentRecoveryRepository>();

    bullnym.recoverEnabled = false;
    bullnym.recoverableSwaps = [_refundDueSwap()];

    final scan = await facade.scan();
    expect(scan.recoveryEnabled, isFalse);
    expect(scan.needsAttentionCount, 1);
    expect((await repo.fetch(_invoiceId))!.state, RecoveryState.detected);

    // The UI gates the button on recoveryEnabled; even if recover is invoked,
    // the server route is absent and the row stays visible (no crash, no POST
    // that pretends success).
    bullnym.recoveryMode = FakeRecoveryMode.routeAbsent404;
    await facade.recover(_invoiceId);
    final row = await repo.fetch(_invoiceId);
    expect(row!.state != RecoveryState.recovered, isTrue);
  });
}

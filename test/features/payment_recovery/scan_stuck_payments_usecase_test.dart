import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart'
    show BullnymAuthSigner;
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_identity_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_pay_service_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/results/recovery_results.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/scan_stuck_payments_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/payment_recovery_error.dart';
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:bb_mobile/features/payment_recovery/domain/repositories/payment_recovery_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// --- In-memory fakes -------------------------------------------------------

class _FakeRepo implements PaymentRecoveryRepository {
  final Map<String, StuckPayment> store = {};

  @override
  Future<List<StuckPayment>> fetchAll() async => store.values.toList();

  @override
  Future<StuckPayment?> fetch(String invoiceId) async => store[invoiceId];

  @override
  Stream<List<StuckPayment>> watch() =>
      Stream.value(store.values.toList());

  @override
  Future<void> upsert(StuckPayment p) async => store[p.invoiceId] = p;

  @override
  Future<void> delete(String invoiceId) async => store.remove(invoiceId);
}

class _FakeIdentity implements RecoveryIdentityPort {
  final bool available;
  _FakeIdentity({this.available = true});

  @override
  Future<BullnymAuthSigner> getSigningHandle() async {
    if (!available) throw const PaymentRecoveryException.noDefaultBitcoinWallet();
    return BullnymAuthSigner(npubHex: 'npub', signHashHex: (_) async => '00');
  }
}

class _FakePayService implements RecoveryPayServicePort {
  RecoverableSwapsResult? result;
  PaymentRecoveryException? error;

  @override
  Future<RecoverableSwapsResult> listRecoverable({
    required BullnymAuthSigner signer,
  }) async {
    if (error != null) throw error!;
    return result ??
        const RecoverableSwapsResult(
          recoveryEnabled: false,
          hasMore: false,
          swaps: [],
        );
  }

  @override
  Future<RecoverResult> recover({
    required BullnymAuthSigner signer,
    required String nym,
    required String invoiceId,
    required String btcAddress,
  }) async =>
      const RecoverResult(status: 'recovered', txid: 'tx');
}

RecoverableSwapRecord _swap({
  String invoiceId = 'inv-1',
  String nym = 'alice',
  String status = 'refund_due',
  String lockup = 'bc1qlock',
  String? refundAddress,
  String? refundTxid,
}) {
  return RecoverableSwapRecord(
    invoiceId: invoiceId,
    nym: nym,
    recoveryStatus: status,
    userLockAmountSat: 105000,
    serverLockAmountSat: 100000,
    lockupAddress: lockup,
    refundAddress: refundAddress,
    refundTxid: refundTxid,
    swapCreatedAtUnix: 1000,
    swapUpdatedAtUnix: 2000,
    invoiceStatus: 'expired',
    invoiceAmountSat: 100000,
    fiatAmountMinor: 5000,
    fiatCurrency: 'CAD',
    publicDescription: 'Order 1',
    invoiceNumber: 'INV-1',
    invoiceCreatedAtUnix: 900,
  );
}

void main() {
  late _FakeRepo repo;
  late _FakeIdentity identity;
  late _FakePayService pay;

  ScanStuckPaymentsUsecase build() => ScanStuckPaymentsUsecase(
    identity: identity,
    payService: pay,
    repository: repo,
    nowSecs: () => 1_700_000_000,
  );

  setUp(() {
    repo = _FakeRepo();
    identity = _FakeIdentity();
    pay = _FakePayService();
  });

  test('empty recoverable set → zero detections', () async {
    pay.result = const RecoverableSwapsResult(
      recoveryEnabled: true,
      hasMore: false,
      swaps: [],
    );
    final r = await build().execute();
    expect(r.needsAttentionCount, 0);
    expect(r.recoveryEnabled, isTrue);
    expect(repo.store, isEmpty);
  });

  test('refund_due with no address → detected, badge counts it', () async {
    pay.result = RecoverableSwapsResult(
      recoveryEnabled: true,
      hasMore: false,
      swaps: [_swap()],
    );
    final r = await build().execute();
    expect(r.needsAttentionCount, 1);
    final row = repo.store['inv-1']!;
    expect(row.state, RecoveryState.detected);
    expect(row.refundAddress, isNull);
    expect(row.nym, 'alice');
    expect(row.amountSat, 105000);
    expect(row.detectedAtUnix, 1_700_000_000);
  });

  test('fresh install adopts server-echoed committed address', () async {
    pay.result = RecoverableSwapsResult(
      recoveryEnabled: true,
      hasMore: false,
      swaps: [_swap(refundAddress: 'bc1qechoed')],
    );
    await build().execute();
    final row = repo.store['inv-1']!;
    expect(row.state, RecoveryState.addressCommitted);
    expect(row.refundAddress, 'bc1qechoed');
  });

  test('refunding → recovering; refunded → recovered with txid', () async {
    pay.result = RecoverableSwapsResult(
      recoveryEnabled: true,
      hasMore: false,
      swaps: [_swap(status: 'refunding', refundAddress: 'bc1qc')],
    );
    await build().execute();
    expect(repo.store['inv-1']!.state, RecoveryState.recovering);

    pay.result = RecoverableSwapsResult(
      recoveryEnabled: true,
      hasMore: false,
      swaps: [_swap(status: 'refunded', refundAddress: 'bc1qc', refundTxid: 'txid-1')],
    );
    await build().execute();
    final row = repo.store['inv-1']!;
    expect(row.state, RecoveryState.recovered);
    expect(row.refundTxid, 'txid-1');
  });

  test('echo-mismatch surfaces failed and never overwrites local address',
      () async {
    repo.store['inv-1'] = const StuckPayment(
      invoiceId: 'inv-1',
      nym: 'alice',
      state: RecoveryState.addressCommitted,
      refundAddress: 'bc1qLOCAL',
      detectedAtUnix: 100,
    );
    pay.result = RecoverableSwapsResult(
      recoveryEnabled: true,
      hasMore: false,
      swaps: [_swap(refundAddress: 'bc1qDIFFERENT')],
    );
    await build().execute();
    final row = repo.store['inv-1']!;
    expect(row.state, RecoveryState.failed);
    expect(row.lastErrorCode, 'RecoveryAddressMismatch');
    expect(row.refundAddress, 'bc1qLOCAL', reason: 'local address preserved');
  });

  test('multiple swaps per invoice fold to one row; actionable swap wins',
      () async {
    pay.result = RecoverableSwapsResult(
      recoveryEnabled: true,
      hasMore: false,
      swaps: [
        _swap(status: 'refunded', lockup: 'bc1qA', refundTxid: 'txA'),
        _swap(status: 'refund_due', lockup: 'bc1qB'),
      ],
    );
    final r = await build().execute();
    expect(repo.store.length, 1);
    final row = repo.store['inv-1']!;
    expect(row.state, RecoveryState.detected, reason: 'refund_due wins');
    expect(row.lockupAddress, 'bc1qB');
    expect(r.needsAttentionCount, 1);
  });

  test('no default wallet → no-op (empty result, no rows)', () async {
    identity = _FakeIdentity(available: false);
    pay.result = RecoverableSwapsResult(
      recoveryEnabled: true,
      hasMore: false,
      swaps: [_swap()],
    );
    final r = await build().execute();
    expect(r, same(ScanResult.empty));
    expect(repo.store, isEmpty);
  });

  test('route-absent server (recoveryUnavailable) is inert', () async {
    pay.error = const PaymentRecoveryException.recoveryUnavailable();
    final r = await build().execute();
    expect(r.needsAttentionCount, 0);
    expect(repo.store, isEmpty);
  });

  test('stale local detection no longer returned → dismissed', () async {
    repo.store['gone'] = const StuckPayment(
      invoiceId: 'gone',
      nym: 'alice',
      state: RecoveryState.detected,
      detectedAtUnix: 100,
    );
    pay.result = const RecoverableSwapsResult(
      recoveryEnabled: true,
      hasMore: false,
      swaps: [],
    );
    await build().execute();
    expect(repo.store['gone']!.state, RecoveryState.dismissed);
  });

  test('recoveryEnabled=false and hasMore surface on the result', () async {
    pay.result = RecoverableSwapsResult(
      recoveryEnabled: false,
      hasMore: true,
      swaps: [_swap()],
    );
    final r = await build().execute();
    expect(r.recoveryEnabled, isFalse);
    expect(r.hasMore, isTrue);
    // Detection still persists the row even with the recover action disabled.
    expect(repo.store['inv-1']!.state, RecoveryState.detected);
  });
}

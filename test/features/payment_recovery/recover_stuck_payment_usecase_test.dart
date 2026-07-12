import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart'
    show BullnymAuthSigner;
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_identity_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_pay_service_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/results/recovery_results.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/recover_stuck_payment_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/payment_recovery_error.dart';
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recovery_test_doubles.dart';

class _OkIdentity implements RecoveryIdentityPort {
  @override
  Future<BullnymAuthSigner> getSigningHandle() async =>
      BullnymAuthSigner(npubHex: 'npub', signHashHex: (_) async => '00');
}

class _ConfigurablePayService implements RecoveryPayServicePort {
  PaymentRecoveryException? error;
  String txid = 'txid-1';
  final List<({String nym, String invoiceId, String btcAddress})> recoverCalls =
      [];

  @override
  Future<RecoverableSwapsResult> listRecoverable({
    required BullnymAuthSigner signer,
  }) async =>
      const RecoverableSwapsResult(
        recoveryEnabled: true,
        hasMore: false,
        swaps: [],
      );

  @override
  Future<RecoverResult> recover({
    required BullnymAuthSigner signer,
    required String nym,
    required String invoiceId,
    required String btcAddress,
  }) async {
    recoverCalls.add((nym: nym, invoiceId: invoiceId, btcAddress: btcAddress));
    if (error != null) throw error!;
    return RecoverResult(status: 'recovered', txid: txid);
  }
}

class _UnusedWalletRepo implements WalletRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _UnusedAddressRepo implements WalletAddressRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _UnusedSettings implements GetSettingsUsecase {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  late InMemoryPaymentRecoveryRepository repo;
  late _ConfigurablePayService pay;

  RecoverStuckPaymentUsecase build() => RecoverStuckPaymentUsecase(
    identity: _OkIdentity(),
    payService: pay,
    repository: repo,
    walletRepository: _UnusedWalletRepo(),
    walletAddressRepository: _UnusedAddressRepo(),
    getSettings: _UnusedSettings(),
    nowSecs: () => 1_700_000_000,
  );

  // A row with a committed address exercises the reuse path (no wallet
  // derivation), so the wallet/settings deps stay unused.
  StuckPayment committed({
    RecoveryState state = RecoveryState.addressCommitted,
    String address = 'bc1qcommitted',
  }) {
    return StuckPayment(
      invoiceId: 'inv-1',
      nym: 'alice',
      state: state,
      refundAddress: address,
      detectedAtUnix: 100,
    );
  }

  setUp(() {
    repo = InMemoryPaymentRecoveryRepository();
    pay = _ConfigurablePayService();
  });

  test('reuses the committed address and recovers → recovered + txid', () async {
    repo.store['inv-1'] = committed();
    await build().execute('inv-1');

    expect(pay.recoverCalls, hasLength(1));
    expect(pay.recoverCalls.single.btcAddress, 'bc1qcommitted');
    expect(pay.recoverCalls.single.nym, 'alice');
    final row = repo.store['inv-1']!;
    expect(row.state, RecoveryState.recovered);
    expect(row.refundTxid, 'txid-1');
    expect(row.attemptCount, 1);
  });

  test('never re-derives a committed address on retry', () async {
    repo.store['inv-1'] = committed(state: RecoveryState.failed);
    await build().execute('inv-1');
    expect(pay.recoverCalls.single.btcAddress, 'bc1qcommitted');
  });

  test('RecoveryInProgress keeps the row recovering (poll elsewhere)', () async {
    repo.store['inv-1'] = committed();
    pay.error = const PaymentRecoveryException.recoveryInProgress();
    await build().execute('inv-1');
    final row = repo.store['inv-1']!;
    expect(row.state, RecoveryState.recovering);
    expect(row.lastErrorCode, 'RecoveryInProgress');
  });

  test('network error stays addressCommitted (retryable, address kept)',
      () async {
    repo.store['inv-1'] = committed();
    pay.error = const PaymentRecoveryException.network();
    await build().execute('inv-1');
    final row = repo.store['inv-1']!;
    expect(row.state, RecoveryState.addressCommitted);
    expect(row.refundAddress, 'bc1qcommitted');
  });

  test('RecoveryNotAvailable surfaces as failed (scan reconciles later)',
      () async {
    repo.store['inv-1'] = committed();
    pay.error = const PaymentRecoveryException.recoveryNotAvailable();
    await build().execute('inv-1');
    expect(repo.store['inv-1']!.state, RecoveryState.failed);
  });

  test('recoveryUnavailable (flag off / 404) stays actionable', () async {
    repo.store['inv-1'] = committed();
    pay.error = const PaymentRecoveryException.recoveryUnavailable();
    await build().execute('inv-1');
    expect(repo.store['inv-1']!.state, RecoveryState.addressCommitted);
  });

  test('terminal/recovered rows are a no-op', () async {
    repo.store['inv-1'] = committed(state: RecoveryState.recovered);
    await build().execute('inv-1');
    expect(pay.recoverCalls, isEmpty);
  });

  test('concurrent execute is single-flight (one recover call)', () async {
    repo.store['inv-1'] = committed();
    final usecase = build();
    await Future.wait([usecase.execute('inv-1'), usecase.execute('inv-1')]);
    expect(pay.recoverCalls, hasLength(1));
  });
}

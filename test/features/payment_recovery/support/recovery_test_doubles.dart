import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart'
    show BullnymAuthSigner;
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_identity_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_pay_service_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/results/recovery_results.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/dismiss_stuck_payment_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/recover_stuck_payment_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/scan_stuck_payments_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/watch_stuck_payments_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/payment_recovery_error.dart';
import 'package:bb_mobile/features/payment_recovery/domain/repositories/payment_recovery_repository.dart';
import 'package:bb_mobile/features/payment_recovery/public/payment_recovery_facade.dart';

/// In-memory [PaymentRecoveryRepository] for tests.
class InMemoryPaymentRecoveryRepository implements PaymentRecoveryRepository {
  final Map<String, StuckPayment> store = {};

  @override
  Future<List<StuckPayment>> fetchAll() async => store.values.toList();

  @override
  Future<StuckPayment?> fetch(String invoiceId) async => store[invoiceId];

  @override
  Stream<List<StuckPayment>> watch() => Stream.value(store.values.toList());

  @override
  Future<void> upsert(StuckPayment p) async => store[p.invoiceId] = p;

  @override
  Future<void> delete(String invoiceId) async => store.remove(invoiceId);
}

/// Identity port that reports no wallet, so a scan no-ops (returns empty).
class NoWalletRecoveryIdentity implements RecoveryIdentityPort {
  @override
  Future<BullnymAuthSigner> getSigningHandle() async =>
      throw const PaymentRecoveryException.noDefaultBitcoinWallet();
}

/// Pay-service that returns an empty recoverable set.
class EmptyRecoveryPayService implements RecoveryPayServicePort {
  @override
  Future<RecoverableSwapsResult> listRecoverable({
    required BullnymAuthSigner signer,
  }) async =>
      const RecoverableSwapsResult(
        recoveryEnabled: false,
        hasMore: false,
        swaps: [],
      );

  @override
  Future<RecoverResult> recover({
    required BullnymAuthSigner signer,
    required String nym,
    required String invoiceId,
    required String btcAddress,
  }) async =>
      const RecoverResult(status: 'recovered', txid: 'tx');
}

/// Unused-in-the-no-op wallet/settings deps for the recover usecase — recovery
/// is never invoked through [noopPaymentRecoveryFacade], so any call throws.
class _UnusedWalletRepository implements WalletRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _UnusedWalletAddressRepository implements WalletAddressRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _UnusedGetSettingsUsecase implements GetSettingsUsecase {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// A [PaymentRecoveryFacade] whose scan is a no-op (empty result) and whose
/// store starts empty — for wiring into cubits under test that consume it but
/// don't exercise recovery behavior.
PaymentRecoveryFacade noopPaymentRecoveryFacade() {
  final repo = InMemoryPaymentRecoveryRepository();
  return PaymentRecoveryFacade(
    scan: ScanStuckPaymentsUsecase(
      identity: NoWalletRecoveryIdentity(),
      payService: EmptyRecoveryPayService(),
      repository: repo,
      nowSecs: () => 0,
    ),
    watch: WatchStuckPaymentsUsecase(repository: repo),
    dismiss: DismissStuckPaymentUsecase(repository: repo),
    recover: RecoverStuckPaymentUsecase(
      identity: NoWalletRecoveryIdentity(),
      payService: EmptyRecoveryPayService(),
      repository: repo,
      walletRepository: _UnusedWalletRepository(),
      walletAddressRepository: _UnusedWalletAddressRepository(),
      getSettings: _UnusedGetSettingsUsecase(),
      nowSecs: () => 0,
    ),
  );
}

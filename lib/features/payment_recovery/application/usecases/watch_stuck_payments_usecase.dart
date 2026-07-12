import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/repositories/payment_recovery_repository.dart';

/// Reactive view of persisted stuck payments — backs the hub badge and the
/// stuck-payments list. Emits on every store write (e.g. after a scan).
class WatchStuckPaymentsUsecase {
  final PaymentRecoveryRepository _repository;

  WatchStuckPaymentsUsecase({required this._repository});

  Stream<List<StuckPayment>> execute() => _repository.watch();
}

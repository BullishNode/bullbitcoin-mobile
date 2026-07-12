import 'dart:async';

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:bb_mobile/features/payment_recovery/presentation/stuck_payment_detail_state.dart';
import 'package:bb_mobile/features/payment_recovery/public/payment_recovery_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Drives the stuck-payment detail screen for one invoice: one-tap recover +
/// a bounded poll of the recoverable endpoint while the swap is `refunding`
/// (the RecoveryInProgress case). Read of the row is reactive via the store.
class StuckPaymentDetailCubit extends Cubit<StuckPaymentDetailState> {
  final PaymentRecoveryFacade _recovery;
  final String _invoiceId;
  StreamSubscription<List<StuckPayment>>? _sub;

  /// Backoff for polling while `refunding` (§5.3: 3s → ×2 → cap 30s).
  static const _pollBackoffSecs = [3, 6, 12, 24, 30, 30];

  StuckPaymentDetailCubit({
    required this._recovery,
    required this._invoiceId,
  }) : super(const StuckPaymentDetailState()) {
    _sub = _recovery.watch().listen(
      (payments) {
        final match = payments.where((p) => p.invoiceId == _invoiceId);
        emit(
          match.isEmpty
              ? state.copyWith(clearPayment: true)
              : state.copyWith(payment: match.first),
        );
      },
      onError: (Object e, StackTrace s) =>
          log.warning('stuck payment detail watch failed', error: e, trace: s),
    );
  }

  /// Refresh the server flags (recover-enabled / has-more) on open.
  Future<void> load() async {
    try {
      final result = await _recovery.scan();
      if (isClosed) return;
      emit(state.copyWith(
        recoveryActionEnabled: result.recoveryEnabled,
        hasMore: result.hasMore,
      ));
    } on Exception catch (e, s) {
      log.warning('stuck payment detail load failed', error: e, trace: s);
    }
  }

  /// One-tap recover. After the call, if the swap is `refunding` server-side,
  /// poll to completion with backoff so the screen reflects the terminal txid
  /// without the merchant re-tapping.
  Future<void> recover() async {
    if (state.isBusy) return;
    emit(state.copyWith(isBusy: true));
    try {
      await _recovery.recover(_invoiceId);
      for (final secs in _pollBackoffSecs) {
        if (isClosed) return;
        if (state.payment?.state != RecoveryState.recovering) break;
        await Future<void>.delayed(Duration(seconds: secs));
        if (isClosed) return;
        await _recovery.scan();
      }
    } on Exception catch (e, s) {
      log.warning('recover failed', error: e, trace: s);
    } finally {
      if (!isClosed) emit(state.copyWith(isBusy: false));
    }
  }

  Future<void> acknowledge() => _recovery.acknowledge(_invoiceId);

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}

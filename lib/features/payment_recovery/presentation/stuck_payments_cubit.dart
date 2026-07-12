import 'dart:async';

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/presentation/stuck_payments_state.dart';
import 'package:bb_mobile/features/payment_recovery/public/payment_recovery_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Drives the stuck-payments list screen. Subscribes to the store's live view
/// for the rows and runs a scan on open / pull-to-refresh to refresh the
/// server flags (`recoveryActionEnabled`, `hasMore`). Read-only in Phase 2 —
/// no recover action yet.
class StuckPaymentsCubit extends Cubit<StuckPaymentsState> {
  final PaymentRecoveryFacade _recovery;
  StreamSubscription<List<StuckPayment>>? _sub;

  StuckPaymentsCubit({required this._recovery})
    : super(const StuckPaymentsState()) {
    _sub = _recovery.watch().listen(
      (payments) => emit(state.copyWith(payments: payments)),
      onError: (Object e, StackTrace s) =>
          log.warning('stuck payments watch failed', error: e, trace: s),
    );
  }

  /// Refresh the server flags via a scan. The row list updates reactively
  /// through the watch subscription as the scan writes to the store.
  Future<void> refresh() async {
    emit(state.copyWith(isLoading: true));
    try {
      final result = await _recovery.scan();
      if (isClosed) return;
      emit(state.copyWith(
        isLoading: false,
        recoveryActionEnabled: result.recoveryEnabled,
        hasMore: result.hasMore,
      ));
    } on Exception catch (e, s) {
      log.warning('stuck payments scan failed', error: e, trace: s);
      if (isClosed) return;
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> dismiss(String invoiceId) => _recovery.dismiss(invoiceId);

  Future<void> acknowledge(String invoiceId) =>
      _recovery.acknowledge(invoiceId);

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}

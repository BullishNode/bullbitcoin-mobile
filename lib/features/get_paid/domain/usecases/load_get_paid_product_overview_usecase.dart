import 'dart:async';

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/ensure_get_paid_automatic_fallback_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/ensure_get_paid_product_wallet_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_pos_terminal_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_product_probe.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_lightning_registration_usecase.dart';

/// Domain events emitted while the coupled Lightning Address / Donation Page /
/// POS overview is assembled. The stream preserves independent card progress
/// without leaving cross-product sequencing policy inside the dashboard Cubit.
sealed class GetPaidProductOverviewEvent {
  const GetPaidProductOverviewEvent();
}

final class GetPaidRegistrationResolved extends GetPaidProductOverviewEvent {
  final GetPaidLightningRegistration registration;

  const GetPaidRegistrationResolved(this.registration);
}

final class GetPaidRegistrationUnavailable extends GetPaidProductOverviewEvent {
  const GetPaidRegistrationUnavailable();
}

final class GetPaidPaymentPageResolved extends GetPaidProductOverviewEvent {
  final GetPaidProductProbe<GetPaidPaymentPageSnapshot> probe;

  const GetPaidPaymentPageResolved(this.probe);
}

final class GetPaidPosResolved extends GetPaidProductOverviewEvent {
  final GetPaidProductProbe<GetPaidPosTerminalSnapshot> probe;

  const GetPaidPosResolved(this.probe);
}

final class GetPaidProductWalletResolved extends GetPaidProductOverviewEvent {
  final GetPaidWalletBackedProduct product;
  final GetPaidProductWalletOutcome outcome;

  const GetPaidProductWalletResolved(this.product, this.outcome);
}

final class GetPaidAutomaticFallbackResolved
    extends GetPaidProductOverviewEvent {
  final bool ready;

  const GetPaidAutomaticFallbackResolved(this.ready);
}

final class GetPaidProductOverviewUnavailable
    extends GetPaidProductOverviewEvent {
  const GetPaidProductOverviewUnavailable();
}

/// Coordinates the coupled product rules for the Get Paid hub.
///
/// Donation Page and POS are keyed by the Lightning Address nym, automatic
/// fallback is ensured only after that identity exists, and fixed-path wallets
/// are healed only for active products. Presentation receives owned events and
/// decides only how to render them.
class LoadGetPaidProductOverviewUsecase {
  final LookUpGetPaidLightningRegistrationUsecase _lookUpRegistration;
  final FindGetPaidPaymentPageUsecase _findPaymentPage;
  final FindGetPaidPosTerminalUsecase _findPos;
  final EnsureGetPaidAutomaticFallbackUsecase _ensureAutomaticFallback;
  final EnsureGetPaidProductWalletUsecase _ensureProductWallet;

  const LoadGetPaidProductOverviewUsecase({
    required this._lookUpRegistration,
    required this._findPaymentPage,
    required this._findPos,
    required this._ensureAutomaticFallback,
    required this._ensureProductWallet,
  });

  Stream<GetPaidProductOverviewEvent> execute({
    required bool Function() isCurrent,
  }) {
    final controller = StreamController<GetPaidProductOverviewEvent>();
    unawaited(_run(controller, isCurrent));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<GetPaidProductOverviewEvent> controller,
    bool Function() isCurrent,
  ) async {
    try {
      final registration = await _lookUpRegistration.execute();
      if (!isCurrent()) return;
      if (registration == null) {
        controller.add(const GetPaidRegistrationUnavailable());
        return;
      }
      controller.add(GetPaidRegistrationResolved(registration));

      final nym = registration.nym;
      if (nym == null) {
        controller
          ..add(const GetPaidPaymentPageResolved(GetPaidProductAbsent()))
          ..add(const GetPaidPosResolved(GetPaidProductAbsent()));
        return;
      }

      // Preserve the dashboard's established concurrency: independent setup,
      // wallet healing, and product reads start together. Each product read
      // still rechecks the refresh generation before publishing or healing.
      await Future.wait([
        _resolveFallback(controller, isCurrent),
        if (registration.active)
          _resolveWallet(
            controller,
            GetPaidWalletBackedProduct.lightningAddress,
            isCurrent,
          ),
        _resolvePaymentPage(controller, nym, isCurrent),
        _resolvePos(controller, nym, isCurrent),
      ]);
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid product overview orchestration failed',
        error: error,
        trace: trace,
      );
      controller.add(const GetPaidProductOverviewUnavailable());
    } finally {
      await controller.close();
    }
  }

  Future<void> _resolveFallback(
    StreamController<GetPaidProductOverviewEvent> controller,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    try {
      final ready = await _ensureAutomaticFallback.execute();
      if (!isCurrent()) return;
      controller.add(GetPaidAutomaticFallbackResolved(ready));
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid automatic fallback setup threw unexpectedly',
        error: error,
        trace: trace,
      );
      if (isCurrent()) {
        controller.add(const GetPaidAutomaticFallbackResolved(false));
      }
    }
  }

  Future<void> _resolvePaymentPage(
    StreamController<GetPaidProductOverviewEvent> controller,
    String nym,
    bool Function() isCurrent,
  ) async {
    final probe = await _findPaymentPage.execute(nym: nym);
    if (!isCurrent()) return;
    controller.add(GetPaidPaymentPageResolved(probe));
    if (probe case GetPaidProductFound(:final row) when !row.isArchived) {
      await _resolveWallet(
        controller,
        GetPaidWalletBackedProduct.paymentPage,
        isCurrent,
      );
    }
  }

  Future<void> _resolvePos(
    StreamController<GetPaidProductOverviewEvent> controller,
    String nym,
    bool Function() isCurrent,
  ) async {
    final probe = await _findPos.execute(nym: nym);
    if (!isCurrent()) return;
    controller.add(GetPaidPosResolved(probe));
    if (probe case GetPaidProductFound(:final row) when !row.isArchived) {
      await _resolveWallet(
        controller,
        GetPaidWalletBackedProduct.pos,
        isCurrent,
      );
    }
  }

  Future<void> _resolveWallet(
    StreamController<GetPaidProductOverviewEvent> controller,
    GetPaidWalletBackedProduct product,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    final outcome = await _ensureProductWallet.execute(product);
    if (isCurrent()) {
      controller.add(GetPaidProductWalletResolved(product, outcome));
    }
  }
}

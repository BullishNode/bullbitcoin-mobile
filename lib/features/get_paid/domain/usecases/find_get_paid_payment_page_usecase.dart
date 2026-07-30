import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_product_probe.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';

/// Get Paid's narrow wrapper over the Donation Page boundary: probe the page for
/// a nym and classify the read as found / confirmed-absent / unavailable. A
/// failure never reads as absent, so the hub cannot show "not configured" for a
/// page it simply could not reach.
class FindGetPaidPaymentPageUsecase {
  final PaymentPageFacade _paymentPage;

  const FindGetPaidPaymentPageUsecase({required this._paymentPage});

  Future<GetPaidProductProbe<GetPaidPaymentPageSnapshot>> execute({
    required String nym,
  }) async {
    try {
      final page = await _paymentPage.find(nym: nym);
      return page == null
          ? const GetPaidProductAbsent()
          : GetPaidProductFound(
              GetPaidPaymentPageSnapshot(
                publicUrl: page.publicUrl,
                isArchived: page.isArchived,
              ),
            );
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid Donation Page lookup failed',
        error: error,
        trace: trace,
      );
      return const GetPaidProductUnavailable();
    }
  }
}

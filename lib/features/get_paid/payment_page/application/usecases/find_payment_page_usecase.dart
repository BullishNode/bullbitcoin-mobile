import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';

class FindPaymentPageUsecase {
  final PaymentPageServicePort _paymentPageService;

  const FindPaymentPageUsecase({
    required PaymentPageServicePort paymentPageService,
  }) : _paymentPageService = paymentPageService;

  Future<PaymentPage?> execute({required String nym}) async {
    try {
      return await _paymentPageService.getPaymentPage(nym: nym);
    } on PaymentPageNotFoundError {
      return null;
    }
  }
}

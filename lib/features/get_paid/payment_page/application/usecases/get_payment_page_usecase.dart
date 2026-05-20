import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';

class GetPaymentPageUsecase {
  final PaymentPageServicePort _paymentPageService;

  const GetPaymentPageUsecase({
    required PaymentPageServicePort paymentPageService,
  }) : _paymentPageService = paymentPageService;

  Future<PaymentPage> execute({required String nym}) {
    return _paymentPageService.getPaymentPage(nym: nym);
  }
}

import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';

class SavePaymentPageUsecase {
  final PaymentPageServicePort _paymentPageService;
  final PaymentPageIdentityPort _paymentPageIdentity;

  const SavePaymentPageUsecase({
    required PaymentPageServicePort paymentPageService,
    required PaymentPageIdentityPort paymentPageIdentity,
  }) : _paymentPageService = paymentPageService,
       _paymentPageIdentity = paymentPageIdentity;

  Future<PaymentPage> execute({required SavePaymentPageCommand command}) async {
    final handle = await _paymentPageIdentity.getSigningHandle();
    return _paymentPageService.savePaymentPage(
      command: command,
      handle: handle,
    );
  }
}

import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';

class ArchivePaymentPageUsecase {
  final PaymentPageServicePort _paymentPageService;
  final PaymentPageIdentityPort _paymentPageIdentity;

  const ArchivePaymentPageUsecase({
    required PaymentPageServicePort paymentPageService,
    required PaymentPageIdentityPort paymentPageIdentity,
  }) : _paymentPageService = paymentPageService,
       _paymentPageIdentity = paymentPageIdentity;

  Future<PaymentPage> execute({
    required ArchivePaymentPageCommand command,
  }) async {
    final handle = await _paymentPageIdentity.getSigningHandle();
    return _paymentPageService.archivePaymentPage(
      command: command,
      handle: handle,
    );
  }
}

import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/payment_page_constants.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';

class UploadPaymentPageImageUsecase {
  final PaymentPageServicePort _paymentPageService;
  final PaymentPageIdentityPort _paymentPageIdentity;

  const UploadPaymentPageImageUsecase({
    required PaymentPageServicePort paymentPageService,
    required PaymentPageIdentityPort paymentPageIdentity,
  }) : _paymentPageService = paymentPageService,
       _paymentPageIdentity = paymentPageIdentity;

  Future<PaymentPage> execute({
    required String nym,
    required List<int> bytes,
  }) async {
    validateBytes(bytes);
    final handle = await _paymentPageIdentity.getSigningHandle();
    return _paymentPageService.uploadImage(
      nym: nym,
      bytes: bytes,
      handle: handle,
    );
  }

  static void validateBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const PaymentPageValidationError('image file is empty');
    }
    if (bytes.length > paymentPageImageMaxBytes) {
      throw const PaymentPageValidationError('image file is larger than 2 MB');
    }
    if (!_isAllowedImage(bytes)) {
      throw const PaymentPageValidationError(
        'image file must be JPEG, PNG, or WebP',
      );
    }
  }

  static bool _isAllowedImage(List<int> bytes) {
    return _isJpeg(bytes) || _isPng(bytes) || _isWebp(bytes);
  }

  static bool _isJpeg(List<int> bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
  }

  static bool _isPng(List<int> bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a;
  }

  static bool _isWebp(List<int> bytes) {
    return bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
  }
}

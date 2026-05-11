import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_client.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_errors.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/models/bullnym_models.dart';

class PaymentPageDatasource implements PaymentPageServicePort {
  final BullnymClient _bullnymClient;

  const PaymentPageDatasource({required BullnymClient bullnymClient})
    : _bullnymClient = bullnymClient;

  @override
  Future<PaymentPage> getPaymentPage({required String nym}) async {
    try {
      final dto = await _bullnymClient.getPaymentPage(nym: nym);
      return dto.toEntity();
    } on BullnymException catch (e) {
      throw _mapBullnymError(e);
    }
  }

  @override
  Future<PaymentPage> savePaymentPage({
    required SavePaymentPageCommand command,
    required NostrKeychainHandle handle,
  }) async {
    try {
      final dto = await _bullnymClient.savePaymentPage(
        handle: handle,
        nym: command.nym,
        header: command.header,
        description: command.description,
        displayCurrency: command.displayCurrency,
        website: command.website,
        twitter: command.twitter,
        instagram: command.instagram,
        enabled: command.enabled,
      );
      return dto.toEntity();
    } on BullnymException catch (e) {
      throw _mapBullnymError(e);
    }
  }

  @override
  Future<PaymentPage> archivePaymentPage({
    required ArchivePaymentPageCommand command,
    required NostrKeychainHandle handle,
  }) async {
    try {
      final dto = await _bullnymClient.archivePaymentPage(
        handle: handle,
        nym: command.nym,
      );
      return dto.toEntity();
    } on BullnymException catch (e) {
      throw _mapBullnymError(e);
    }
  }

  PaymentPageApplicationError _mapBullnymError(BullnymException e) {
    return PaymentPageApplicationError.fromCode(
      code: e.code,
      reason: e.reason,
    );
  }
}

extension on BullnymDonationPageDto {
  PaymentPage toEntity() {
    return PaymentPage(
      nym: nym,
      header: header,
      description: description,
      displayCurrency: displayCurrency,
      website: website,
      twitter: twitter,
      instagram: instagram,
      enabled: enabled,
      isArchived: isArchived,
      avatarSha256: avatarSha256,
      ogSha256: ogSha256,
      publicUrl: publicUrl,
    );
  }
}

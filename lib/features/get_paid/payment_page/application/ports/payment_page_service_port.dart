import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';

abstract class PaymentPageServicePort {
  Future<PaymentPage> getPaymentPage({required String nym});

  Future<PaymentPage> savePaymentPage({
    required SavePaymentPageCommand command,
    required NostrKeychainHandle handle,
  });

  Future<PaymentPage> archivePaymentPage({
    required ArchivePaymentPageCommand command,
    required NostrKeychainHandle handle,
  });
}

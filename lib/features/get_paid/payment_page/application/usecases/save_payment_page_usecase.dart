import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';

class SavePaymentPageUsecase {
  final PaymentPageServicePort _paymentPageService;
  final PaymentPageIdentityPort _paymentPageIdentity;
  final GetSettingsUsecase _getSettings;
  final ExternalReceiveWalletsFacade _externalReceiveWallets;

  const SavePaymentPageUsecase({
    required PaymentPageServicePort paymentPageService,
    required PaymentPageIdentityPort paymentPageIdentity,
    required GetSettingsUsecase getSettings,
    required ExternalReceiveWalletsFacade externalReceiveWallets,
  }) : _paymentPageService = paymentPageService,
       _paymentPageIdentity = paymentPageIdentity,
       _getSettings = getSettings,
       _externalReceiveWallets = externalReceiveWallets;

  Future<PaymentPage> execute({required SavePaymentPageCommand command}) async {
    String? ctDescriptor;
    if (command.enabled) {
      ctDescriptor =
          (await _ensurePaymentPageReceiveWallet()).externalPublicDescriptor;
    }
    final handle = await _paymentPageIdentity.getSigningHandle();
    return _paymentPageService.savePaymentPage(
      command: command,
      handle: handle,
      ctDescriptor: ctDescriptor ?? '',
    );
  }

  Future<Wallet> _ensurePaymentPageReceiveWallet() async {
    final settings = await _getSettings.execute();
    final accountKey = ExternalReceiveWalletPurpose.paymentPage
        .liquidAccountKey(isTestnet: settings.environment.isTestnet);
    try {
      final existing = await _externalReceiveWallets.get(
        environment: settings.environment,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
        accountKey: accountKey,
      );
      if (existing != null) return existing;
      return _externalReceiveWallets.create(
        environment: settings.environment,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
        accountKey: accountKey,
      );
    } on ExternalReceiveWalletAlreadyExistsException {
      final existing = await _externalReceiveWallets.get(
        environment: settings.environment,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
        accountKey: accountKey,
      );
      if (existing != null) return existing;
      throw const PaymentPageUnexpectedError('Payment Page wallet exists');
    } on ExternalReceiveWalletNoDefaultWalletException {
      throw const PaymentPageIdentityUnavailableError(
        'No default Liquid wallet found',
      );
    } on ExternalReceiveWalletMetadataException catch (e) {
      throw PaymentPageUnexpectedError(e.message);
    }
  }
}

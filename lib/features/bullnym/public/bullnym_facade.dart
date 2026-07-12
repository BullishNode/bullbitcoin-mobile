import 'package:bb_mobile/features/bullnym/domain/bullnym_auth_signer.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_donation_page.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_invoice.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_registration.dart';
import 'package:bb_mobile/features/bullnym/domain/bullpay_signing.dart';
import 'package:bb_mobile/features/bullnym/domain/usecases/archive_donation_page_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/usecases/delete_bullnym_registration_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/usecases/get_donation_page_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/usecases/get_supported_currencies_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/usecases/lookup_bullnym_registration_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/usecases/register_bullnym_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/usecases/save_donation_page_usecase.dart';

export 'package:bb_mobile/features/bullnym/domain/bullnym_auth_signer.dart';
export 'package:bb_mobile/features/bullnym/domain/bullnym_donation_page.dart';
export 'package:bb_mobile/features/bullnym/domain/bullnym_error.dart';
export 'package:bb_mobile/features/bullnym/domain/bullnym_invoice.dart';
export 'package:bb_mobile/features/bullnym/domain/bullnym_registration.dart';

class BullnymFacade {
  final BullnymClientPort _client;
  final RegisterBullnymUsecase _register;
  final DeleteBullnymRegistrationUsecase _deleteRegistration;
  final LookupBullnymRegistrationUsecase _lookupRegistration;
  final GetDonationPageUsecase _getDonationPage;
  final SaveDonationPageUsecase _saveDonationPage;
  final ArchiveDonationPageUsecase _archiveDonationPage;
  final GetSupportedCurrenciesUsecase _getSupportedCurrencies;

  BullnymFacade({
    required BullnymClientPort client,
    int Function() nowSecs = currentBullpayTimestampSecs,
  }) : _client = client,
       _register = RegisterBullnymUsecase(client, nowSecs),
       _deleteRegistration = DeleteBullnymRegistrationUsecase(client, nowSecs),
       _lookupRegistration = LookupBullnymRegistrationUsecase(client),
       _getDonationPage = GetDonationPageUsecase(client),
       _saveDonationPage = SaveDonationPageUsecase(client, nowSecs),
       _archiveDonationPage = ArchiveDonationPageUsecase(client, nowSecs),
       _getSupportedCurrencies = GetSupportedCurrenciesUsecase(client);

  Future<BullnymRegisterResult> register({
    required BullnymAuthSigner signer,
    required String nym,
    required String ctDescriptor,
  }) {
    return _register.execute(
      signer: signer,
      nym: nym,
      ctDescriptor: ctDescriptor,
    );
  }

  Future<void> deleteRegistration({
    required BullnymAuthSigner signer,
    required String nym,
  }) {
    return _deleteRegistration.execute(signer: signer, nym: nym);
  }

  Future<BullnymLookupResult> lookupRegistration({required String npubHex}) {
    return _lookupRegistration.execute(npubHex: npubHex);
  }

  Future<BullnymDonationPage> getDonationPage({
    required String nym,
    required String kind,
  }) {
    return _getDonationPage.execute(nym: nym, kind: kind);
  }

  // `kind` is surfaced (not pinned) so the future POS surface reuses this
  // client; the payment_page feature pins `kind = payment_page`.
  Future<BullnymDonationPage> saveDonationPage({
    required BullnymAuthSigner signer,
    required String nym,
    required String ctDescriptor,
    required String header,
    required String description,
    required String displayCurrency,
    required String website,
    required String twitter,
    required String instagram,
    required bool enabled,
    required String kind,
  }) {
    return _saveDonationPage.execute(
      signer: signer,
      nym: nym,
      ctDescriptor: ctDescriptor,
      header: header,
      description: description,
      displayCurrency: displayCurrency,
      website: website,
      twitter: twitter,
      instagram: instagram,
      enabled: enabled,
      kind: kind,
    );
  }

  Future<BullnymDonationPage> archiveDonationPage({
    required BullnymAuthSigner signer,
    required String nym,
    required String kind,
  }) {
    return _archiveDonationPage.execute(signer: signer, nym: nym, kind: kind);
  }

  Future<BullnymSupportedCurrencies> getSupportedCurrencies() {
    return _getSupportedCurrencies.execute();
  }

  // Invoice methods sign in the client (the `invoice-*` actions) and delegate
  // straight through. `nym` stays nullable (default null = the unlinked v1
  // path) so the facade is linked-capable when DG-I1 later flips it on.
  Future<BullnymCreateInvoiceResponse> createInvoice({
    required BullnymAuthSigner signer,
    String? nym,
    required BullnymCreateInvoiceFields fields,
  }) {
    return _client.createInvoice(signer: signer, nym: nym, fields: fields);
  }

  Future<BullnymCancelInvoiceResponse> cancelInvoice({
    required BullnymAuthSigner signer,
    String? nym,
    required String invoiceId,
  }) {
    return _client.cancelInvoice(
      signer: signer,
      nym: nym,
      invoiceId: invoiceId,
    );
  }

  Future<BullnymListInvoicesResponse> listInvoices({
    required BullnymAuthSigner signer,
    required int page,
    required int pageSize,
    String? status,
  }) {
    return _client.listInvoices(
      signer: signer,
      page: page,
      pageSize: pageSize,
      status: status,
    );
  }

  Future<BullnymInvoiceStatus> getInvoiceStatus({required String invoiceId}) {
    return _client.getInvoiceStatus(invoiceId: invoiceId);
  }

  Future<BullnymRecoverableSwapList> listRecoverableChainSwaps({
    required BullnymAuthSigner signer,
  }) {
    return _client.listRecoverableChainSwaps(signer: signer);
  }

  Future<BullnymRecoverChainSwapResponse> recoverChainSwap({
    required BullnymAuthSigner signer,
    required String nym,
    required String invoiceId,
    required String btcAddress,
  }) {
    return _client.recoverChainSwap(
      signer: signer,
      nym: nym,
      invoiceId: invoiceId,
      btcAddress: btcAddress,
    );
  }

  @override
  String toString() => 'BullnymFacade';
}

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_auth_signer.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_donation_page.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_failure.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_invoice.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_registration.dart';

/// A hand fake [BullnymClientPort] for payment_page unit tests: it records the
/// donation-page write calls (so zero-write assertions are possible) and lets a
/// test seed a stored page or inject typed failures per method.
class RecordingBullnymClient implements BullnymClientPort {
  final List<BullnymSaveDonationPageRequest> saveCalls = [];
  final List<BullnymArchiveDonationPageRequest> archiveCalls = [];
  int getDonationPageCalls = 0;

  BullnymDonationPage? storedPage;
  BullnymFailure? getError;
  BullnymFailure? saveError;
  BullnymFailure? archiveError;
  BullnymFailure? currenciesError;

  List<BullnymSupportedCurrency> currencies = const [
    BullnymSupportedCurrency(code: 'CAD', precision: 2),
    BullnymSupportedCurrency(code: 'USD', precision: 2),
  ];

  int get totalWriteCalls => saveCalls.length + archiveCalls.length;

  @override
  Future<Result<BullnymRegisterResult, BullnymFailure>> register(
    BullnymRegisterRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<void, BullnymFailure>> deleteRegistration(
    BullnymDeleteRegistrationRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<BullnymLookupResult, BullnymFailure>> lookupRegistration({
    required String npubHex,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<BullnymDonationPage, BullnymFailure>> getDonationPage({
    required String nym,
    required String kind,
  }) async {
    getDonationPageCalls += 1;
    final error = getError;
    if (error != null) return Err(error);
    final page = storedPage;
    if (page == null) {
      return const Err(
        BullnymFailure.serverRejectedRequest(
          code: 'DonationPageNotFound',
          logMessage: 'no donation page',
          statusCode: 200,
          retryable: false,
        ),
      );
    }
    return Ok(page);
  }

  @override
  Future<Result<BullnymDonationPage, BullnymFailure>> saveDonationPage(
    BullnymSaveDonationPageRequest request,
  ) async {
    saveCalls.add(request);
    final error = saveError;
    if (error != null) return Err(error);
    return Ok(_viewFromSave(request));
  }

  @override
  Future<Result<BullnymDonationPage, BullnymFailure>> archiveDonationPage(
    BullnymArchiveDonationPageRequest request,
  ) async {
    archiveCalls.add(request);
    final error = archiveError;
    if (error != null) return Err(error);
    final page = storedPage;
    return Ok(
      BullnymDonationPage(
        nym: request.nym,
        header: page?.header ?? 'Tip me',
        description: page?.description ?? 'Support my work',
        displayCurrency: page?.displayCurrency ?? 'CAD',
        kind: request.kind,
        posMode: false,
        enabled: page?.enabled ?? true,
        isArchived: true,
        publicUrl: page?.publicUrl ?? 'https://bullpay.ca/${request.nym}',
      ),
    );
  }

  @override
  Future<Result<BullnymSupportedCurrencies, BullnymFailure>>
  getSupportedCurrencies() async {
    final error = currenciesError;
    if (error != null) return Err(error);
    return Ok(BullnymSupportedCurrencies(currencies: currencies));
  }

  // Invoice surface — not exercised by the payment_page donation-page tests.
  @override
  Future<Result<BullnymCreateInvoiceResponse, BullnymFailure>> createInvoice({
    required BullnymAuthSigner signer,
    String? nym,
    required BullnymCreateInvoiceFields fields,
  }) => throw UnimplementedError();

  @override
  Future<Result<BullnymCancelInvoiceResponse, BullnymFailure>> cancelInvoice({
    required BullnymAuthSigner signer,
    String? nym,
    required String invoiceId,
  }) => throw UnimplementedError();

  @override
  Future<Result<BullnymListInvoicesResponse, BullnymFailure>> listInvoices({
    required BullnymAuthSigner signer,
    required int page,
    required int pageSize,
    String? status,
  }) => throw UnimplementedError();

  @override
  Future<Result<BullnymInvoiceStatus, BullnymFailure>> getInvoiceStatus({
    required String invoiceId,
  }) => throw UnimplementedError();

  BullnymDonationPage _viewFromSave(BullnymSaveDonationPageRequest request) {
    return BullnymDonationPage(
      nym: request.nym,
      header: request.header,
      description: request.description,
      displayCurrency: request.displayCurrency,
      website: request.website.isEmpty ? null : request.website,
      twitter: request.twitter.isEmpty ? null : request.twitter,
      instagram: request.instagram.isEmpty ? null : request.instagram,
      kind: request.kind,
      posMode: false,
      enabled: request.enabled,
      isArchived: false,
      publicUrl: 'https://bullpay.ca/${request.nym}',
    );
  }
}

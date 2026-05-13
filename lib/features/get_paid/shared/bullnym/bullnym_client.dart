import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_constants.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_errors.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullpay_signing.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/models/bullnym_models.dart';
import 'package:dio/dio.dart';

const Duration bullnymConnectTimeout = Duration(seconds: 10);
const Duration bullnymReceiveTimeout = Duration(seconds: 15);

class BullnymClient {
  BullnymClient({Dio? dio, String baseUrl = bullnymDefaultBaseUrl})
    : _dio = dio ?? _newDio(baseUrl);

  final Dio _dio;

  static Dio _newDio(String baseUrl) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: bullnymConnectTimeout,
        receiveTimeout: bullnymReceiveTimeout,
        validateStatus: (status) => status != null && status < 600,
      ),
    );
  }

  Future<BullnymRegisterResponseDto> register({
    required NostrKeychainHandle handle,
    required String nym,
    required String ctDescriptor,
    int? timestampSecs,
  }) async {
    final ts = timestampSecs ?? currentBullpayTimestampSecs();
    final response = await _postMap(
      '/register',
      data: {
        'nym': nym,
        'ct_descriptor': ctDescriptor,
        ..._signedFields(
          handle: handle,
          action: bullpayActionRegister,
          nymOrEmpty: nym,
          payloadFields: [ctDescriptor],
          timestampSecs: ts,
        ),
      },
    );
    return BullnymRegisterResponseDto.fromJson(response);
  }

  Future<BullnymDeleteResponseDto> deleteRegistration({
    required NostrKeychainHandle handle,
    required String nym,
    int? timestampSecs,
  }) async {
    final ts = timestampSecs ?? currentBullpayTimestampSecs();
    final response = await _deleteMap(
      '/register',
      data: {
        'nym': nym,
        ..._signedFields(
          handle: handle,
          action: bullpayActionDelete,
          nymOrEmpty: nym,
          payloadFields: const [],
          timestampSecs: ts,
        ),
      },
    );
    return BullnymDeleteResponseDto.fromJson(response);
  }

  Future<BullnymLookupResponseDto> lookupRegistration({
    required String npubHex,
  }) async {
    final response = await _getMap(
      '/register/lookup',
      queryParameters: {'npub': npubHex},
    );
    return BullnymLookupResponseDto.fromJson(response);
  }

  Future<BullnymSupportedCurrenciesDto> getSupportedCurrencies() async {
    final response = await _getMap('/api/v1/supported-currencies');
    return BullnymSupportedCurrenciesDto.fromJson(response);
  }

  Future<BullnymDonationPageDto> getPaymentPage({required String nym}) async {
    final response = await _getMap('/donation-page/$nym');
    return BullnymDonationPageDto.fromJson(response);
  }

  Future<BullnymDonationPageDto> savePaymentPage({
    required NostrKeychainHandle handle,
    required String nym,
    required String header,
    required String description,
    required String displayCurrency,
    String? website,
    String? twitter,
    String? instagram,
    required bool enabled,
    int? timestampSecs,
  }) async {
    final ts = timestampSecs ?? currentBullpayTimestampSecs();
    final websiteValue = website ?? '';
    final twitterValue = twitter ?? '';
    final instagramValue = instagram ?? '';
    final enabledValue = enabled ? '1' : '0';
    final response = await _putMap(
      '/donation-page',
      data: {
        'nym': nym,
        'header': header,
        'description': description,
        'display_currency': displayCurrency,
        'website': websiteValue,
        'twitter': twitterValue,
        'instagram': instagramValue,
        'enabled': enabled,
        ..._signedFields(
          handle: handle,
          action: bullpayActionDonationPageSave,
          nymOrEmpty: nym,
          payloadFields: [
            header,
            description,
            displayCurrency,
            websiteValue,
            twitterValue,
            instagramValue,
            enabledValue,
          ],
          timestampSecs: ts,
        ),
      },
    );
    return BullnymDonationPageDto.fromJson(response);
  }

  Future<BullnymDonationPageDto> archivePaymentPage({
    required NostrKeychainHandle handle,
    required String nym,
    int? timestampSecs,
  }) async {
    final ts = timestampSecs ?? currentBullpayTimestampSecs();
    final response = await _deleteMap(
      '/donation-page',
      data: {
        'nym': nym,
        ..._signedFields(
          handle: handle,
          action: bullpayActionDonationPageArchive,
          nymOrEmpty: nym,
          payloadFields: const [],
          timestampSecs: ts,
        ),
      },
    );
    return BullnymDonationPageDto.fromJson(response);
  }

  Future<BullnymCreateInvoiceResponseDto> createInvoice({
    required NostrKeychainHandle handle,
    required String? nym,
    required int? amountSat,
    required int? fiatAmountMinor,
    required String? fiatCurrency,
    required String? publicDescription,
    required String? recipientName,
    required String? invoiceNumber,
    required bool acceptBtc,
    required bool acceptLn,
    required bool acceptLiquid,
    required String? bitcoinAddress,
    required String? liquidAddress,
    String? liquidBlindingKeyHex,
    required DateTime expiresAt,
    int? timestampSecs,
  }) async {
    final ts = timestampSecs ?? currentBullpayTimestampSecs();
    final nymOrEmpty = nym ?? '';
    final amountSatValue = amountSat?.toString() ?? '';
    final fiatAmountMinorValue = fiatAmountMinor?.toString() ?? '';
    final fiatCurrencyValue = fiatCurrency ?? '';
    final publicDescriptionValue = publicDescription ?? '';
    final recipientNameValue = recipientName ?? '';
    final invoiceNumberValue = invoiceNumber ?? '';
    final acceptBtcValue = acceptBtc.toString();
    final acceptLnValue = acceptLn.toString();
    final acceptLiquidValue = acceptLiquid.toString();
    final bitcoinAddressValue = bitcoinAddress ?? '';
    final liquidAddressValue = liquidAddress ?? '';
    final liquidBlindingKeyHexValue = liquidBlindingKeyHex ?? '';
    final expiresAtUnix = expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    final expiresAtValue = expiresAtUnix.toString();
    final data = <String, dynamic>{
      'npub': handle.publicKeyHex,
      'accept_btc': acceptBtc,
      'accept_ln': acceptLn,
      'accept_liquid': acceptLiquid,
      'expires_at_unix': expiresAtUnix,
      'signature': signBullpayAction(
        handle: handle,
        action: bullpayActionInvoiceCreate,
        nymOrEmpty: nymOrEmpty,
        payloadFields: [
          amountSatValue,
          fiatAmountMinorValue,
          fiatCurrencyValue,
          publicDescriptionValue,
          recipientNameValue,
          invoiceNumberValue,
          acceptBtcValue,
          acceptLnValue,
          acceptLiquidValue,
          bitcoinAddressValue,
          liquidAddressValue,
          liquidBlindingKeyHexValue,
          expiresAtValue,
        ],
        timestampSecs: ts,
      ),
      'timestamp': ts,
    };
    void addIfPresent(String key, Object? value) {
      if (value != null) data[key] = value;
    }

    addIfPresent('amount_sat', amountSat);
    addIfPresent('fiat_amount_minor', fiatAmountMinor);
    addIfPresent('fiat_currency', fiatCurrency);
    addIfPresent('public_description', publicDescription);
    addIfPresent('recipient_name', recipientName);
    addIfPresent('invoice_number', invoiceNumber);
    addIfPresent('bitcoin_address', bitcoinAddress);
    addIfPresent('liquid_address', liquidAddress);
    addIfPresent('liquid_blinding_key_hex', liquidBlindingKeyHex);

    final response = await _postMap(
      nym == null ? '/api/v1/invoices' : '/api/v1/$nym/invoices',
      data: data,
    );
    return BullnymCreateInvoiceResponseDto.fromJson(response);
  }

  Future<BullnymCancelInvoiceResponseDto> cancelInvoice({
    required NostrKeychainHandle handle,
    required String invoiceId,
    required String? nym,
    int? timestampSecs,
  }) async {
    final ts = timestampSecs ?? currentBullpayTimestampSecs();
    final nymOrEmpty = nym ?? '';
    final response = await _deleteMap(
      nym == null
          ? '/api/v1/invoices/$invoiceId'
          : '/api/v1/$nym/invoices/$invoiceId',
      data: {
        'npub': handle.publicKeyHex,
        'signature': signBullpayAction(
          handle: handle,
          action: bullpayActionInvoiceCancel,
          nymOrEmpty: nymOrEmpty,
          payloadFields: [invoiceId],
          timestampSecs: ts,
        ),
        'timestamp': ts,
      },
    );
    return BullnymCancelInvoiceResponseDto.fromJson(response);
  }

  Future<BullnymListInvoicesResponseDto> listInvoices({
    required NostrKeychainHandle handle,
    required int page,
    required int pageSize,
    String? status,
    int? timestampSecs,
  }) async {
    if (page < 1 || page > 1000) {
      throw ArgumentError.value(page, 'page', 'must be between 1 and 1000');
    }
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'must be between 1 and 100',
      );
    }
    final ts = timestampSecs ?? currentBullpayTimestampSecs();
    final pageValue = page.toString();
    final pageSizeValue = pageSize.toString();
    final statusValue = status ?? '';
    final queryParameters = <String, dynamic>{
      'npub': handle.publicKeyHex,
      'timestamp': ts,
      'signature': signBullpayAction(
        handle: handle,
        action: bullpayActionInvoiceList,
        nymOrEmpty: '',
        payloadFields: [pageValue, pageSizeValue, statusValue],
        timestampSecs: ts,
      ),
      'page': page,
      'pageSize': pageSize,
    };
    if (status != null) queryParameters['status'] = status;

    final response = await _getMap(
      '/api/v1/invoices',
      queryParameters: queryParameters,
    );
    return BullnymListInvoicesResponseDto.fromJson(response);
  }

  Future<BullnymInvoiceStatusDto> getInvoiceStatus({
    required String invoiceId,
  }) async {
    final response = await _getMap('/api/v1/invoices/$invoiceId/status');
    return BullnymInvoiceStatusDto.fromJson(response);
  }

  Map<String, dynamic> _signedFields({
    required NostrKeychainHandle handle,
    required String action,
    required String nymOrEmpty,
    required List<String> payloadFields,
    required int timestampSecs,
  }) {
    return {
      'npub': handle.publicKeyHex,
      'signature': signBullpayAction(
        handle: handle,
        action: action,
        nymOrEmpty: nymOrEmpty,
        payloadFields: payloadFields,
        timestampSecs: timestampSecs,
      ),
      'timestamp': timestampSecs,
    };
  }

  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _requestMap(
      () => _dio.get<dynamic>(
        path,
        queryParameters: _withoutNulls(queryParameters),
      ),
    );
  }

  Future<Map<String, dynamic>> _postMap(String path, {Object? data}) async {
    return _requestMap(() => _dio.post<dynamic>(path, data: data));
  }

  Future<Map<String, dynamic>> _putMap(String path, {Object? data}) async {
    return _requestMap(() => _dio.put<dynamic>(path, data: data));
  }

  Future<Map<String, dynamic>> _deleteMap(String path, {Object? data}) async {
    return _requestMap(() => _dio.delete<dynamic>(path, data: data));
  }

  Future<Map<String, dynamic>> _requestMap(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      return _decodeMap(await request());
    } on DioException catch (e) {
      final response = e.response;
      if (response != null) return _decodeMap(response);
      throw BullnymNetworkException(_networkErrorMessage(e));
    }
  }

  String _networkErrorMessage(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout => 'Connection timed out',
      DioExceptionType.sendTimeout => 'Request timed out',
      DioExceptionType.receiveTimeout => 'Server took too long to respond',
      DioExceptionType.connectionError => 'Unable to reach Bullpay',
      _ => e.message ?? 'Network request failed',
    };
  }

  Map<String, dynamic> _decodeMap(Response<dynamic> response) {
    throwIfBullnymError(response);
    final statusCode = response.statusCode;
    if (statusCode == null || statusCode < 200 || statusCode >= 300) {
      throw BullnymException.fromResponse(response);
    }
    final data = requireJson(response);
    if (data is Map<String, dynamic>) return data;
    throw BullnymException(
      code: 'InvalidJson',
      reason: 'Server returned an unexpected response shape',
      statusCode: response.statusCode,
    );
  }

  Map<String, dynamic>? _withoutNulls(Map<String, dynamic>? source) {
    if (source == null) return null;
    return {
      for (final entry in source.entries)
        if (entry.value != null) entry.key: entry.value,
    };
  }
}

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/data/datasources/payment_page_datasource.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBullnymClient extends Mock implements BullnymClient {}

void main() {
  late _MockBullnymClient bullnymClient;
  late PaymentPageDatasource datasource;
  late NostrKeychainHandle handle;

  setUp(() {
    bullnymClient = _MockBullnymClient();
    datasource = PaymentPageDatasource(bullnymClient: bullnymClient);
    handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);
  });

  test('maps get payment page dto to entity', () async {
    when(
      () => bullnymClient.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _dto());

    final page = await datasource.getPaymentPage(nym: 'alice');

    expect(page.nym, 'alice');
    expect(page.displayCurrency, 'CAD');
    expect(page.isActive, isTrue);
    expect(page.publicUrl, 'https://bullpay.ca/alice');
  });

  test('passes save command fields to Bullnym client', () async {
    when(
      () => bullnymClient.savePaymentPage(
        handle: handle,
        nym: 'alice',
        ctDescriptor: 'ct-desc',
        header: "Alice's Coffee",
        description: 'Tips welcome',
        displayCurrency: 'USD',
        website: 'https://alice.example',
        twitter: 'alice',
        instagram: 'alice_ig',
        enabled: true,
      ),
    ).thenAnswer((_) async => _dto(displayCurrency: 'USD'));

    final page = await datasource.savePaymentPage(
      command: SavePaymentPageCommand(
        nym: 'alice',
        header: "Alice's Coffee",
        description: 'Tips welcome',
        displayCurrency: 'USD',
        website: 'https://alice.example',
        twitter: 'alice',
        instagram: 'alice_ig',
        enabled: true,
      ),
      handle: handle,
      ctDescriptor: 'ct-desc',
    );

    expect(page.displayCurrency, 'USD');
    verify(
      () => bullnymClient.savePaymentPage(
        handle: handle,
        nym: 'alice',
        ctDescriptor: 'ct-desc',
        header: "Alice's Coffee",
        description: 'Tips welcome',
        displayCurrency: 'USD',
        website: 'https://alice.example',
        twitter: 'alice',
        instagram: 'alice_ig',
        enabled: true,
      ),
    ).called(1);
  });

  test('passes archive command fields to Bullnym client', () async {
    when(
      () => bullnymClient.archivePaymentPage(handle: handle, nym: 'alice'),
    ).thenAnswer((_) async => _dto(isArchived: true));

    final page = await datasource.archivePaymentPage(
      command: const ArchivePaymentPageCommand(nym: 'alice'),
      handle: handle,
    );

    expect(page.isArchived, isTrue);
    verify(
      () => bullnymClient.archivePaymentPage(handle: handle, nym: 'alice'),
    ).called(1);
  });

  test('maps Bullnym not found errors to payment page errors', () async {
    when(() => bullnymClient.getPaymentPage(nym: 'alice')).thenThrow(
      const BullnymException(
        code: 'DonationPageNotFound',
        reason: 'alice',
        statusCode: 404,
      ),
    );

    await expectLater(
      datasource.getPaymentPage(nym: 'alice'),
      throwsA(isA<PaymentPageNotFoundError>()),
    );
  });

  test('maps Bullnym validation errors to payment page errors', () async {
    when(() => bullnymClient.getPaymentPage(nym: 'alice')).thenThrow(
      const BullnymException(
        code: 'DonationPageInvalid',
        reason: 'invalid page',
        statusCode: 400,
      ),
    );

    await expectLater(
      datasource.getPaymentPage(nym: 'alice'),
      throwsA(isA<PaymentPageValidationError>()),
    );
  });

  test('maps Bullnym auth errors to payment page errors', () async {
    when(() => bullnymClient.getPaymentPage(nym: 'alice')).thenThrow(
      const BullnymException(
        code: 'AuthError',
        reason: 'bad signature',
        statusCode: 401,
      ),
    );

    await expectLater(
      datasource.getPaymentPage(nym: 'alice'),
      throwsA(isA<PaymentPageAuthorizationError>()),
    );
  });

  test('maps Bullnym network errors to payment page errors', () async {
    when(
      () => bullnymClient.getPaymentPage(nym: 'alice'),
    ).thenThrow(BullnymNetworkException('offline'));

    await expectLater(
      datasource.getPaymentPage(nym: 'alice'),
      throwsA(isA<PaymentPageNetworkError>()),
    );
  });

  test(
    'maps unknown Bullnym errors to unexpected payment page errors',
    () async {
      when(() => bullnymClient.getPaymentPage(nym: 'alice')).thenThrow(
        const BullnymException(
          code: 'UnknownThing',
          reason: 'unknown',
          statusCode: 500,
        ),
      );

      await expectLater(
        datasource.getPaymentPage(nym: 'alice'),
        throwsA(isA<PaymentPageUnexpectedError>()),
      );
    },
  );
}

BullnymDonationPageDto _dto({
  String displayCurrency = 'CAD',
  bool isArchived = false,
}) {
  return BullnymDonationPageDto(
    nym: 'alice',
    header: "Alice's Coffee",
    description: 'Tips welcome',
    displayCurrency: displayCurrency,
    website: 'https://alice.example',
    twitter: 'alice',
    instagram: 'alice_ig',
    enabled: true,
    isArchived: isArchived,
    avatarSha256: null,
    ogSha256: null,
    publicUrl: 'https://bullpay.ca/alice',
  );
}

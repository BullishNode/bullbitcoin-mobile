import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/get_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPaymentPageService extends Mock implements PaymentPageServicePort {}

class _MockPaymentPageIdentity extends Mock
    implements PaymentPageIdentityPort {}

void main() {
  late _MockPaymentPageService paymentPageService;
  late _MockPaymentPageIdentity paymentPageIdentity;
  late NostrKeychainHandle handle;

  setUp(() {
    paymentPageService = _MockPaymentPageService();
    paymentPageIdentity = _MockPaymentPageIdentity();
    handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);
    when(
      () => paymentPageIdentity.getSigningHandle(),
    ).thenAnswer((_) async => handle);
  });

  test('get payment page usecase delegates to service', () async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());

    final page = await GetPaymentPageUsecase(
      paymentPageService: paymentPageService,
    ).execute(nym: 'alice');

    expect(page.nym, 'alice');
    verify(() => paymentPageService.getPaymentPage(nym: 'alice')).called(1);
  });

  test('save payment page usecase delegates command and handle', () async {
    final command = SavePaymentPageCommand(
      nym: 'alice',
      header: "Alice's Coffee",
      description: 'Tips welcome',
      displayCurrency: 'CAD',
      enabled: true,
    );
    when(
      () =>
          paymentPageService.savePaymentPage(command: command, handle: handle),
    ).thenAnswer((_) async => _page());

    final page = await SavePaymentPageUsecase(
      paymentPageService: paymentPageService,
      paymentPageIdentity: paymentPageIdentity,
    ).execute(command: command);

    expect(page.isActive, isTrue);
    verify(() => paymentPageIdentity.getSigningHandle()).called(1);
    verify(
      () =>
          paymentPageService.savePaymentPage(command: command, handle: handle),
    ).called(1);
  });

  test('archive payment page usecase delegates command and handle', () async {
    const command = ArchivePaymentPageCommand(nym: 'alice');
    when(
      () => paymentPageService.archivePaymentPage(
        command: command,
        handle: handle,
      ),
    ).thenAnswer((_) async => _page(isArchived: true));

    final page = await ArchivePaymentPageUsecase(
      paymentPageService: paymentPageService,
      paymentPageIdentity: paymentPageIdentity,
    ).execute(command: command);

    expect(page.isArchived, isTrue);
    verify(() => paymentPageIdentity.getSigningHandle()).called(1);
    verify(
      () => paymentPageService.archivePaymentPage(
        command: command,
        handle: handle,
      ),
    ).called(1);
  });

  test('find payment page usecase returns null for not found', () async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'missing'),
    ).thenThrow(const PaymentPageNotFoundError('missing'));

    final page = await FindPaymentPageUsecase(
      paymentPageService: paymentPageService,
    ).execute(nym: 'missing');

    expect(page, isNull);
  });

  test('save command validates backend field constraints', () {
    expect(
      () => SavePaymentPageCommand(
        nym: 'alice',
        header: '',
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        enabled: true,
      ),
      throwsA(isA<PaymentPageValidationError>()),
    );
    expect(
      () => SavePaymentPageCommand(
        nym: 'alice',
        header: 'Alice',
        description: 'Tips welcome',
        displayCurrency: 'JPY',
        enabled: true,
      ),
      throwsA(isA<PaymentPageValidationError>()),
    );
    expect(
      () => SavePaymentPageCommand(
        nym: 'alice',
        header: 'Alice',
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        website: 'http://alice.example',
        enabled: true,
      ),
      throwsA(isA<PaymentPageValidationError>()),
    );
    expect(
      () => SavePaymentPageCommand(
        nym: 'alice',
        header: 'Alice',
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        twitter: 'not-valid!',
        enabled: true,
      ),
      throwsA(isA<PaymentPageValidationError>()),
    );
  });
}

PaymentPage _page({bool isArchived = false}) {
  return PaymentPage(
    nym: 'alice',
    header: "Alice's Coffee",
    description: 'Tips welcome',
    displayCurrency: 'CAD',
    website: null,
    twitter: null,
    instagram: null,
    enabled: true,
    isArchived: isArchived,
    avatarSha256: null,
    ogSha256: null,
    publicUrl: 'https://bullpay.ca/alice',
  );
}

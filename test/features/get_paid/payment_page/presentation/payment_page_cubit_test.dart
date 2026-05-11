import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPaymentPageService extends Mock implements PaymentPageServicePort {}

class _MockPaymentPageIdentity extends Mock
    implements PaymentPageIdentityPort {}

void main() {
  late _MockPaymentPageService paymentPageService;
  late _MockPaymentPageIdentity paymentPageIdentity;
  late PaymentPageCubit cubit;
  late NostrKeychainHandle handle;

  setUpAll(() {
    registerFallbackValue(
      SavePaymentPageCommand(
        nym: 'fallback',
        header: 'Fallback',
        description: 'Fallback description',
        displayCurrency: 'CAD',
        enabled: true,
      ),
    );
    registerFallbackValue(const ArchivePaymentPageCommand(nym: 'fallback'));
    registerFallbackValue(NostrKeychainHandle.fromSecretKeyHex('02' * 32));
  });

  setUp(() {
    paymentPageService = _MockPaymentPageService();
    paymentPageIdentity = _MockPaymentPageIdentity();
    handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);

    when(
      () => paymentPageIdentity.getSigningHandle(),
    ).thenAnswer((_) async => handle);
    when(
      () => paymentPageService.getPaymentPage(nym: any(named: 'nym')),
    ).thenThrow(const PaymentPageNotFoundError('missing'));

    cubit = PaymentPageCubit(
      findPaymentPage: FindPaymentPageUsecase(
        paymentPageService: paymentPageService,
      ),
      savePaymentPage: SavePaymentPageUsecase(
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
      archivePaymentPage: ArchivePaymentPageUsecase(
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
  });

  tearDown(() => cubit.close());

  test(
    'load blocks creation when Lightning Address nym is unavailable',
    () async {
      await cubit.load(nym: '');

      expect(cubit.state.nym, isEmpty);
      expect(cubit.state.page, isNull);
      expect(
        cubit.state.error,
        'Create a Lightning Address before creating a payment page',
      );
      verifyNever(
        () => paymentPageService.getPaymentPage(nym: any(named: 'nym')),
      );
    },
  );

  test('load populates an existing active payment page', () async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());

    await cubit.load(nym: 'alice');

    expect(cubit.state.nym, 'alice');
    expect(cubit.state.header, "Alice's Coffee");
    expect(cubit.state.description, 'Tips welcome');
    expect(cubit.state.displayCurrency, 'CAD');
    expect(cubit.state.hasExistingPage, isTrue);
  });

  test('load treats missing payment page as a clean create form', () async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenThrow(const PaymentPageNotFoundError('missing'));

    await cubit.load(nym: 'alice');

    expect(cubit.state.nym, 'alice');
    expect(cubit.state.page, isNull);
    expect(cubit.state.error, isNull);
    expect(cubit.state.isLoading, isFalse);
  });

  test(
    'save trims optional fields and delegates through identity port',
    () async {
      when(
        () => paymentPageService.savePaymentPage(
          command: any(named: 'command'),
          handle: handle,
        ),
      ).thenAnswer((_) async => _page(website: 'https://alice.example'));

      await cubit.load(nym: 'alice');
      cubit
        ..setHeader(" Alice's Coffee ")
        ..setDescription(' Tips welcome ')
        ..setWebsite(' https://alice.example ')
        ..setTwitter(' ')
        ..setInstagram('')
        ..setEnabled(true);

      await cubit.save();

      final captured =
          verify(
                () => paymentPageService.savePaymentPage(
                  command: captureAny(named: 'command'),
                  handle: handle,
                ),
              ).captured.single
              as SavePaymentPageCommand;
      expect(captured.nym, 'alice');
      expect(captured.header, "Alice's Coffee");
      expect(captured.description, 'Tips welcome');
      expect(captured.website, 'https://alice.example');
      expect(captured.twitter, isNull);
      expect(captured.instagram, isNull);
      expect(cubit.state.saved, isTrue);
      verify(() => paymentPageIdentity.getSigningHandle()).called(1);
    },
  );

  test('save surfaces validation errors without calling service', () async {
    await cubit.load(nym: 'alice');
    cubit
      ..setHeader('')
      ..setDescription('Tips welcome');

    await cubit.save();

    expect(cubit.state.error, isNotNull);
    expect(cubit.state.isSaving, isFalse);
    verifyNever(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
      ),
    );
  });

  test('archive archives only the payment page', () async {
    when(
      () => paymentPageService.archivePaymentPage(
        command: any(named: 'command'),
        handle: handle,
      ),
    ).thenAnswer((_) async => _page(isArchived: true));

    await cubit.load(nym: 'alice');
    await cubit.archive();

    final captured =
        verify(
              () => paymentPageService.archivePaymentPage(
                command: captureAny(named: 'command'),
                handle: handle,
              ),
            ).captured.single
            as ArchivePaymentPageCommand;
    expect(captured.nym, 'alice');
    expect(cubit.state.archived, isTrue);
    expect(cubit.state.page, isNull);
    verify(() => paymentPageIdentity.getSigningHandle()).called(1);
  });
}

PaymentPage _page({bool isArchived = false, String? website}) {
  return PaymentPage(
    nym: 'alice',
    header: "Alice's Coffee",
    description: 'Tips welcome',
    displayCurrency: 'CAD',
    website: website,
    twitter: null,
    instagram: null,
    enabled: true,
    isArchived: isArchived,
    avatarSha256: null,
    ogSha256: null,
    publicUrl: 'https://bullpay.ca/alice',
  );
}

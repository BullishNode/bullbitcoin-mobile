import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/upload_payment_page_image_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/payment_page_constants.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_error_message.dart';
import 'package:bb_mobile/features/get_paid/shared/register_get_paid_nym_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPaymentPageService extends Mock implements PaymentPageServicePort {}

class _MockPaymentPageIdentity extends Mock
    implements PaymentPageIdentityPort {}

class _MockGetSettings extends Mock implements GetSettingsUsecase {}

class _MockExternalReceiveWallets extends Mock
    implements ExternalReceiveWalletsFacade {}

class _MockRegisterGetPaidNym extends Mock
    implements RegisterGetPaidNymUsecase {}

void main() {
  late _MockPaymentPageService paymentPageService;
  late _MockPaymentPageIdentity paymentPageIdentity;
  late _MockGetSettings getSettings;
  late _MockExternalReceiveWallets externalReceiveWallets;
  late _MockRegisterGetPaidNym registerNym;
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
    getSettings = _MockGetSettings();
    externalReceiveWallets = _MockExternalReceiveWallets();
    registerNym = _MockRegisterGetPaidNym();
    handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);
    final paymentPageKey = ExternalReceiveWalletPurpose.paymentPage
        .liquidAccountKey(isTestnet: false);

    when(
      () => paymentPageIdentity.getSigningHandle(),
    ).thenAnswer((_) async => handle);
    when(
      () => paymentPageService.getPaymentPage(nym: any(named: 'nym')),
    ).thenThrow(const PaymentPageNotFoundError('missing'));
    when(() => getSettings.execute()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
      ),
    );
    when(
      () => externalReceiveWallets.get(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
        accountKey: paymentPageKey,
      ),
    ).thenAnswer((_) async => _wallet('payment-page-wallet'));

    cubit = PaymentPageCubit(
      findPaymentPage: FindPaymentPageUsecase(
        paymentPageService: paymentPageService,
      ),
      savePaymentPage: SavePaymentPageUsecase(
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
        getSettings: getSettings,
        externalReceiveWallets: externalReceiveWallets,
      ),
      archivePaymentPage: ArchivePaymentPageUsecase(
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
      uploadImage: UploadPaymentPageImageUsecase(
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
      registerNym: registerNym,
    );
  });

  tearDown(() => cubit.close());

  test('load blocks creation when Bullnym name is unavailable', () async {
    await cubit.load(nym: '');

    expect(cubit.state.nym, isEmpty);
    expect(cubit.state.page, isNull);
    expect(cubit.state.error, isNull);
    verifyNever(
      () => paymentPageService.getPaymentPage(nym: any(named: 'nym')),
    );
  });

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
    expect(cubit.state.loadFailed, isFalse);
  });

  test('load maps generic exceptions to friendly copy', () async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenThrow(Exception('socket details'));

    await cubit.load(nym: 'alice');

    expect(cubit.state.error, 'Something went wrong. Please try again.');
    expect(cubit.state.error, isNot(contains('socket details')));
    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.loadFailed, isTrue);
  });

  test('save is blocked after load failure', () async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenThrow(Exception('socket details'));

    await cubit.load(nym: 'alice');
    cubit
      ..setHeader("Alice's Coffee")
      ..setDescription('Tips welcome');

    await cubit.save();

    expect(cubit.state.loadFailed, isTrue);
    verifyNever(() => paymentPageIdentity.getSigningHandle());
    verifyNever(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    );
  });

  test('page mutations are blocked after load failure', () async {
    const pngHeader = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());

    await cubit.load(nym: 'alice');

    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenThrow(Exception('socket details'));

    await cubit.load(nym: 'alice');
    await cubit.archive();
    await cubit.uploadImage(pngHeader);

    expect(cubit.state.loadFailed, isTrue);
    verifyNever(() => paymentPageIdentity.getSigningHandle());
    verifyNever(
      () => paymentPageService.archivePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
      ),
    );
    verifyNever(
      () => paymentPageService.uploadImage(
        nym: any(named: 'nym'),
        bytes: any(named: 'bytes'),
        handle: any(named: 'handle'),
      ),
    );
  });

  test('payment page error mapper hides raw reasons', () {
    expect(
      paymentPageErrorMessage(const PaymentPageValidationError('raw invalid')),
      'Check the payment page details and try again.',
    );
    expect(
      paymentPageErrorMessage(
        const PaymentPageValidationError('must be between 1 and 80 bytes'),
      ),
      'Add a title.',
    );
    expect(
      paymentPageErrorMessage(
        const PaymentPageValidationError('must be between 1 and 280 bytes'),
      ),
      'Add a description.',
    );
    expect(
      paymentPageErrorMessage(
        const PaymentPageValidationError(
          'must start with https:// and be at most 200 bytes',
        ),
      ),
      'Website must start with https://.',
    );
    expect(
      paymentPageErrorMessage(const PaymentPageNotFoundError('raw missing')),
      'Payment page not found.',
    );
    expect(
      paymentPageErrorMessage(
        const PaymentPageAuthorizationError('bad signature'),
      ),
      'Payment page authorization failed.',
    );
    expect(
      paymentPageErrorMessage(const PaymentPageNetworkError('raw network')),
      'Network error. Check your connection.',
    );
    expect(
      paymentPageErrorMessage(
        const PaymentPageValidationError(
          'Image dimensions are too large. Maximum 1200x1200.',
        ),
      ),
      'Choose a JPEG, PNG, or WebP image under 2 MB.',
    );
    expect(
      paymentPageErrorMessage(
        const PaymentPageIdentityUnavailableError('raw identity'),
      ),
      'Set up a Liquid wallet before editing your payment page.',
    );
    expect(
      paymentPageErrorMessage(const PaymentPageUnexpectedError('raw surprise')),
      'Something went wrong. Please try again.',
    );
  });

  test(
    'save trims optional fields and delegates through identity port',
    () async {
      when(
        () => paymentPageService.savePaymentPage(
          command: any(named: 'command'),
          handle: handle,
          ctDescriptor: any(named: 'ctDescriptor'),
        ),
      ).thenAnswer((_) async => _page(website: 'https://alice.example'));

      await cubit.load(nym: 'alice');
      cubit
        ..setHeader(" Alice's Coffee ")
        ..setDescription(' Tips welcome ')
        ..setWebsite(' https://alice.example ')
        ..setTwitter(' ')
        ..setInstagram('');

      await cubit.save();

      final captured =
          verify(
                () => paymentPageService.savePaymentPage(
                  command: captureAny(named: 'command'),
                  handle: handle,
                  ctDescriptor: any(named: 'ctDescriptor'),
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

    expect(cubit.state.error, 'Add a title.');
    expect(cubit.state.isSaving, isFalse);
    verifyNever(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    );
  });

  test('save does not leak raw application error message', () async {
    when(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: handle,
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    ).thenThrow(const PaymentPageAuthorizationError('bad signature'));

    await cubit.load(nym: 'alice');
    cubit
      ..setHeader("Alice's Coffee")
      ..setDescription('Tips welcome');

    await cubit.save();

    expect(cubit.state.error, isNot(contains('bad signature')));
    expect(cubit.state.error, 'Payment page authorization failed.');
  });

  test('save maps generic exceptions to friendly copy', () async {
    when(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: handle,
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    ).thenThrow(Exception('connection refused'));

    await cubit.load(nym: 'alice');
    cubit
      ..setHeader("Alice's Coffee")
      ..setDescription('Tips welcome');

    await cubit.save();

    expect(cubit.state.error, 'Something went wrong. Please try again.');
    expect(cubit.state.error, isNot(contains('connection refused')));
    expect(cubit.state.isSaving, isFalse);
  });

  test(
    'save maps missing payment page wallet prerequisite to setup copy',
    () async {
      final paymentPageKey = ExternalReceiveWalletPurpose.paymentPage
          .liquidAccountKey(isTestnet: false);
      when(
        () => externalReceiveWallets.get(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: paymentPageKey,
        ),
      ).thenThrow(ExternalReceiveWalletNoDefaultWalletException());

      await cubit.load(nym: 'alice');
      cubit
        ..setHeader("Alice's Coffee")
        ..setDescription('Tips welcome');

      await cubit.save();

      expect(
        cubit.state.error,
        'Set up a Liquid wallet before editing your payment page.',
      );
      expect(cubit.state.isSaving, isFalse);
      verifyNever(
        () => paymentPageService.savePaymentPage(
          command: any(named: 'command'),
          handle: any(named: 'handle'),
          ctDescriptor: any(named: 'ctDescriptor'),
        ),
      );
    },
  );

  test('save validates selected image before creating page', () async {
    await cubit.load(nym: 'alice');
    cubit
      ..setHeader("Alice's Coffee")
      ..setDescription('Tips welcome');

    await cubit.save(imageBytes: [1, 2, 3]);

    expect(cubit.state.error, 'Choose a JPEG, PNG, or WebP image under 2 MB.');
    expect(cubit.state.isSaving, isFalse);
    verifyNever(() => paymentPageIdentity.getSigningHandle());
    verifyNever(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    );
  });

  test(
    'valid image selection clears previous image validation error',
    () async {
      await cubit.load(nym: 'alice');

      expect(cubit.validateImageBytes([1, 2, 3]), isFalse);
      expect(
        cubit.state.error,
        'Choose a JPEG, PNG, or WebP image under 2 MB.',
      );

      const pngHeader = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
      expect(cubit.validateImageBytes(pngHeader), isTrue);
      expect(cubit.state.error, isNull);
    },
  );

  test('save uploads selected image after page creation', () async {
    const pngHeader = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    when(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: handle,
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    ).thenAnswer((_) async => _page());
    when(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: pngHeader,
        handle: handle,
      ),
    ).thenAnswer((_) async => _page(ogSha256: 'aa' * 32));

    await cubit.load(nym: 'alice');
    cubit
      ..setHeader("Alice's Coffee")
      ..setDescription('Tips welcome');

    await cubit.save(imageBytes: pngHeader);

    expect(cubit.state.saved, isTrue);
    expect(cubit.state.page?.ogSha256, 'aa' * 32);
    verify(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: handle,
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    ).called(1);
    verify(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: pngHeader,
        handle: handle,
      ),
    ).called(1);
    verify(() => paymentPageIdentity.getSigningHandle()).called(2);
  });

  test('publish saves an unpublished page as enabled', () async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page(enabled: false));
    when(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: handle,
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    ).thenAnswer((_) async => _page(enabled: true));

    await cubit.load(nym: 'alice');
    expect(cubit.state.enabled, isFalse);

    await cubit.publish();

    final command =
        verify(
              () => paymentPageService.savePaymentPage(
                command: captureAny(named: 'command'),
                handle: handle,
                ctDescriptor: any(named: 'ctDescriptor'),
              ),
            ).captured.single
            as SavePaymentPageCommand;
    expect(command.enabled, isTrue);
    expect(cubit.state.enabled, isTrue);
    expect(cubit.state.saved, isTrue);
  });

  test('save keeps created page when selected image upload fails', () async {
    const pngHeader = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    when(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: handle,
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    ).thenAnswer((_) async => _page());
    when(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: pngHeader,
        handle: handle,
      ),
    ).thenThrow(
      const PaymentPageValidationError('Image dimensions are too large.'),
    );

    await cubit.load(nym: 'alice');
    cubit
      ..setHeader("Alice's Coffee")
      ..setDescription('Tips welcome');

    await cubit.save(imageBytes: pngHeader);

    expect(cubit.state.hasExistingPage, isTrue);
    expect(cubit.state.saved, isFalse);
    expect(cubit.state.error, 'Choose a JPEG, PNG, or WebP image under 2 MB.');
    verify(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: handle,
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    ).called(1);
    verify(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: pngHeader,
        handle: handle,
      ),
    ).called(1);
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

  test('archive maps generic exceptions to friendly copy', () async {
    when(
      () => paymentPageService.archivePaymentPage(
        command: any(named: 'command'),
        handle: handle,
      ),
    ).thenThrow(Exception('disk full'));

    await cubit.load(nym: 'alice');
    await cubit.archive();

    expect(cubit.state.error, 'Something went wrong. Please try again.');
    expect(cubit.state.error, isNot(contains('disk full')));
    expect(cubit.state.isArchiving, isFalse);
  });

  test('upload image validates file bytes before signing', () async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());
    await cubit.load(nym: 'alice');

    await cubit.uploadImage([1, 2, 3]);

    expect(cubit.state.error, 'Choose a JPEG, PNG, or WebP image under 2 MB.');
    verifyNever(() => paymentPageIdentity.getSigningHandle());
    verifyNever(
      () => paymentPageService.uploadImage(
        nym: any(named: 'nym'),
        bytes: any(named: 'bytes'),
        handle: any(named: 'handle'),
      ),
    );
  });

  test('upload image rejects oversized files before signing', () async {
    final bytes = <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      ...List<int>.filled(paymentPageImageMaxBytes - 7, 0),
    ];
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());
    await cubit.load(nym: 'alice');

    await cubit.uploadImage(bytes);

    expect(cubit.state.error, 'Choose a JPEG, PNG, or WebP image under 2 MB.');
    verifyNever(() => paymentPageIdentity.getSigningHandle());
    verifyNever(
      () => paymentPageService.uploadImage(
        nym: any(named: 'nym'),
        bytes: any(named: 'bytes'),
        handle: any(named: 'handle'),
      ),
    );
  });

  test('upload image delegates through identity port', () async {
    const pngHeader = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());
    when(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: pngHeader,
        handle: handle,
      ),
    ).thenAnswer((_) async => _page(ogSha256: 'aa' * 32));

    await cubit.load(nym: 'alice');
    await cubit.uploadImage(pngHeader);

    expect(cubit.state.isUploadingImage, isFalse);
    expect(cubit.state.page?.ogSha256, 'aa' * 32);
    verify(() => paymentPageIdentity.getSigningHandle()).called(1);
    verify(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: pngHeader,
        handle: handle,
      ),
    ).called(1);
  });
}

Wallet _wallet(String id) {
  return Wallet(
    origin: id,
    label: id,
    network: Network.liquidMainnet,
    isDefault: false,
    masterFingerprint: 'aabbccdd',
    xpubFingerprint: 'aabbccdd',
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: 'ct(slip77(...),elwpkh(xpub/0/*))',
    internalPublicDescriptor: 'ct(slip77(...),elwpkh(xpub/1/*))',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}

PaymentPage _page({
  bool isArchived = false,
  bool enabled = true,
  String? website,
  String? avatarSha256,
  String? ogSha256,
}) {
  return PaymentPage(
    nym: 'alice',
    header: "Alice's Coffee",
    description: 'Tips welcome',
    displayCurrency: 'CAD',
    website: website,
    twitter: null,
    instagram: null,
    enabled: enabled,
    isArchived: isArchived,
    avatarSha256: avatarSha256,
    ogSha256: ogSha256,
    publicUrl: 'https://bullpay.ca/alice',
  );
}

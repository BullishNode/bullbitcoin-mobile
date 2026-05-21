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
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/get_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPaymentPageService extends Mock implements PaymentPageServicePort {}

class _MockPaymentPageIdentity extends Mock
    implements PaymentPageIdentityPort {}

class _MockGetSettings extends Mock implements GetSettingsUsecase {}

class _MockExternalReceiveWallets extends Mock
    implements ExternalReceiveWalletsFacade {}

void main() {
  late _MockPaymentPageService paymentPageService;
  late _MockPaymentPageIdentity paymentPageIdentity;
  late _MockGetSettings getSettings;
  late _MockExternalReceiveWallets externalReceiveWallets;
  late NostrKeychainHandle handle;

  setUp(() {
    paymentPageService = _MockPaymentPageService();
    paymentPageIdentity = _MockPaymentPageIdentity();
    getSettings = _MockGetSettings();
    externalReceiveWallets = _MockExternalReceiveWallets();
    handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);
    when(
      () => paymentPageIdentity.getSigningHandle(),
    ).thenAnswer((_) async => handle);
  });

  SavePaymentPageUsecase saveUsecase() {
    return SavePaymentPageUsecase(
      paymentPageService: paymentPageService,
      paymentPageIdentity: paymentPageIdentity,
      getSettings: getSettings,
      externalReceiveWallets: externalReceiveWallets,
    );
  }

  void stubSettings({Environment environment = Environment.mainnet}) {
    when(() => getSettings.execute()).thenAnswer(
      (_) async => SettingsEntity(
        environment: environment,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
      ),
    );
  }

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

  test('save payment page usecase provisions wallet before saving', () async {
    final command = SavePaymentPageCommand(
      nym: 'alice',
      header: "Alice's Coffee",
      description: 'Tips welcome',
      displayCurrency: 'CAD',
      enabled: true,
    );
    final key = ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
      isTestnet: false,
    );
    final calls = <String>[];
    stubSettings();
    when(
      () => externalReceiveWallets.get(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
        accountKey: key,
      ),
    ).thenAnswer((_) async {
      calls.add('get-wallet');
      return null;
    });
    when(
      () => externalReceiveWallets.create(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
        accountKey: key,
      ),
    ).thenAnswer((_) async {
      calls.add('create-wallet');
      return _wallet('payment-page-wallet');
    });
    when(
      () => paymentPageService.savePaymentPage(
        command: command,
        handle: handle,
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    ).thenAnswer((_) async {
      calls.add('save-page');
      return _page();
    });

    final page = await saveUsecase().execute(command: command);

    expect(page.isActive, isTrue);
    expect(calls, ['get-wallet', 'create-wallet', 'save-page']);
    verify(() => getSettings.execute()).called(1);
    verify(
      () => externalReceiveWallets.get(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
        accountKey: key,
      ),
    ).called(1);
    verify(
      () => externalReceiveWallets.create(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
        accountKey: key,
      ),
    ).called(1);
    verify(() => paymentPageIdentity.getSigningHandle()).called(1);
    verify(
      () => paymentPageService.savePaymentPage(
        command: command,
        handle: handle,
        ctDescriptor: any(named: 'ctDescriptor'),
      ),
    ).called(1);
  });

  test(
    'save payment page usecase delegates disabled page without wallet provisioning',
    () async {
      final command = SavePaymentPageCommand(
        nym: 'alice',
        header: "Alice's Coffee",
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        enabled: false,
      );
      when(
        () => paymentPageService.savePaymentPage(
          command: command,
          handle: handle,
          ctDescriptor: any(named: 'ctDescriptor'),
        ),
      ).thenAnswer((_) async => _page(enabled: false));

      final page = await saveUsecase().execute(command: command);

      expect(page.enabled, isFalse);
      verifyNever(() => getSettings.execute());
      verify(() => paymentPageIdentity.getSigningHandle()).called(1);
      verify(
        () => paymentPageService.savePaymentPage(
          command: command,
          handle: handle,
          ctDescriptor: any(named: 'ctDescriptor'),
        ),
      ).called(1);
    },
  );

  test(
    'save payment page usecase reuses existing payment page wallet',
    () async {
      final command = SavePaymentPageCommand(
        nym: 'alice',
        header: "Alice's Coffee",
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        enabled: true,
      );
      final key = ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
        isTestnet: false,
      );
      stubSettings();
      when(
        () => externalReceiveWallets.get(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      ).thenAnswer((_) async => _wallet('existing-payment-page-wallet'));
      when(
        () => paymentPageService.savePaymentPage(
          command: command,
          handle: handle,
          ctDescriptor: any(named: 'ctDescriptor'),
        ),
      ).thenAnswer((_) async => _page());

      final page = await saveUsecase().execute(command: command);

      expect(page.isActive, isTrue);
      verify(
        () => externalReceiveWallets.get(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      ).called(1);
      verifyNever(
        () => externalReceiveWallets.create(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      );
      verify(
        () => paymentPageService.savePaymentPage(
          command: command,
          handle: handle,
          ctDescriptor: any(named: 'ctDescriptor'),
        ),
      ).called(1);
    },
  );

  test(
    'save payment page usecase uses testnet payment page wallet key',
    () async {
      final command = SavePaymentPageCommand(
        nym: 'alice',
        header: "Alice's Coffee",
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        enabled: true,
      );
      final key = ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
        isTestnet: true,
      );
      stubSettings(environment: Environment.testnet);
      when(
        () => externalReceiveWallets.get(
          environment: Environment.testnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      ).thenAnswer((_) async => null);
      when(
        () => externalReceiveWallets.create(
          environment: Environment.testnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      ).thenAnswer((_) async => _wallet('payment-page-wallet'));
      when(
        () => paymentPageService.savePaymentPage(
          command: command,
          handle: handle,
          ctDescriptor: any(named: 'ctDescriptor'),
        ),
      ).thenAnswer((_) async => _page());

      await saveUsecase().execute(command: command);

      verify(
        () => externalReceiveWallets.create(
          environment: Environment.testnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      ).called(1);
    },
  );

  test(
    'save payment page maps missing default wallet before remote save',
    () async {
      final command = SavePaymentPageCommand(
        nym: 'alice',
        header: "Alice's Coffee",
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        enabled: true,
      );
      final key = ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
        isTestnet: false,
      );
      stubSettings();
      when(
        () => externalReceiveWallets.get(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      ).thenAnswer((_) async => null);
      when(
        () => externalReceiveWallets.create(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      ).thenThrow(ExternalReceiveWalletNoDefaultWalletException());

      await expectLater(
        saveUsecase().execute(command: command),
        throwsA(isA<PaymentPageIdentityUnavailableError>()),
      );

      verifyNever(() => paymentPageIdentity.getSigningHandle());
      verifyNever(
        () => paymentPageService.savePaymentPage(
          command: command,
          handle: handle,
          ctDescriptor: any(named: 'ctDescriptor'),
        ),
      );
    },
  );

  test(
    'save payment page maps missing default wallet during wallet lookup',
    () async {
      final command = SavePaymentPageCommand(
        nym: 'alice',
        header: "Alice's Coffee",
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        enabled: true,
      );
      final key = ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
        isTestnet: false,
      );
      stubSettings();
      when(
        () => externalReceiveWallets.get(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      ).thenThrow(ExternalReceiveWalletNoDefaultWalletException());

      await expectLater(
        saveUsecase().execute(command: command),
        throwsA(isA<PaymentPageIdentityUnavailableError>()),
      );

      verifyNever(
        () => externalReceiveWallets.create(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: key,
        ),
      );
      verifyNever(() => paymentPageIdentity.getSigningHandle());
      verifyNever(
        () => paymentPageService.savePaymentPage(
          command: command,
          handle: handle,
          ctDescriptor: any(named: 'ctDescriptor'),
        ),
      );
    },
  );

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
        nym: 'Alice',
        header: 'Alice',
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        enabled: true,
      ),
      throwsA(isA<PaymentPageValidationError>()),
    );
    expect(
      () => SavePaymentPageCommand(
        nym: 'alice',
        header: '😀' * 21,
        description: 'Tips welcome',
        displayCurrency: 'CAD',
        enabled: true,
      ),
      throwsA(isA<PaymentPageValidationError>()),
    );
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

PaymentPage _page({bool enabled = true, bool isArchived = false}) {
  return PaymentPage(
    nym: 'alice',
    header: "Alice's Coffee",
    description: 'Tips welcome',
    displayCurrency: 'CAD',
    website: null,
    twitter: null,
    instagram: null,
    enabled: enabled,
    isArchived: isArchived,
    avatarSha256: null,
    ogSha256: null,
    publicUrl: 'https://bullpay.ca/alice',
  );
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

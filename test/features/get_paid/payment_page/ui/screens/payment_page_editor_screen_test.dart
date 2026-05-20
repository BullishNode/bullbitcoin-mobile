import 'dart:async';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/widgets/inputs/utf8_byte_limit_formatter.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/upload_payment_page_image_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/payment_page_constants.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/get_paid/payment_page/ui/screens/payment_page_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
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
    registerFallbackValue(NostrKeychainHandle.fromSecretKeyHex('02' * 32));
  });

  setUp(() {
    paymentPageService = _MockPaymentPageService();
    paymentPageIdentity = _MockPaymentPageIdentity();

    when(
      () => paymentPageService.getPaymentPage(nym: any(named: 'nym')),
    ).thenThrow(const PaymentPageNotFoundError('missing'));
    when(
      () => paymentPageIdentity.getSigningHandle(),
    ).thenAnswer((_) async => NostrKeychainHandle.fromSecretKeyHex('01' * 32));
  });

  testWidgets('shows Bullnym name requirement when nym is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        nym: '',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.pump();

    expect(
      find.text('Choose a Bullnym name before creating a payment page'),
      findsOneWidget,
    );
    verifyNever(
      () => paymentPageService.getPaymentPage(nym: any(named: 'nym')),
    );
  });

  testWidgets('renders editable text fields for an existing payment page', (
    tester,
  ) async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());

    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.pump();

    expect(find.text('Edit alice'), findsOneWidget);
    expect(find.text('Store URL'), findsOneWidget);
    expect(find.text('https://bullpay.ca/alice'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Page title'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Website'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Twitter'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Instagram'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();

    expect(find.text('Deactivate'), findsOneWidget);
  });

  testWidgets('shows clickable store URL with copy action', (tester) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = call.arguments as Map<dynamic, dynamic>;
            clipboardText = data['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());

    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.pump();

    expect(find.text('Store URL'), findsOneWidget);
    expect(find.text('https://bullpay.ca/alice'), findsOneWidget);
    expect(find.byTooltip('Copy store URL'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy store URL'));

    expect(clipboardText, 'https://bullpay.ca/alice');
  });

  testWidgets('keeps creation flow focused before page exists', (tester) async {
    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.pump();

    expect(find.text('Create alice'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Page title'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
    expect(find.text('OG image'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Display currency'), findsNothing);
    expect(find.text('Published'), findsNothing);
    expect(find.text('Deactivate'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Website'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Twitter'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Instagram'), findsOneWidget);
  });

  testWidgets('blocks editor form when existing page load fails', (
    tester,
  ) async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenThrow(Exception('network down'));

    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.pump();

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Page title'), findsNothing);
    expect(find.text('Create'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    verify(() => paymentPageService.getPaymentPage(nym: 'alice')).called(2);
  });

  testWidgets('shows publish action for an unpublished existing page', (
    tester,
  ) async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page(enabled: false));
    when(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
      ),
    ).thenAnswer((_) async => _page(enabled: true));

    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();

    expect(find.text('Publish'), findsOneWidget);
    expect(find.text('Deactivate'), findsNothing);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    final command =
        verify(
              () => paymentPageService.savePaymentPage(
                command: captureAny(named: 'command'),
                handle: any(named: 'handle'),
              ),
            ).captured.single
            as SavePaymentPageCommand;
    expect(command.enabled, isTrue);
  });

  testWidgets('rejects invalid OG images before save or upload', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
        pickImageBytes: () async => const [1, 2, 3],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('OG image'));
    await tester.pump();

    expect(
      find.text('Choose a JPEG, PNG, or WebP image under 2 MB.'),
      findsOneWidget,
    );
    verifyNever(() => paymentPageIdentity.getSigningHandle());
    verifyNever(
      () => paymentPageService.savePaymentPage(
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

  testWidgets('uses UTF-8 byte limits for server-limited fields', (
    tester,
  ) async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());

    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.pump();

    final title = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Page title'),
    );
    expect(title.maxLength, paymentPageHeaderMaxBytes);
    expect(title.buildCounter, isNotNull);
    expect(title.inputFormatters, contains(isA<Utf8ByteLimitFormatter>()));

    final description = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Description'),
    );
    expect(description.maxLength, paymentPageDescriptionMaxBytes);
    expect(description.buildCounter, isNotNull);
    expect(
      description.inputFormatters,
      contains(isA<Utf8ByteLimitFormatter>()),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();

    final website = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Website'),
    );
    expect(website.maxLength, paymentPageWebsiteMaxBytes);
    expect(website.buildCounter, isNotNull);
    expect(website.inputFormatters, contains(isA<Utf8ByteLimitFormatter>()));

    final twitter = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Twitter'),
    );
    expect(twitter.maxLength, paymentPageSocialHandleMaxChars);

    final instagram = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Instagram'),
    );
    expect(instagram.maxLength, paymentPageSocialHandleMaxChars);
  });

  testWidgets('uploads image from the editor for an existing payment page', (
    tester,
  ) async {
    const bytes = _validPngBytes;
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());
    when(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: bytes,
        handle: any(named: 'handle'),
      ),
    ).thenAnswer((_) async => _page(ogSha256: 'aa' * 32));

    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
        pickImageBytes: () async => bytes,
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pump();
    await tester.tap(find.text('OG image'));
    await tester.pumpAndSettle();

    verify(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: bytes,
        handle: any(named: 'handle'),
      ),
    ).called(1);
  });

  testWidgets('creates page then uploads selected image', (tester) async {
    const bytes = _validPngBytes;
    when(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
      ),
    ).thenAnswer((_) async => _page());
    when(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: bytes,
        handle: any(named: 'handle'),
      ),
    ).thenAnswer((_) async => _page(ogSha256: 'aa' * 32));

    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
        pickImageBytes: () async => bytes,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'Page title'),
      "Alice's Coffee",
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Tips welcome',
    );
    await tester.tap(find.text('OG image'));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    verify(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
      ),
    ).called(1);
    verify(
      () => paymentPageService.uploadImage(
        nym: 'alice',
        bytes: bytes,
        handle: any(named: 'handle'),
      ),
    ).called(1);
  });

  testWidgets('renders existing image from the payment page origin', (
    tester,
  ) async {
    when(() => paymentPageService.getPaymentPage(nym: 'alice')).thenAnswer(
      (_) async =>
          _page(ogSha256: 'aa' * 32, publicUrl: 'https://pay.example/alice'),
    );

    await tester.pumpWidget(
      _harness(
        nym: 'alice',
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as NetworkImage).url,
      'https://pay.example/img/alice/og.jpg?v=${'aa' * 32}',
    );
  });

  test('UTF-8 byte formatter rejects over-limit multibyte edits', () {
    final formatter = Utf8ByteLimitFormatter(paymentPageHeaderMaxBytes);
    const oldValue = TextEditingValue(text: 'Alice');

    expect(
      formatter
          .formatEditUpdate(oldValue, TextEditingValue(text: '😀' * 20))
          .text,
      '😀' * 20,
    );
    expect(
      formatter.formatEditUpdate(oldValue, TextEditingValue(text: '😀' * 21)),
      oldValue,
    );
  });

  testWidgets('pops true after successful save', (tester) async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());
    when(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
      ),
    ).thenAnswer((_) async => _page());

    await tester.pumpWidget(
      _routeHarness(
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('changed: true'), findsOneWidget);
  });

  testWidgets('confirms before discarding unsaved edits', (tester) async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());

    await tester.pumpWidget(
      _routeHarness(
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Page title'),
      "Alice's Updated Coffee",
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(find.text('Edit alice'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('changed: false'), findsOneWidget);
  });

  testWidgets('failed reload back action ignores hidden stale edits', (
    tester,
  ) async {
    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenAnswer((_) async => _page());

    await tester.pumpWidget(
      _routeHarness(
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Page title'),
      "Alice's Updated Coffee",
    );
    await tester.pump();

    when(
      () => paymentPageService.getPaymentPage(nym: 'alice'),
    ).thenThrow(Exception('network down'));

    final editorContext = tester.element(find.byType(PaymentPageEditorScreen));
    await editorContext.read<PaymentPageCubit>().load(nym: 'alice');
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('blocks back navigation while save is in flight', (tester) async {
    final saveCompleter = Completer<PaymentPage>();
    when(
      () => paymentPageService.savePaymentPage(
        command: any(named: 'command'),
        handle: any(named: 'handle'),
      ),
    ).thenAnswer((_) => saveCompleter.future);

    await tester.pumpWidget(
      _routeHarness(
        paymentPageService: paymentPageService,
        paymentPageIdentity: paymentPageIdentity,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Page title'),
      "Alice's Coffee",
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Tips welcome',
    );
    for (var i = 0; i < 6 && find.text('Create').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();

    expect(find.text('Payment Page update in progress.'), findsOneWidget);
    expect(find.text('Payment Page'), findsOneWidget);

    saveCompleter.complete(_page());
    await tester.pumpAndSettle();
  });
}

const _validPngBytes = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0a,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];

Widget _harness({
  required String nym,
  required PaymentPageServicePort paymentPageService,
  required PaymentPageIdentityPort paymentPageIdentity,
  Future<List<int>?> Function()? pickImageBytes,
}) {
  return MaterialApp(
    home: BlocProvider(
      create: (_) => PaymentPageCubit(
        findPaymentPage: FindPaymentPageUsecase(
          paymentPageService: paymentPageService,
        ),
        savePaymentPage: SavePaymentPageUsecase(
          paymentPageService: paymentPageService,
          paymentPageIdentity: paymentPageIdentity,
          getSettings: _paymentPageWalletSettings(),
          externalReceiveWallets: _existingPaymentPageWallets(),
        ),
        archivePaymentPage: ArchivePaymentPageUsecase(
          paymentPageService: paymentPageService,
          paymentPageIdentity: paymentPageIdentity,
        ),
        uploadImage: UploadPaymentPageImageUsecase(
          paymentPageService: paymentPageService,
          paymentPageIdentity: paymentPageIdentity,
        ),
      ),
      child: PaymentPageEditorScreen(nym: nym, pickImageBytes: pickImageBytes),
    ),
  );
}

Widget _routeHarness({
  required PaymentPageServicePort paymentPageService,
  required PaymentPageIdentityPort paymentPageIdentity,
}) {
  return MaterialApp(
    home: _RouteHarness(
      paymentPageService: paymentPageService,
      paymentPageIdentity: paymentPageIdentity,
    ),
  );
}

class _RouteHarness extends StatefulWidget {
  final PaymentPageServicePort paymentPageService;
  final PaymentPageIdentityPort paymentPageIdentity;

  const _RouteHarness({
    required this.paymentPageService,
    required this.paymentPageIdentity,
  });

  @override
  State<_RouteHarness> createState() => _RouteHarnessState();
}

class _RouteHarnessState extends State<_RouteHarness> {
  bool? changed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('changed: $changed'),
          TextButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => BlocProvider(
                    create: (_) => PaymentPageCubit(
                      findPaymentPage: FindPaymentPageUsecase(
                        paymentPageService: widget.paymentPageService,
                      ),
                      savePaymentPage: SavePaymentPageUsecase(
                        paymentPageService: widget.paymentPageService,
                        paymentPageIdentity: widget.paymentPageIdentity,
                        getSettings: _paymentPageWalletSettings(),
                        externalReceiveWallets: _existingPaymentPageWallets(),
                      ),
                      archivePaymentPage: ArchivePaymentPageUsecase(
                        paymentPageService: widget.paymentPageService,
                        paymentPageIdentity: widget.paymentPageIdentity,
                      ),
                      uploadImage: UploadPaymentPageImageUsecase(
                        paymentPageService: widget.paymentPageService,
                        paymentPageIdentity: widget.paymentPageIdentity,
                      ),
                    ),
                    child: const PaymentPageEditorScreen(nym: 'alice'),
                  ),
                ),
              );
              setState(() => changed = result);
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

GetSettingsUsecase _paymentPageWalletSettings() {
  final getSettings = _MockGetSettings();
  when(() => getSettings.execute()).thenAnswer(
    (_) async => const SettingsEntity(
      environment: Environment.mainnet,
      bitcoinUnit: BitcoinUnit.sats,
      currencyCode: 'CAD',
    ),
  );
  return getSettings;
}

ExternalReceiveWalletsFacade _existingPaymentPageWallets() {
  final externalReceiveWallets = _MockExternalReceiveWallets();
  final paymentPageKey = ExternalReceiveWalletPurpose.paymentPage
      .liquidAccountKey(isTestnet: false);
  when(
    () => externalReceiveWallets.get(
      environment: Environment.mainnet,
      purpose: ExternalReceiveWalletPurpose.paymentPage,
      accountKey: paymentPageKey,
    ),
  ).thenAnswer((_) async => _wallet('payment-page-wallet'));
  return externalReceiveWallets;
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
  bool enabled = true,
  String? avatarSha256,
  String? ogSha256,
  String publicUrl = 'https://bullpay.ca/alice',
}) {
  return PaymentPage(
    nym: 'alice',
    header: "Alice's Coffee",
    description: 'Tips welcome',
    displayCurrency: 'CAD',
    website: 'https://alice.example',
    twitter: 'alice',
    instagram: null,
    enabled: enabled,
    isArchived: false,
    avatarSha256: avatarSha256,
    ogSha256: ogSha256,
    publicUrl: publicUrl,
  );
}

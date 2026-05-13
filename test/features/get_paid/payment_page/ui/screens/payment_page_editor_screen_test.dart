import 'package:bb_mobile/core/widgets/inputs/utf8_byte_limit_formatter.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/payment_page_constants.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/get_paid/payment_page/ui/screens/payment_page_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPaymentPageService extends Mock implements PaymentPageServicePort {}

class _MockPaymentPageIdentity extends Mock
    implements PaymentPageIdentityPort {}

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

  testWidgets('shows Lightning Address requirement when nym is empty', (
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
      find.text('Create a Lightning Address before creating a payment page'),
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
    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Website'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Twitter'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Instagram'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();

    expect(find.text('Archive'), findsOneWidget);
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
      find.widgetWithText(TextField, 'Title'),
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

    final website = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Website'),
    );
    expect(website.maxLength, paymentPageWebsiteMaxBytes);
    expect(website.buildCounter, isNotNull);
    expect(website.inputFormatters, contains(isA<Utf8ByteLimitFormatter>()));
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
}

Widget _harness({
  required String nym,
  required PaymentPageServicePort paymentPageService,
  required PaymentPageIdentityPort paymentPageIdentity,
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
        ),
        archivePaymentPage: ArchivePaymentPageUsecase(
          paymentPageService: paymentPageService,
          paymentPageIdentity: paymentPageIdentity,
        ),
      ),
      child: PaymentPageEditorScreen(nym: nym),
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
                      ),
                      archivePaymentPage: ArchivePaymentPageUsecase(
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

PaymentPage _page() {
  return const PaymentPage(
    nym: 'alice',
    header: "Alice's Coffee",
    description: 'Tips welcome',
    displayCurrency: 'CAD',
    website: 'https://alice.example',
    twitter: 'alice',
    instagram: null,
    enabled: true,
    isArchived: false,
    avatarSha256: null,
    ogSha256: null,
    publicUrl: 'https://bullpay.ca/alice',
  );
}

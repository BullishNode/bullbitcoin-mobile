import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
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

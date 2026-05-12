import 'package:bb_mobile/features/get_paid/invoices/application/cancel_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/create_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/get_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice_status_snapshot.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_url.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_create_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_detail_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoices_list_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/invoices_router.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/screens/invoice_create_screen.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/screens/invoice_detail_screen.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/screens/invoices_list_screen.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockListInvoicesUsecase extends Mock implements ListInvoicesUsecase {}

class _MockCreateInvoiceUsecase extends Mock implements CreateInvoiceUsecase {}

class _MockGetInvoiceUsecase extends Mock implements GetInvoiceUsecase {}

class _MockCancelInvoiceUsecase extends Mock implements CancelInvoiceUsecase {}

void main() {
  late DateTime now;

  setUpAll(() {
    final fallbackNow = DateTime.utc(2026, 5, 11, 12);
    final fallbackId = InvoiceId('00000000-0000-0000-0000-000000000001');
    registerFallbackValue(ListInvoicesCommand(since: null, status: null));
    registerFallbackValue(
      CreateInvoiceCommand(
        amountSat: 1000,
        fiatAmountMinor: null,
        fiatCurrency: null,
        publicDescription: null,
        recipientName: null,
        invoiceNumber: null,
        acceptBtc: true,
        acceptLn: true,
        acceptLiquid: true,
        expiresAt: fallbackNow.add(const Duration(hours: 1)),
        linkToPageNym: null,
        privateMemo: null,
        now: fallbackNow,
      ),
    );
    registerFallbackValue(
      CancelInvoiceCommand(invoiceId: fallbackId, nymOwner: null),
    );
  });

  setUp(() {
    now = DateTime.utc(2026, 5, 11, 12);
  });

  testWidgets('invoice list loads and filters locally', (tester) async {
    final listInvoices = _MockListInvoicesUsecase();
    when(() => listInvoices.execute(command: any(named: 'command'))).thenAnswer(
      (_) async => [
        _invoice(
          id: '00000000-0000-0000-0000-000000000001',
          status: InvoiceStatus.unpaid,
          description: 'Coffee',
          now: now,
        ),
        _invoice(
          id: '00000000-0000-0000-0000-000000000002',
          status: InvoiceStatus.paid,
          description: 'Tea',
          now: now,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        BlocProvider(
          create: (_) => InvoicesListCubit(listInvoices: listInvoices),
          child: const InvoicesListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Tea'), findsOneWidget);

    await tester.tap(find.text('Paid'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsNothing);
    expect(find.text('Tea'), findsOneWidget);
    final command =
        verify(
              () => listInvoices.execute(command: captureAny(named: 'command')),
            ).captured.single
            as ListInvoicesCommand;
    expect(command.status, isNull);
  });

  testWidgets('invoice list refreshes when create route pops true', (
    tester,
  ) async {
    final listInvoices = _MockListInvoicesUsecase();
    var callCount = 0;
    when(() => listInvoices.execute(command: any(named: 'command'))).thenAnswer(
      (_) async {
        callCount += 1;
        return callCount == 1
            ? []
            : [
                _invoice(
                  id: '00000000-0000-0000-0000-000000000001',
                  status: InvoiceStatus.unpaid,
                  description: 'Coffee',
                  now: now,
                ),
              ];
      },
    );

    final router = GoRouter(
      initialLocation: '/invoices',
      routes: [
        GoRoute(
          path: '/invoices',
          builder: (context, state) => BlocProvider(
            create: (_) => InvoicesListCubit(listInvoices: listInvoices),
            child: const InvoicesListScreen(),
          ),
          routes: [
            GoRoute(
              name: InvoicesRoute.create.name,
              path: 'create',
              builder: (context, state) => Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(true),
                  child: const Text('Finish create'),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('No invoices'), findsOneWidget);

    await tester.tap(find.text('Create invoice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish create'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsOneWidget);
    verify(
      () => listInvoices.execute(command: any(named: 'command')),
    ).called(2);
  });

  testWidgets('invoice list refreshes after returning from detail', (
    tester,
  ) async {
    final listInvoices = _MockListInvoicesUsecase();
    var callCount = 0;
    when(() => listInvoices.execute(command: any(named: 'command'))).thenAnswer(
      (_) async {
        callCount += 1;
        return [
          _invoice(
            id: '00000000-0000-0000-0000-000000000001',
            status: callCount == 1
                ? InvoiceStatus.unpaid
                : InvoiceStatus.cancelled,
            description: 'Coffee',
            now: now,
          ),
        ];
      },
    );

    final router = GoRouter(
      initialLocation: '/invoices',
      routes: [
        GoRoute(
          path: '/invoices',
          builder: (context, state) => BlocProvider(
            create: (_) => InvoicesListCubit(listInvoices: listInvoices),
            child: const InvoicesListScreen(),
          ),
          routes: [
            GoRoute(
              name: InvoicesRoute.detail.name,
              path: 'detail/:invoiceId',
              builder: (context, state) => Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back from detail'),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('unpaid'), findsOneWidget);

    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back from detail'));
    await tester.pumpAndSettle();

    expect(find.text('cancelled'), findsOneWidget);
    verify(
      () => listInvoices.execute(command: any(named: 'command')),
    ).called(2);
  });

  testWidgets('invoice create screen submits sats command', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final createInvoice = _MockCreateInvoiceUsecase();
    final result = CreateInvoiceResult(
      invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
      shareUrl: InvoiceUrl(
        'https://bullpay.ca/invoice/00000000-0000-0000-0000-000000000001',
      ),
    );
    when(
      () => createInvoice.execute(command: any(named: 'command')),
    ).thenAnswer((_) async => result);

    await tester.pumpWidget(
      _app(
        BlocProvider(
          create: (_) => InvoiceCreateCubit(
            createInvoice: createInvoice,
            initialExpiresAt: DateTime.now().toUtc().add(
              const Duration(hours: 1),
            ),
          ),
          child: const InvoiceCreateScreen(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '1000');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is BBButton && widget.label == 'Continue',
      ),
    );
    await tester.pumpAndSettle();

    final createButton = find.byWidgetPredicate(
      (widget) => widget is BBButton && widget.label == 'Create invoice',
    );
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.text('Invoice created'), findsOneWidget);
    final command =
        verify(
              () =>
                  createInvoice.execute(command: captureAny(named: 'command')),
            ).captured.single
            as CreateInvoiceCommand;
    expect(command.amountSat, 1000);
    expect(command.fiatAmountMinor, isNull);
  });

  testWidgets('invoice detail cancel confirms before cancelling', (
    tester,
  ) async {
    final getInvoice = _MockGetInvoiceUsecase();
    final cancelInvoice = _MockCancelInvoiceUsecase();
    final id = InvoiceId('00000000-0000-0000-0000-000000000001');
    when(() => getInvoice.execute(id: id)).thenAnswer(
      (_) async => _snapshot(id: id, status: InvoiceStatus.unpaid, now: now),
    );
    when(
      () => cancelInvoice.execute(command: any(named: 'command')),
    ).thenAnswer(
      (_) async =>
          CancelInvoiceResult(invoiceId: id, status: InvoiceStatus.cancelled),
    );

    await tester.pumpWidget(
      _app(
        BlocProvider(
          create: (_) => InvoiceDetailCubit(
            getInvoice: getInvoice,
            cancelInvoice: cancelInvoice,
          ),
          child: InvoiceDetailScreen(invoiceId: id, nymOwner: 'alice'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel invoice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel invoice').last);
    await tester.pumpAndSettle();

    final command =
        verify(
              () =>
                  cancelInvoice.execute(command: captureAny(named: 'command')),
            ).captured.single
            as CancelInvoiceCommand;
    expect(command.invoiceId, id);
    expect(command.nymOwner, 'alice');
  });

  testWidgets('invoice detail shows server-provided share URL', (tester) async {
    final getInvoice = _MockGetInvoiceUsecase();
    final cancelInvoice = _MockCancelInvoiceUsecase();
    final id = InvoiceId('00000000-0000-0000-0000-000000000001');
    when(() => getInvoice.execute(id: id)).thenAnswer(
      (_) async => _snapshot(id: id, status: InvoiceStatus.unpaid, now: now),
    );

    await tester.pumpWidget(
      _app(
        BlocProvider(
          create: (_) => InvoiceDetailCubit(
            getInvoice: getInvoice,
            cancelInvoice: cancelInvoice,
          ),
          child: InvoiceDetailScreen(
            invoiceId: id,
            nymOwner: 'alice',
            shareUrl: 'https://bullpay.ca/alice/i/$id',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invoice URL'), findsOneWidget);
    expect(find.text('https://bullpay.ca/alice/i/$id'), findsOneWidget);
  });
}

Widget _app(Widget child) {
  return MaterialApp(home: child);
}

Invoice _invoice({
  required String id,
  required InvoiceStatus status,
  required String description,
  required DateTime now,
}) {
  return Invoice(
    id: InvoiceId(id),
    nymOwner: 'alice',
    origin: 'manual',
    status: status,
    amountSat: 1000,
    fiatAmountMinor: null,
    fiatCurrency: null,
    publicDescription: description,
    recipientName: 'Alice',
    invoiceNumber: 'INV-1',
    acceptBtc: true,
    acceptLn: true,
    acceptLiquid: true,
    bitcoinAddress: 'bc1qinvoice',
    liquidAddress: 'lq1invoice',
    createdAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
    paidVia: null,
    paidAt: null,
    paidAmountSat: null,
    shareUrl: InvoiceUrl('https://bullpay.ca/alice/i/$id'),
  );
}

InvoiceStatusSnapshot _snapshot({
  required InvoiceId id,
  required InvoiceStatus status,
  required DateTime now,
}) {
  return InvoiceStatusSnapshot(
    invoiceId: id,
    status: status,
    amountSat: 1000,
    rateMinorPerBtc: null,
    rateLocksUntil: now.add(const Duration(minutes: 5)),
    expiresAt: now.add(const Duration(hours: 1)),
    paidVia: null,
    paidAt: null,
    paidAmountSat: null,
    lightningPr: 'lnbc...',
    liquidAddress: 'lq1invoice',
    bitcoinAddress: 'bc1qinvoice',
    acceptBtc: true,
    acceptLn: true,
    acceptLiquid: true,
    rateStale: false,
  );
}

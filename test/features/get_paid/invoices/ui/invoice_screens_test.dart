import 'package:bb_mobile/features/get_paid/invoices/application/cancel_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/create_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/list_invoices_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/get_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/invoice_constants.dart';
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
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_constants.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/inputs/amount_input_formatter.dart';
import 'package:bb_mobile/core/widgets/timers/countdown.dart';
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
    registerFallbackValue(ListInvoicesCommand(status: null));
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
      (_) async => _listResult([
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
      ]),
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
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final listInvoices = _MockListInvoicesUsecase();
    final createInvoice = _MockCreateInvoiceUsecase();
    var callCount = 0;
    when(() => listInvoices.execute(command: any(named: 'command'))).thenAnswer(
      (_) async {
        callCount += 1;
        return _listResult(
          callCount == 1
              ? []
              : [
                  _invoice(
                    id: '00000000-0000-0000-0000-000000000001',
                    status: InvoiceStatus.unpaid,
                    description: 'Coffee',
                    now: now,
                  ),
                ],
        );
      },
    );
    when(
      () => createInvoice.execute(command: any(named: 'command')),
    ).thenAnswer(
      (_) async => CreateInvoiceResult(
        invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
        shareUrl: InvoiceUrl(
          'https://bullpay.ca/invoice/00000000-0000-0000-0000-000000000001',
        ),
      ),
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
              builder: (context, state) => BlocProvider(
                create: (_) => InvoiceCreateCubit(
                  createInvoice: createInvoice,
                  initialExpiresAt: DateTime.now().toUtc().add(
                    const Duration(hours: 1),
                  ),
                ),
                child: const InvoiceCreateScreen(),
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
    await _submitSatsInvoice(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsOneWidget);
    verify(
      () => listInvoices.execute(command: any(named: 'command')),
    ).called(2);
  });

  testWidgets('invoice list does not refresh after plain detail back', (
    tester,
  ) async {
    final listInvoices = _MockListInvoicesUsecase();
    var callCount = 0;
    when(() => listInvoices.execute(command: any(named: 'command'))).thenAnswer(
      (_) async {
        callCount += 1;
        return _listResult([
          _invoice(
            id: '00000000-0000-0000-0000-000000000001',
            status: callCount == 1
                ? InvoiceStatus.unpaid
                : InvoiceStatus.cancelled,
            description: 'Coffee',
            now: now,
          ),
        ]);
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

    expect(find.text('unpaid'), findsOneWidget);
    verify(
      () => listInvoices.execute(command: any(named: 'command')),
    ).called(1);
  });

  testWidgets('invoice list refreshes when detail route pops true', (
    tester,
  ) async {
    final listInvoices = _MockListInvoicesUsecase();
    var callCount = 0;
    when(() => listInvoices.execute(command: any(named: 'command'))).thenAnswer(
      (_) async {
        callCount += 1;
        return _listResult([
          _invoice(
            id: '00000000-0000-0000-0000-000000000001',
            status: callCount == 1
                ? InvoiceStatus.unpaid
                : InvoiceStatus.cancelled,
            description: 'Coffee',
            now: now,
          ),
        ]);
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
                  onPressed: () => context.pop(true),
                  child: const Text('Changed detail'),
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
    await tester.tap(find.text('Changed detail'));
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
    await tester.enterText(_amountField(), '1000');
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

  testWidgets('invoice create screen pops true after Done', (tester) async {
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

    bool? popResult;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popResult = await context.pushNamed<bool>(
                  InvoicesRoute.create.name,
                );
              },
              child: const Text('Open create'),
            ),
          ),
          routes: [
            GoRoute(
              name: InvoicesRoute.create.name,
              path: 'create',
              builder: (context, state) => BlocProvider(
                create: (_) => InvoiceCreateCubit(
                  createInvoice: createInvoice,
                  initialExpiresAt: DateTime.now().toUtc().add(
                    const Duration(hours: 1),
                  ),
                ),
                child: const InvoiceCreateScreen(),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open create'));
    await tester.pumpAndSettle();
    await _submitSatsInvoice(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(popResult, isTrue);
  });

  testWidgets('invoice create screen pops true on system back from success', (
    tester,
  ) async {
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

    bool? popResult;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popResult = await context.pushNamed<bool>(
                  InvoicesRoute.create.name,
                );
              },
              child: const Text('Open create'),
            ),
          ),
          routes: [
            GoRoute(
              name: InvoicesRoute.create.name,
              path: 'create',
              builder: (context, state) => BlocProvider(
                create: (_) => InvoiceCreateCubit(
                  createInvoice: createInvoice,
                  initialExpiresAt: DateTime.now().toUtc().add(
                    const Duration(hours: 1),
                  ),
                ),
                child: const InvoiceCreateScreen(),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open create'));
    await tester.pumpAndSettle();
    await _submitSatsInvoice(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(popResult, isTrue);
  });

  testWidgets('invoice create screen preserves amount when editing details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final createInvoice = _MockCreateInvoiceUsecase();

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
    await tester.enterText(_amountField(), '1000');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is BBButton && widget.label == 'Continue',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit amount'));
    await tester.pumpAndSettle();

    final amountField = tester.widget<TextField>(_amountField());
    expect(amountField.controller?.text, '1000');
  });

  for (final fiatCase in [
    (currency: 'USD', minor: 12345, display: '123.45'),
    (currency: 'CAD', minor: 12345, display: '123.45'),
    (currency: 'COP', minor: 12345, display: '12345'),
  ]) {
    testWidgets(
      'invoice create screen preserves ${fiatCase.currency} amount when editing details',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 2000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final createInvoice = _MockCreateInvoiceUsecase();

        await tester.pumpWidget(
          _app(
            BlocProvider(
              create: (_) =>
                  InvoiceCreateCubit(
                    createInvoice: createInvoice,
                    initialExpiresAt: DateTime.now().toUtc().add(
                      const Duration(hours: 1),
                    ),
                  )..setFiatAmount(
                    minor: fiatCase.minor,
                    currency: fiatCase.currency,
                  ),
              child: const InvoiceCreateScreen(),
            ),
          ),
        );
        await tester.pump();
        var amountField = tester.widget<TextField>(_amountField());
        expect(amountField.controller?.text, fiatCase.display);
        if (fiatCase.currency == 'COP') {
          expect(amountField.keyboardType, TextInputType.number);
        }

        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is BBButton && widget.label == 'Continue',
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Edit amount'));
        await tester.pumpAndSettle();

        amountField = tester.widget<TextField>(_amountField());
        expect(amountField.controller?.text, fiatCase.display);
      },
    );
  }

  testWidgets('invoice create screen disables submit when all rails are off', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final createInvoice = _MockCreateInvoiceUsecase();

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
    await tester.enterText(_amountField(), '1000');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is BBButton && widget.label == 'Continue',
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['Bitcoin on-chain', 'Lightning', 'Liquid']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    final createButton = tester.widget<BBButton>(
      find.byWidgetPredicate(
        (widget) => widget is BBButton && widget.label == 'Create invoice',
      ),
    );
    expect(createButton.disabled, isTrue);
  });

  testWidgets('invoice create screen keeps selected expiry across rebuilds', (
    tester,
  ) async {
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
              const Duration(days: 1),
            ),
          ),
          child: const InvoiceCreateScreen(),
        ),
      ),
    );
    await tester.enterText(_amountField(), '1000');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is BBButton && widget.label == 'Continue',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1 day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 days').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Public description'),
      'Coffee',
    );
    await tester.pumpAndSettle();

    expect(find.text('2 days'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is BBButton && widget.label == 'Create invoice',
      ),
    );
    await tester.pumpAndSettle();

    final command =
        verify(
              () =>
                  createInvoice.execute(command: captureAny(named: 'command')),
            ).captured.single
            as CreateInvoiceCommand;
    expect(
      command.expiresAt.difference(DateTime.now().toUtc()).inSeconds,
      closeTo(const Duration(days: 2).inSeconds, 10),
    );
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

    bool? poppedResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              poppedResult = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => BlocProvider(
                    create: (_) => InvoiceDetailCubit(
                      getInvoice: getInvoice,
                      cancelInvoice: cancelInvoice,
                    ),
                    child: InvoiceDetailScreen(
                      invoiceId: id,
                      nymOwner: 'alice',
                    ),
                  ),
                ),
              );
            },
            child: const Text('Open detail'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is BBButton && widget.label == 'Cancel invoice',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, cancel'));
    await tester.pumpAndSettle();

    final command =
        verify(
              () =>
                  cancelInvoice.execute(command: captureAny(named: 'command')),
            ).captured.single
            as CancelInvoiceCommand;
    expect(command.invoiceId, id);
    expect(command.nymOwner, 'alice');
    expect(poppedResult, isTrue);
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
    expect(find.byType(Countdown), findsOneWidget);
  });

  testWidgets('invoice detail formats multi-day countdown clearly', (
    tester,
  ) async {
    final getInvoice = _MockGetInvoiceUsecase();
    final cancelInvoice = _MockCancelInvoiceUsecase();
    final id = InvoiceId('00000000-0000-0000-0000-000000000001');
    when(() => getInvoice.execute(id: id)).thenAnswer(
      (_) async => _snapshot(
        id: id,
        status: InvoiceStatus.unpaid,
        now: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(
          const Duration(days: 1, minutes: 5),
        ),
      ),
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

    expect(find.textContaining('1d 0h'), findsOneWidget);
    expect(find.text('1440:00'), findsNothing);
  });

  testWidgets('invoice detail derives share URL when route omits it', (
    tester,
  ) async {
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
          child: InvoiceDetailScreen(invoiceId: id, nymOwner: 'alice'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        invoicePublicUrlFor(
          nym: 'alice',
          id: id,
          domain: bullnymDefaultDomain,
        ).value,
      ),
      findsOneWidget,
    );
  });

  test('COP amount formatter rejects decimals', () {
    final formatter = AmountInputFormatter(
      'COP',
      decimalPlaces: invoiceFiatCurrencyPrecision('COP'),
    );
    final oldValue = const TextEditingValue(
      text: '100',
      selection: TextSelection.collapsed(offset: 3),
    );

    expect(
      formatter
          .formatEditUpdate(
            oldValue,
            const TextEditingValue(
              text: '100.50',
              selection: TextSelection.collapsed(offset: 6),
            ),
          )
          .text,
      '100',
    );
  });
}

Widget _app(Widget child) {
  return MaterialApp(home: child);
}

Finder _amountField() => find.byKey(const ValueKey('invoice-amount-field'));

Future<void> _submitSatsInvoice(WidgetTester tester) async {
  await tester.enterText(_amountField(), '1000');
  await tester.pump();
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget is BBButton && widget.label == 'Continue',
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget is BBButton && widget.label == 'Create invoice',
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Invoice created'), findsOneWidget);
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

ListInvoicesResult _listResult(List<Invoice> invoices) {
  return ListInvoicesResult(
    invoices: invoices,
    page: 1,
    pageSize: 100,
    hasMore: false,
  );
}

InvoiceStatusSnapshot _snapshot({
  required InvoiceId id,
  required InvoiceStatus status,
  required DateTime now,
  DateTime? expiresAt,
}) {
  return InvoiceStatusSnapshot(
    invoiceId: id,
    status: status,
    amountSat: 1000,
    rateMinorPerBtc: null,
    rateLocksUntil: now.add(const Duration(minutes: 5)),
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
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

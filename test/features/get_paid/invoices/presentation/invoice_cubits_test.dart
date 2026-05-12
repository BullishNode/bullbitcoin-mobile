import 'package:bb_mobile/features/get_paid/invoices/application/cancel_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/create_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
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
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/payment_method.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_url.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_create_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_detail_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoices_list_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockListInvoicesUsecase extends Mock implements ListInvoicesUsecase {}

class _MockCreateInvoiceUsecase extends Mock implements CreateInvoiceUsecase {}

class _MockGetInvoiceUsecase extends Mock implements GetInvoiceUsecase {}

class _MockCancelInvoiceUsecase extends Mock implements CancelInvoiceUsecase {}

void main() {
  late DateTime now;

  setUpAll(() {
    final fallbackId = InvoiceId('00000000-0000-0000-0000-000000000001');
    final fallbackNow = DateTime.utc(2026, 5, 11, 12);
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

  group('InvoicesListCubit', () {
    late _MockListInvoicesUsecase listInvoices;

    setUp(() {
      listInvoices = _MockListInvoicesUsecase();
    });

    test('loads invoices and filters locally by status', () async {
      final unpaid = _invoice(
        id: '00000000-0000-0000-0000-000000000001',
        status: InvoiceStatus.unpaid,
        now: now,
      );
      final paid = _invoice(
        id: '00000000-0000-0000-0000-000000000002',
        status: InvoiceStatus.paid,
        now: now,
      );
      when(
        () => listInvoices.execute(command: any(named: 'command')),
      ).thenAnswer((_) async => [unpaid, paid]);

      final cubit = InvoicesListCubit(listInvoices: listInvoices);
      await cubit.load();
      cubit.setStatusFilter(InvoiceStatus.paid);

      expect(cubit.state.invoices, [unpaid, paid]);
      expect(cubit.state.filteredInvoices, [paid]);
      final command =
          verify(
                () =>
                    listInvoices.execute(command: captureAny(named: 'command')),
              ).captured.single
              as ListInvoicesCommand;
      expect(command.status, isNull);
      expect(command.since, isNull);
      expect(command.limit, 100);
    });

    test('maps typed list errors to state error', () async {
      when(
        () => listInvoices.execute(command: any(named: 'command')),
      ).thenThrow(const InvoicesAuthorizationError('bad signature'));

      final cubit = InvoicesListCubit(listInvoices: listInvoices);
      await cubit.load();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.error, 'bad signature');
    });
  });

  group('InvoiceCreateCubit', () {
    late _MockCreateInvoiceUsecase createInvoice;

    setUp(() {
      createInvoice = _MockCreateInvoiceUsecase();
    });

    test('builds command and stores create result after submit', () async {
      final result = CreateInvoiceResult(
        invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
        shareUrl: InvoiceUrl(
          'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
        ),
      );
      when(
        () => createInvoice.execute(command: any(named: 'command')),
      ).thenAnswer((_) async => result);

      final cubit =
          InvoiceCreateCubit(
              createInvoice: createInvoice,
              initialExpiresAt: now.add(const Duration(hours: 1)),
            )
            ..setAmountSat(1000)
            ..setPublicDescription('  Coffee  ')
            ..setRecipientName('  Alice  ')
            ..setInvoiceNumber('  INV-1  ')
            ..setLinkToPageNym('alice')
            ..setPrivateMemo('  local memo  ');

      await cubit.submit(now: now);

      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.result, result);
      final command =
          verify(
                () => createInvoice.execute(
                  command: captureAny(named: 'command'),
                ),
              ).captured.single
              as CreateInvoiceCommand;
      expect(command.amountSat, 1000);
      expect(command.fiatAmountMinor, isNull);
      expect(command.publicDescription, 'Coffee');
      expect(command.recipientName, 'Alice');
      expect(command.invoiceNumber, 'INV-1');
      expect(command.linkToPageNym, 'alice');
      expect(command.privateMemo, 'local memo');
    });

    test('builds fiat command after fiat amount submit', () async {
      final result = CreateInvoiceResult(
        invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
        shareUrl: InvoiceUrl(
          'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
        ),
      );
      when(
        () => createInvoice.execute(command: any(named: 'command')),
      ).thenAnswer((_) async => result);

      final cubit = InvoiceCreateCubit(
        createInvoice: createInvoice,
        initialExpiresAt: now.add(const Duration(hours: 1)),
      )..setFiatAmount(minor: 5000, currency: ' USD ');

      await cubit.submit(now: now);

      final command =
          verify(
                () => createInvoice.execute(
                  command: captureAny(named: 'command'),
                ),
              ).captured.single
              as CreateInvoiceCommand;
      expect(command.amountSat, isNull);
      expect(command.fiatAmountMinor, 5000);
      expect(command.fiatCurrency, 'USD');
    });

    test('amount mode setters clear the other amount mode', () {
      final cubit = InvoiceCreateCubit(
        createInvoice: createInvoice,
        initialExpiresAt: now.add(const Duration(hours: 1)),
      );

      cubit.setFiatAmount(minor: 5000, currency: 'USD');
      cubit.setAmountSat(1000);

      expect(cubit.state.amountSat, 1000);
      expect(cubit.state.fiatAmountMinor, isNull);
      expect(cubit.state.fiatCurrency, isNull);

      cubit.setFiatAmount(minor: 2500, currency: 'CAD');

      expect(cubit.state.amountSat, isNull);
      expect(cubit.state.fiatAmountMinor, 2500);
      expect(cubit.state.fiatCurrency, 'CAD');
    });

    test('field edits after successful submit clear result', () async {
      final result = CreateInvoiceResult(
        invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
        shareUrl: InvoiceUrl(
          'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
        ),
      );
      when(
        () => createInvoice.execute(command: any(named: 'command')),
      ).thenAnswer((_) async => result);

      final cubit = InvoiceCreateCubit(
        createInvoice: createInvoice,
        initialExpiresAt: now.add(const Duration(hours: 1)),
      )..setAmountSat(1000);
      await cubit.submit(now: now);
      expect(cubit.state.result, result);

      cubit.setPublicDescription('new description');

      expect(cubit.state.result, isNull);
    });

    test('field edits are ignored while submitting', () async {
      final result = CreateInvoiceResult(
        invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
        shareUrl: InvoiceUrl(
          'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
        ),
      );
      when(
        () => createInvoice.execute(command: any(named: 'command')),
      ).thenAnswer(
        (_) => Future<CreateInvoiceResult>.delayed(
          const Duration(milliseconds: 1),
          () => result,
        ),
      );

      final cubit = InvoiceCreateCubit(
        createInvoice: createInvoice,
        initialExpiresAt: now.add(const Duration(hours: 1)),
      )..setAmountSat(1000);

      final submit = cubit.submit(now: now);
      cubit.setPublicDescription('ignored');

      expect(cubit.state.publicDescription, '');
      await submit;
    });

    test('maps command validation errors without calling usecase', () async {
      final cubit = InvoiceCreateCubit(
        createInvoice: createInvoice,
        initialExpiresAt: now.add(const Duration(hours: 1)),
      );

      await cubit.submit(now: now);

      expect(cubit.state.isSubmitting, isFalse);
      expect(
        cubit.state.error,
        'invoice amount must be sats or fiat, but not both',
      );
      verifyNever(() => createInvoice.execute(command: any(named: 'command')));
    });
  });

  group('InvoiceDetailCubit', () {
    late _MockGetInvoiceUsecase getInvoice;
    late _MockCancelInvoiceUsecase cancelInvoice;

    setUp(() {
      getInvoice = _MockGetInvoiceUsecase();
      cancelInvoice = _MockCancelInvoiceUsecase();
    });

    test('loads public invoice status', () async {
      final id = InvoiceId('00000000-0000-0000-0000-000000000001');
      final snapshot = _snapshot(id: id, now: now);
      when(() => getInvoice.execute(id: id)).thenAnswer((_) async => snapshot);

      final cubit = InvoiceDetailCubit(
        getInvoice: getInvoice,
        cancelInvoice: cancelInvoice,
      );
      await cubit.load(id: id, nymOwner: 'alice');

      expect(cubit.state.invoiceId, id);
      expect(cubit.state.nymOwner, 'alice');
      expect(cubit.state.snapshot, snapshot);
      expect(cubit.state.isLoading, isFalse);
    });

    test('maps typed load errors to state error', () async {
      final id = InvoiceId('00000000-0000-0000-0000-000000000001');
      when(
        () => getInvoice.execute(id: id),
      ).thenThrow(const InvoicesNotFoundError('invoice not found'));

      final cubit = InvoiceDetailCubit(
        getInvoice: getInvoice,
        cancelInvoice: cancelInvoice,
      );
      await cubit.load(id: id, nymOwner: 'alice');

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.error, 'invoice not found');
    });

    test('clears stale snapshot when loading a different invoice', () async {
      final firstId = InvoiceId('00000000-0000-0000-0000-000000000001');
      final secondId = InvoiceId('00000000-0000-0000-0000-000000000002');
      final firstSnapshot = _snapshot(id: firstId, now: now);
      when(
        () => getInvoice.execute(id: firstId),
      ).thenAnswer((_) async => firstSnapshot);
      when(() => getInvoice.execute(id: secondId)).thenAnswer(
        (_) => Future<InvoiceStatusSnapshot>.delayed(
          const Duration(milliseconds: 1),
          () => _snapshot(id: secondId, now: now),
        ),
      );

      final cubit = InvoiceDetailCubit(
        getInvoice: getInvoice,
        cancelInvoice: cancelInvoice,
      );
      await cubit.load(id: firstId, nymOwner: 'alice');

      final loadingSecond = cubit.load(id: secondId, nymOwner: 'alice');

      expect(cubit.state.invoiceId, secondId);
      expect(cubit.state.snapshot, isNull);
      expect(cubit.state.isLoading, isTrue);
      await loadingSecond;
    });

    test('cancels current invoice with linked nym owner', () async {
      final id = InvoiceId('00000000-0000-0000-0000-000000000001');
      final snapshot = _snapshot(id: id, now: now);
      final result = CancelInvoiceResult(
        invoiceId: id,
        status: InvoiceStatus.cancelled,
      );
      when(() => getInvoice.execute(id: id)).thenAnswer((_) async => snapshot);
      when(
        () => cancelInvoice.execute(command: any(named: 'command')),
      ).thenAnswer((_) async => result);

      final cubit = InvoiceDetailCubit(
        getInvoice: getInvoice,
        cancelInvoice: cancelInvoice,
      );
      await cubit.load(id: id, nymOwner: 'alice');
      await cubit.cancel();

      expect(cubit.state.cancelResult, result);
      expect(cubit.state.isCancelling, isFalse);
      final command =
          verify(
                () => cancelInvoice.execute(
                  command: captureAny(named: 'command'),
                ),
              ).captured.single
              as CancelInvoiceCommand;
      expect(command.invoiceId, id);
      expect(command.nymOwner, 'alice');
    });

    test('maps typed cancel errors to state error', () async {
      final id = InvoiceId('00000000-0000-0000-0000-000000000001');
      final snapshot = _snapshot(id: id, now: now);
      when(() => getInvoice.execute(id: id)).thenAnswer((_) async => snapshot);
      when(
        () => cancelInvoice.execute(command: any(named: 'command')),
      ).thenThrow(const InvoicesAuthorizationError('bad signature'));

      final cubit = InvoiceDetailCubit(
        getInvoice: getInvoice,
        cancelInvoice: cancelInvoice,
      );
      await cubit.load(id: id, nymOwner: 'alice');
      await cubit.cancel();

      expect(cubit.state.isCancelling, isFalse);
      expect(cubit.state.cancelResult, isNull);
      expect(cubit.state.error, 'bad signature');
    });

    test('cancel before load is a no-op', () async {
      final cubit = InvoiceDetailCubit(
        getInvoice: getInvoice,
        cancelInvoice: cancelInvoice,
      );

      await cubit.cancel();

      verifyNever(() => cancelInvoice.execute(command: any(named: 'command')));
    });
  });
}

Invoice _invoice({
  required String id,
  required InvoiceStatus status,
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
    publicDescription: 'Coffee',
    recipientName: 'Alice',
    invoiceNumber: 'INV-1',
    acceptBtc: true,
    acceptLn: true,
    acceptLiquid: true,
    bitcoinAddress: 'bc1qinvoice',
    liquidAddress: 'lq1invoice',
    createdAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
    paidVia: status == InvoiceStatus.paid ? PaymentMethod.lightning : null,
    paidAt: status == InvoiceStatus.paid ? now : null,
    paidAmountSat: status == InvoiceStatus.paid ? 1000 : null,
    shareUrl: InvoiceUrl('https://bullpay.ca/alice/i/$id'),
  );
}

InvoiceStatusSnapshot _snapshot({
  required InvoiceId id,
  required DateTime now,
}) {
  return InvoiceStatusSnapshot(
    invoiceId: id,
    status: InvoiceStatus.unpaid,
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

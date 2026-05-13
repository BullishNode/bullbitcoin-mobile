import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/data/datasources/invoices_pay_service_datasource.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_client.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_errors.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/models/bullnym_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBullnymClient extends Mock implements BullnymClient {}

final _key = '11' * 32;

void main() {
  late _MockBullnymClient bullnymClient;
  late InvoicesPayServiceDatasource datasource;
  late NostrKeychainHandle handle;
  late DateTime expiresAt;

  setUp(() {
    bullnymClient = _MockBullnymClient();
    datasource = InvoicesPayServiceDatasource(bullnymClient: bullnymClient);
    handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);
    expiresAt = DateTime.utc(2026, 5, 12);
  });

  test('passes create command fields to Bullnym client', () async {
    when(
      () => bullnymClient.createInvoice(
        handle: handle,
        nym: 'alice',
        amountSat: 1000,
        fiatAmountMinor: null,
        fiatCurrency: null,
        publicDescription: 'Coffee',
        recipientName: 'Alice',
        invoiceNumber: 'INV-1',
        acceptBtc: true,
        acceptLn: true,
        acceptLiquid: true,
        bitcoinAddress: 'bc1qexample',
        liquidAddress: 'lq1example',
        liquidBlindingKeyHex: _key,
        expiresAt: expiresAt,
      ),
    ).thenAnswer(
      (_) async => const BullnymCreateInvoiceResponseDto(
        invoiceId: '00000000-0000-0000-0000-000000000001',
        shareUrl:
            'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
      ),
    );

    final result = await datasource.createInvoice(
      command: CreateInvoiceCommand(
        amountSat: 1000,
        fiatAmountMinor: null,
        fiatCurrency: null,
        publicDescription: 'Coffee',
        recipientName: 'Alice',
        invoiceNumber: 'INV-1',
        acceptBtc: true,
        acceptLn: true,
        acceptLiquid: true,
        expiresAt: expiresAt,
        linkToPageNym: 'alice',
        privateMemo: 'private',
        now: DateTime.utc(2026, 5, 11),
      ),
      handle: handle,
      bitcoinAddress: 'bc1qexample',
      liquidAddress: 'lq1example',
      liquidBlindingKeyHex: _key,
    );

    expect(result.invoiceId.value, '00000000-0000-0000-0000-000000000001');
    expect(
      result.shareUrl.value,
      'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
    );
  });

  test('maps list dto to invoice entity', () async {
    when(
      () => bullnymClient.listInvoices(
        handle: handle,
        page: 1,
        pageSize: 100,
        status: null,
      ),
    ).thenAnswer(
      (_) async => BullnymListInvoicesResponseDto(
        invoices: [_invoiceDto()],
        page: 1,
        pageSize: 100,
        hasMore: false,
      ),
    );

    final result = await datasource.listInvoices(
      command: ListInvoicesCommand(status: null),
      handle: handle,
    );

    expect(result.page, 1);
    expect(result.pageSize, 100);
    expect(result.hasMore, isFalse);
    final invoice = result.invoices.single;
    expect(invoice.id.value, '00000000-0000-0000-0000-000000000001');
    expect(invoice.status, InvoiceStatus.unpaid);
    expect(invoice.createdAt, DateTime.utc(2026, 5, 11, 12));
    expect(invoice.expiresAt, DateTime.utc(2026, 5, 12, 12));
  });

  test('maps partially paid invoice status from Bullnym', () async {
    when(
      () => bullnymClient.listInvoices(
        handle: handle,
        page: 1,
        pageSize: 100,
        status: null,
      ),
    ).thenAnswer(
      (_) async => BullnymListInvoicesResponseDto(
        invoices: [_invoiceDto(status: 'partially_paid')],
        page: 1,
        pageSize: 100,
        hasMore: false,
      ),
    );

    final result = await datasource.listInvoices(
      command: ListInvoicesCommand(status: null),
      handle: handle,
    );

    expect(result.invoices.single.status, InvoiceStatus.partiallyPaid);
  });

  test('maps cancel response to cancel result', () async {
    when(
      () => bullnymClient.cancelInvoice(
        handle: handle,
        invoiceId: '00000000-0000-0000-0000-000000000001',
        nym: 'alice',
      ),
    ).thenAnswer(
      (_) async => const BullnymCancelInvoiceResponseDto(
        invoiceId: '00000000-0000-0000-0000-000000000001',
        status: 'cancelled',
      ),
    );

    final result = await datasource.cancelInvoice(
      command: CancelInvoiceCommand(
        invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
        nymOwner: 'alice',
      ),
      handle: handle,
    );

    expect(result.status, InvoiceStatus.cancelled);
  });

  test('maps status dto to status snapshot', () async {
    when(
      () => bullnymClient.getInvoiceStatus(
        invoiceId: '00000000-0000-0000-0000-000000000001',
      ),
    ).thenAnswer((_) async => _statusDto());

    final snapshot = await datasource.getInvoiceStatus(
      id: InvoiceId('00000000-0000-0000-0000-000000000001'),
    );

    expect(snapshot.status, InvoiceStatus.inProgress);
    expect(snapshot.amountSat, 1000);
    expect(snapshot.lightningPr, 'lnbc...');
  });

  test('maps Bullnym errors to invoice application errors', () async {
    when(
      () => bullnymClient.getInvoiceStatus(invoiceId: any(named: 'invoiceId')),
    ).thenThrow(
      const BullnymException(
        code: 'InvoiceNotFound',
        reason: 'missing',
        statusCode: 404,
      ),
    );

    await expectLater(
      datasource.getInvoiceStatus(
        id: InvoiceId('00000000-0000-0000-0000-000000000001'),
      ),
      throwsA(isA<InvoicesNotFoundError>()),
    );
  });

  test('maps unexpected wire enum values to typed invoice errors', () async {
    when(
      () => bullnymClient.listInvoices(
        handle: handle,
        page: 1,
        pageSize: 100,
        status: null,
      ),
    ).thenAnswer(
      (_) async => BullnymListInvoicesResponseDto(
        invoices: [_invoiceDto(status: 'settled')],
        page: 1,
        pageSize: 100,
        hasMore: false,
      ),
    );

    await expectLater(
      datasource.listInvoices(
        command: ListInvoicesCommand(status: null),
        handle: handle,
      ),
      throwsA(isA<InvoicesUnexpectedError>()),
    );
  });

  test(
    'maps unexpected create response shape to typed invoice errors',
    () async {
      when(
        () => bullnymClient.createInvoice(
          handle: handle,
          nym: 'alice',
          amountSat: 1000,
          fiatAmountMinor: null,
          fiatCurrency: null,
          publicDescription: 'Coffee',
          recipientName: 'Alice',
          invoiceNumber: 'INV-1',
          acceptBtc: true,
          acceptLn: true,
          acceptLiquid: true,
          bitcoinAddress: 'bc1qexample',
          liquidAddress: 'lq1example',
          liquidBlindingKeyHex: _key,
          expiresAt: expiresAt,
        ),
      ).thenAnswer(
        (_) async => const BullnymCreateInvoiceResponseDto(
          invoiceId: '00000000-0000-0000-0000-000000000001',
          shareUrl:
              'http://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
        ),
      );

      await expectLater(
        datasource.createInvoice(
          command: CreateInvoiceCommand(
            amountSat: 1000,
            fiatAmountMinor: null,
            fiatCurrency: null,
            publicDescription: 'Coffee',
            recipientName: 'Alice',
            invoiceNumber: 'INV-1',
            acceptBtc: true,
            acceptLn: true,
            acceptLiquid: true,
            expiresAt: expiresAt,
            linkToPageNym: 'alice',
            privateMemo: null,
            now: DateTime.utc(2026, 5, 11),
          ),
          handle: handle,
          bitcoinAddress: 'bc1qexample',
          liquidAddress: 'lq1example',
          liquidBlindingKeyHex: _key,
        ),
        throwsA(isA<InvoicesUnexpectedError>()),
      );
    },
  );

  test(
    'maps unexpected cancel response shape to typed invoice errors',
    () async {
      when(
        () => bullnymClient.cancelInvoice(
          handle: handle,
          invoiceId: '00000000-0000-0000-0000-000000000001',
          nym: 'alice',
        ),
      ).thenAnswer(
        (_) async => const BullnymCancelInvoiceResponseDto(
          invoiceId: '00000000-0000-0000-0000-000000000001',
          status: 'settled',
        ),
      );

      await expectLater(
        datasource.cancelInvoice(
          command: CancelInvoiceCommand(
            invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
            nymOwner: 'alice',
          ),
          handle: handle,
        ),
        throwsA(isA<InvoicesUnexpectedError>()),
      );
    },
  );

  test(
    'maps unexpected status response shape to typed invoice errors',
    () async {
      when(
        () => bullnymClient.getInvoiceStatus(
          invoiceId: '00000000-0000-0000-0000-000000000001',
        ),
      ).thenAnswer((_) async => _statusDto(paidVia: 'cash'));

      await expectLater(
        datasource.getInvoiceStatus(
          id: InvoiceId('00000000-0000-0000-0000-000000000001'),
        ),
        throwsA(isA<InvoicesUnexpectedError>()),
      );
    },
  );
}

BullnymInvoiceListItemDto _invoiceDto({String status = 'unpaid'}) {
  return BullnymInvoiceListItemDto(
    id: '00000000-0000-0000-0000-000000000001',
    nymOwner: 'alice',
    origin: 'wallet',
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
    bitcoinAddress: 'bc1qexample',
    liquidAddress: 'lq1example',
    createdAtUnix: 1778500800,
    expiresAtUnix: 1778587200,
    paidVia: null,
    paidAtUnix: null,
    paidAmountSat: null,
  );
}

BullnymInvoiceStatusDto _statusDto({String? paidVia}) {
  return BullnymInvoiceStatusDto(
    status: 'in_progress',
    amountSat: 1000,
    rateMinorPerBtc: null,
    rateLocksUntilUnix: 1778501700,
    expiresAtUnix: 1778587200,
    paidVia: paidVia,
    paidAtUnix: null,
    paidAmountSat: null,
    lightningPr: 'lnbc...',
    liquidAddress: 'lq1example',
    bitcoinAddress: 'bc1qexample',
    acceptBtc: true,
    acceptLn: true,
    acceptLiquid: true,
    rateStale: false,
  );
}

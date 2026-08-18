import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart'
    show BullnymAuthSigner;
import 'package:bb_mobile/features/invoices/domain/entities/invoice_commands.dart';
import 'package:bb_mobile/features/invoices/application/ports/invoices_identity_port.dart';
import 'package:bb_mobile/features/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_results.dart';
import 'package:bb_mobile/features/invoices/application/usecases/get_merchant_invoice_usecase.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/invoices/domain/value_objects/invoice_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockIdentity extends Mock implements InvoicesIdentityPort {}

class _MockPayService extends Mock implements InvoicesPayServicePort {}

void main() {
  final signer = BullnymAuthSigner(
    npubHex: 'aa' * 32,
    signHashHex: (_) => 'bb' * 64,
  );
  late _MockIdentity identity;
  late _MockPayService payService;
  late GetMerchantInvoiceUsecase usecase;

  setUpAll(() {
    registerFallbackValue(
      BullnymAuthSigner(npubHex: '00' * 32, signHashHex: (_) => ''),
    );
    registerFallbackValue(const ListInvoicesCommand());
  });

  setUp(() {
    identity = _MockIdentity();
    payService = _MockPayService();
    usecase = GetMerchantInvoiceUsecase(identity, payService);
    when(() => identity.getSigningHandle()).thenAnswer((_) async => Ok(signer));
  });

  test(
    'pages the signed projection without reading fallback supervision',
    () async {
      final target = _invoice('target');
      when(
        () => payService.listInvoices(
          signer: any(named: 'signer'),
          command: any(named: 'command'),
        ),
      ).thenAnswer((invocation) async {
        final command =
            invocation.namedArguments[#command]! as ListInvoicesCommand;
        return Ok(
          ListInvoicesResult(
            invoices: command.page == 1 ? [_invoice('other')] : [target],
            page: command.page,
            pageSize: 100,
            hasMore: command.page == 1,
          ),
        );
      });

      final result = await usecase.execute(InvoiceId('target'));

      final value = result.fold(
        (invoice) => invoice,
        (failure) => throw TestFailure('expected Ok, got $failure'),
      );
      expect(value?.id, InvoiceId('target'));
      final commands = verify(
        () => payService.listInvoices(
          signer: signer,
          command: captureAny(named: 'command'),
        ),
      ).captured.cast<ListInvoicesCommand>();
      expect(commands.map((command) => command.page), [1, 2]);
      verifyNever(
        () => payService.listFallbackSupervision(signer: any(named: 'signer')),
      );
    },
  );

  test('stops on an empty page even if has_more is stale', () async {
    when(
      () => payService.listInvoices(
        signer: any(named: 'signer'),
        command: any(named: 'command'),
      ),
    ).thenAnswer(
      (_) async => const Ok(
        ListInvoicesResult(invoices: [], page: 1, pageSize: 100, hasMore: true),
      ),
    );

    final result = await usecase.execute(InvoiceId('missing'));

    final value = result.fold(
      (invoice) => invoice,
      (failure) => throw TestFailure('expected Ok, got $failure'),
    );
    expect(value, isNull);
    verify(
      () => payService.listInvoices(
        signer: signer,
        command: any(named: 'command'),
      ),
    ).called(1);
  });
}

Invoice _invoice(String id) => Invoice(
  id: InvoiceId(id),
  status: InvoiceStatus.unpaid,
  amountSat: 1000,
  remainingAmountSat: 1000,
  acceptBtc: true,
  acceptLn: true,
  acceptLiquid: true,
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2030),
);

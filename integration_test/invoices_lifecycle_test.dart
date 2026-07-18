import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/get_paid_fixtures.dart';

// SPEC-INV-01 — the fake-backed Invoices lifecycle round-trip.
//
// AUTHORED-BUT-CI-ONLY (flagged deviation, same rationale as SPEC-PP-01 /
// SPEC-POS-01): excluded from the aggregated L1 suite (tool/gen_all_test.dart
// skip set) because the live app-startup timers/blocs make an app-process run
// non-deterministic. The deterministic gates for this feature are the L0
// usecase/cubit suites; this file is retained for a dedicated CI job.

T _unwrap<T>(Result<T, InvoicesFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw TestFailure(
    'Expected invoice operation to succeed, got $failure',
  ),
};

List<Label> _invoiceReservationLabels(List<Label> labels) => labels
    .where(
      (label) =>
          label.label == LabelSystem.invoice.label && label.origin == 'invoice',
    )
    .toList();

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  Future<void> bootstrap(FakeBullnymClient bullnym) async {
    await locator.unregister<BullnymClientPort>();
    locator.registerLazySingleton<BullnymClientPort>(() => bullnym);
    // Default wallets only: invoices own no reserved wallet and need no nym.
    await ensureFixtureSeed();
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );
  }

  CreateInvoiceCommand liquidInvoice() => CreateInvoiceCommand(
    amountSat: 25000,
    acceptBtc: false,
    acceptLn: true,
    acceptLiquid: true,
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
    publicDescription: 'Coffee',
  );

  test('create (unlinked, default-wallet address + blinding key) -> list -> '
      'status -> cancel', () async {
    final bullnym = FakeBullnymClient();
    await bootstrap(bullnym);

    final created = _unwrap(
      await locator<InvoicesFacade>().create(liquidInvoice()),
    );
    // Unlinked v1: the public render is /invoice/:id.
    expect(created.shareUrl.value, contains('/invoice/'));

    // Payout discipline: the signed create carried an EMPTY nym slot and a
    // fresh Liquid address WITH its per-address blinding key (from the default
    // wallet, never a reserved descriptor).
    final call = bullnym.createInvoiceCalls.single;
    expect(call.nym, isNull);
    expect(call.fields.liquidAddress, isNotEmpty);
    expect(call.fields.liquidBlindingKeyHex, isNotEmpty);
    expect(call.fields.bitcoinAddress, anyOf(isNull, isEmpty));

    // The list shows it and the status polls unpaid.
    final listed = _unwrap(
      await locator<InvoicesFacade>().list(const ListInvoicesCommand()),
    );
    expect(
      listed.invoices.map((i) => i.id.value),
      contains(created.invoiceId.value),
    );

    final status = _unwrap(
      await locator<InvoicesFacade>().status(created.invoiceId),
    );
    expect(status.status, InvoiceStatus.unpaid);

    // Cancel (unpaid) settles to cancelled.
    final cancelled = _unwrap(
      await locator<InvoicesFacade>().cancel(
        CancelInvoiceCommand(invoiceId: created.invoiceId),
      ),
    );
    expect(cancelled.finalStatus, InvoiceStatus.cancelled);
    final after = _unwrap(
      await locator<InvoicesFacade>().status(created.invoiceId),
    );
    expect(after.status, InvoiceStatus.cancelled);
  });

  test(
    'reused Liquid address: the single regenerate-and-retry succeeds',
    () async {
      final bullnym = FakeBullnymClient()
        ..invoiceMode = FakeInvoiceMode.reusedLiquidAddressOnce;
      await bootstrap(bullnym);

      final created = _unwrap(
        await locator<InvoicesFacade>().create(liquidInvoice()),
      );
      expect(created.shareUrl.value, contains('/invoice/'));
      // Two create attempts were signed (the reuse, then the retry).
      expect(bullnym.createInvoiceCalls, hasLength(2));
      // The retry supplied a DIFFERENT fresh Liquid address.
      expect(
        bullnym.createInvoiceCalls[0].fields.liquidAddress,
        isNot(bullnym.createInvoiceCalls[1].fields.liquidAddress),
      );
    },
  );

  test(
    'reused Liquid address twice: typed failure releases reservations',
    () async {
      final bullnym = FakeBullnymClient()
        ..invoiceMode = FakeInvoiceMode.reusedLiquidAddressOnSelectedAttempts
        ..reusedLiquidAddressAttemptOrdinals.addAll({1, 2});
      await bootstrap(bullnym);

      final failed = await locator<InvoicesFacade>().create(liquidInvoice());

      expect(
        failed,
        isA<Err<CreateInvoiceResult, InvoicesFailure>>().having(
          (error) => error.failure.kind,
          'failure kind',
          InvoicesFailureKind.reusedLiquidAddress,
        ),
      );
      expect(bullnym.createInvoiceCalls, hasLength(2));

      final firstFields = bullnym.createInvoiceCalls[0].fields;
      final retryFields = bullnym.createInvoiceCalls[1].fields;
      expect(firstFields.liquidAddress, isNotEmpty);
      expect(retryFields.liquidAddress, isNotEmpty);
      expect(firstFields.liquidBlindingKeyHex, isNotEmpty);
      expect(retryFields.liquidBlindingKeyHex, isNotEmpty);
      expect(firstFields.liquidAddress, isNot(retryFields.liquidAddress));
      expect(
        firstFields.liquidBlindingKeyHex,
        isNot(retryFields.liquidBlindingKeyHex),
      );

      final listedAfterFailure = _unwrap(
        await locator<InvoicesFacade>().list(const ListInvoicesCommand()),
      );
      expect(listedAfterFailure.invoices, isEmpty);

      final labels = locator<LabelsFacade>();
      final firstAttemptLabels = await labels.fetchByReference(
        firstFields.liquidAddress!,
      );
      final retryAttemptLabels = await labels.fetchByReference(
        retryFields.liquidAddress!,
      );
      expect(_invoiceReservationLabels(firstAttemptLabels), isEmpty);
      expect(_invoiceReservationLabels(retryAttemptLabels), isEmpty);

      final later = _unwrap(
        await locator<InvoicesFacade>().create(liquidInvoice()),
      );
      expect(later.shareUrl.value, contains('/invoice/'));
      expect(bullnym.createInvoiceCalls, hasLength(3));

      final listedAfterSuccess = _unwrap(
        await locator<InvoicesFacade>().list(const ListInvoicesCommand()),
      );
      expect(
        listedAfterSuccess.invoices.map((invoice) => invoice.id.value),
        contains(later.invoiceId.value),
      );
    },
  );

  test(
    'two back-to-back invoices reserve DISTINCT Liquid addresses + keys',
    () async {
      // No funding between creates: the first invoice's unfunded address must be
      // reserved (system label) so the second derives a fresh index instead of
      // colliding on the same address + blinding key.
      final bullnym = FakeBullnymClient();
      await bootstrap(bullnym);

      final first = _unwrap(
        await locator<InvoicesFacade>().create(liquidInvoice()),
      );
      final second = _unwrap(
        await locator<InvoicesFacade>().create(liquidInvoice()),
      );

      // Both creates succeeded and produced distinct invoices.
      expect(first.invoiceId.value, isNot(second.invoiceId.value));
      expect(bullnym.createInvoiceCalls, hasLength(2));

      final firstFields = bullnym.createInvoiceCalls[0].fields;
      final secondFields = bullnym.createInvoiceCalls[1].fields;
      expect(firstFields.liquidAddress, isNotEmpty);
      expect(secondFields.liquidAddress, isNotEmpty);
      expect(firstFields.liquidAddress, isNot(secondFields.liquidAddress));
      expect(
        firstFields.liquidBlindingKeyHex,
        isNot(secondFields.liquidBlindingKeyHex),
      );
    },
  );

  test(
    'feature-disabled server: create FAILS CLOSED, never a silent success',
    () async {
      final bullnym = FakeBullnymClient()
        ..invoiceMode = FakeInvoiceMode.featureDisabled;
      await bootstrap(bullnym);

      final result = await locator<InvoicesFacade>().create(liquidInvoice());
      expect(
        result,
        isA<Err<CreateInvoiceResult, InvoicesFailure>>().having(
          (error) => error.failure.kind,
          'failure kind',
          InvoicesFailureKind.server,
        ),
      );

      final listed = await locator<InvoicesFacade>().list(
        const ListInvoicesCommand(),
      );
      expect(listed, isA<Err<ListInvoicesResult, InvoicesFailure>>());

      final cancelled = await locator<InvoicesFacade>().cancel(
        CancelInvoiceCommand(invoiceId: InvoiceId('feature-disabled-id')),
      );
      expect(cancelled, isA<Err<CancelInvoiceResult, InvoicesFailure>>());
    },
  );
}

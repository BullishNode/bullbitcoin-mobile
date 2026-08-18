import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/get_paid_fixtures.dart';
import 'support/get_paid_test_harness.dart';
import 'support/integration_test_profile.dart';

// SPEC-INV-01 — the fake-backed Invoices lifecycle round-trip.
//
// Runs in the aggregated L1 suite against the deterministic fake Bullnym
// backend. Product lifecycle journeys must not exist only as unaudited files.

T _unwrap<T>(Result<T, InvoicesFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw TestFailure(
    'Expected invoice operation to succeed, got $failure',
  ),
};

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await initializeIntegrationTestApp(isInitialized: isInitialized);

  CreateInvoiceCommand liquidInvoice() => CreateInvoiceCommand(
    amountSat: 25000,
    presentation: PrivateInvoicePresentation(
      invoice: PrivateInvoiceDetails(description: 'Coffee'),
    ),
    acceptBtc: false,
    acceptLn: true,
    acceptLiquid: true,
  );

  group('fake-backed invoice lifecycle', () {
    final bullnym = FakeBullnymClient();

    setUpAll(() => installFakeBullnymClient(bullnym));

    setUp(() async {
      bullnym.mode = FakeBullnymMode.live;
      bullnym.invoiceMode = FakeInvoiceMode.normal;
      bullnym.createInvoiceCalls.clear();
      await wipeGetPaidLocalState();
      // Default wallets only: invoices own no reserved wallet and need no nym.
      await locator<CreateDefaultWalletsUsecase>().execute(
        mnemonicWords: getPaidFixtureMnemonicWords,
      );
    });

    tearDown(wipeGetPaidLocalState);

    test('create (unlinked, default-wallet address + blinding key) -> list -> '
        'status -> cancel', () async {
      final created = _unwrap(
        await locator<InvoicesFacade>().create(liquidInvoice()),
      );
      expect(created.privateLink.value, contains('/invoice/'));
      expect(created.privateLink.value, contains('#v1.'));

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
        bullnym.invoiceMode = FakeInvoiceMode.reusedLiquidAddressOnce;

        final created = _unwrap(
          await locator<InvoicesFacade>().create(liquidInvoice()),
        );
        expect(created.privateLink.value, contains('/invoice/'));
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
      'two back-to-back invoices reserve DISTINCT Liquid addresses + keys',
      () async {
        // No funding between creates: the first invoice's unfunded address must
        // be reserved (system label) so the second derives a fresh index instead
        // of colliding on the same address + blinding key.
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
        bullnym.invoiceMode = FakeInvoiceMode.featureDisabled;

        final result = await locator<InvoicesFacade>().create(liquidInvoice());
        expect(
          result,
          isA<Err<CreateInvoiceResult, InvoicesFailure>>().having(
            (error) => error.failure.kind,
            'failure kind',
            InvoicesFailureKind.outcomeUnknown,
          ),
        );
      },
    );
  });
}

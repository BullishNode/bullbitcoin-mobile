import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_cubit.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/live_nopay_fixtures.dart';
import 'support/wipe_app_state.dart';

// S-REAL-PROD-LIVE-NOPAY: production Bullnym + production Nostr, real
// seed-derived keys, real encrypted backups, and real Get Paid metadata.
//
// This spec intentionally does NOT import send/pay/broadcast code. It may
// create invoice metadata and payable addresses, but it must never execute an
// actual Bitcoin, Liquid, or Lightning payment.
//
// Permanent names (permanent_names_v1): a wallet seed owns exactly one nym for
// life, so every test that registers uses its OWN fresh throwaway seed (see
// LiveNoPayFixtures) and every nym is kept within the 1-32 char Bullnym syntax.
T _unwrap<T>(Result<T, InvoicesFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw TestFailure(
    'Expected invoice operation to succeed, got $failure',
  ),
};

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  late final LiveNoPayFixtures fixtures;

  setUpAll(() {
    fixtures = LiveNoPayFixtures.fromEnvironment();
  });

  // TEST A — the registration + autobackup portion, which does not resolve a
  // nym via lookup and so is unaffected by the permanent-names lookup defect
  // (see TEST B). This is the standalone green signal that the RC can register
  // a wallet-owned nym and build its keychain manifest against production.
  test('production Bullnym registration and keychain manifest for a '
      'wallet-owned nym (no payment)', () async {
    final nym = fixtures.nymFor(LiveNoPayFixtures.registrationScenario);
    await _resetWithMnemonic(fixtures.registrationMnemonicWords);
    await _assertSeedCanClaim(nym);
    await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
      automatedBackupEnabled: true,
    );

    final registration = await locator<LightningAddressFacade>()
        .registerWalletOwned(nym: nym);
    expect(registration.registration.nym, nym);
    expect(registration.registration.lightningAddress, isNotEmpty);
    expect(registration.walletId, isNotEmpty);

    final defaultWallet = (await locator<WalletRepository>().getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    )).first;
    final manifest = await locator<KeychainManifestFacade>()
        .buildManifestFilePayload(defaultWallet.masterFingerprint);
    // A standalone fresh seed that has registered only the wallet-owned nym has
    // a single keychain-manifest entry. The old >=3 expectation assumed the
    // combined lifecycle (registration + payment page + POS) had all run on the
    // same seed; after the test split (fresh seed per test) that no longer
    // holds, so assert the manifest is populated (>=1) for this seed.
    expect(manifest.entryCount, greaterThanOrEqualTo(1));
  });

  // TEST B — payment page, POS, invoice metadata, and Nostr remote recovery for
  // a registered nym, WITHOUT any payment.
  //
  // KNOWN-RED pending the client fix: under permanent_names_v1 the production
  // lookup omits the legacy `active` bool (liveness is `lightning_address_online`),
  // but BullnymHttpClient._parseLookupResponse still requires `active`
  // unconditionally (bullnym_http_client.dart:791), so every nym-identity
  // resolution — payment-page save, POS save, post-recovery lookup — throws
  // InvalidServerResponse. Evidence:
  // .quarantine/nopay-rc-run-20260716151742/VERDICT.md + lookup-response-body.json.
  // This test is intentionally left exercising the full flow so it turns green
  // on its own once the client parser fix lands; it is NOT worked around here.
  test('payment page, POS, invoice metadata, and Nostr recovery for a '
      'registered nym (no payment)', () async {
    final nym = fixtures.nymFor(LiveNoPayFixtures.lifecycleScenario);
    await _resetWithMnemonic(fixtures.lifecycleMnemonicWords);
    await _assertSeedCanClaim(nym);
    await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
      automatedBackupEnabled: true,
    );

    final registration = await locator<LightningAddressFacade>()
        .registerWalletOwned(nym: nym);
    expect(registration.registration.nym, nym);
    expect(registration.registration.lightningAddress, isNotEmpty);
    expect(registration.walletId, isNotEmpty);

    final page = await locator<PaymentPageFacade>().save(
      SavePaymentPageCommand(
        header: 'Live no-pay ${fixtures.runId}',
        description: 'Production identity recovery coverage',
        displayCurrency: 'CAD',
        website: 'https://bullbitcoin.com',
      ),
    );
    expect(page.nym, nym);
    expect(page.isActive, isTrue);
    expect(page.publicUrl, isNotEmpty);

    final pos = await locator<PosFacade>().provision(
      PosProvisionCommand(
        label: 'No-pay POS ${fixtures.runId}',
        displayCurrency: 'CAD',
      ),
    );
    expect(pos.nym, nym);
    expect(pos.isActive, isTrue);
    expect(pos.terminalUrl, contains(nym));

    final invoice = _unwrap(
      await locator<InvoicesFacade>().create(
        CreateInvoiceCommand(
          amountSat: 25000,
          acceptBtc: true,
          acceptLn: true,
          acceptLiquid: true,
          publicDescription: 'No-pay invoice metadata ${fixtures.runId}',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
        ),
      ),
    );
    expect(invoice.invoiceId.value, isNotEmpty);
    expect(invoice.shareUrl.value, contains('/invoice/'));

    final invoiceStatus = _unwrap(
      await locator<InvoicesFacade>().status(invoice.invoiceId),
    );
    expect(invoiceStatus.status, InvoiceStatus.unpaid);
    expect(invoiceStatus.acceptBtc, isTrue);
    expect(invoiceStatus.acceptLn, isTrue);
    expect(invoiceStatus.acceptLiquid, isTrue);

    final cancelled = _unwrap(
      await locator<InvoicesFacade>().cancel(
        CancelInvoiceCommand(invoiceId: invoice.invoiceId),
      ),
    );
    expect(cancelled.invoiceId, invoice.invoiceId);
    expect(cancelled.finalStatus, InvoiceStatus.cancelled);

    await _resetWithMnemonic(fixtures.lifecycleMnemonicWords);

    final recovery = await _runRemoteRecovery();
    expect(
      recovery.status,
      anyOf(
        RemoteKeychainRecoveryStatus.restored,
        RemoteKeychainRecoveryStatus.partiallyRestored,
      ),
    );
    expect(recovery.restoredCount, greaterThan(0));

    final restoredRegistration = await locator<LightningAddressFacade>()
        .lookupWalletOwnedRegistration();
    expect(restoredRegistration.nym, nym);
    expect(restoredRegistration.active, isTrue);

    final lightningHeal = await locator<LightningAddressFacade>()
        .ensureRegistrationLive();
    expect(
      lightningHeal.liveness,
      anyOf(
        LightningAddressRegistrationLiveness.live,
        LightningAddressRegistrationLiveness.reregistered,
      ),
    );

    final restoredPage = await locator<PaymentPageFacade>().find(nym: nym);
    expect(restoredPage, isNotNull);
    expect(restoredPage!.isActive, isTrue);
    final pageHeal = await locator<PaymentPageFacade>().ensurePageLive();
    expect(pageHeal.liveness, PaymentPageLiveness.live);

    final restoredPos = await locator<PosFacade>().find(nym: nym);
    expect(restoredPos, isNotNull);
    expect(restoredPos!.isActive, isTrue);
    final posHeal = await locator<PosFacade>().ensurePosLive();
    expect(posHeal.liveness, PosLiveness.live);
  });

  // TEST 2 — anti-takeover under permanent names. A FRESH owner seed claims the
  // nym; a FRESH attacker seed (which owns no name) then attempts the SAME nym
  // and must be rejected server-side as a name it does not own — not merely
  // "some exception". Using two fresh seeds is essential: reusing a seed that
  // already owns a name would instead fail with "cannot claim a second name".
  test('a second real seed cannot take over a live Bullnym nym', () async {
    final nym = fixtures.nymFor(LiveNoPayFixtures.takeoverScenario);

    // Fresh owner claims the nym.
    await _resetWithMnemonic(fixtures.takeoverOwnerMnemonicWords);
    await _assertSeedCanClaim(nym);
    await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
      automatedBackupEnabled: true,
    );
    final ownerRegistration = await locator<LightningAddressFacade>()
        .registerWalletOwned(nym: nym);
    expect(ownerRegistration.registration.nym, nym);

    // Fresh attacker (owns nothing) attempts the same nym: the server must
    // reject the submission as an already-owned name, non-retryably.
    await _resetWithMnemonic(fixtures.takeoverAttackerMnemonicWords);
    await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
      automatedBackupEnabled: true,
    );
    await expectLater(
      locator<LightningAddressFacade>().registerWalletOwned(nym: nym),
      throwsA(
        isA<WalletOwnedLightningAddressRegistrationException>()
            .having(
              (e) => e.phase,
              'phase',
              WalletOwnedLightningAddressRegistrationFailurePhase
                  .registrationSubmission,
            )
            .having(
              (e) => e.cause.kind,
              'cause.kind',
              LightningAddressErrorKind.serverRejectedRequest,
            )
            .having((e) => e.retryable, 'retryable', isFalse),
      ),
    );
  });

  // TEST 3 — a clean seed that registers WITHOUT the backup disclosure has no
  // live Nostr backup to recover. Fresh seed; short nym within the syntax cap.
  test('without backup disclosure, a clean seed has no recoverable live Nostr '
      'backup', () async {
    final nym = fixtures.nymFor(LiveNoPayFixtures.noDisclosureScenario);

    await _resetWithMnemonic(fixtures.cleanMnemonicWords);
    await _assertSeedCanClaim(nym);
    await locator<LightningAddressFacade>().registerWalletOwned(nym: nym);

    await _resetWithMnemonic(fixtures.cleanMnemonicWords);

    final recovery = await _runRemoteRecovery();
    expect(recovery.status, RemoteKeychainRecoveryStatus.noManifestFound);
  });
}

Future<void> _resetWithMnemonic(List<String> mnemonicWords) async {
  await wipeAppState(locator);
  await locator<CreateDefaultWalletsUsecase>().execute(
    mnemonicWords: mnemonicWords,
  );
}

/// Fail fast (before the registering call reaches the wire) if the current
/// default-wallet seed has already burned its one permanent name. A fresh seed
/// has no registration (server → NymNotFound), so the lookup throws and we
/// proceed. If instead a registration exists for a different nym, or the
/// permanent-name quota is exhausted, the fixtures reused a seed that permanent
/// names forbid — surface that clearly rather than as an opaque server reject.
Future<void> _assertSeedCanClaim(String intendedNym) async {
  final LightningAddressStatus existing;
  try {
    existing = await locator<LightningAddressFacade>()
        .lookupWalletOwnedRegistration();
  } on LightningAddressException catch (e) {
    if (e.code == 'NymNotFound') return;
    rethrow;
  }
  final quota = existing.permanentNameStatus?.quota;
  final ownsOther = existing.nym.isNotEmpty && existing.nym != intendedNym;
  if (ownsOther || (quota != null && quota.remaining <= 0)) {
    fail(
      'Fixture seed already owns permanent name "${existing.nym}" '
      '(quota remaining ${quota?.remaining}); live no-pay fixtures must provide '
      'a FRESH seed per run — permanent names are one per seed for life.',
    );
  }
}

Future<RemoteKeychainRecoveryState> _runRemoteRecovery() async {
  final cubit = locator<RemoteKeychainRecoveryCubit>();
  addTearDown(cubit.close);
  await cubit.start();
  if (cubit.state.status ==
      RemoteKeychainRecoveryStatus.requiresRelayDisclosure) {
    await cubit.acceptRelayDisclosure();
  }
  return cubit.state;
}

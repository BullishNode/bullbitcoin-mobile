import 'package:bb_mobile/core/failures/failure.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/entities/frozen_wallet_outpoint.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_utxo_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_frozen_wallet_outpoints_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_preferences_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/live_nopay_fixtures.dart';
import 'support/wipe_app_state.dart';

// S-REAL-PROD-LIVE-NOPAY: production Bullnym, real seed-derived keys, real
// encrypted backups, and real Get Paid metadata.
//
// This spec intentionally does NOT import send/pay/broadcast code. It may
// create invoice metadata and payable addresses, but it must never execute an
// actual Bitcoin, Liquid, or Lightning payment.
//
// Permanent names (permanent_names_v1): a wallet seed owns exactly one nym for
// life, so every test that registers uses its OWN fresh throwaway seed (see
// LiveNoPayFixtures) and every nym is kept within the 1-32 char Bullnym syntax.
const _smallBackupTxId =
    'a00000000000000000000000000000000000000000000000000000000000000a';
const _smallBackupVout = 3;

T _unwrap<T, F extends Failure>(Result<T, F> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw TestFailure(
    'Expected operation to succeed, got $failure',
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
    await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);

    final registration = await locator<LightningAddressFacade>()
        .registerWalletOwned(nym: nym);
    expect(registration.registration.nym, nym);
    expect(registration.registration.lightningAddress, isNotEmpty);
    expect(registration.walletId, isNotEmpty);
    final emptyComments = await locator<LightningAddressFacade>()
        .listPaymentComments(page: 1, pageSize: 20);
    expect(emptyComments.comments, isEmpty);

    final pageCurrencies = await locator<PaymentPageFacade>()
        .supportedCurrencies();
    final posCurrencies = await locator<PosFacade>().supportedCurrencies();
    final invoiceCurrencies = _unwrap(
      await locator<InvoicesFacade>().supportedCurrencies(),
    );
    expect(pageCurrencies.map((currency) => currency.code), contains('CAD'));
    expect(posCurrencies.map((currency) => currency.code), contains('CAD'));
    expect(
      invoiceCurrencies.currencies.map((currency) => currency.code),
      contains('CAD'),
    );

    await locator<KeychainManifestFacade>().backupNow();
    final metadataRecovery = await locator<WalletMetadataBackupFacade>()
        .beginRecoverySession();
    try {
      final result = _unwrap(
        await metadataRecovery.recover(createdWalletRefs: const <String>{}),
      );
      expect(result.status, WalletMetadataRecoveryStatus.noSnapshotFound);
    } finally {
      metadataRecovery.close();
    }

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

    final remoteManifest = await locator<KeychainManifestFacade>()
        .fetchRemoteImportPlan();
    expect(remoteManifest.status, KeychainManifestRemoteImportStatus.success);

    await locator<KeychainManifestFacade>().deleteRemoteBackup(confirmed: true);
    final deletedManifest = await locator<KeychainManifestFacade>()
        .fetchRemoteImportPlan();
    expect(deletedManifest.status, KeychainManifestRemoteImportStatus.absent);
  }, timeout: const Timeout(Duration(minutes: 6)));

  // TEST B — payment page, POS, invoice metadata, and Bullnym remote recovery
  // for a registered nym, WITHOUT any payment.
  test('payment page, POS, invoice metadata, and Bullnym recovery for a '
      'registered nym (no payment)', () async {
    final nym = fixtures.nymFor(LiveNoPayFixtures.lifecycleScenario);
    await _resetWithMnemonic(fixtures.lifecycleMnemonicWords);
    await _assertSeedCanClaim(nym);
    await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);
    _unwrap(await locator<WalletMetadataBackupFacade>().setEnabled(true));

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

    final updatedPage = await locator<PaymentPageFacade>().save(
      SavePaymentPageCommand(
        header: 'Updated live no-pay ${fixtures.runId}',
        description: 'Updated production lifecycle coverage',
        displayCurrency: 'CAD',
        website: 'https://bullbitcoin.com',
        twitter: 'bullbitcoin',
      ),
    );
    expect(updatedPage.header, startsWith('Updated live no-pay'));
    expect(updatedPage.twitter, 'bullbitcoin');
    final archivedPage = await locator<PaymentPageFacade>().archive();
    expect(archivedPage, isNotNull);
    expect(archivedPage!.isActive, isFalse);
    final reactivatedPage = await locator<PaymentPageFacade>().save(
      SavePaymentPageCommand(
        header: updatedPage.header,
        description: updatedPage.description,
        displayCurrency: updatedPage.displayCurrency,
        website: 'https://bullbitcoin.com',
        twitter: 'bullbitcoin',
      ),
    );
    expect(reactivatedPage.isActive, isTrue);

    final pos = await locator<PosFacade>().provision(
      PosProvisionCommand(
        label: 'No-pay POS ${fixtures.runId}',
        displayCurrency: 'CAD',
      ),
    );
    expect(pos.nym, nym);
    expect(pos.isActive, isTrue);
    expect(pos.terminalUrl, contains(nym));

    final updatedPos = await locator<PosFacade>().provision(
      PosProvisionCommand(
        label: 'Updated no-pay POS ${fixtures.runId}',
        displayCurrency: 'CAD',
      ),
    );
    expect(updatedPos.label, startsWith('Updated no-pay POS'));
    final archivedPos = await locator<PosFacade>().archive();
    expect(archivedPos, isNotNull);
    expect(archivedPos!.isActive, isFalse);
    final pageWhilePosArchived = await locator<PaymentPageFacade>().find(
      nym: nym,
    );
    expect(pageWhilePosArchived, isNotNull);
    expect(pageWhilePosArchived!.isActive, isTrue);
    final reactivatedPos = await locator<PosFacade>().provision(
      PosProvisionCommand(
        label: updatedPos.label,
        displayCurrency: updatedPos.displayCurrency,
      ),
    );
    expect(reactivatedPos.isActive, isTrue);

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

    final listedInvoices = _unwrap(
      await locator<InvoicesFacade>().list(const ListInvoicesCommand()),
    );
    expect(
      listedInvoices.invoices.map((invoice) => invoice.id),
      contains(invoice.invoiceId),
    );
    final fallbackOverview = _unwrap(
      await locator<InvoicesFacade>().fallbackSupervision(),
    );
    expect(fallbackOverview.forInvoice(invoice.invoiceId), isEmpty);

    final cancelled = _unwrap(
      await locator<InvoicesFacade>().cancel(
        CancelInvoiceCommand(invoiceId: invoice.invoiceId),
      ),
    );
    expect(cancelled.invoiceId, invoice.invoiceId);
    expect(cancelled.finalStatus, InvoiceStatus.cancelled);

    final fiatInvoice = _unwrap(
      await locator<InvoicesFacade>().create(
        CreateInvoiceCommand(
          fiatAmountMinor: 500,
          fiatCurrency: 'CAD',
          acceptBtc: true,
          acceptLn: true,
          acceptLiquid: true,
          publicDescription: 'Fiat quote coverage ${fixtures.runId}',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
        ),
      ),
    );
    for (final rail in PaymentMethod.values) {
      final quote = _unwrap(
        await locator<InvoicesFacade>().quote(
          invoiceId: fiatInvoice.invoiceId,
          rail: rail,
        ),
      );
      expect(quote.selectedRail, rail);
      expect(quote.instruction.copyPayload, isNotEmpty);
      expect(quote.isExpired(DateTime.now().toUtc()), isFalse);
    }
    final cancelledFiat = _unwrap(
      await locator<InvoicesFacade>().cancel(
        CancelInvoiceCommand(invoiceId: fiatInvoice.invoiceId),
      ),
    );
    expect(cancelledFiat.finalStatus, InvoiceStatus.cancelled);

    final walletsBeforeRecovery = await locator<WalletRepository>()
        .getWallets();
    final metadataWallet = walletsBeforeRecovery.firstWhere(
      (wallet) => wallet.isDefault,
    );
    final expectedLabel = Bip329LabelRecord(
      type: 'tx',
      reference: _smallBackupTxId,
      label: 'live-small-backup-${fixtures.runId}',
      origin: metadataWallet.id,
    );
    final labels = locator<LabelsFacade>();
    final restoredLabel = _unwrap(
      await labels.restoreBip329LabelRecords([expectedLabel]),
    );
    expect(restoredLabel.restoredCount, 1);
    await locator<UpdateWalletBehaviorUsecase>().execute(
      walletId: metadataWallet.id,
      hideOnHome: true,
      autoSweepEnabled: true,
    );
    await locator<WalletUtxoRepository>().freezeUtxos(
      walletId: metadataWallet.id,
      outpoints: const [(txId: _smallBackupTxId, vout: _smallBackupVout)],
    );
    final metadataPublish = _unwrap(
      await locator<WalletMetadataBackupFacade>().backupNow(),
    );
    expect(metadataPublish.status, WalletMetadataPublishStatus.stored);
    await locator<KeychainManifestFacade>().backupNow();

    await _resetWithMnemonic(fixtures.lifecycleMnemonicWords);

    expect(await labels.fetchAll(), isEmpty);
    expect(await locator<GetFrozenWalletOutpointsUsecase>().execute(), isEmpty);

    final recovery = await _runRemoteRecovery();
    expect(
      recovery.status,
      anyOf(
        RemoteKeychainRecoveryStatus.restored,
        RemoteKeychainRecoveryStatus.partiallyRestored,
      ),
    );
    expect(recovery.restoredCount, greaterThan(0));

    final recoveredLabels = _unwrap(await labels.exportBip329LabelRecords());
    expect(
      recoveredLabels,
      contains(
        isA<Bip329LabelRecord>()
            .having((label) => label.reference, 'reference', _smallBackupTxId)
            .having((label) => label.label, 'label', expectedLabel.label),
      ),
    );
    final recoveredPreferences = _unwrap(
      await locator<GetWalletPreferencesUsecase>().execute(),
    ).singleWhere((entry) => entry.walletRef == metadataWallet.id);
    expect(recoveredPreferences.hideOnHome, isTrue);
    expect(recoveredPreferences.autoSweepEnabled, isTrue);
    final recoveredFreezes = await locator<GetFrozenWalletOutpointsUsecase>()
        .execute();
    expect(
      recoveredFreezes,
      contains(
        isA<FrozenWalletOutpoint>()
            .having((freeze) => freeze.walletId, 'walletId', metadataWallet.id)
            .having((freeze) => freeze.txId, 'txId', _smallBackupTxId)
            .having((freeze) => freeze.vout, 'vout', _smallBackupVout),
      ),
    );

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

    _unwrap(await locator<WalletMetadataBackupFacade>().setEnabled(false));
    final deletedMetadata = await locator<WalletMetadataBackupFacade>()
        .deleteRemoteBackup();
    expect(deletedMetadata, isA<Ok<void, WalletMetadataBackupFailure>>());
    await locator<KeychainManifestFacade>().deleteRemoteBackup(confirmed: true);

    final deletedManifest = await locator<KeychainManifestFacade>()
        .fetchRemoteImportPlan();
    expect(deletedManifest.status, KeychainManifestRemoteImportStatus.absent);
    final deletedMetadataRecovery = await locator<WalletMetadataBackupFacade>()
        .beginRecoverySession();
    try {
      final result = _unwrap(
        await deletedMetadataRecovery.recover(
          createdWalletRefs: (await locator<WalletRepository>().getWallets())
              .map((wallet) => wallet.id)
              .toSet(),
        ),
      );
      expect(result.status, WalletMetadataRecoveryStatus.noSnapshotFound);
    } finally {
      deletedMetadataRecovery.close();
    }
  }, timeout: const Timeout(Duration(minutes: 6)));

  // TEST 2 — anti-takeover under permanent names. A FRESH owner seed claims the
  // nym; a FRESH attacker seed (which owns no name) then attempts the SAME nym
  // and must be rejected server-side as a name it does not own — not merely
  // "some exception". Using two fresh seeds is essential: reusing a seed that
  // already owns a name would instead fail with "cannot claim a second name".
  test(
    'a second real seed cannot take over a live Bullnym nym',
    () async {
      final nym = fixtures.nymFor(LiveNoPayFixtures.takeoverScenario);

      // Fresh owner claims the nym.
      await _resetWithMnemonic(fixtures.takeoverOwnerMnemonicWords);
      await _assertSeedCanClaim(nym);
      await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);
      final ownerRegistration = await locator<LightningAddressFacade>()
          .registerWalletOwned(nym: nym);
      expect(ownerRegistration.registration.nym, nym);

      // Fresh attacker (owns nothing) attempts the same nym: the server must
      // reject the submission as an already-owned name, non-retryably.
      await _resetWithMnemonic(fixtures.takeoverAttackerMnemonicWords);
      await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);
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
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  // TEST 3 — a clean seed that registers WITHOUT the backup disclosure has no
  // live Bullnym backup to recover. Fresh seed; short nym within the syntax cap.
  test('without backup disclosure, a clean seed has no recoverable Bullnym '
      'backup', () async {
    final nym = fixtures.nymFor(LiveNoPayFixtures.noDisclosureScenario);

    await _resetWithMnemonic(fixtures.cleanMnemonicWords);
    await _assertSeedCanClaim(nym);
    await locator<LightningAddressFacade>().registerWalletOwned(nym: nym);

    await _resetWithMnemonic(fixtures.cleanMnemonicWords);

    final recovery = await _runRemoteRecovery();
    expect(recovery.status, RemoteKeychainRecoveryStatus.noBackup);
  }, timeout: const Timeout(Duration(minutes: 6)));
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
  // Opt-in only (default OFF). Fresh-per-run seeds + the fixtures' static
  // distinctness guard already prevent seed reuse; skipping the network
  // preflight keeps the suite under the server's per-source rate window.
  if (!LiveNoPayFixtures.preflightSeedCheckEnabled) return;

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

Future<RemoteKeychainRecoveryResult> _runRemoteRecovery() async {
  // The staged, relay-consent-gated cubit is gone: recovery is now one
  // synchronous call with no disclosure gate to drive past.
  final defaultWalletIds = (await locator<WalletRepository>().getWallets(
    onlyDefaults: true,
  )).map((wallet) => wallet.id).toSet();
  return locator<RemoteKeychainRecoveryFacade>().recover(
    defaultCreatedWalletIds: defaultWalletIds,
  );
}

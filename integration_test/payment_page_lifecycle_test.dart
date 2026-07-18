import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_activation_cubit.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_activation_state.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/get_paid_fixtures.dart';

// SPEC-PP-01 - the fake-backed Donation Page lifecycle round-trip.
//
// AUTHORED-BUT-CI-ONLY (flagged deviation, same rationale as
// get_paid_backup_roundtrip_test.dart): excluded from the aggregated L1 suite
// (tool/gen_all_test.dart skip set) because the live app-startup timers/blocs
// make an app-process run non-deterministic. The deterministic gates for this
// feature are the L0 usecase/cubit suites; this file is retained for a
// dedicated CI job with a per-test relay-only harness.

const _nym = 'alice';

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  test('create -> backup -> recover restores wallet 102, and the '
      'DG-3 heal classifies the page read-only', () async {
    final bullnym = FakeBullnymClient();
    await locator.unregister<BullnymClientPort>();
    locator.registerLazySingleton<BullnymClientPort>(() => bullnym);
    await ensureFixtureSeed();
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );

    // Register the nym (creates wallet 101) then create the Donation Page
    // (derives + records wallet 102 and saves the page with descriptor + kind).
    await locator<LightningAddressFacade>().registerWalletOwned(nym: _nym);
    final created = await locator<PaymentPageFacade>().save(
      const SavePaymentPageCommand(
        header: 'Tip me',
        description: 'Support my work',
        displayCurrency: 'CAD',
      ),
    );
    expect(created.nym, _nym);
    expect(created.isActive, isTrue);
    // The save signed a non-empty descriptor and kind=payment_page.
    final savedRequest = bullnym.saveDonationPageCalls.single;
    expect(savedRequest.ctDescriptor, isNotEmpty);
    expect(savedRequest.kind, 'payment_page');
    expect(savedRequest.enabled, isTrue);
    final writesAfterCreate = bullnym.totalDonationWriteCalls;

    await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);
    await locator<KeychainManifestFacade>().backupNow();
    final recovered = await locator<RemoteKeychainRecoveryFacade>().recover();
    expect(recovered.status, RemoteKeychainRecoveryStatus.restored);
    expect(recovered.restoredCount, greaterThan(0));
    expect(
      recovered.healOutcome?.paymentPage?.liveness,
      PaymentPageLiveness.live,
    );

    // The DG-3 heal is read-only: recovery must not have written to the page.
    expect(bullnym.totalDonationWriteCalls, writesAfterCreate);

    // Heal matrix via the real facade against the surviving server state.
    bullnym.donationPageMode = FakeDonationPageMode.normal;
    final live = await locator<PaymentPageFacade>().ensurePageLive();
    expect(live.liveness, PaymentPageLiveness.live);

    bullnym.donationPageMode = FakeDonationPageMode.archived;
    final archived = await locator<PaymentPageFacade>().ensurePageLive();
    expect(archived.liveness, PaymentPageLiveness.archivedByUser);

    bullnym.donationPageMode = FakeDonationPageMode.missing;
    final missing = await locator<PaymentPageFacade>().ensurePageLive();
    expect(missing.liveness, PaymentPageLiveness.needsReactivation);

    expect(bullnym.totalDonationWriteCalls, writesAfterCreate);
  });

  test('UF-43: lightning-address deactivation commit with lost response '
      'stays uncertain then reloads inactive authoritatively', () async {
    final bullnym = FakeBullnymClient();
    await locator.unregister<BullnymClientPort>();
    locator.registerLazySingleton<BullnymClientPort>(() => bullnym);
    await ensureFixtureSeed();
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );

    await locator<LightningAddressFacade>().registerWalletOwned(nym: _nym);
    expect(bullnym.registeredNyms, [_nym]);

    final cubit = locator<LightningAddressActivationCubit>();
    addTearDown(cubit.close);

    await cubit.load();
    expect(cubit.state.status, LightningAddressActivationStatus.active);
    expect(cubit.state.nym, _nym);
    expect(cubit.state.hasPermanentNym, isTrue);

    final wallet101Before = await _lightningAddressWallets();
    expect(wallet101Before, hasLength(1));
    final initialWallet = wallet101Before.single;

    bullnym.deleteRegistrationMode =
        FakeDeleteRegistrationMode.commitThenTimeoutOnce;
    await cubit.deactivate();

    expect(bullnym.deleteRegistrationCalls, hasLength(1));
    expect(bullnym.deleteRegistrationCalls.single.nym, _nym);
    expect(bullnym.registeredNyms, [_nym]);
    expect(cubit.state.status, LightningAddressActivationStatus.active);
    expect(
      cubit.state.failure,
      LightningAddressActivationFailure.toggleUncertain,
    );
    expect(cubit.state.onlineSaving, isFalse);

    final wallet101AfterUncertainToggle = await _lightningAddressWallets();
    expect(wallet101AfterUncertainToggle, hasLength(wallet101Before.length));
    expect(wallet101AfterUncertainToggle.single.id, initialWallet.id);
    expect(
      wallet101AfterUncertainToggle.single.externalPublicDescriptor,
      initialWallet.externalPublicDescriptor,
    );

    await cubit.load();

    expect(cubit.state.status, LightningAddressActivationStatus.inactive);
    expect(cubit.state.nym, _nym);
    expect(cubit.state.hasPermanentNym, isTrue);
    expect(cubit.state.registeredAddress, isNull);
    expect(cubit.state.failure, isNull);
    expect(bullnym.deleteRegistrationCalls, hasLength(1));
    expect(bullnym.registeredNyms, [_nym]);

    final wallet101AfterReload = await _lightningAddressWallets();
    expect(wallet101AfterReload, hasLength(wallet101Before.length));
    expect(wallet101AfterReload.single.id, initialWallet.id);
    expect(
      wallet101AfterReload.single.externalPublicDescriptor,
      initialWallet.externalPublicDescriptor,
    );
  });

  test('UF-48: payment-page edit rejected before server mutation keeps the '
      'existing page and wallet 102 authoritative', () async {
    final bullnym = FakeBullnymClient();
    await locator.unregister<BullnymClientPort>();
    locator.registerLazySingleton<BullnymClientPort>(() => bullnym);
    await ensureFixtureSeed();
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );

    await locator<LightningAddressFacade>().registerWalletOwned(nym: _nym);
    final created = await locator<PaymentPageFacade>().save(
      const SavePaymentPageCommand(
        header: 'Tip me',
        description: 'Support my work',
        displayCurrency: 'CAD',
      ),
    );
    expect(created.isActive, isTrue);

    final wallet102Before = await _paymentPageWallets();
    expect(wallet102Before, hasLength(1));
    final initialWallet = wallet102Before.single;
    final initialSave = bullnym.saveDonationPageCalls.single;
    expect(initialSave.ctDescriptor, initialWallet.externalPublicDescriptor);

    bullnym.donationPageMode = FakeDonationPageMode.rejectNextSave;
    try {
      await locator<PaymentPageFacade>().save(
        const SavePaymentPageCommand(
          header: 'Edited header',
          description: 'Edited description',
          displayCurrency: 'USD',
        ),
      );
      fail('Payment Page edit should be rejected by the fake server');
    } on PaymentPageSaveException catch (e) {
      expect(e.phase, PaymentPageSaveFailurePhase.submission);
      expect(e.kind, PaymentPageErrorKind.rejected);
      expect(e.code, 'DonationPageInvalid');
      expect(e.submissionMayBeUncertain, isFalse);
    }
    expect(bullnym.donationPageMode, FakeDonationPageMode.normal);

    expect(bullnym.saveDonationPageCalls, hasLength(2));
    final rejectedSave = bullnym.saveDonationPageCalls.last;
    expect(rejectedSave.header, 'Edited header');
    expect(rejectedSave.description, 'Edited description');
    expect(rejectedSave.displayCurrency, 'USD');
    expect(rejectedSave.ctDescriptor, initialSave.ctDescriptor);
    expect(rejectedSave.kind, 'payment_page');

    final authoritative = await locator<PaymentPageFacade>().find(nym: _nym);
    expect(authoritative, isNotNull);
    expect(authoritative!.header, 'Tip me');
    expect(authoritative.description, 'Support my work');
    expect(authoritative.displayCurrency, 'CAD');
    expect(authoritative.isActive, isTrue);

    final wallet102After = await _paymentPageWallets();
    expect(wallet102After, hasLength(wallet102Before.length));
    expect(wallet102After.single.id, initialWallet.id);
    expect(
      wallet102After.single.externalPublicDescriptor,
      initialWallet.externalPublicDescriptor,
    );
  });
}

Future<List<Wallet>> _lightningAddressWallets() async {
  final wallets = await locator<GetWalletsUsecase>().execute(sync: false);
  return wallets
      .where(
        (wallet) =>
            wallet.label == 'Lightning Address Liquid' &&
            wallet.network.isLiquid &&
            !wallet.isDefault,
      )
      .toList(growable: false);
}

Future<List<Wallet>> _paymentPageWallets() async {
  final wallets = await locator<GetWalletsUsecase>().execute(sync: false);
  return wallets
      .where(
        (wallet) =>
            wallet.label == 'Payment Page Liquid' &&
            wallet.network.isLiquid &&
            !wallet.isDefault,
      )
      .toList(growable: false);
}

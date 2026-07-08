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
Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  late final LiveNoPayFixtures fixtures;

  setUpAll(() {
    fixtures = LiveNoPayFixtures.fromEnvironment();
  });

  test('live Bullnym, Nostr backup, restore, payment page, POS, and invoice '
      'metadata work without executing payments', () async {
    final nym = fixtures.nymFor('');
    await _resetWithMnemonic(fixtures.primaryMnemonicWords);
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

    final invoice = await locator<InvoicesFacade>().create(
      CreateInvoiceCommand(
        amountSat: 25000,
        acceptBtc: true,
        acceptLn: true,
        acceptLiquid: true,
        publicDescription: 'No-pay invoice metadata ${fixtures.runId}',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      ),
    );
    expect(invoice.invoiceId.value, isNotEmpty);
    expect(invoice.shareUrl.value, contains('/invoice/'));

    final invoiceStatus = await locator<InvoicesFacade>().status(
      invoice.invoiceId,
    );
    expect(invoiceStatus.status, InvoiceStatus.unpaid);
    expect(invoiceStatus.acceptBtc, isTrue);
    expect(invoiceStatus.acceptLn, isTrue);
    expect(invoiceStatus.acceptLiquid, isTrue);

    final cancelled = await locator<InvoicesFacade>().cancel(
      CancelInvoiceCommand(invoiceId: invoice.invoiceId),
    );
    expect(cancelled.invoiceId, invoice.invoiceId);
    expect(cancelled.finalStatus, InvoiceStatus.cancelled);

    final defaultWallet = (await locator<WalletRepository>().getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    )).first;
    final manifest = await locator<KeychainManifestFacade>()
        .buildManifestFilePayload(defaultWallet.masterFingerprint);
    expect(manifest.entryCount, greaterThanOrEqualTo(3));

    await _resetWithMnemonic(fixtures.primaryMnemonicWords);

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

  test(
    'a second real seed cannot silently take over a live Bullnym nym',
    () async {
      final secondaryMnemonic = fixtures.secondaryMnemonicWords;

      final nym = fixtures.nymFor('takeover');
      await _resetWithMnemonic(fixtures.primaryMnemonicWords);
      await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
        automatedBackupEnabled: true,
      );
      final primaryRegistration = await locator<LightningAddressFacade>()
          .registerWalletOwned(nym: nym);
      expect(primaryRegistration.registration.nym, nym);

      await _resetWithMnemonic(secondaryMnemonic);
      await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
        automatedBackupEnabled: true,
      );
      await expectLater(
        locator<LightningAddressFacade>().registerWalletOwned(nym: nym),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('without backup disclosure, a clean seed has no recoverable live Nostr '
      'backup', () async {
    final cleanMnemonic = fixtures.cleanMnemonicWords;

    await _resetWithMnemonic(cleanMnemonic);
    await locator<LightningAddressFacade>().registerWalletOwned(
      nym: fixtures.nymFor('nodisclosure'),
    );

    await _resetWithMnemonic(cleanMnemonic);

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

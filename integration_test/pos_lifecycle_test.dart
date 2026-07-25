import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/get_paid_test_harness.dart';
import 'support/integration_test_profile.dart';

// SPEC-POS-01 - the fake-backed Point of Sale lifecycle round-trip.
//
// Runs in the aggregated L1 suite against the deterministic fake Bullnym
// backend. Product lifecycle journeys must not exist only as unaudited files.

const _nym = 'alice';
const _mnemonicWords = <String>[
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'wrong',
];

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await initializeIntegrationTestApp(isInitialized: isInitialized);

  group('fake-backed Point of Sale lifecycle', () {
    late FakeBullnymClient bullnym;

    setUp(() async {
      bullnym = FakeBullnymClient();
      await installFakeBullnymClient(bullnym);
      await wipeGetPaidLocalState();
      await locator<CreateDefaultWalletsUsecase>().execute(
        mnemonicWords: _mnemonicWords,
      );
    });

    tearDown(wipeGetPaidLocalState);

    test(
      'provision -> backup -> recover restores wallet 103, and the '
      'DG-3 heal classifies the POS read-only',
      timeout: const Timeout(Duration(minutes: 1)),
      () async {
        expect(
          await locator<SetWalletBackupEnabledUsecase>().execute(true),
          isA<Ok<void, BackupSettingsFailure>>(),
        );

        // Register the nym (creates wallet 101) then provision the POS (derives +
        // records wallet 103 and saves the row with descriptor + kind=pos).
        await locator<LightningAddressFacade>().registerWalletOwned(nym: _nym);
        final created = await locator<PosFacade>().provision(
          const PosProvisionCommand(label: 'My Till', displayCurrency: 'CAD'),
        );
        expect(created.nym, _nym);
        expect(created.isActive, isTrue);
        expect(created.terminalUrl, endsWith('/$_nym/pos'));
        final savedRequest = bullnym.saveDonationPageCalls.single;
        expect(savedRequest.ctDescriptor, isNotEmpty);
        expect(savedRequest.kind, 'pos');
        expect(savedRequest.enabled, isTrue);
        final writesAfterCreate = bullnym.totalDonationWriteCalls;

        expect(
          await locator<BackupWalletNowUsecase>().execute(),
          isA<Ok<void, BackupSettingsFailure>>(),
        );

        // Simulate a fresh local install while retaining the fake remote backup
        // and POS record.
        await wipeGetPaidLocalState();
        await locator<CreateDefaultWalletsUsecase>().execute(
          mnemonicWords: _mnemonicWords,
        );

        final recovered = await locator<RemoteKeychainRecoveryFacade>()
            .recover();
        expect(recovered.status, RemoteKeychainRecoveryStatus.restored);
        expect(recovered.restoredCount, greaterThan(0));
        final recoveredWallets = await Future.wait(
          recovered.createdWalletIds.map(
            (id) => locator<WalletRepository>().getWallet(id),
          ),
        );
        expect(
          recoveredWallets.any((wallet) => wallet?.label == 'POS Liquid'),
          isTrue,
        );
        final recoveredPos = await locator<PosFacade>().ensurePosLive();
        expect(recoveredPos.liveness, PosLiveness.live);

        // The DG-3 heal is read-only: recovery must not have written to the POS.
        expect(bullnym.totalDonationWriteCalls, writesAfterCreate);

        bullnym.posMode = FakePosMode.normal;
        final live = await locator<PosFacade>().ensurePosLive();
        expect(live.liveness, PosLiveness.live);

        bullnym.posMode = FakePosMode.archived;
        final archived = await locator<PosFacade>().ensurePosLive();
        expect(archived.liveness, PosLiveness.archivedByUser);

        bullnym.posMode = FakePosMode.missing;
        final missing = await locator<PosFacade>().ensurePosLive();
        expect(missing.liveness, PosLiveness.needsReactivation);

        expect(bullnym.totalDonationWriteCalls, writesAfterCreate);
      },
    );

    test('coexistence: a Donation Page (102) and a POS (103) under one nym are '
        'independent - archiving the POS leaves the page untouched', () async {
      await locator<LightningAddressFacade>().registerWalletOwned(nym: _nym);

      // Create the page (102) first, then provision the POS (103).
      final page = await locator<PaymentPageFacade>().save(
        const SavePaymentPageCommand(
          header: 'Tip me',
          description: 'Support my work',
          displayCurrency: 'CAD',
        ),
      );
      expect(page.isActive, isTrue);

      await locator<PosFacade>().provision(
        const PosProvisionCommand(label: 'My Till', displayCurrency: 'CAD'),
      );

      // Both rows coexist and are independently readable.
      final foundPage = await locator<PaymentPageFacade>().find(nym: _nym);
      final foundPos = await locator<PosFacade>().find(nym: _nym);
      expect(foundPage, isNotNull);
      expect(foundPos, isNotNull);
      expect(foundPage!.header, 'Tip me');
      expect(foundPos!.label, 'My Till');
      expect(foundPage.isActive, isTrue);
      expect(foundPos.isActive, isTrue);

      // Archiving the POS leaves the page live and untouched.
      await locator<PosFacade>().archive();
      final pageAfterPosArchive = await locator<PaymentPageFacade>().find(
        nym: _nym,
      );
      expect(pageAfterPosArchive, isNotNull);
      expect(pageAfterPosArchive!.isActive, isTrue);
    });
  });
}

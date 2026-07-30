import 'dart:async';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_failure.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/get_btcpay_wallet_behaviors_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/preview_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/btcpay/ui/screens/btcpay_settings_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCompleteBtcpaySamRockPairingUsecase extends Mock
    implements CompleteBtcpaySamRockPairingUsecase {}

class _MockGetBtcpayConnectionUsecase extends Mock
    implements GetBtcpayConnectionUsecase {}

class _MockPreviewBtcpaySamRockPairingUsecase extends Mock
    implements PreviewBtcpaySamRockPairingUsecase {}

class _MockGetBtcpayWalletBehaviorsUsecase extends Mock
    implements GetBtcpayWalletBehaviorsUsecase {}

class _MockUpdateWalletBehaviorUsecase extends Mock
    implements UpdateWalletBehaviorUsecase {}

const _pairingUrl =
    'https://btcpay.example.com/plugins/store123/samrock/protocol?otp=sensitive-otp&setup=btc,lbtc,btcln';

void main() {
  late _MockCompleteBtcpaySamRockPairingUsecase completePairing;
  late _MockGetBtcpayConnectionUsecase getConnection;
  late _MockGetBtcpayWalletBehaviorsUsecase getWalletBehaviors;
  late _MockPreviewBtcpaySamRockPairingUsecase previewPairing;
  late _MockUpdateWalletBehaviorUsecase updateWalletBehavior;
  late BtcpayPairingCubit cubit;

  setUp(() {
    completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    getConnection = _MockGetBtcpayConnectionUsecase();
    getWalletBehaviors = _MockGetBtcpayWalletBehaviorsUsecase();
    previewPairing = _MockPreviewBtcpaySamRockPairingUsecase();
    updateWalletBehavior = _MockUpdateWalletBehaviorUsecase();
    cubit = BtcpayPairingCubit(
      completePairing: completePairing,
      getConnection: getConnection,
      getWalletBehaviors: getWalletBehaviors,
      previewPairing: previewPairing,
      updateWalletBehavior: updateWalletBehavior,
    );
    when(() => getConnection.execute()).thenAnswer((_) async => const Ok(null));
    when(() => previewPairing.execute(_pairingUrl)).thenReturn(
      const Ok(
        BtcpaySamRockPairingPreview(
          serverUrl: 'https://btcpay.example.com',
          supportsBitcoinChain: true,
          supportsLiquidChain: true,
          supportsLightning: true,
        ),
      ),
    );
  });

  tearDown(() => cubit.close());

  testWidgets('validates first, discloses descriptors, and cancels safely', (
    tester,
  ) async {
    await _pumpScreen(tester, cubit);

    await tester.tap(find.text('Pair BTCPay'));
    await tester.pump();
    expect(find.text('Enter a pairing URL'), findsOneWidget);
    verifyNever(() => previewPairing.execute(any()));
    verifyNever(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    );

    await tester.enterText(find.byType(TextFormField), _pairingUrl);
    await tester.tap(find.text('Pair BTCPay'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    final dialogText = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Text),
          ),
        )
        .map((widget) => widget.data ?? '')
        .join(' ');
    expect(dialogText, contains('watch-only wallet descriptors'));
    expect(dialogText, contains('https://btcpay.example.com'));
    expect(dialogText, contains('Liquid and Bitcoin wallets'));
    expect(dialogText, isNot(contains('sensitive-otp')));
    verifyNever(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);
    verifyNever(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    );
  });

  testWidgets('back dismisses confirmation without pairing', (tester) async {
    await _pumpScreen(tester, cubit);
    await tester.enterText(find.byType(TextFormField), _pairingUrl);
    await tester.tap(find.text('Pair BTCPay'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);
    verifyNever(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    );
  });

  testWidgets('submits only after explicit descriptor consent', (tester) async {
    when(
      () => completePairing.execute(pairingUrl: _pairingUrl),
    ).thenAnswer((_) async => const Err(BtcpayPairingRejectedFailure()));
    await _pumpScreen(tester, cubit);
    await tester.enterText(find.byType(TextFormField), _pairingUrl);
    await tester.tap(find.text('Pair BTCPay'));
    await tester.pumpAndSettle();

    verifyNever(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    );
    await tester.tap(find.text('Pair and share details'));
    await tester.pumpAndSettle();

    verify(() => completePairing.execute(pairingUrl: _pairingUrl)).called(1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('blocks back while a consented submission is in flight', (
    tester,
  ) async {
    final completion = Completer<Result<BtcpayConnection, BtcpayFailure>>();
    when(
      () => completePairing.execute(pairingUrl: _pairingUrl),
    ).thenAnswer((_) => completion.future);
    await _pumpScreen(tester, cubit);
    await tester.enterText(find.byType(TextFormField), _pairingUrl);
    await tester.tap(find.text('Pair BTCPay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pair and share details'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('BTCPay'), findsOneWidget);
    expect(
      find.text('Wait for BTCPay pairing to finish before leaving.'),
      findsOneWidget,
    );
    verify(() => completePairing.execute(pairingUrl: _pairingUrl)).called(1);

    completion.complete(const Err(BtcpayPairingRejectedFailure()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  group('wallet behavior switches', () {
    Future<void> pumpConnected(
      WidgetTester tester, {
      required bool hideOnHome,
      required bool autoSweepEnabled,
    }) async {
      when(
        () => getConnection.execute(),
      ).thenAnswer((_) async => Ok(_connection()));
      when(
        () => getWalletBehaviors.execute(connection: any(named: 'connection')),
      ).thenAnswer(
        (_) async => Ok([
          BtcpayWalletBehavior(
            network: BtcpayWalletNetwork.bitcoin,
            wallet: _wallet(
              hideOnHome: hideOnHome,
              autoSweepEnabled: autoSweepEnabled,
            ),
          ),
        ]),
      );
      await _pumpScreen(tester, cubit);
    }

    testWidgets('hiding is not offered while auto-sweep is off, and says why', (
      tester,
    ) async {
      await pumpConnected(tester, hideOnHome: false, autoSweepEnabled: false);

      expect(_isEnabled(tester, _hideSwitch), isFalse);
      expect(_isEnabled(tester, _sweepSwitch), isTrue);
      expect(
        find.text(
          'Available only while auto-sweep is on: a wallet keeping its funds '
          'stays on your home list.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hiding is offered once auto-sweep is on', (tester) async {
      await pumpConnected(tester, hideOnHome: false, autoSweepEnabled: true);

      expect(_isEnabled(tester, _hideSwitch), isTrue);
      expect(
        find.text(
          'Available only while auto-sweep is on: a wallet keeping its funds '
          'stays on your home list.',
        ),
        findsNothing,
      );
    });

    testWidgets('a hidden wallet can always be unhidden', (tester) async {
      // Only reachable from data written before the rule existed, but the way
      // out must never be blocked.
      when(
        () => updateWalletBehavior.execute(
          walletId: any(named: 'walletId'),
          hideOnHome: any(named: 'hideOnHome'),
          autoSweepEnabled: any(named: 'autoSweepEnabled'),
        ),
      ).thenAnswer((_) async {});
      await pumpConnected(tester, hideOnHome: true, autoSweepEnabled: false);

      expect(_isEnabled(tester, _hideSwitch), isTrue);
      await tester.tap(find.byKey(_hideSwitch));
      await tester.pumpAndSettle();

      verify(
        () => updateWalletBehavior.execute(
          walletId: 'btcpay-btc',
          hideOnHome: false,
        ),
      ).called(1);
    });
  });

  testWidgets(
    'initial read error shows unavailable and retry, never the pairing form',
    (tester) async {
      var reads = 0;
      when(() => getConnection.execute()).thenAnswer((_) async {
        reads++;
        return reads == 1
            ? const Err<BtcpayConnection?, BtcpayFailure>(
                BtcpayStorageFailure(),
              )
            : const Ok<BtcpayConnection?, BtcpayFailure>(null);
      });

      await _pumpScreen(tester, cubit);

      expect(find.text('BTCPay settings unavailable'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Pair BTCPay'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(reads, 2);
      expect(find.byType(TextFormField), findsOneWidget);
    },
  );

  testWidgets('wallet behavior read error is visible and retryable', (
    tester,
  ) async {
    var reads = 0;
    when(
      () => getConnection.execute(),
    ).thenAnswer((_) async => Ok(_connection()));
    when(
      () => getWalletBehaviors.execute(connection: any(named: 'connection')),
    ).thenAnswer((_) async {
      reads++;
      return reads == 1
          ? const Err<List<BtcpayWalletBehavior>, BtcpayFailure>(
              BtcpayStorageFailure(),
            )
          : const Ok<List<BtcpayWalletBehavior>, BtcpayFailure>([]);
    });

    await _pumpScreen(tester, cubit);

    expect(
      find.text(
        'Could not load wallet settings. Retry before changing wallet behavior.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(_hideSwitch), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(reads, 2);
    expect(
      find.text(
        'Could not load wallet settings. Retry before changing wallet behavior.',
      ),
      findsNothing,
    );
    expect(find.text('Connected BTCPay Server'), findsOneWidget);
  });
}

const _hideSwitch = Key('btcpay_hide_on_home_switch_btcpay-btc');
const _sweepSwitch = Key('btcpay_auto_sweep_switch_btcpay-btc');

bool _isEnabled(WidgetTester tester, Key key) =>
    tester.widget<SwitchListTile>(find.byKey(key)).onChanged != null;

BtcpayConnection _connection() {
  return BtcpayConnection.tryCreate(
    environment: Environment.mainnet,
    serverUrl: 'https://btcpay.example.com',
    storeId: 'store123',
    capabilities: const [SamRockSetupCapability.bitcoinChain],
    walletNetworks: const [BtcpayWalletNetwork.bitcoin],
    status: BtcpayConnectionStatus.paired,
    pairedAt: DateTime.utc(2026, 5, 23),
    updatedAt: DateTime.utc(2026, 5, 23),
  )!;
}

Wallet _wallet({required bool hideOnHome, required bool autoSweepEnabled}) {
  return Wallet(
    origin: 'btcpay-btc',
    label: 'BTCPay Bitcoin',
    network: Network.bitcoinMainnet,
    isDefault: false,
    masterFingerprint: 'fingerprint',
    xpubFingerprint: 'xpub-fingerprint',
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: 'external-desc',
    internalPublicDescriptor: 'internal-desc',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
    hideOnHome: hideOnHome,
    autoSweepEnabled: autoSweepEnabled,
  );
}

Future<void> _pumpScreen(WidgetTester tester, BtcpayPairingCubit cubit) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider.value(
        value: cubit,
        child: const BtcpaySettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

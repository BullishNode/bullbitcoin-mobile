import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_activation_cubit.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_activation_state.dart';
import 'package:bb_mobile/features/lightning_address/ui/screens/lightning_address_activation_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../fiat_settlement/support/testnet_fiat_settlement_dependencies.dart';

void main() {
  String? copiedText;

  setUp(() {
    registerTestnetFiatSettlementDependencies();
    copiedText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await locator.reset();
  });

  testWidgets('keeps wallet settings unavailability visibly stated', (
    tester,
  ) async {
    final cubit = await _pump(
      tester,
      const LightningAddressActivationState(
        status: LightningAddressActivationStatus.unsupported,
        walletBehaviorUnavailable: true,
      ),
    );

    expect(
      find.byKey(const Key('get_paid_wallet_behavior_unavailable_warning')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Wallet settings are temporarily unavailable. '
        'Try again.',
      ),
      findsOneWidget,
    );
    final priorLoads = cubit.loadCalls;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(cubit.loadCalls, priorLoads);
    expect(cubit.retryWalletBehaviorCalls, 1);
  });

  testWidgets('old-server state hides every name and availability control', (
    tester,
  ) async {
    await _pump(
      tester,
      const LightningAddressActivationState(
        status: LightningAddressActivationStatus.unsupported,
      ),
    );

    expect(find.text('Permanent names unavailable'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(
      find.byKey(const Key('lightning_address_online_switch')),
      findsNothing,
    );
  });

  testWidgets('first claim shows one input, the owner copy, and no dialog', (
    tester,
  ) async {
    await _pump(
      tester,
      const LightningAddressActivationState(
        status: LightningAddressActivationStatus.idle,
        permanentNamesSupported: true,
      ),
    );

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Claim your Bull Nym'), findsOneWidget);
    expect(
      find.text(
        'This is a permanent anonymous identity linked to your Bitcoin wallet '
        'and will become your public Lightning Address.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Claim your nym'));
    await tester.tap(find.text('Claim your nym'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'connection failure uses Lightning Address language and retries',
    (tester) async {
      final cubit = await _pump(
        tester,
        const LightningAddressActivationState(
          status: LightningAddressActivationStatus.failure,
          failure: LightningAddressActivationFailure.capabilityUnavailable,
        ),
      );

      expect(find.text('Lightning Address unavailable'), findsOneWidget);
      expect(
        find.text(
          'Your Lightning Address could not be loaded. '
          'Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('permanent-name support'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(cubit.loadCalls, 2);
    },
  );

  testWidgets('active nym shows its address and hides secondary metadata', (
    tester,
  ) async {
    await _pump(tester, _ownedState(online: true));

    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Lightning address is active'), findsOneWidget);
    expect(find.text('alice@pay2.bull-wallet.com'), findsOneWidget);
    expect(find.text('Name'), findsNothing);
    expect(
      find.text('This lifetime name is permanent and read-only.'),
      findsNothing,
    );
    expect(find.text('Advanced settings'), findsOneWidget);
    expect(
      find.byKey(const Key('lightning_address_online_switch')),
      findsNothing,
    );
  });

  testWidgets('inactive nym retains the same server-owned address', (
    tester,
  ) async {
    await _pump(tester, _ownedState(online: false));

    expect(find.text('Lightning Address is inactive'), findsOneWidget);
    expect(find.text('alice@pay2.bull-wallet.com'), findsOneWidget);
    expect(find.text('Name'), findsNothing);
    expect(find.text('Advanced settings'), findsOneWidget);
  });

  testWidgets(
    'address tap opens QR and copy actions without explorer actions',
    (tester) async {
      await _pump(tester, _ownedState(online: true));

      await tester.tap(find.byKey(const Key('lightning_address_tile')));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Tap to copy'), findsOneWidget);
      expect(find.text('Copy Link'), findsNothing);
      expect(find.text('View in Explorer'), findsNothing);

      await tester.tap(find.text('Tap to copy'));
      await tester.pumpAndSettle();
      expect(copiedText, 'alice@pay2.bull-wallet.com');
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('long press copies the Lightning Address', (tester) async {
    await _pump(tester, _ownedState(online: true));

    await tester.longPress(find.byKey(const Key('lightning_address_tile')));
    await tester.pump();

    expect(copiedText, 'alice@pay2.bull-wallet.com');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('missing lookup address is explicit and reloadable', (
    tester,
  ) async {
    final cubit = await _pump(
      tester,
      const LightningAddressActivationState(
        status: LightningAddressActivationStatus.addressUnavailable,
        nym: 'alice',
        permanentNamesSupported: true,
        hasPermanentNym: true,
      ),
    );

    expect(
      find.text('The server did not return your Lightning Address. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Lightning address is active'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(cubit.loadCalls, 2);
  });

  testWidgets('turning off confirms first and says the other products stay', (
    tester,
  ) async {
    final cubit = await _pump(tester, _ownedState(online: true));

    await _tapOnlineSwitch(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Turn off Lightning Address?'), findsOneWidget);
    expect(
      find.text(
        'People will no longer be able to send funds to your Lightning '
        'Address. Your permanent names remain claimed, and your Donation Page '
        'and Point of Sale stay online and keep accepting payments.',
      ),
      findsOneWidget,
    );
    // Nothing is deactivated until the merchant confirms.
    expect(cubit.deactivateCalls, 0);

    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(cubit.deactivateCalls, 1);
  });

  testWidgets('cancelling the turn-off confirmation leaves it on', (
    tester,
  ) async {
    final cubit = await _pump(tester, _ownedState(online: true));

    await _tapOnlineSwitch(tester);
    await tester.tap(find.text('Keep online'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(cubit.deactivateCalls, 0);
    final switchTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('lightning_address_online_switch')),
    );
    expect(switchTile.value, isTrue);
  });

  testWidgets('turning on reuses the owned nym without another confirmation', (
    tester,
  ) async {
    final cubit = await _pump(tester, _ownedState(online: false));

    await _tapOnlineSwitch(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(cubit.activateExistingCalls, 1);
  });

  testWidgets(
    'a claim the server never answered says so and retries the claim',
    (tester) async {
      final cubit = await _pump(
        tester,
        const LightningAddressActivationState(
          status: LightningAddressActivationStatus.failure,
          failure: LightningAddressActivationFailure.noServerResponse,
          nym: 'alice',
          permanentNamesSupported: true,
        ),
      );

      expect(find.text('The server did not respond'), findsOneWidget);
      expect(
        find.textContaining('nothing was claimed and nothing changed'),
        findsOneWidget,
      );
      // Not the half-known outcome story, and not a status re-read: a retry.
      expect(find.text('Status Unknown'), findsNothing);
      expect(find.text('Check Status'), findsNothing);

      await tester.tap(
        find.byKey(const Key('lightning_address_server_outcome_action')),
      );
      await tester.pumpAndSettle();

      expect(cubit.submitCalls, 1);
      expect(cubit.loadCalls, 1); // only the initial load on mount
    },
  );
}

/// Opens Advanced Settings and flips the availability switch inside it.
Future<void> _tapOnlineSwitch(WidgetTester tester) async {
  await tester.tap(find.text('Advanced settings'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const Key('lightning_address_online_switch')),
  );
  await tester.tap(find.byKey(const Key('lightning_address_online_switch')));
  await tester.pumpAndSettle();
}

LightningAddressActivationState _ownedState({required bool online}) {
  return LightningAddressActivationState(
    status: online
        ? LightningAddressActivationStatus.active
        : LightningAddressActivationStatus.inactive,
    nym: 'alice',
    registeredAddress: 'alice@pay2.bull-wallet.com',
    permanentNamesSupported: true,
    hasPermanentNym: true,
    permanentNameQuota: const LightningAddressPermanentNameQuota(
      used: 1,
      cap: 1,
      remaining: 0,
    ),
  );
}

Future<_StubCubit> _pump(
  WidgetTester tester,
  LightningAddressActivationState state,
) async {
  final cubit = _StubCubit(state);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<LightningAddressActivationCubit>.value(
        value: cubit,
        child: const LightningAddressActivationScreen(),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

class _StubCubit extends Cubit<LightningAddressActivationState>
    implements LightningAddressActivationCubit {
  _StubCubit(super.initialState);

  int activateExistingCalls = 0;
  int deactivateCalls = 0;
  int loadCalls = 0;
  int retryWalletBehaviorCalls = 0;
  int submitCalls = 0;

  @override
  Future<void> load() async {
    loadCalls += 1;
  }

  @override
  Future<void> retryWalletBehavior() async {
    retryWalletBehaviorCalls += 1;
  }

  @override
  void nymChanged(String value) {}

  @override
  void showRegistrationForm() {}

  @override
  LightningAddressActivationFailure? validateNym(String value) => null;

  @override
  Future<void> submit() async {
    submitCalls += 1;
  }

  @override
  Future<void> activateExisting() async {
    activateExistingCalls += 1;
  }

  @override
  Future<void> deactivate() async {
    deactivateCalls += 1;
  }

  @override
  Future<void> updateWalletBehavior({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {}
}

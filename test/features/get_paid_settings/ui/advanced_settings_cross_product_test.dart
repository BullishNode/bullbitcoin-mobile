import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/get_paid_settings/ui/get_paid_advanced_settings_sheet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_activation_cubit.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_activation_state.dart';
import 'package:bb_mobile/features/lightning_address/ui/screens/lightning_address_activation_screen.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_state.dart';
import 'package:bb_mobile/features/payment_page/ui/screens/payment_page_editor_screen.dart';
import 'package:bb_mobile/features/pos/domain/pos_terminal.dart';
import 'package:bb_mobile/features/pos/presentation/pos_cubit.dart';
import 'package:bb_mobile/features/pos/presentation/pos_state.dart';
import 'package:bb_mobile/features/pos/ui/screens/pos_provisioning_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three Get Paid products (Lightning Address, Donation Page, POS) must
/// each expose the SAME Advanced Settings surface — turn on/off + Auto-Sweep +
/// Hide-on-Home — driven by the one shared widget, with the wallet-behavior
/// toggles targeting that product's own manifest-resolved reserved wallet.
void main() {
  Future<void> harness(WidgetTester tester, Widget child, Cubit cubit) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: child,
      ),
    );
    await tester.pump();
  }

  void expectIdenticalSheet() {
    expect(find.byType(GetPaidAdvancedSettingsSheet), findsOneWidget);
    // The exact same three controls, every time.
    expect(find.byType(SwitchListTile), findsNWidgets(3));
    expect(find.text('Auto-sweep'), findsOneWidget);
    expect(find.text('Hide on home'), findsOneWidget);
  }

  testWidgets('Lightning Address surfaces the shared sheet for wallet 101', (
    tester,
  ) async {
    final cubit = _LaCubit(
      _laState(GetPaidWalletProduct.lightningAddress, 'w-101'),
    );
    await harness(
      tester,
      BlocProvider<LightningAddressActivationCubit>.value(
        value: cubit,
        child: const LightningAddressActivationScreen(),
      ),
      cubit,
    );

    await tester.tap(find.text('Advanced settings'));
    await tester.pumpAndSettle();
    expectIdenticalSheet();

    await tester.ensureVisible(find.text('Auto-sweep'));
    await tester.tap(find.text('Auto-sweep'));
    await tester.pumpAndSettle();
    expect(cubit.behaviorWrites, ['w-101']);
  });

  testWidgets('Donation Page surfaces the shared sheet for wallet 102', (
    tester,
  ) async {
    final cubit = _PageCubit(
      _pageState(GetPaidWalletProduct.paymentPage, 'w-102'),
    );
    await harness(
      tester,
      BlocProvider<PaymentPageCubit>.value(
        value: cubit,
        child: const PaymentPageEditorScreen(),
      ),
      cubit,
    );

    await tester.tap(
      find.byKey(const Key('payment_page_advanced_settings_button')),
    );
    await tester.pumpAndSettle();
    expectIdenticalSheet();

    await tester.ensureVisible(find.text('Auto-sweep'));
    await tester.tap(find.text('Auto-sweep'));
    await tester.pumpAndSettle();
    expect(cubit.behaviorWrites, ['w-102']);
  });

  testWidgets('Point of Sale surfaces the shared sheet for wallet 103', (
    tester,
  ) async {
    final cubit = _PosCubit(_posState(GetPaidWalletProduct.pos, 'w-103'));
    await harness(
      tester,
      BlocProvider<PosCubit>.value(
        value: cubit,
        child: const PosProvisioningScreen(),
      ),
      cubit,
    );

    await tester.tap(find.byKey(const Key('pos_advanced_settings_button')));
    await tester.pumpAndSettle();
    expectIdenticalSheet();

    await tester.ensureVisible(find.text('Auto-sweep'));
    await tester.tap(find.text('Auto-sweep'));
    await tester.pumpAndSettle();
    expect(cubit.behaviorWrites, ['w-103']);
  });
}

GetPaidWalletBehavior _behavior(
  GetPaidWalletProduct product,
  String walletId,
) => GetPaidWalletBehavior(
  product: product,
  walletId: walletId,
  hideOnHome: false,
  autoSweepEnabled: false,
);

LightningAddressActivationState _laState(
  GetPaidWalletProduct product,
  String walletId,
) => LightningAddressActivationState(
  status: LightningAddressActivationStatus.active,
  nym: 'alice',
  registeredAddress: 'alice@pay2.bull-wallet.com',
  permanentNamesSupported: true,
  hasPermanentNym: true,
  permanentNameQuota: const LightningAddressPermanentNameQuota(
    used: 1,
    cap: 1,
    remaining: 0,
  ),
  walletBehavior: _behavior(product, walletId),
);

PaymentPageState _pageState(GetPaidWalletProduct product, String walletId) =>
    PaymentPageState(
      status: PaymentPageStatus.edit,
      permanentAlias: 'alice',
      page: const PaymentPage(
        nym: 'alice',
        header: 'Header',
        description: 'Description',
        displayCurrency: 'CAD',
        enabled: true,
        isArchived: false,
        alias: 'alice',
        publicUrl: 'https://pay2.bull-wallet.com/alice',
      ),
      header: 'Header',
      description: 'Description',
      displayCurrency: 'CAD',
      walletBehavior: _behavior(product, walletId),
    );

PosState _posState(GetPaidWalletProduct product, String walletId) => PosState(
  status: PosStatus.edit,
  permanentAlias: 'alice',
  terminal: const PosTerminal(
    nym: 'alice',
    label: 'Shop',
    displayCurrency: 'CAD',
    enabled: true,
    isArchived: false,
    alias: 'alice',
    terminalUrl: 'https://pay2.bull-wallet.com/pos/alice',
  ),
  label: 'Shop',
  displayCurrency: 'CAD',
  walletBehavior: _behavior(product, walletId),
);

class _LaCubit extends Cubit<LightningAddressActivationState>
    implements LightningAddressActivationCubit {
  _LaCubit(super.initialState);
  final List<String> behaviorWrites = [];

  @override
  Future<void> load() async {}
  @override
  void nymChanged(String value) {}
  @override
  void showRegistrationForm() {}
  @override
  LightningAddressActivationFailure? validateNym(String value) => null;
  @override
  Future<void> submit() async {}
  @override
  Future<void> activateExisting() async {}
  @override
  Future<void> deactivate() async {}
  @override
  Future<void> updateWalletBehavior({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {
    behaviorWrites.add(walletId);
  }
}

class _PageCubit extends Cubit<PaymentPageState> implements PaymentPageCubit {
  _PageCubit(super.initialState);
  final List<String> behaviorWrites = [];

  @override
  Future<void> load() async {}
  @override
  Future<void> save() async {}
  @override
  Future<void> setOnline(bool online) async {}
  @override
  Future<void> archive() async {}
  @override
  Future<void> retryCurrencies() async {}
  @override
  void aliasDraftChanged(String value) {}
  @override
  void headerChanged(String value) {}
  @override
  void descriptionChanged(String value) {}
  @override
  void displayCurrencyChanged(String value) {}
  @override
  void websiteChanged(String value) {}
  @override
  void twitterChanged(String value) {}
  @override
  void instagramChanged(String value) {}
  @override
  Future<void> updateWalletBehavior({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {
    behaviorWrites.add(walletId);
  }
}

class _PosCubit extends Cubit<PosState> implements PosCubit {
  _PosCubit(super.initialState);
  final List<String> behaviorWrites = [];

  @override
  Future<void> load() async {}
  @override
  Future<void> provision() async {}
  @override
  Future<void> setOnline(bool online) async {}
  @override
  Future<void> archive() async {}
  @override
  Future<void> retryCurrencies() async {}
  @override
  void aliasDraftChanged(String value) {}
  @override
  void labelChanged(String value) {}
  @override
  void displayCurrencyChanged(String value) {}
  @override
  Future<void> updateWalletBehavior({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {
    behaviorWrites.add(walletId);
  }
}

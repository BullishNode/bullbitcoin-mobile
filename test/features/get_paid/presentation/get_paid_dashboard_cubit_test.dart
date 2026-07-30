import 'dart:async';

import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/automatic_fallback/public/automatic_fallback_facade.dart';
import 'package:bb_mobile/features/btcpay/public/btcpay_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/ensure_get_paid_automatic_fallback_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/ensure_get_paid_product_wallet_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_pos_terminal_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_get_paid_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_get_paid_fiat_settlement_summary_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_paid_fallback_attention_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_lightning_registration_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/load_get_paid_invoices_overview_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/load_get_paid_product_overview_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWallets extends Mock implements GetWalletsUsecase {}

class _MockWallet extends Mock implements Wallet {}

class _MockFallbackAttention extends Mock
    implements GetPaidFallbackAttentionUsecase {}

class _MockFiatFacade extends Mock implements FiatSettlementFacade {}

class _MockEnsureProductWallet extends Mock
    implements EnsureGetPaidProductWalletUsecase {}

class _MockGetSettings extends Mock implements GetSettingsUsecase {}

class _MockSettings extends Mock implements SettingsEntity {}

FiatSettlementConfigurationView _fiatView(
  FiatSettlementProduct product,
  int pct, {
  FiatCurrency? currency,
}) {
  return FiatSettlementConfigurationView(
    products: [
      FiatSettlementProductConfig(
        product: product,
        fiatPercentage: pct,
        currency: currency,
      ),
    ],
    credentialActive: true,
  );
}

// The public facades are callback-injected, so the tests wire real facade
// instances to plain closures — no mocking framework needed. Each facade then
// goes through the Get Paid use case the cubit actually depends on, so these
// tests exercise the real wrapping (the cubit never sees a foreign facade).

LightningAddressFacade _laFacade(
  Future<LightningAddressStatus> Function() lookup,
) {
  return LightningAddressFacade(
    prepareWallet: () async => throw UnimplementedError(),
    lookupRegistration: ({required String npubHex}) async =>
        throw UnimplementedError(),
    registerWalletOwned: ({required String nym}) async =>
        throw UnimplementedError(),
    lookupWalletOwnedRegistration: lookup,
    ensureRegistrationLive:
        ({DateTime? deadline, bool allowReregister = true}) async =>
            throw UnimplementedError(),
  );
}

PaymentPageFacade _pageFacade(
  Future<PaymentPage?> Function({required String nym}) find,
) {
  return PaymentPageFacade(
    find: find,
    save: (command) async => throw UnimplementedError(),
    archive: () async => throw UnimplementedError(),
    supportedCurrencies: () async => throw UnimplementedError(),
    ensurePageLive: () async => throw UnimplementedError(),
    prepareWallet: () async => throw UnimplementedError(),
  );
}

PosFacade _posFacade(
  Future<PosTerminal?> Function({required String nym}) find,
) {
  return PosFacade(
    find: find,
    provision: (command) async => throw UnimplementedError(),
    archive: () async => throw UnimplementedError(),
    supportedCurrencies: () async => throw UnimplementedError(),
    ensurePosLive: () async => throw UnimplementedError(),
    prepareWallet: () async => throw UnimplementedError(),
  );
}

BtcpayFacade _btcpayFacade(
  Future<Result<BtcpayConnection?, BtcpayFailure>> Function() connection,
) {
  return BtcpayFacade(connection: connection);
}

EnsureGetPaidAutomaticFallbackUsecase _fallbackUsecase(
  Future<Result<AutomaticFallbackSetup, AutomaticFallbackFailure>> Function()
  ensure,
) {
  return EnsureGetPaidAutomaticFallbackUsecase(
    automaticFallback: AutomaticFallbackFacade(ensureReady: ensure),
  );
}

Future<Result<AutomaticFallbackSetup, AutomaticFallbackFailure>>
_fallbackReady() async {
  return Ok(
    AutomaticFallbackSetup(
      btcAddress: 'bc1qfallbackaddress',
      commitmentVersion: 1,
      signedAtUnix: 1_700_000_000,
      registeredNow: false,
    ),
  );
}

LightningAddressStatus _status({
  bool active = false,
  String nym = 'satoshi',
  String? address,
}) {
  return LightningAddressStatus(
    nym: nym,
    active: active,
    lightningAddress: address,
  );
}

PaymentPage _page({bool enabled = true, bool archived = false}) {
  return PaymentPage(
    nym: 'satoshi',
    header: 'Donate',
    description: 'desc',
    displayCurrency: 'USD',
    enabled: enabled,
    isArchived: archived,
    publicUrl: 'https://pay.example/satoshi',
  );
}

PosTerminal _pos({bool enabled = true, bool archived = false}) {
  return PosTerminal(
    nym: 'satoshi',
    label: 'Till',
    displayCurrency: 'USD',
    enabled: enabled,
    isArchived: archived,
    terminalUrl: 'https://pos.example/satoshi/pos',
  );
}

BtcpayConnection _connection() {
  return BtcpayConnection.tryCreate(
    environment: Environment.mainnet,
    serverUrl: 'https://btcpay.example',
    storeId: 'store',
    capabilities: const [SamRockSetupCapability.bitcoinChain],
    walletNetworks: const [BtcpayWalletNetwork.bitcoin],
    status: BtcpayConnectionStatus.paired,
    pairedAt: DateTime.utc(2024),
    updatedAt: DateTime.utc(2024),
  )!;
}

GetWalletsUsecase _getWallets({bool hasDefaultWallet = false}) {
  final usecase = _MockGetWallets();
  when(
    () => usecase.execute(
      onlyDefaults: any(named: 'onlyDefaults'),
      onlyBitcoin: any(named: 'onlyBitcoin'),
      onlyLiquid: any(named: 'onlyLiquid'),
      sync: any(named: 'sync'),
    ),
  ).thenAnswer((_) async => hasDefaultWallet ? [_MockWallet()] : <Wallet>[]);
  return usecase;
}

GetPaidDashboardCubit _cubit({
  Future<LightningAddressStatus> Function()? lookup,
  Future<PaymentPage?> Function({required String nym})? pageFind,
  Future<PosTerminal?> Function({required String nym})? posFind,
  Future<Result<BtcpayConnection?, BtcpayFailure>> Function()? connection,
  Future<Result<AutomaticFallbackSetup, AutomaticFallbackFailure>> Function()?
  ensureFallback,
  bool hasDefaultWallet = false,
  int? fallbackAttentionCount = 0,
  Future<GetPaidFallbackAttentionResult> Function()? fallbackAttentionLookup,
  Future<Result<FiatSettlementConfigurationView, FiatSettlementFailure>>
  Function()?
  fiatConfiguration,
  Environment environment = Environment.mainnet,
  Future<GetPaidProductWalletOutcome> Function(GetPaidWalletBackedProduct)?
  productWalletHeal,
}) {
  final fallbackAttention = _MockFallbackAttention();
  when(() => fallbackAttention.execute()).thenAnswer(
    (_) async => fallbackAttentionLookup != null
        ? fallbackAttentionLookup()
        : fallbackAttentionCount == null
        ? const GetPaidFallbackAttentionUnavailable()
        : GetPaidFallbackAttentionKnown(fallbackAttentionCount),
  );

  // The product-wallet self-heal defaults to a no-op "present" outcome.
  final ensureProductWallet = _MockEnsureProductWallet();
  when(() => ensureProductWallet.execute(any())).thenAnswer(
    (invocation) async => productWalletHeal == null
        ? GetPaidProductWalletOutcome.present
        : productWalletHeal(
            invocation.positionalArguments.first as GetPaidWalletBackedProduct,
          ),
  );

  // The settlement summary is a REQUIRED dependency: a test that does not opt in
  // gets one on testnet, where the use case itself reports that settlement does
  // not apply — the same empty outcome, without a nullable dependency.
  final fiatFacade = _MockFiatFacade();
  when(() => fiatFacade.configuration()).thenAnswer(
    (_) =>
        fiatConfiguration?.call() ??
        Future.value(const Err(FiatSettlementFailure.bullnymUnreachable())),
  );
  final settings = _MockSettings();
  when(
    () => settings.environment,
  ).thenReturn(fiatConfiguration == null ? Environment.testnet : environment);
  final settingsUsecase = _MockGetSettings();
  when(() => settingsUsecase.execute()).thenAnswer((_) async => settings);
  final fiatSettlementSummary = GetGetPaidFiatSettlementSummaryUsecase(
    fiatSettlement: fiatFacade,
    getSettings: settingsUsecase,
  );

  return GetPaidDashboardCubit(
    loadProductOverview: LoadGetPaidProductOverviewUsecase(
      lookUpRegistration: LookUpGetPaidLightningRegistrationUsecase(
        lightningAddress: _laFacade(lookup ?? () async => _status()),
      ),
      findPaymentPage: FindGetPaidPaymentPageUsecase(
        paymentPage: _pageFacade(
          pageFind ?? ({required String nym}) async => null,
        ),
      ),
      findPos: FindGetPaidPosTerminalUsecase(
        pos: _posFacade(posFind ?? ({required String nym}) async => null),
      ),
      ensureAutomaticFallback: _fallbackUsecase(
        ensureFallback ?? _fallbackReady,
      ),
      ensureProductWallet: ensureProductWallet,
    ),
    getBtcpayConnection: GetGetPaidBtcpayConnectionUsecase(
      btcpay: _btcpayFacade(
        connection ??
            () async => const Ok<BtcpayConnection?, BtcpayFailure>(null),
      ),
    ),
    loadInvoicesOverview: LoadGetPaidInvoicesOverviewUsecase(
      getWallets: _getWallets(hasDefaultWallet: hasDefaultWallet),
      fallbackAttention: fallbackAttention,
    ),
    fiatSettlementSummary: fiatSettlementSummary,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(GetPaidWalletBackedProduct.lightningAddress);
  });

  test('all products unset after refresh', () async {
    final cubit = _cubit();

    await cubit.refresh();

    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.hasLightningAddress, isFalse);
    expect(cubit.state.paymentPage, isNull);
    expect(cubit.state.posTerminal, isNull);
    expect(cubit.state.btcpayConnection, isNull);
    expect(cubit.state.error, isNull);
    await cubit.close();
  });

  test('unclaimed nym is an empty dashboard state, not an error', () async {
    var pageProbed = false;
    var posProbed = false;
    final cubit = _cubit(
      lookup: () async =>
          throw const LightningAddressServerRejectedRequestException(
            code: 'NymNotFound',
            retryable: false,
          ),
      pageFind: ({required String nym}) async {
        pageProbed = true;
        return null;
      },
      posFind: ({required String nym}) async {
        posProbed = true;
        return null;
      },
    );

    await cubit.refresh();

    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.error, isNull);
    expect(cubit.state.nym, isNull);
    expect(cubit.state.hasLightningAddress, isFalse);
    // UX-2: a confirmed empty account is ABSENT for all three products (never a
    // guessed "active" and never "unavailable"); the manifest creates no card.
    expect(cubit.state.lightningStatus, GetPaidProductStatus.absent);
    expect(cubit.state.paymentPageStatus, GetPaidProductStatus.absent);
    expect(cubit.state.posStatus, GetPaidProductStatus.absent);
    expect(pageProbed, isFalse);
    expect(posProbed, isFalse);
    await cubit.close();
  });

  test(
    'independent cards resolve without waiting for Lightning lookup',
    () async {
      final registration = Completer<LightningAddressStatus>();
      final cubit = _cubit(
        lookup: () => registration.future,
        connection: () async =>
            Ok<BtcpayConnection?, BtcpayFailure>(_connection()),
        hasDefaultWallet: true,
      );

      final refresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.lightningStatus, GetPaidProductStatus.loading);
      expect(cubit.state.invoicesStatus, GetPaidDashboardCardStatus.loaded);
      expect(cubit.state.btcpayStatus, GetPaidDashboardCardStatus.loaded);
      expect(cubit.state.invoicesWalletReady, isTrue);
      expect(cubit.state.hasBtcpayConnection, isTrue);

      registration.complete(_status(nym: ''));
      await refresh;
      await cubit.close();
    },
  );

  test(
    'Point of Sale can resolve while Donation Page is still loading',
    () async {
      final page = Completer<PaymentPage?>();
      final posResolved = Completer<void>();
      final cubit = _cubit(
        pageFind: ({required String nym}) => page.future,
        posFind: ({required String nym}) async {
          posResolved.complete();
          return _pos();
        },
      );

      final refresh = cubit.refresh();
      await posResolved.future;
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.posStatus, GetPaidProductStatus.active);
      expect(cubit.state.hasPos, isTrue);
      expect(cubit.state.paymentPageStatus, GetPaidProductStatus.loading);

      page.complete(null);
      await refresh;
      await cubit.close();
    },
  );

  test('Page and POS queries run concurrently: both dispatch before either '
      'resolves, and POS updates while Page is still loading (Q10)', () async {
    final pageGate = Completer<PaymentPage?>();
    final posGate = Completer<PosTerminal?>();
    var pageCalled = false;
    var posCalled = false;
    final cubit = _cubit(
      lookup: () async => _status(active: true, address: 'a@b'),
      pageFind: ({required String nym}) {
        pageCalled = true;
        return pageGate.future;
      },
      posFind: ({required String nym}) {
        posCalled = true;
        return posGate.future;
      },
    );

    final refresh = cubit.refresh();
    await Future<void>.delayed(Duration.zero);

    // Both queries are in flight together — POS did not wait for Page.
    expect(pageCalled, isTrue);
    expect(posCalled, isTrue);
    expect(cubit.state.paymentPageStatus, GetPaidProductStatus.loading);
    expect(cubit.state.posStatus, GetPaidProductStatus.loading);

    // Resolve POS FIRST; its card updates while Page is still loading.
    posGate.complete(_pos());
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.posStatus, GetPaidProductStatus.active);
    expect(cubit.state.paymentPageStatus, GetPaidProductStatus.loading);

    pageGate.complete(_page());
    await refresh;
    await cubit.close();
  });

  test('active Lightning Address populates address + nym', () async {
    final cubit = _cubit(
      lookup: () async => _status(active: true, address: 'satoshi@bull.money'),
    );

    await cubit.refresh();

    expect(cubit.state.hasLightningAddress, isTrue);
    expect(cubit.state.lightningAddress, 'satoshi@bull.money');
    expect(cubit.state.lightningActive, isTrue);
    expect(cubit.state.nym, 'satoshi');
    await cubit.close();
  });

  test('inactive registration keeps the address but is not active', () async {
    final cubit = _cubit(
      lookup: () async => _status(active: false, address: 'satoshi@bull.money'),
    );

    await cubit.refresh();

    expect(cubit.state.lightningAddress, 'satoshi@bull.money');
    expect(cubit.state.lightningActive, isFalse);
    await cubit.close();
  });

  test('invoices tile is ready when a default wallet exists', () async {
    final cubit = _cubit(hasDefaultWallet: true);

    await cubit.refresh();

    expect(cubit.state.invoicesWalletReady, isTrue);
    await cubit.close();
  });

  test(
    'invoices tile carries the read-only fallback attention count',
    () async {
      final cubit = _cubit(hasDefaultWallet: true, fallbackAttentionCount: 2);

      await cubit.refresh();

      expect(cubit.state.fallbackAttentionCount, 2);
      expect(cubit.state.hasFallbackAttention, isTrue);
      await cubit.close();
    },
  );

  test(
    'an unavailable refresh clears stale invoice readiness and count',
    () async {
      var available = true;
      final cubit = _cubit(
        hasDefaultWallet: true,
        fallbackAttentionLookup: () async => available
            ? const GetPaidFallbackAttentionKnown(2)
            : const GetPaidFallbackAttentionUnavailable(),
      );

      await cubit.refresh();
      expect(cubit.state.fallbackAttentionCount, 2);
      expect(cubit.state.invoicesWalletReady, isTrue);

      available = false;
      await cubit.refresh();

      expect(cubit.state.invoicesUnavailable, isTrue);
      expect(cubit.state.fallbackAttentionCount, isNull);
      expect(cubit.state.invoicesWalletReady, isFalse);
      await cubit.close();
    },
  );

  test('invoices tile is not ready without a default wallet', () async {
    final cubit = _cubit();

    await cubit.refresh();

    expect(cubit.state.invoicesWalletReady, isFalse);
    await cubit.close();
  });

  test('published Donation Page is active', () async {
    final cubit = _cubit(
      lookup: () async => _status(active: true, address: 'satoshi@bull.money'),
      pageFind: ({required String nym}) async => _page(enabled: true),
    );

    await cubit.refresh();

    expect(cubit.state.hasPaymentPage, isTrue);
    expect(cubit.state.paymentPage!.publicUrl, isNotEmpty);
    await cubit.close();
  });

  test('unpublished Donation Page is present but disabled', () async {
    final cubit = _cubit(
      lookup: () async => _status(active: true, address: 'satoshi@bull.money'),
      pageFind: ({required String nym}) async => _page(enabled: false),
    );

    await cubit.refresh();

    expect(cubit.state.paymentPage, isNotNull);
    expect(cubit.state.paymentPage!.publicUrl, isNotEmpty);
    await cubit.close();
  });

  test('archived Donation Page is a distinct archived state (UX-2), not '
      'unset', () async {
    final cubit = _cubit(
      lookup: () async => _status(active: true, address: 'satoshi@bull.money'),
      pageFind: ({required String nym}) async => _page(archived: true),
    );

    await cubit.refresh();

    // UX-2: archived is its own status-only state — the object is kept for the
    // card, and it is NOT active (no green/settlement affordances).
    expect(cubit.state.paymentPageStatus, GetPaidProductStatus.archived);
    expect(cubit.state.paymentPage, isNotNull);
    expect(cubit.state.hasPaymentPage, isFalse);
    await cubit.close();
  });

  group('UX-2 product truth', () {
    test('a Lightning Address lookup failure leaves ALL three products '
        'unavailable, never absent', () async {
      final cubit = _cubit(lookup: () async => throw Exception('boom'));

      await cubit.refresh();

      expect(cubit.state.lightningStatus, GetPaidProductStatus.unavailable);
      expect(cubit.state.paymentPageStatus, GetPaidProductStatus.unavailable);
      expect(cubit.state.posStatus, GetPaidProductStatus.unavailable);
      await cubit.close();
    });

    test(
      'a Donation Page lookup failure is unavailable, never absent',
      () async {
        final cubit = _cubit(
          lookup: () async => _status(active: true, address: 'a@b'),
          pageFind: ({required String nym}) async => throw Exception('boom'),
        );

        await cubit.refresh();

        expect(cubit.state.paymentPageStatus, GetPaidProductStatus.unavailable);
        await cubit.close();
      },
    );

    test('a confirmed-absent product stays absent (the manifest never '
        'promotes it to a card)', () async {
      final cubit = _cubit(
        lookup: () async => _status(active: true, address: 'a@b'),
        pageFind: ({required String nym}) async => null,
        posFind: ({required String nym}) async => null,
      );

      await cubit.refresh();

      expect(cubit.state.paymentPageStatus, GetPaidProductStatus.absent);
      expect(cubit.state.posStatus, GetPaidProductStatus.absent);
      await cubit.close();
    });

    test('every refresh re-queries every product (no cache)', () async {
      var lookups = 0;
      var pageFinds = 0;
      var posFinds = 0;
      final cubit = _cubit(
        lookup: () async {
          lookups++;
          return _status(active: true, address: 'a@b');
        },
        pageFind: ({required String nym}) async {
          pageFinds++;
          return _page();
        },
        posFind: ({required String nym}) async {
          posFinds++;
          return _pos();
        },
      );

      await cubit.refresh();
      await cubit.refresh();

      expect(lookups, 2);
      expect(pageFinds, 2);
      expect(posFinds, 2);
      await cubit.close();
    });

    test('an active product with a missing wallet is re-derived, and no '
        'warning is raised on success', () async {
      final healed = <GetPaidWalletBackedProduct>[];
      final cubit = _cubit(
        lookup: () async => _status(active: true, address: 'a@b'),
        posFind: ({required String nym}) async => _pos(),
        productWalletHeal: (product) async {
          healed.add(product);
          return GetPaidProductWalletOutcome.rederived;
        },
      );

      await cubit.refresh();

      expect(healed, contains(GetPaidWalletBackedProduct.pos));
      expect(cubit.state.posWalletWarning, isFalse);
      await cubit.close();
    });

    test(
      'a re-derivation failure raises the product missing-wallet warning',
      () async {
        final cubit = _cubit(
          lookup: () async => _status(active: true, address: 'a@b'),
          posFind: ({required String nym}) async => _pos(),
          productWalletHeal: (product) async =>
              product == GetPaidWalletBackedProduct.pos
              ? GetPaidProductWalletOutcome.failed
              : GetPaidProductWalletOutcome.present,
        );

        await cubit.refresh();

        expect(cubit.state.posWalletWarning, isTrue);
        await cubit.close();
      },
    );

    test('archived and absent products are NOT self-healed', () async {
      final healed = <GetPaidWalletBackedProduct>[];
      final cubit = _cubit(
        // Inactive Lightning Address (present but not active) => not healed.
        lookup: () async => _status(active: false, address: 'a@b'),
        pageFind: ({required String nym}) async => _page(archived: true),
        posFind: ({required String nym}) async => null,
        productWalletHeal: (product) async {
          healed.add(product);
          return GetPaidProductWalletOutcome.present;
        },
      );

      await cubit.refresh();

      expect(healed, isEmpty);
      expect(cubit.state.paymentPageWalletWarning, isFalse);
      await cubit.close();
    });

    test('a late product response never overwrites a newer refresh', () async {
      final gate = Completer<PaymentPage?>();
      final reachedGate = Completer<void>();
      final healed = <GetPaidWalletBackedProduct>[];
      var fallbackCalls = 0;
      var calls = 0;
      final cubit = _cubit(
        lookup: () async => _status(active: true, address: 'a@b'),
        pageFind: ({required String nym}) {
          calls++;
          if (calls == 1) {
            // Generation 1 reaches the page query and then hangs.
            reachedGate.complete();
            return gate.future;
          }
          // Generation 2 resolves immediately as archived.
          return Future.value(_page(archived: true));
        },
        ensureFallback: () async {
          fallbackCalls++;
          return _fallbackReady();
        },
        productWalletHeal: (product) async {
          healed.add(product);
          return GetPaidProductWalletOutcome.present;
        },
      );

      final first = cubit.refresh(); // generation 1 — page pending
      await reachedGate.future; // gen 1 is now awaiting the page query
      await cubit.refresh(); // generation 2 — page archived
      expect(healed, [
        GetPaidWalletBackedProduct.lightningAddress,
        GetPaidWalletBackedProduct.lightningAddress,
      ]);
      expect(fallbackCalls, 2);

      // The stale generation-1 read now resolves as a live (active) page.
      gate.complete(_page());
      await first;

      // The newer refresh wins. Work admitted while generation 1 was current
      // may finish, but its late Page result cannot publish or trigger healing.
      expect(cubit.state.paymentPageStatus, GetPaidProductStatus.archived);
      expect(healed, [
        GetPaidWalletBackedProduct.lightningAddress,
        GetPaidWalletBackedProduct.lightningAddress,
      ]);
      expect(fallbackCalls, 2);
      await cubit.close();
    });
  });

  test('active Point of Sale populates the terminal', () async {
    final cubit = _cubit(
      lookup: () async => _status(active: true, address: 'satoshi@bull.money'),
      posFind: ({required String nym}) async => _pos(enabled: true),
    );

    await cubit.refresh();

    expect(cubit.state.hasPos, isTrue);
    expect(cubit.state.posTerminal!.terminalUrl, isNotEmpty);
    await cubit.close();
  });

  test('paired BTCPay connection is exposed', () async {
    final cubit = _cubit(
      connection: () async =>
          Ok<BtcpayConnection?, BtcpayFailure>(_connection()),
    );

    await cubit.refresh();

    expect(cubit.state.hasBtcpayConnection, isTrue);
    expect(cubit.state.btcpayConnection!.serverUrl, 'https://btcpay.example');
    await cubit.close();
  });

  test('a typed BTCPay failure preserves the partial dashboard', () async {
    final cubit = _cubit(
      lookup: () async => _status(active: true, address: 'satoshi@bull.money'),
      connection: () async =>
          const Err(BtcpayStorageFailure('fixture failure')),
    );

    await cubit.refresh();

    expect(cubit.state.hasLightningAddress, isTrue);
    expect(cubit.state.btcpayConnection, isNull);
    expect(cubit.state.error, isNotNull);
    await cubit.close();
  });

  test('nym-keyed products are not probed without a nym', () async {
    var pageProbed = false;
    var posProbed = false;
    var fallbackProbed = false;
    final cubit = _cubit(
      lookup: () async => _status(nym: '', active: false),
      ensureFallback: () async {
        fallbackProbed = true;
        return _fallbackReady();
      },
      pageFind: ({required String nym}) async {
        pageProbed = true;
        return null;
      },
      posFind: ({required String nym}) async {
        posProbed = true;
        return null;
      },
    );

    await cubit.refresh();

    expect(pageProbed, isFalse);
    expect(posProbed, isFalse);
    expect(fallbackProbed, isFalse);
    expect(cubit.state.nym, isNull);
    await cubit.close();
  });

  test('wallet-owned nym triggers automatic fallback setup once', () async {
    var calls = 0;
    final cubit = _cubit(
      ensureFallback: () async {
        calls++;
        return _fallbackReady();
      },
    );

    await cubit.refresh();

    expect(calls, 1);
    expect(cubit.state.error, isNull);
    await cubit.close();
  });

  test('fallback failure preserves other Get Paid product reads', () async {
    var pageProbed = false;
    var posProbed = false;
    final cubit = _cubit(
      lookup: () async => _status(active: true, address: 'satoshi@bull.money'),
      ensureFallback: () async => const Err(
        AutomaticFallbackFailure.remoteLookupFailed(
          code: 'NetworkError',
          retryable: true,
        ),
      ),
      pageFind: ({required String nym}) async {
        pageProbed = true;
        return _page();
      },
      posFind: ({required String nym}) async {
        posProbed = true;
        return _pos();
      },
    );

    await cubit.refresh();

    expect(cubit.state.hasLightningAddress, isTrue);
    expect(cubit.state.hasPaymentPage, isTrue);
    expect(cubit.state.hasPos, isTrue);
    expect(pageProbed, isTrue);
    expect(posProbed, isTrue);
    expect(cubit.state.error, isNotNull);
    await cubit.close();
  });

  test('a facade failure surfaces an error and stops loading', () async {
    final cubit = _cubit(lookup: () async => throw Exception('boom'));

    await cubit.refresh();

    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.error, isNotNull);
    await cubit.close();
  });

  test('refresh clears a prior error on success', () async {
    var shouldThrow = true;
    final cubit = _cubit(
      lookup: () async {
        if (shouldThrow) throw Exception('boom');
        return _status(active: true, address: 'satoshi@bull.money');
      },
    );

    await cubit.refresh();
    expect(cubit.state.error, isNotNull);

    shouldThrow = false;
    await cubit.refresh();

    expect(cubit.state.error, isNull);
    expect(cubit.state.hasLightningAddress, isTrue);
    await cubit.close();
  });

  test(
    'a confirmed fiat-settlement read populates the per-product config',
    () async {
      final cubit = _cubit(
        fiatConfiguration: () async => Ok(
          _fiatView(
            FiatSettlementProduct.paymentPage,
            50,
            currency: FiatCurrency.cad,
          ),
        ),
      );

      await cubit.refresh();

      final config = cubit
          .state
          .fiatSettlement?[GetPaidDashboardSettlementProduct.paymentPage];
      expect(config?.fiatPercentage, 50);
      expect(config?.currencyCode, 'CAD');
      expect(cubit.state.fiatSettlementUnavailable, isFalse);
      await cubit.close();
    },
  );

  test('a fiat-settlement read failure is unavailable, never Bitcoin-only, and '
      'does not fail the dashboard', () async {
    final cubit = _cubit(
      fiatConfiguration: () async =>
          const Err(FiatSettlementFailure.bullnymUnreachable()),
    );

    await cubit.refresh();

    // No config map (so no card can render a guessed Bitcoin-only), the
    // unavailable flag is set, and the rest of the dashboard still succeeds.
    expect(cubit.state.fiatSettlement, isNull);
    expect(cubit.state.fiatSettlementUnavailable, isTrue);
    expect(cubit.state.error, isNull);
    expect(cubit.state.isLoading, isFalse);
    await cubit.close();
  });

  test('a non-mainnet environment shows no settlement state', () async {
    final cubit = _cubit(
      environment: Environment.testnet,
      fiatConfiguration: () async =>
          Ok(_fiatView(FiatSettlementProduct.paymentPage, 100)),
    );

    await cubit.refresh();

    expect(cubit.state.fiatSettlement, isNull);
    expect(cubit.state.fiatSettlementUnavailable, isFalse);
    await cubit.close();
  });

  test(
    'a late fiat-settlement response never overwrites a newer refresh',
    () async {
      final gate =
          Completer<
            Result<FiatSettlementConfigurationView, FiatSettlementFailure>
          >();
      var calls = 0;
      final cubit = _cubit(
        fiatConfiguration: () {
          calls++;
          // Gen 1 hangs; gen 2 resolves immediately with a different config.
          return calls == 1
              ? gate.future
              : Future.value(
                  Ok(_fiatView(FiatSettlementProduct.paymentPage, 100)),
                );
        },
      );

      final first = cubit.refresh(); // generation 1 — fiat read pending
      await cubit.refresh(); // generation 2 — resolves with fiatPercentage 100

      // The stale generation-1 read now resolves with a DIFFERENT value.
      gate.complete(Ok(_fiatView(FiatSettlementProduct.paymentPage, 25)));
      await first;

      // The newer refresh wins; the late gen-1 response is dropped by the guard.
      expect(
        cubit
            .state
            .fiatSettlement?[GetPaidDashboardSettlementProduct.paymentPage]
            ?.fiatPercentage,
        100,
      );
      await cubit.close();
    },
  );
}

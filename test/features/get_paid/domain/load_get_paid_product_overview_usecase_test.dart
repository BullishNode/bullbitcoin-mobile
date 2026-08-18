import 'package:bb_mobile/features/get_paid/domain/ensure_get_paid_automatic_fallback_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/ensure_get_paid_product_wallet_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/find_get_paid_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/find_get_paid_pos_terminal_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_product_probe.dart';
import 'package:bb_mobile/features/get_paid/domain/load_get_paid_product_overview_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/look_up_get_paid_lightning_registration_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'coordinates identity, product probes, fallback and active wallet heals',
    () async {
      final registration = _Registration(
        const GetPaidLightningRegistration(
          nym: 'alice',
          address: 'alice@example.com',
          active: true,
        ),
      );
      final page = _Page(
        const GetPaidProductFound(
          GetPaidPaymentPageSnapshot(
            publicUrl: 'https://pay.example/alice',
            isArchived: false,
          ),
        ),
      );
      final pos = _Pos(
        const GetPaidProductFound(
          GetPaidPosTerminalSnapshot(
            terminalUrl: 'https://pos.example/alice',
            isArchived: true,
          ),
        ),
      );
      final fallback = _Fallback(true);
      final wallets = _Wallets();
      final usecase = LoadGetPaidProductOverviewUsecase(
        lookUpRegistration: registration,
        findPaymentPage: page,
        findPos: pos,
        ensureAutomaticFallback: fallback,
        ensureProductWallet: wallets,
      );

      final events = await usecase.execute(isCurrent: () => true).toList();

      expect(events.whereType<GetPaidRegistrationResolved>(), hasLength(1));
      expect(events.whereType<GetPaidPaymentPageResolved>(), hasLength(1));
      expect(events.whereType<GetPaidPosResolved>(), hasLength(1));
      expect(
        events.whereType<GetPaidAutomaticFallbackResolved>(),
        hasLength(1),
      );
      expect(
        wallets.products,
        containsAll([
          GetPaidWalletBackedProduct.lightningAddress,
          GetPaidWalletBackedProduct.paymentPage,
        ]),
      );
      expect(wallets.products, isNot(contains(GetPaidWalletBackedProduct.pos)));
      expect(page.nyms, ['alice']);
      expect(pos.nyms, ['alice']);
    },
  );

  test(
    'an unknown registration does not guess or invoke dependent work',
    () async {
      final page = _Page(const GetPaidProductAbsent());
      final pos = _Pos(const GetPaidProductAbsent());
      final fallback = _Fallback(true);
      final wallets = _Wallets();
      final usecase = LoadGetPaidProductOverviewUsecase(
        lookUpRegistration: _Registration(null),
        findPaymentPage: page,
        findPos: pos,
        ensureAutomaticFallback: fallback,
        ensureProductWallet: wallets,
      );

      final events = await usecase.execute(isCurrent: () => true).toList();

      expect(events, [isA<GetPaidRegistrationUnavailable>()]);
      expect(page.nyms, isEmpty);
      expect(pos.nyms, isEmpty);
      expect(fallback.calls, 0);
      expect(wallets.products, isEmpty);
    },
  );

  test('a fallback exception preserves resolved product truth', () async {
    final usecase = LoadGetPaidProductOverviewUsecase(
      lookUpRegistration: _Registration(
        const GetPaidLightningRegistration(
          nym: 'alice',
          address: 'alice@example.com',
          active: true,
        ),
      ),
      findPaymentPage: _Page(const GetPaidProductAbsent()),
      findPos: _Pos(const GetPaidProductAbsent()),
      ensureAutomaticFallback: _ThrowingFallback(),
      ensureProductWallet: _Wallets(),
    );

    final events = await usecase.execute(isCurrent: () => true).toList();

    expect(events.whereType<GetPaidRegistrationResolved>(), hasLength(1));
    expect(events.whereType<GetPaidPaymentPageResolved>(), hasLength(1));
    expect(events.whereType<GetPaidPosResolved>(), hasLength(1));
    expect(
      events.whereType<GetPaidAutomaticFallbackResolved>().single.ready,
      isFalse,
    );
    expect(events.whereType<GetPaidProductOverviewUnavailable>(), isEmpty);
  });
}

class _Registration implements LookUpGetPaidLightningRegistrationUsecase {
  final GetPaidLightningRegistration? value;
  _Registration(this.value);

  @override
  Future<GetPaidLightningRegistration?> execute() async => value;
}

class _Page implements FindGetPaidPaymentPageUsecase {
  final GetPaidProductProbe<GetPaidPaymentPageSnapshot> value;
  final List<String> nyms = [];
  _Page(this.value);

  @override
  Future<GetPaidProductProbe<GetPaidPaymentPageSnapshot>> execute({
    required String nym,
  }) async {
    nyms.add(nym);
    return value;
  }
}

class _Pos implements FindGetPaidPosTerminalUsecase {
  final GetPaidProductProbe<GetPaidPosTerminalSnapshot> value;
  final List<String> nyms = [];
  _Pos(this.value);

  @override
  Future<GetPaidProductProbe<GetPaidPosTerminalSnapshot>> execute({
    required String nym,
  }) async {
    nyms.add(nym);
    return value;
  }
}

class _Fallback implements EnsureGetPaidAutomaticFallbackUsecase {
  final bool value;
  int calls = 0;
  _Fallback(this.value);

  @override
  Future<bool> execute() async {
    calls++;
    return value;
  }
}

class _ThrowingFallback implements EnsureGetPaidAutomaticFallbackUsecase {
  @override
  Future<bool> execute() => throw Exception('fallback unavailable');
}

class _Wallets implements EnsureGetPaidProductWalletUsecase {
  final List<GetPaidWalletBackedProduct> products = [];

  @override
  Future<GetPaidProductWalletOutcome> execute(
    GetPaidWalletBackedProduct product,
  ) async {
    products.add(product);
    return GetPaidProductWalletOutcome.present;
  }
}

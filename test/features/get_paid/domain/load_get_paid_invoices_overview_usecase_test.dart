import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_fallback_attention_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/load_get_paid_invoices_overview_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _GetWallets extends Mock implements GetWalletsUsecase {}

class _Wallet extends Mock implements Wallet {}

void main() {
  late _GetWallets getWallets;

  setUp(() {
    getWallets = _GetWallets();
  });

  test(
    'a confirmed missing default wallet is known, not unavailable',
    () async {
      when(
        () => getWallets.execute(onlyDefaults: true),
      ).thenAnswer((_) async => <Wallet>[]);
      final fallback = _Fallback(const GetPaidFallbackAttentionKnown(2));
      final usecase = LoadGetPaidInvoicesOverviewUsecase(
        getWallets: getWallets,
        fallbackAttention: fallback,
      );

      final result = await usecase.execute();

      expect(result, isA<GetPaidInvoicesOverviewKnown>());
      final known = result as GetPaidInvoicesOverviewKnown;
      expect(known.walletReady, isFalse);
      expect(known.fallbackAttentionCount, isNull);
      expect(fallback.calls, 0);
    },
  );

  test(
    'returns supervision count only after wallet readiness is known',
    () async {
      when(
        () => getWallets.execute(onlyDefaults: true),
      ).thenAnswer((_) async => [_Wallet()]);
      final usecase = LoadGetPaidInvoicesOverviewUsecase(
        getWallets: getWallets,
        fallbackAttention: _Fallback(const GetPaidFallbackAttentionKnown(2)),
      );

      final result = await usecase.execute() as GetPaidInvoicesOverviewKnown;

      expect(result.walletReady, isTrue);
      expect(result.fallbackAttentionCount, 2);
    },
  );

  test('does not turn an unavailable read into no attention', () async {
    when(
      () => getWallets.execute(onlyDefaults: true),
    ).thenAnswer((_) async => [_Wallet()]);
    final usecase = LoadGetPaidInvoicesOverviewUsecase(
      getWallets: getWallets,
      fallbackAttention: _Fallback(const GetPaidFallbackAttentionUnavailable()),
    );

    expect(await usecase.execute(), isA<GetPaidInvoicesOverviewUnavailable>());
  });

  test('programming errors remain visible', () async {
    when(
      () => getWallets.execute(onlyDefaults: true),
    ).thenThrow(StateError('bug'));
    final usecase = LoadGetPaidInvoicesOverviewUsecase(
      getWallets: getWallets,
      fallbackAttention: _Fallback(const GetPaidFallbackAttentionKnown(0)),
    );

    expect(usecase.execute, throwsA(isA<StateError>()));
  });
}

class _Fallback implements GetPaidFallbackAttentionUsecase {
  final GetPaidFallbackAttentionResult value;
  int calls = 0;
  _Fallback(this.value);

  @override
  Future<GetPaidFallbackAttentionResult> execute() async {
    calls++;
    return value;
  }
}

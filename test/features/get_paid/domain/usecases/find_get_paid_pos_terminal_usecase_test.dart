import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_pos_terminal_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_product_probe.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a POS terminal into the facts owned by Get Paid', () async {
    final usecase = FindGetPaidPosTerminalUsecase(
      pos: _facade(
        ({required nym}) async => PosTerminal(
          nym: nym,
          label: 'Till',
          displayCurrency: 'CAD',
          enabled: true,
          isArchived: true,
          terminalUrl: 'https://pos.example/$nym',
        ),
      ),
    );

    final result = await usecase.execute(nym: 'alice');

    expect(result, isA<GetPaidProductFound<GetPaidPosTerminalSnapshot>>());
    final snapshot =
        (result as GetPaidProductFound<GetPaidPosTerminalSnapshot>).row;
    expect(snapshot.terminalUrl, 'https://pos.example/alice');
    expect(snapshot.isArchived, isTrue);
  });

  test('keeps confirmed absence distinct from an unavailable read', () async {
    final absent = FindGetPaidPosTerminalUsecase(
      pos: _facade(({required nym}) async => null),
    );
    final unavailable = FindGetPaidPosTerminalUsecase(
      pos: _facade(({required nym}) async => throw Exception('down')),
    );

    expect(
      await absent.execute(nym: 'alice'),
      isA<GetPaidProductAbsent<GetPaidPosTerminalSnapshot>>(),
    );
    expect(
      await unavailable.execute(nym: 'alice'),
      isA<GetPaidProductUnavailable<GetPaidPosTerminalSnapshot>>(),
    );
  });
}

PosFacade _facade(Future<PosTerminal?> Function({required String nym}) find) =>
    PosFacade(
      find: find,
      provision: (command) async => throw UnimplementedError(),
      archive: () async => throw UnimplementedError(),
      supportedCurrencies: () async => throw UnimplementedError(),
      ensurePosLive: () async => throw UnimplementedError(),
      prepareWallet: () async => throw UnimplementedError(),
    );

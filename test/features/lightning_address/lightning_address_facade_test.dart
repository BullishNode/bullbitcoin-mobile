import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayServicePort extends Mock implements PayServicePort {}

void main() {
  late _MockPayServicePort payService;
  late LightningAddressFacade facade;

  setUp(() {
    payService = _MockPayServicePort();

    facade = LightningAddressFacade(payService: payService);
  });

  test('reads current address from pay service', () async {
    when(
      () => payService.getStoredAddress(),
    ).thenAnswer((_) async => 'alice@bullpay.ca');

    expect(await facade.getCurrentLightningAddress(), 'alice@bullpay.ca');
    verify(() => payService.getStoredAddress()).called(1);
  });
}

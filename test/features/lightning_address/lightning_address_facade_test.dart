import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/recover_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRecoverLightningAddressUsecase extends Mock
    implements RecoverLightningAddressUsecase {}

class _MockPayServicePort extends Mock implements PayServicePort {}

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
  });

  late _MockRecoverLightningAddressUsecase recover;
  late _MockPayServicePort payService;
  late LightningAddressFacade facade;

  setUp(() {
    recover = _MockRecoverLightningAddressUsecase();
    payService = _MockPayServicePort();

    facade = LightningAddressFacade(recover: recover, payService: payService);
  });

  test(
    'Lightning Address recovery remains Lightning Address specific',
    () async {
      when(
        () => recover.execute(environment: any(named: 'environment')),
      ).thenAnswer((_) async => 'alice@bullpay.ca');

      final address = await facade.recoverIfNeeded(
        environment: Environment.mainnet,
      );

      expect(address, 'alice@bullpay.ca');
      verify(() => recover.execute(environment: Environment.mainnet)).called(1);
      verifyNoMoreInteractions(recover);
    },
  );

  test('reads current address and nym from pay service', () async {
    when(
      () => payService.getStoredAddress(),
    ).thenAnswer((_) async => 'alice@bullpay.ca');

    expect(await facade.getCurrentLightningAddress(), 'alice@bullpay.ca');
    expect(await facade.getCurrentNym(), 'alice');
    verify(() => payService.getStoredAddress()).called(2);
  });
}

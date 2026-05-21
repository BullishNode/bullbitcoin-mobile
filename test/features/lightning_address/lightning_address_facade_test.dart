import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_status_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayServicePort extends Mock implements PayServicePort {}

class _MockLookupStatus extends Mock
    implements LookupLightningAddressStatusUsecase {}

void main() {
  late _MockPayServicePort payService;
  late _MockLookupStatus lookupStatus;
  late LightningAddressFacade facade;

  setUp(() {
    payService = _MockPayServicePort();
    lookupStatus = _MockLookupStatus();
    when(() => payService.storeAddress(any())).thenAnswer((_) async {});
    when(() => payService.clearStoredAddress()).thenAnswer((_) async {});

    facade = LightningAddressFacade(
      payService: payService,
      lookupStatus: lookupStatus,
    );
  });

  test('returns active server-owned address and refreshes cache', () async {
    when(
      () => payService.getStoredAddress(),
    ).thenAnswer((_) async => 'old@bullpay.ca');
    when(() => lookupStatus.execute()).thenAnswer(
      (_) async => const ActiveLookupResult(
        nym: 'alice',
        quota: NymQuota(used: 1, cap: 3),
        previousNyms: [],
      ),
    );

    expect(await facade.getCurrentLightningAddress(), 'alice@bullpay.ca');
    verify(() => payService.storeAddress('alice@bullpay.ca')).called(1);
  });

  test(
    'clears stale cached address when auth npub has no active nym',
    () async {
      when(
        () => payService.getStoredAddress(),
      ).thenAnswer((_) async => 'old@bullpay.ca');
      when(() => lookupStatus.execute()).thenAnswer((_) async => null);

      expect(await facade.getCurrentLightningAddress(), isNull);
      verify(() => payService.clearStoredAddress()).called(1);
    },
  );

  test(
    'falls back to cache only when lookup has a transient failure',
    () async {
      when(
        () => payService.getStoredAddress(),
      ).thenAnswer((_) async => 'alice@bullpay.ca');
      when(
        () => lookupStatus.execute(),
      ).thenThrow(PayServiceException('offline'));

      expect(await facade.getCurrentLightningAddress(), 'alice@bullpay.ca');
    },
  );
}

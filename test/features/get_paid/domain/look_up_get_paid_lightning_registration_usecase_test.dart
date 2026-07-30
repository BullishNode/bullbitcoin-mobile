import 'package:bb_mobile/features/get_paid/domain/look_up_get_paid_lightning_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the wallet-owned registration into Get Paid facts', () async {
    final usecase = LookUpGetPaidLightningRegistrationUsecase(
      lightningAddress: _facade(
        () async => const LightningAddressStatus(
          nym: 'alice',
          active: true,
          lightningAddress: 'alice@example.com',
        ),
      ),
    );

    final registration = await usecase.execute();

    expect(registration?.nym, 'alice');
    expect(registration?.address, 'alice@example.com');
    expect(registration?.active, isTrue);
  });

  test(
    'distinguishes confirmed empty registration from an unknown read',
    () async {
      final absent = LookUpGetPaidLightningRegistrationUsecase(
        lightningAddress: _facade(
          () async =>
              throw const LightningAddressServerRejectedRequestException(
                code: 'NymNotFound',
                retryable: false,
              ),
        ),
      );
      final unavailable = LookUpGetPaidLightningRegistrationUsecase(
        lightningAddress: _facade(() async => throw Exception('down')),
      );

      final empty = await absent.execute();
      expect(empty, isNotNull);
      expect(empty?.nym, isNull);
      expect(await unavailable.execute(), isNull);
    },
  );
}

LightningAddressFacade _facade(
  Future<LightningAddressStatus> Function() lookup,
) => LightningAddressFacade(
  prepareWallet: () async => throw UnimplementedError(),
  lookupRegistration: ({required npubHex}) async => throw UnimplementedError(),
  registerWalletOwned: ({required nym}) async => throw UnimplementedError(),
  lookupWalletOwnedRegistration: lookup,
  ensureRegistrationLive: ({deadline, allowReregister = true}) async =>
      throw UnimplementedError(),
);

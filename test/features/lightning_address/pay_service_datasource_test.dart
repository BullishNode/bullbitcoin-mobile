import 'dart:io';

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/pay_service_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockBullnymClient extends Mock implements BullnymClient {}

void main() {
  late Directory hiveDir;
  late _MockBullnymClient bullnymClient;
  late PayServiceDatasource datasource;
  late NostrKeychainHandle handle;

  setUpAll(() {
    registerFallbackValue(NostrKeychainHandle.fromSecretKeyHex('01' * 32));
  });

  setUp(() {
    hiveDir = Directory.systemTemp.createTempSync(
      'pay_service_datasource_test',
    );
    Hive.init(hiveDir.path);
    bullnymClient = _MockBullnymClient();
    datasource = PayServiceDatasource(bullnymClient: bullnymClient);
    handle = NostrKeychainHandle.fromSecretKeyHex('02' * 32);
  });

  tearDown(() async {
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  test('register delegates to Bullnym and stores returned address', () async {
    when(
      () => bullnymClient.register(
        handle: any(named: 'handle'),
        nym: any(named: 'nym'),
        ctDescriptor: any(named: 'ctDescriptor'),
        verificationNpubHex: any(named: 'verificationNpubHex'),
      ),
    ).thenAnswer(
      (_) async => const BullnymRegisterResponseDto(
        nym: 'alice',
        lightningAddress: 'alice@bullpay.ca',
        nip05: 'alice@bullpay.ca',
        quota: BullnymQuotaDto(used: 1, cap: 3, remaining: 2),
      ),
    );

    final result = await datasource.register(
      nym: 'alice',
      ctDescriptor: 'ct(elwpkh(...))',
      authHandle: handle,
      verificationNpubHex: '03' * 32,
    );

    expect(result.address, 'alice@bullpay.ca');
    expect(result.quota.used, 1);
    expect(result.quota.cap, 3);
    expect(await datasource.getStoredAddress(), 'alice@bullpay.ca');
  });

  test(
    'register maps unavailable nym errors to the normal UX message',
    () async {
      when(
        () => bullnymClient.register(
          handle: any(named: 'handle'),
          nym: any(named: 'nym'),
          ctDescriptor: any(named: 'ctDescriptor'),
          verificationNpubHex: any(named: 'verificationNpubHex'),
        ),
      ).thenThrow(
        const BullnymException(code: 'NymReserved', reason: 'reserved nym'),
      );

      await expectLater(
        datasource.register(
          nym: 'admin',
          ctDescriptor: 'ct(elwpkh(...))',
          authHandle: handle,
          verificationNpubHex: '03' * 32,
        ),
        throwsA(
          isA<PayServiceException>().having(
            (e) => e.message,
            'message',
            'This nym is not available',
          ),
        ),
      );
    },
  );

  test('lookup maps active Bullnym registration', () async {
    when(
      () => bullnymClient.lookupRegistration(npubHex: any(named: 'npubHex')),
    ).thenAnswer(
      (_) async => BullnymLookupResponseDto(
        nym: 'alice',
        active: true,
        quota: const BullnymQuotaDto(used: 2, cap: 3, remaining: 1),
        previousNyms: [
          BullnymPreviousNymDto(
            nym: 'oldalice',
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        ],
      ),
    );

    final result = await datasource.lookupByNpub('abc');

    expect(result, isA<ActiveLookupResult>());
    final active = result! as ActiveLookupResult;
    expect(active.nym, 'alice');
    expect(active.quota.used, 2);
    expect(active.previousNyms.single.nym, 'oldalice');
  });

  test('lookup maps inactive Bullnym registration', () async {
    when(
      () => bullnymClient.lookupRegistration(npubHex: any(named: 'npubHex')),
    ).thenAnswer(
      (_) async => const BullnymLookupResponseDto(
        nym: 'alice',
        active: false,
        quota: BullnymQuotaDto(used: 3, cap: 3, remaining: 0),
        previousNyms: [],
      ),
    );

    final result = await datasource.lookupByNpub('abc');

    expect(result, isA<InactiveLookupResult>());
    expect((result! as InactiveLookupResult).quota.remaining, 0);
  });

  test('lookup maps Bullnym not-found to null', () async {
    when(
      () => bullnymClient.lookupRegistration(npubHex: any(named: 'npubHex')),
    ).thenThrow(
      const BullnymException(
        code: 'NymNotFound',
        reason: 'Nym not found',
        statusCode: 404,
      ),
    );

    expect(await datasource.lookupByNpub('abc'), isNull);
  });

  test('lookup maps transient Bullnym errors to PayServiceException', () async {
    when(
      () => bullnymClient.lookupRegistration(npubHex: any(named: 'npubHex')),
    ).thenThrow(BullnymNetworkException('Unable to reach Bullpay'));

    await expectLater(
      datasource.lookupByNpub('abc'),
      throwsA(isA<PayServiceException>()),
    );
  });

  test('delete delegates to Bullnym and clears stored address', () async {
    await datasource.storeAddress('alice@bullpay.ca');
    when(
      () => bullnymClient.deleteRegistration(
        handle: any(named: 'handle'),
        nym: any(named: 'nym'),
      ),
    ).thenAnswer(
      (_) async => const BullnymDeleteResponseDto(
        quota: BullnymQuotaDto(used: 1, cap: 3, remaining: 2),
      ),
    );

    final quota = await datasource.deleteRegistration(
      nym: 'alice',
      handle: handle,
    );

    expect(quota.remaining, 2);
    expect(await datasource.getStoredAddress(), isNull);
    verify(
      () => bullnymClient.deleteRegistration(handle: handle, nym: 'alice'),
    ).called(1);
  });
}

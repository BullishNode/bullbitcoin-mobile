import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_address.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/cancel_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/create_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/list_invoices_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_identity_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/get_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice_status_snapshot.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/payment_method.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_url.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockWalletAddressRepository extends Mock
    implements WalletAddressRepository {}

class _MockLabelsFacade extends Mock implements LabelsFacade {}

class _MockInvoicesPayServicePort extends Mock
    implements InvoicesPayServicePort {}

class _MockInvoicesIdentityPort extends Mock implements InvoicesIdentityPort {}

final _key = '11' * 32;

void main() {
  late _MockWalletRepository walletRepository;
  late _MockWalletAddressRepository walletAddressRepository;
  late _MockLabelsFacade labelsFacade;
  late _MockInvoicesPayServicePort invoiceService;
  late _MockInvoicesIdentityPort invoiceIdentity;
  late NostrKeychainHandle handle;
  late DateTime now;

  setUpAll(() {
    registerFallbackValue(
      NewLabel.addr(address: 'bc1qfallback', label: 'memo'),
    );
  });

  setUp(() {
    walletRepository = _MockWalletRepository();
    walletAddressRepository = _MockWalletAddressRepository();
    labelsFacade = _MockLabelsFacade();
    invoiceService = _MockInvoicesPayServicePort();
    invoiceIdentity = _MockInvoicesIdentityPort();
    handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);
    now = DateTime.utc(2026, 5, 11, 12);
  });

  group('CreateInvoiceUsecase', () {
    test(
      'generates rail addresses and creates invoice with memo labels',
      () async {
        final command = _createCommand(now: now, privateMemo: 'Order 100');
        final result = _createResult();
        when(
          () => walletRepository.getWallets(
            onlyDefaults: true,
            onlyBitcoin: true,
          ),
        ).thenAnswer((_) async => [_wallet(id: 'btc-wallet')]);
        when(
          () =>
              walletRepository.getWallets(onlyDefaults: true, onlyLiquid: true),
        ).thenAnswer(
          (_) async => [
            _wallet(id: 'liq-wallet', network: Network.liquidMainnet),
          ],
        );
        when(
          () => walletAddressRepository.generateNewReceiveAddress(
            walletId: 'btc-wallet',
          ),
        ).thenAnswer((_) async => _address('bc1qinvoice'));
        when(
          () => walletAddressRepository
              .generateNewLiquidReceiveAddressWithBlindingKey(
                walletId: 'liq-wallet',
              ),
        ).thenAnswer((_) async => (address: 'lq1invoice', blindingKey: _key));
        when(
          () => invoiceIdentity.getSigningHandle(),
        ).thenAnswer((_) async => handle);
        when(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: 'bc1qinvoice',
            liquidAddress: 'lq1invoice',
            liquidBlindingKeyHex: _key,
          ),
        ).thenAnswer((_) async => result);
        when(() => labelsFacade.store(any())).thenAnswer(
          (_) async => Label.addr(id: 1, address: 'unused', label: 'Order 100'),
        );

        final usecase = _createUsecase(
          walletRepository: walletRepository,
          walletAddressRepository: walletAddressRepository,
          labelsFacade: labelsFacade,
          invoiceService: invoiceService,
          invoiceIdentity: invoiceIdentity,
        );

        await expectLater(
          usecase.execute(command: command),
          completion(result),
        );
        verify(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: 'bc1qinvoice',
            liquidAddress: 'lq1invoice',
            liquidBlindingKeyHex: _key,
          ),
        ).called(1);
        verify(
          () => walletAddressRepository
              .generateNewLiquidReceiveAddressWithBlindingKey(
                walletId: 'liq-wallet',
              ),
        ).called(1);
        verifyNever(
          () => walletAddressRepository.generateNewReceiveAddress(
            walletId: 'liq-wallet',
          ),
        );
        final labels = verify(
          () => labelsFacade.store(captureAny()),
        ).captured.cast<NewLabel>();
        expect(labels.map((label) => label.reference), [
          'bc1qinvoice',
          'lq1invoice',
        ]);
        expect(labels.every((label) => label.label == 'Order 100'), isTrue);
        expect(
          labels.every(
            (label) => label.origin == 'invoice:${result.invoiceId.value}',
          ),
          isTrue,
        );
      },
    );

    test(
      'does not fail created invoice when memo label storage fails',
      () async {
        final command = _createCommand(
          now: now,
          acceptBtc: true,
          acceptLn: true,
          acceptLiquid: true,
          privateMemo: 'Order 100',
        );
        final result = _createResult();
        when(
          () => walletRepository.getWallets(
            onlyDefaults: true,
            onlyBitcoin: true,
          ),
        ).thenAnswer((_) async => [_wallet(id: 'btc-wallet')]);
        when(
          () => walletAddressRepository.generateNewReceiveAddress(
            walletId: 'btc-wallet',
          ),
        ).thenAnswer((_) async => _address('bc1qinvoice'));
        when(
          () =>
              walletRepository.getWallets(onlyDefaults: true, onlyLiquid: true),
        ).thenAnswer(
          (_) async => [
            _wallet(id: 'liq-wallet', network: Network.liquidMainnet),
          ],
        );
        when(
          () => walletAddressRepository
              .generateNewLiquidReceiveAddressWithBlindingKey(
                walletId: 'liq-wallet',
              ),
        ).thenAnswer((_) async => (address: 'lq1invoice', blindingKey: _key));
        when(
          () => invoiceIdentity.getSigningHandle(),
        ).thenAnswer((_) async => handle);
        when(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: 'bc1qinvoice',
            liquidAddress: 'lq1invoice',
            liquidBlindingKeyHex: _key,
          ),
        ).thenAnswer((_) async => result);
        when(() => labelsFacade.store(any())).thenThrow(Exception('disk full'));

        final usecase = _createUsecase(
          walletRepository: walletRepository,
          walletAddressRepository: walletAddressRepository,
          labelsFacade: labelsFacade,
          invoiceService: invoiceService,
          invoiceIdentity: invoiceIdentity,
        );

        await expectLater(
          usecase.execute(command: command),
          completion(result),
        );
        verify(() => labelsFacade.store(any())).called(2);
      },
    );

    test('does not request blinding key for Lightning-only invoices', () async {
      final command = _createCommand(
        now: now,
        acceptBtc: false,
        acceptLn: true,
        acceptLiquid: false,
      );
      final result = _createResult();
      when(
        () => invoiceIdentity.getSigningHandle(),
      ).thenAnswer((_) async => handle);
      when(
        () => walletRepository.getWallets(onlyDefaults: true, onlyLiquid: true),
      ).thenAnswer(
        (_) async => [
          _wallet(id: 'liq-wallet', network: Network.liquidMainnet),
        ],
      );
      when(
        () => walletAddressRepository.generateNewReceiveAddress(
          walletId: 'liq-wallet',
        ),
      ).thenAnswer((_) async => _address('lq1invoice'));
      when(
        () => invoiceService.createInvoice(
          command: command,
          handle: handle,
          bitcoinAddress: null,
          liquidAddress: 'lq1invoice',
          liquidBlindingKeyHex: null,
        ),
      ).thenAnswer((_) async => result);

      final usecase = _createUsecase(
        walletRepository: walletRepository,
        walletAddressRepository: walletAddressRepository,
        labelsFacade: labelsFacade,
        invoiceService: invoiceService,
        invoiceIdentity: invoiceIdentity,
      );

      await expectLater(usecase.execute(command: command), completion(result));
      verify(
        () => walletAddressRepository.generateNewReceiveAddress(
          walletId: 'liq-wallet',
        ),
      ).called(1);
      verifyNever(
        () => walletAddressRepository
            .generateNewLiquidReceiveAddressWithBlindingKey(
              walletId: any(named: 'walletId'),
            ),
      );
    });

    test(
      'retries once with a fresh Bitcoin address when server rejects reuse',
      () async {
        final command = _createCommand(
          now: now,
          acceptBtc: true,
          acceptLn: false,
          acceptLiquid: false,
        );
        final result = _createResult();
        var generated = 0;
        when(
          () => invoiceIdentity.getSigningHandle(),
        ).thenAnswer((_) async => handle);
        when(
          () => walletRepository.getWallets(
            onlyDefaults: true,
            onlyBitcoin: true,
          ),
        ).thenAnswer((_) async => [_wallet(id: 'btc-wallet')]);
        when(
          () => walletAddressRepository.generateNewReceiveAddress(
            walletId: 'btc-wallet',
          ),
        ).thenAnswer((_) async {
          generated += 1;
          return _address(generated == 1 ? 'bc1qused' : 'bc1qfresh');
        });
        when(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: 'bc1qused',
            liquidAddress: null,
            liquidBlindingKeyHex: null,
          ),
        ).thenThrow(
          const InvoicesBitcoinAddressAlreadyUsedError('address already used'),
        );
        when(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: 'bc1qfresh',
            liquidAddress: null,
            liquidBlindingKeyHex: null,
          ),
        ).thenAnswer((_) async => result);

        final usecase = _createUsecase(
          walletRepository: walletRepository,
          walletAddressRepository: walletAddressRepository,
          labelsFacade: labelsFacade,
          invoiceService: invoiceService,
          invoiceIdentity: invoiceIdentity,
        );

        await expectLater(
          usecase.execute(command: command),
          completion(result),
        );
        verify(
          () => walletAddressRepository.generateNewReceiveAddress(
            walletId: 'btc-wallet',
          ),
        ).called(2);
        verify(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: 'bc1qused',
            liquidAddress: null,
            liquidBlindingKeyHex: null,
          ),
        ).called(1);
        verify(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: 'bc1qfresh',
            liquidAddress: null,
            liquidBlindingKeyHex: null,
          ),
        ).called(1);
      },
    );

    test(
      'stores memo label on fresh address after Bitcoin address retry',
      () async {
        final command = _createCommand(
          now: now,
          acceptBtc: true,
          acceptLn: false,
          acceptLiquid: false,
          privateMemo: 'Order 100',
        );
        final result = _createResult();
        var generated = 0;
        when(
          () => invoiceIdentity.getSigningHandle(),
        ).thenAnswer((_) async => handle);
        when(
          () => walletRepository.getWallets(
            onlyDefaults: true,
            onlyBitcoin: true,
          ),
        ).thenAnswer((_) async => [_wallet(id: 'btc-wallet')]);
        when(
          () => walletAddressRepository.generateNewReceiveAddress(
            walletId: 'btc-wallet',
          ),
        ).thenAnswer((_) async {
          generated += 1;
          return _address(generated == 1 ? 'bc1qused' : 'bc1qfresh');
        });
        when(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: 'bc1qused',
            liquidAddress: null,
            liquidBlindingKeyHex: null,
          ),
        ).thenThrow(
          const InvoicesBitcoinAddressAlreadyUsedError('address already used'),
        );
        when(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: 'bc1qfresh',
            liquidAddress: null,
            liquidBlindingKeyHex: null,
          ),
        ).thenAnswer((_) async => result);
        when(() => labelsFacade.store(any())).thenAnswer(
          (_) async =>
              Label.addr(id: 1, address: 'bc1qfresh', label: 'Order 100'),
        );

        final usecase = _createUsecase(
          walletRepository: walletRepository,
          walletAddressRepository: walletAddressRepository,
          labelsFacade: labelsFacade,
          invoiceService: invoiceService,
          invoiceIdentity: invoiceIdentity,
        );

        await expectLater(
          usecase.execute(command: command),
          completion(result),
        );
        final labels = verify(
          () => labelsFacade.store(captureAny()),
        ).captured.cast<NewLabel>();
        expect(labels.single.reference, 'bc1qfresh');
      },
    );

    test(
      'retries once with a fresh Liquid address when server rejects reuse',
      () async {
        final command = _createCommand(
          now: now,
          acceptBtc: false,
          acceptLn: false,
          acceptLiquid: true,
        );
        final result = _createResult();
        var generated = 0;
        when(
          () => invoiceIdentity.getSigningHandle(),
        ).thenAnswer((_) async => handle);
        when(
          () =>
              walletRepository.getWallets(onlyDefaults: true, onlyLiquid: true),
        ).thenAnswer(
          (_) async => [
            _wallet(id: 'liq-wallet', network: Network.liquidMainnet),
          ],
        );
        when(
          () => walletAddressRepository
              .generateNewLiquidReceiveAddressWithBlindingKey(
                walletId: 'liq-wallet',
              ),
        ).thenAnswer((_) async {
          generated += 1;
          return (
            address: generated == 1 ? 'lq1used' : 'lq1fresh',
            blindingKey: generated == 1 ? '22' * 32 : '33' * 32,
          );
        });
        when(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: null,
            liquidAddress: 'lq1used',
            liquidBlindingKeyHex: '22' * 32,
          ),
        ).thenThrow(
          const InvoicesLiquidAddressAlreadyUsedError('address already used'),
        );
        when(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: null,
            liquidAddress: 'lq1fresh',
            liquidBlindingKeyHex: '33' * 32,
          ),
        ).thenAnswer((_) async => result);

        final usecase = _createUsecase(
          walletRepository: walletRepository,
          walletAddressRepository: walletAddressRepository,
          labelsFacade: labelsFacade,
          invoiceService: invoiceService,
          invoiceIdentity: invoiceIdentity,
        );

        await expectLater(
          usecase.execute(command: command),
          completion(result),
        );
        verify(
          () => walletAddressRepository
              .generateNewLiquidReceiveAddressWithBlindingKey(
                walletId: 'liq-wallet',
              ),
        ).called(2);
        verify(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: null,
            liquidAddress: 'lq1used',
            liquidBlindingKeyHex: '22' * 32,
          ),
        ).called(1);
        verify(
          () => invoiceService.createInvoice(
            command: command,
            handle: handle,
            bitcoinAddress: null,
            liquidAddress: 'lq1fresh',
            liquidBlindingKeyHex: '33' * 32,
          ),
        ).called(1);
      },
    );

    test('does not store memo labels when private memo is absent', () async {
      final command = _createCommand(
        now: now,
        acceptBtc: true,
        acceptLn: false,
        acceptLiquid: false,
      );
      final result = _createResult();
      when(
        () => invoiceIdentity.getSigningHandle(),
      ).thenAnswer((_) async => handle);
      when(
        () =>
            walletRepository.getWallets(onlyDefaults: true, onlyBitcoin: true),
      ).thenAnswer((_) async => [_wallet(id: 'btc-wallet')]);
      when(
        () => walletAddressRepository.generateNewReceiveAddress(
          walletId: 'btc-wallet',
        ),
      ).thenAnswer((_) async => _address('bc1qinvoice'));
      when(
        () => invoiceService.createInvoice(
          command: command,
          handle: handle,
          bitcoinAddress: 'bc1qinvoice',
          liquidAddress: null,
          liquidBlindingKeyHex: null,
        ),
      ).thenAnswer((_) async => result);

      final usecase = _createUsecase(
        walletRepository: walletRepository,
        walletAddressRepository: walletAddressRepository,
        labelsFacade: labelsFacade,
        invoiceService: invoiceService,
        invoiceIdentity: invoiceIdentity,
      );

      await expectLater(usecase.execute(command: command), completion(result));
      verifyNever(() => labelsFacade.store(any()));
    });

    test('does not store memo labels when private memo is empty', () async {
      final command = _createCommand(
        now: now,
        acceptBtc: true,
        acceptLn: false,
        acceptLiquid: false,
        privateMemo: '',
      );
      final result = _createResult();
      when(
        () => invoiceIdentity.getSigningHandle(),
      ).thenAnswer((_) async => handle);
      when(
        () =>
            walletRepository.getWallets(onlyDefaults: true, onlyBitcoin: true),
      ).thenAnswer((_) async => [_wallet(id: 'btc-wallet')]);
      when(
        () => walletAddressRepository.generateNewReceiveAddress(
          walletId: 'btc-wallet',
        ),
      ).thenAnswer((_) async => _address('bc1qinvoice'));
      when(
        () => invoiceService.createInvoice(
          command: command,
          handle: handle,
          bitcoinAddress: 'bc1qinvoice',
          liquidAddress: null,
          liquidBlindingKeyHex: null,
        ),
      ).thenAnswer((_) async => result);

      final usecase = _createUsecase(
        walletRepository: walletRepository,
        walletAddressRepository: walletAddressRepository,
        labelsFacade: labelsFacade,
        invoiceService: invoiceService,
        invoiceIdentity: invoiceIdentity,
      );

      await expectLater(usecase.execute(command: command), completion(result));
      verifyNever(() => labelsFacade.store(any()));
    });

    test(
      'throws typed error before generating addresses when identity is missing',
      () async {
        final command = _createCommand(now: now);
        when(
          () => invoiceIdentity.getSigningHandle(),
        ).thenThrow(const InvoicesIdentityUnavailableError('missing identity'));

        final usecase = _createUsecase(
          walletRepository: walletRepository,
          walletAddressRepository: walletAddressRepository,
          labelsFacade: labelsFacade,
          invoiceService: invoiceService,
          invoiceIdentity: invoiceIdentity,
        );

        await expectLater(
          usecase.execute(command: command),
          throwsA(isA<InvoicesIdentityUnavailableError>()),
        );
        verifyNever(
          () => walletAddressRepository.generateNewReceiveAddress(
            walletId: any(named: 'walletId'),
          ),
        );
        verifyNever(
          () => walletAddressRepository
              .generateNewLiquidReceiveAddressWithBlindingKey(
                walletId: any(named: 'walletId'),
              ),
        );
      },
    );

    test('throws typed error when default Bitcoin wallet is missing', () async {
      final command = _createCommand(
        now: now,
        acceptBtc: true,
        acceptLn: false,
        acceptLiquid: false,
      );
      when(
        () => invoiceIdentity.getSigningHandle(),
      ).thenAnswer((_) async => handle);
      when(
        () =>
            walletRepository.getWallets(onlyDefaults: true, onlyBitcoin: true),
      ).thenAnswer((_) async => []);

      final usecase = _createUsecase(
        walletRepository: walletRepository,
        walletAddressRepository: walletAddressRepository,
        labelsFacade: labelsFacade,
        invoiceService: invoiceService,
        invoiceIdentity: invoiceIdentity,
      );

      await expectLater(
        usecase.execute(command: command),
        throwsA(isA<InvoicesNoDefaultBitcoinWalletError>()),
      );
      verify(() => invoiceIdentity.getSigningHandle()).called(1);
    });

    test('throws typed error when default Liquid wallet is missing', () async {
      final command = _createCommand(
        now: now,
        acceptBtc: false,
        acceptLn: true,
        acceptLiquid: false,
      );
      when(
        () => invoiceIdentity.getSigningHandle(),
      ).thenAnswer((_) async => handle);
      when(
        () => walletRepository.getWallets(onlyDefaults: true, onlyLiquid: true),
      ).thenAnswer((_) async => []);

      final usecase = _createUsecase(
        walletRepository: walletRepository,
        walletAddressRepository: walletAddressRepository,
        labelsFacade: labelsFacade,
        invoiceService: invoiceService,
        invoiceIdentity: invoiceIdentity,
      );

      await expectLater(
        usecase.execute(command: command),
        throwsA(isA<InvoicesNoDefaultLiquidWalletError>()),
      );
      verify(() => invoiceIdentity.getSigningHandle()).called(1);
    });
  });

  test('CancelInvoiceUsecase gets signing handle and delegates', () async {
    final command = CancelInvoiceCommand(
      invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
      nymOwner: 'alice',
    );
    final result = CancelInvoiceResult(
      invoiceId: command.invoiceId,
      status: InvoiceStatus.cancelled,
    );
    when(
      () => invoiceIdentity.getSigningHandle(),
    ).thenAnswer((_) async => handle);
    when(
      () => invoiceService.cancelInvoice(command: command, handle: handle),
    ).thenAnswer((_) async => result);

    final usecase = CancelInvoiceUsecase(
      invoiceService: invoiceService,
      invoiceIdentity: invoiceIdentity,
    );

    await expectLater(usecase.execute(command: command), completion(result));
  });

  test('ListInvoicesUsecase gets signing handle and delegates', () async {
    final command = ListInvoicesCommand(status: null);
    const result = ListInvoicesResult(
      invoices: [],
      page: 1,
      pageSize: 100,
      hasMore: false,
    );
    when(
      () => invoiceIdentity.getSigningHandle(),
    ).thenAnswer((_) async => handle);
    when(
      () => invoiceService.listInvoices(command: command, handle: handle),
    ).thenAnswer((_) async => result);

    final usecase = ListInvoicesUsecase(
      invoiceService: invoiceService,
      invoiceIdentity: invoiceIdentity,
    );

    final listed = await usecase.execute(command: command);

    expect(listed.invoices, isEmpty);
    expect(listed.page, result.page);
    expect(listed.pageSize, result.pageSize);
    expect(listed.hasMore, result.hasMore);
  });

  test(
    'ListInvoicesUsecase hides unpaid and expired checkout invoices',
    () async {
      final command = ListInvoicesCommand(status: null);
      final walletUnpaid = _invoice(
        id: '00000000-0000-0000-0000-000000000001',
        origin: 'wallet',
        status: InvoiceStatus.unpaid,
        now: now,
      );
      final checkoutUnpaid = _invoice(
        id: '00000000-0000-0000-0000-000000000002',
        origin: 'checkout',
        status: InvoiceStatus.unpaid,
        now: now,
      );
      final checkoutExpired = _invoice(
        id: '00000000-0000-0000-0000-000000000003',
        origin: 'checkout',
        status: InvoiceStatus.expired,
        now: now,
      );
      final checkoutPaid = _invoice(
        id: '00000000-0000-0000-0000-000000000004',
        origin: 'checkout',
        status: InvoiceStatus.paid,
        now: now,
      );
      final result = ListInvoicesResult(
        invoices: [walletUnpaid, checkoutUnpaid, checkoutExpired, checkoutPaid],
        page: 1,
        pageSize: 100,
        hasMore: false,
      );
      when(
        () => invoiceIdentity.getSigningHandle(),
      ).thenAnswer((_) async => handle);
      when(
        () => invoiceService.listInvoices(command: command, handle: handle),
      ).thenAnswer((_) async => result);

      final usecase = ListInvoicesUsecase(
        invoiceService: invoiceService,
        invoiceIdentity: invoiceIdentity,
      );

      final filtered = await usecase.execute(command: command);

      expect(filtered.invoices, [walletUnpaid, checkoutPaid]);
    },
  );

  test('ListInvoicesCommand rejects values outside backend page bounds', () {
    expect(
      () => ListInvoicesCommand(page: 0, status: null),
      throwsA(isA<InvoicesValidationError>()),
    );
    expect(
      () => ListInvoicesCommand(page: 1001, status: null),
      throwsA(isA<InvoicesValidationError>()),
    );
    expect(
      () => ListInvoicesCommand(pageSize: 0, status: null),
      throwsA(isA<InvoicesValidationError>()),
    );
    expect(
      () => ListInvoicesCommand(pageSize: 101, status: null),
      throwsA(isA<InvoicesValidationError>()),
    );
  });

  test(
    'GetInvoiceUsecase delegates to public status lookup without identity',
    () async {
      final id = InvoiceId('00000000-0000-0000-0000-000000000001');
      final snapshot = InvoiceStatusSnapshot(
        invoiceId: id,
        status: InvoiceStatus.unpaid,
        pricingMode: 'fixed_sats',
        settlementStatus: 'none',
        amountSat: 1000,
        fiatAmountMinor: null,
        fiatCurrency: null,
        remainingAmountSat: 1000,
        paymentToleranceSat: 1,
        rateMinorPerBtc: null,
        publicDescription: 'Coffee',
        recipientName: 'Alice',
        invoiceNumber: 'INV-1',
        createdAt: now,
        rateLocksUntil: now,
        expiresAt: now.add(const Duration(hours: 1)),
        paidVia: null,
        paidAt: null,
        paidAmountSat: null,
        lightningPr: null,
        liquidAddress: 'lq1invoice',
        bitcoinAddress: 'bc1qinvoice',
        bitcoinChainAddress: null,
        bitcoinChainBip21: null,
        acceptBtc: true,
        acceptLn: true,
        acceptLiquid: true,
        shareUrl: InvoiceUrl('https://bullpay.ca/alice/i/$id'),
      );
      when(
        () => invoiceService.getInvoiceStatus(id: id),
      ).thenAnswer((_) async => snapshot);

      final usecase = GetInvoiceUsecase(invoiceService: invoiceService);

      await expectLater(usecase.execute(id: id), completion(snapshot));
      verifyNever(() => invoiceIdentity.getSigningHandle());
    },
  );
}

CreateInvoiceUsecase _createUsecase({
  required WalletRepository walletRepository,
  required WalletAddressRepository walletAddressRepository,
  required LabelsFacade labelsFacade,
  required InvoicesPayServicePort invoiceService,
  required InvoicesIdentityPort invoiceIdentity,
}) {
  return CreateInvoiceUsecase(
    walletRepository: walletRepository,
    walletAddressRepository: walletAddressRepository,
    labelsFacade: labelsFacade,
    invoiceService: invoiceService,
    invoiceIdentity: invoiceIdentity,
  );
}

CreateInvoiceCommand _createCommand({
  required DateTime now,
  bool acceptBtc = true,
  bool acceptLn = true,
  bool acceptLiquid = true,
  String? privateMemo,
}) {
  return CreateInvoiceCommand(
    amountSat: 1000,
    fiatAmountMinor: null,
    fiatCurrency: null,
    publicDescription: 'Coffee',
    recipientName: 'Alice',
    invoiceNumber: 'INV-1',
    acceptBtc: acceptBtc,
    acceptLn: acceptLn,
    acceptLiquid: acceptLiquid,
    expiresAt: now.add(const Duration(hours: 1)),
    linkToPageNym: 'alice',
    privateMemo: privateMemo,
    now: now,
  );
}

CreateInvoiceResult _createResult() {
  return CreateInvoiceResult(
    invoiceId: InvoiceId('00000000-0000-0000-0000-000000000001'),
    shareUrl: InvoiceUrl(
      'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
    ),
  );
}

Invoice _invoice({
  required String id,
  required String origin,
  required InvoiceStatus status,
  required DateTime now,
}) {
  return Invoice(
    id: InvoiceId(id),
    nymOwner: 'alice',
    origin: origin,
    status: status,
    amountSat: 1000,
    remainingAmountSat: status == InvoiceStatus.paid ? 0 : 1000,
    fiatAmountMinor: null,
    fiatCurrency: null,
    publicDescription: 'Coffee',
    recipientName: 'Alice',
    invoiceNumber: 'INV-1',
    acceptBtc: true,
    acceptLn: true,
    acceptLiquid: false,
    bitcoinAddress: 'bc1qinvoice',
    liquidAddress: 'lq1invoice',
    createdAt: now,
    expiresAt: status == InvoiceStatus.expired
        ? now.subtract(const Duration(minutes: 1))
        : now.add(const Duration(hours: 1)),
    paidVia: status == InvoiceStatus.paid ? PaymentMethod.lightning : null,
    paidAt: status == InvoiceStatus.paid ? now : null,
    paidAmountSat: status == InvoiceStatus.paid ? 1000 : null,
    shareUrl: InvoiceUrl('https://bullpay.ca/alice/i/$id'),
  );
}

Wallet _wallet({required String id, Network network = Network.bitcoinMainnet}) {
  return Wallet(
    origin: id,
    network: network,
    isDefault: true,
    masterFingerprint: '73c5da0a',
    xpubFingerprint: '73c5da0a',
    scriptType: ScriptType.bip84,
    xpub: 'xpubFAKE',
    externalPublicDescriptor: 'wpkh(xpubFAKE/0/*)',
    internalPublicDescriptor: 'wpkh(xpubFAKE/1/*)',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}

WalletAddress _address(String address) {
  return WalletAddress(
    walletId: 'wallet',
    index: 0,
    address: address,
    createdAt: DateTime.utc(2026, 5, 11),
    updatedAt: DateTime.utc(2026, 5, 11),
  );
}

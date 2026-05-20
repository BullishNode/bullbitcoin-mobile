import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/create_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_identity_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_command.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';

class CreateInvoiceUsecase {
  final WalletRepository _walletRepository;
  final WalletAddressRepository _walletAddressRepository;
  final LabelsFacade _labelsFacade;
  final InvoicesPayServicePort _invoiceService;
  final InvoicesIdentityPort _invoiceIdentity;

  const CreateInvoiceUsecase({
    required WalletRepository walletRepository,
    required WalletAddressRepository walletAddressRepository,
    required LabelsFacade labelsFacade,
    required InvoicesPayServicePort invoiceService,
    required InvoicesIdentityPort invoiceIdentity,
  }) : _walletRepository = walletRepository,
       _walletAddressRepository = walletAddressRepository,
       _labelsFacade = labelsFacade,
       _invoiceService = invoiceService,
       _invoiceIdentity = invoiceIdentity;

  Future<CreateInvoiceResult> execute({
    required CreateInvoiceCommand command,
  }) async {
    final handle = await _invoiceIdentity.getSigningHandle();
    String? bitcoinAddress;
    String? liquidAddress;
    String? liquidBlindingKeyHex;

    if (command.acceptBtc) {
      bitcoinAddress = await _generateBitcoinAddress();
    }

    if (command.acceptLn || command.acceptLiquid) {
      final address = await _generateLiquidAddress(
        includeBlindingKey: command.acceptLiquid,
      );
      liquidAddress = address.address;
      liquidBlindingKeyHex = address.blindingKeyHex;
    }

    final create = await _createInvoiceRetryingUsedAddress(
      command: command,
      handle: handle,
      bitcoinAddress: bitcoinAddress,
      liquidAddress: liquidAddress,
      liquidBlindingKeyHex: liquidBlindingKeyHex,
    );

    final privateMemo = command.privateMemo;
    if (privateMemo != null && privateMemo.isNotEmpty) {
      await _storeMemoLabelsBestEffort(
        invoiceId: create.result.invoiceId.value,
        privateMemo: privateMemo,
        bitcoinAddress: create.bitcoinAddress,
        liquidAddress: create.liquidAddress,
      );
    }

    return create.result;
  }

  Future<
    ({
      CreateInvoiceResult result,
      String? bitcoinAddress,
      String? liquidAddress,
    })
  >
  _createInvoiceRetryingUsedAddress({
    required CreateInvoiceCommand command,
    required NostrKeychainHandle handle,
    required String? bitcoinAddress,
    required String? liquidAddress,
    required String? liquidBlindingKeyHex,
  }) async {
    try {
      final result = await _invoiceService.createInvoice(
        command: command,
        handle: handle,
        bitcoinAddress: bitcoinAddress,
        liquidAddress: liquidAddress,
        liquidBlindingKeyHex: liquidBlindingKeyHex,
      );
      return (
        result: result,
        bitcoinAddress: bitcoinAddress,
        liquidAddress: liquidAddress,
      );
    } on InvoicesBitcoinAddressAlreadyUsedError {
      if (!command.acceptBtc) rethrow;
      final freshBitcoinAddress = await _generateBitcoinAddress();
      final result = await _invoiceService.createInvoice(
        command: command,
        handle: handle,
        bitcoinAddress: freshBitcoinAddress,
        liquidAddress: liquidAddress,
        liquidBlindingKeyHex: liquidBlindingKeyHex,
      );
      return (
        result: result,
        bitcoinAddress: freshBitcoinAddress,
        liquidAddress: liquidAddress,
      );
    } on InvoicesLiquidAddressAlreadyUsedError {
      if (!command.acceptLn && !command.acceptLiquid) rethrow;
      final address = await _generateLiquidAddress(
        includeBlindingKey: command.acceptLiquid,
      );
      final result = await _invoiceService.createInvoice(
        command: command,
        handle: handle,
        bitcoinAddress: bitcoinAddress,
        liquidAddress: address.address,
        liquidBlindingKeyHex: address.blindingKeyHex,
      );
      return (
        result: result,
        bitcoinAddress: bitcoinAddress,
        liquidAddress: address.address,
      );
    }
  }

  Future<String> _generateBitcoinAddress() async {
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    final wallet = wallets.firstOrNull;
    if (wallet == null) {
      throw const InvoicesNoDefaultBitcoinWalletError(
        'No default Bitcoin wallet found',
      );
    }
    final address = await _walletAddressRepository.generateNewReceiveAddress(
      walletId: wallet.id,
    );
    return address.address;
  }

  Future<({String address, String? blindingKeyHex})> _generateLiquidAddress({
    required bool includeBlindingKey,
  }) async {
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyLiquid: true,
    );
    final wallet = wallets.firstOrNull;
    if (wallet == null) {
      throw const InvoicesNoDefaultLiquidWalletError(
        'No default Liquid wallet found',
      );
    }
    if (includeBlindingKey) {
      final address = await _walletAddressRepository
          .generateNewLiquidReceiveAddressWithBlindingKey(walletId: wallet.id);
      return (address: address.address, blindingKeyHex: address.blindingKey);
    }
    final address = await _walletAddressRepository.generateNewReceiveAddress(
      walletId: wallet.id,
    );
    return (address: address.address, blindingKeyHex: null);
  }

  Future<void> _storeMemoLabelsBestEffort({
    required String invoiceId,
    required String privateMemo,
    required String? bitcoinAddress,
    required String? liquidAddress,
  }) async {
    final origin = 'invoice:$invoiceId';
    for (final address in [bitcoinAddress, liquidAddress]) {
      if (address == null) continue;
      try {
        await _labelsFacade.store(
          NewLabel.addr(address: address, label: privateMemo, origin: origin),
        );
      } on Exception catch (e) {
        log.warning('Failed to store invoice private memo label', error: e);
      }
    }
  }
}

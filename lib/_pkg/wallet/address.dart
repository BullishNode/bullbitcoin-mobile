import 'package:bb_mobile/_model/address.dart';
import 'package:bb_mobile/_model/wallet.dart';
import 'package:bb_mobile/_pkg/error.dart';
import 'package:bdk_flutter/bdk_flutter.dart' as bdk;

class WalletAddress {
  Future<(({int index, String address})?, Err?)> newDeposit({
    required bdk.Wallet bdkWallet,
  }) async {
    try {
      final address = await bdkWallet.getAddress(
        addressIndex: const bdk.AddressIndex.new(),
      );

      return ((index: address.index, address: address.address), null);
    } catch (e) {
      return (null, Err(e.toString()));
    }
  }

  Future<(({int index, String address})?, Err?)> lastUnused({
    required bdk.Wallet bdkWallet,
  }) async {
    try {
      final address = await bdkWallet.getAddress(
        addressIndex: const bdk.AddressIndex.lastUnused(),
      );

      return ((index: address.index, address: address.address), null);
    } catch (e) {
      return (null, Err(e.toString()));
    }
  }

  Future<String?> getLabel({required Wallet wallet, required String address}) async {
    final addresses = wallet.addresses;

    String? label;
    if (addresses.any((element) => element.address == address)) {
      final x = addresses.firstWhere(
        (element) => element.address == address,
      );
      label = x.label;
    }

    return label;
  }

  Future<(Wallet?, Err?)> loadAddresses({
    required Wallet wallet,
    required bdk.Wallet bdkWallet,
  }) async {
    try {
      final addressLastUnused = await bdkWallet.getAddress(
        addressIndex: const bdk.AddressIndex.lastUnused(),
      );
      Wallet w;
      if (wallet.lastUnusedAddress == null) {
        w = wallet.copyWith(
          lastUnusedAddress: Address(
            address: addressLastUnused.address,
            index: addressLastUnused.index,
            kind: AddressKind.deposit,
            state: AddressStatus.unused,
          ),
        );
      } else if (wallet.lastUnusedAddress!.index == addressLastUnused.index) {
        // return (wallet, null);
      }
      final List<Address> addresses = [...wallet.addresses];
      for (var i = 0; i <= addressLastUnused.index + 5; i++) {
        final address = await bdkWallet.getAddress(
          addressIndex: bdk.AddressIndex.peek(index: i),
        );
        final contain = wallet.addresses.where(
          (element) => element.address == address.address,
        );
        if (contain.isEmpty)
          addresses.add(
            Address(
              address: address.address,
              index: address.index,
              kind: AddressKind.deposit,
              state: AddressStatus.unset,
            ),
          );
      }
      w = wallet.copyWith(
        addresses: addresses,
        lastUnusedAddress: Address(
          address: addressLastUnused.address,
          index: addressLastUnused.index,
          kind: AddressKind.deposit,
          state: AddressStatus.unused,
        ),
      );

      return (w, null);
    } catch (e) {
      return (null, Err(e.toString()));
    }
  }

  Future<(String?, Err?)> peekIndex(bdk.Wallet bdkWallet, int idx) async {
    try {
      final address = await bdkWallet.getAddress(
        addressIndex: const bdk.AddressIndex.peek(index: 0),
      );

      return (address.address, null);
    } catch (e) {
      return (null, Err(e.toString()));
    }
  }

  Future<(Wallet?, Err?)> updateUtxos({
    required Wallet wallet,
    required bdk.Wallet bdkWallet,
  }) async {
    try {
      final unspentList = await bdkWallet.listUnspent();
      final addresses = wallet.addresses.toList();
      for (final unspent in unspentList) {
        final scr = await bdk.Script.create(unspent.txout.scriptPubkey.internal);
        final addresss = await bdk.Address.fromScript(
          scr,
          wallet.getBdkNetwork(),
        );
        final addressStr = addresss.toString();

        late bool isRelated = false;
        late String txLabel = '';
        final address = addresses.firstWhere(
          (a) => a.address == addressStr,
          // if the address does not exist, its because its new change
          orElse: () => Address(
            address: addressStr,
            kind: AddressKind.change,
            state: AddressStatus.active,
          ),
        );

        final utxos = address.utxos?.toList() ?? [];
        for (final tx in wallet.transactions) {
          for (final addrs in tx.outAddresses ?? []) {
            if (addrs == addressStr) {
              isRelated = true;
              txLabel = tx.label ?? '';
            }
          }
        }
        // tjhe above might not be the best way to update change label from a send tx

        if (utxos.indexWhere((u) => u.outpoint.txid == unspent.outpoint.txid) == -1)
          utxos.add(unspent);

        var updated = address.copyWith(
          utxos: utxos,
          label: isRelated ? address.label : txLabel,
          state: AddressStatus.active,
        );

        if (updated.calculateBalance() > 0 &&
            updated.calculateBalance() > updated.highestPreviousBalance)
          updated = updated.copyWith(
            highestPreviousBalance: updated.calculateBalance(),
          );

        addresses.removeWhere((a) => a.address == address.address);
        addresses.add(updated);
      }
      final w = wallet.copyWith(addresses: addresses);

      return (w, null);
    } catch (e) {
      return (null, Err(e.toString()));
    }
  }

  Future<(Address, Wallet)> addAddressToWallet({
    required (int?, String) address,
    required Wallet wallet,
    String? label,
    String? spentTxId,
    AddressKind? kind,
    AddressStatus state = AddressStatus.unset,
  }) async {
    try {
      final (idx, adr) = address;
      final addresses = (kind == AddressKind.external
              ? wallet.toAddresses?.toList()
              : wallet.addresses.toList()) ??
          <Address>[];

      Address a;

      final existing = addresses.indexWhere(
        (element) => element.address == adr,
      );
      final addressExists = existing != -1;
      if (addressExists) {
        a = addresses.removeAt(existing);
        a = a.copyWith(
          label: label,
          spentTxId: spentTxId,
          state: state,
        );
        addresses.insert(existing, a);
      } else {
        a = Address(
          address: adr,
          index: idx,
          label: label,
          spentTxId: spentTxId,
          kind: kind!,
          state: state,
        );
        addresses.add(a);
      }

      final w = kind == AddressKind.external
          ? wallet.copyWith(toAddresses: addresses)
          : wallet.copyWith(addresses: addresses);

      return (a, w);
    } catch (e) {
      rethrow;
    }

    // Future<Err?> freezeUtxo({
    //   required String address,
    //   required bdk.Wallet bdkWallet,
    // }) async {
    //   try {
    //     //
    //     return null;
    //   } catch (e) {
    //     rethrow;
    //   }
    // }
  }
}

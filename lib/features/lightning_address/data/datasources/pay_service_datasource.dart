import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_client.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_errors.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/models/bullnym_models.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/previous_nym.dart';
import 'package:hive/hive.dart';

class PayServiceDatasource implements PayServicePort {
  static const _boxName = 'lightning_address';
  static const _addressKey = 'address';

  final BullnymClient _bullnymClient;

  PayServiceDatasource({BullnymClient? bullnymClient})
    : _bullnymClient = bullnymClient ?? BullnymClient();

  @override
  Future<({String address, NymQuota quota})> register({
    required String nym,
    required String ctDescriptor,
    required NostrKeychainHandle handle,
  }) async {
    try {
      final response = await _bullnymClient.register(
        handle: handle,
        nym: nym,
        ctDescriptor: ctDescriptor,
      );
      final address = response.lightningAddress;
      final quota = _quotaFromDto(response.quota);

      final box = await Hive.openBox<String>(_boxName);
      await box.put(_addressKey, address);

      return (address: address, quota: quota);
    } on BullnymException catch (e) {
      throw PayServiceException(_registerErrorMessage(e));
    }
  }

  @override
  Future<String?> getStoredAddress() async {
    final box = await Hive.openBox<String>(_boxName);
    return box.get(_addressKey);
  }

  @override
  Future<void> storeAddress(String address) async {
    final box = await Hive.openBox<String>(_boxName);
    await box.put(_addressKey, address);
  }

  @override
  Future<LookupResult?> lookupByNpub(String npubHex) async {
    try {
      final response = await _bullnymClient.lookupRegistration(
        npubHex: npubHex,
      );
      final quota = _quotaFromDto(response.quota);
      final previousNyms = _previousNymsFromDto(response.previousNyms);
      return response.active
          ? ActiveLookupResult(
              nym: response.nym,
              quota: quota,
              previousNyms: previousNyms,
            )
          : InactiveLookupResult(
              nym: response.nym,
              quota: quota,
              previousNyms: previousNyms,
            );
    } on BullnymException catch (e) {
      // 404 = npub has no registration. Anything else (5xx, timeout,
      // connection-reset) is a transient failure the caller must distinguish
      // from "not registered" — otherwise one network blip silently kills
      // recovery on this device.
      if (e.statusCode == 404 || e.code == 'NymNotFound') return null;
      throw PayServiceException(e.reason);
    }
  }

  @override
  Future<NymQuota> deleteRegistration({
    required String nym,
    required NostrKeychainHandle handle,
  }) async {
    try {
      final response = await _bullnymClient.deleteRegistration(
        handle: handle,
        nym: nym,
      );

      final box = await Hive.openBox<String>(_boxName);
      await box.delete(_addressKey);

      return _quotaFromDto(response.quota);
    } on BullnymException catch (e) {
      throw PayServiceException(e.reason);
    }
  }

  List<PreviousNym> _previousNymsFromDto(List<BullnymPreviousNymDto> raw) {
    return [
      for (final item in raw)
        PreviousNym(nym: item.nym, createdAt: item.createdAt),
    ];
  }

  // remaining is recomputed locally; never trust a derived field over the wire.
  NymQuota _quotaFromDto(BullnymQuotaDto quota) {
    return NymQuota(used: quota.used, cap: quota.cap);
  }

  String _registerErrorMessage(BullnymException e) {
    return switch (e.code) {
      'NymReserved' ||
      'NymTaken' ||
      'NymUnavailable' => 'This nym is not available',
      _ => e.reason,
    };
  }
}

import 'dart:convert';

import 'package:bb_mobile/core/exchange/data/models/api_key_model.dart';
import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:flutter/foundation.dart';

class BullbitcoinApiKeyDatasource {
  static const String _apiKeyStorageKey = 'exchange_api_key';
  static const String _apiKeyTestnetStorageKey = 'exchange_api_key_testnet';

  final KeyValueStorageDatasource<String> _secureStorage;

  BullbitcoinApiKeyDatasource({
    required KeyValueStorageDatasource<String> secureStorage,
  }) : _secureStorage = secureStorage;

  Future<void> store(
    ExchangeApiKeyModel apiKey, {
    required bool isTestnet,
  }) async {
    try {
      final jsonString = jsonEncode(apiKey.toJson());
      final key = isTestnet ? _apiKeyTestnetStorageKey : _apiKeyStorageKey;
      await _secureStorage.saveValue(key: key, value: jsonString);
      debugPrint('API key stored successfully');
    } catch (e) {
      debugPrint('Error storing API key: $e');
      rethrow;
    }
  }

  Future<ExchangeApiKeyModel?> get({required bool isTestnet}) async {
    try {
      final key = isTestnet ? _apiKeyTestnetStorageKey : _apiKeyStorageKey;
      final jsonString = await _secureStorage.getValue(key);

      if (jsonString == null || jsonString.isEmpty) {
        debugPrint('No API key found in storage');
        return null;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return ExchangeApiKeyModel.fromJson(json);
    } catch (e) {
      debugPrint('Error retrieving API key: $e');
      return null;
    }
  }

  Future<void> delete({required bool isTestnet}) async {
    try {
      final key = isTestnet ? _apiKeyTestnetStorageKey : _apiKeyStorageKey;
      await _secureStorage.deleteValue(key);
      debugPrint('API key deleted successfully');
    } catch (e) {
      debugPrint('Error deleting API key: $e');
      rethrow;
    }
  }
}

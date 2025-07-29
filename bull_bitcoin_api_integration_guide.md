# Bull Bitcoin API Integration Guide for Flutter/Dart Wallets

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Dependencies](#dependencies)
4. [Environment Configuration](#environment-configuration)
5. [Authentication](#authentication)
6. [Core API Client](#core-api-client)
7. [API Documentation](#api-documentation)
8. [Data Models](#data-models)
9. [Repository Pattern](#repository-pattern)
10. [Use Cases](#use-cases)
11. [Order Management](#order-management)
12. [User Management](#user-management)
13. [Pricing and Rates](#pricing-and-rates)
14. [WebView Integration](#webview-integration)
15. [Error Handling](#error-handling)
16. [Testing](#testing)
17. [Complete Implementation Example](#complete-implementation-example)

## Overview

This guide provides comprehensive documentation for integrating Bull Bitcoin exchange features into a Flutter/Dart wallet application. The integration follows clean architecture principles with clear separation between data, domain, and presentation layers.

### Hybrid Integration Approach

Bull Bitcoin API integration uses a **hybrid approach** that combines native API calls with WebView (iframe-like) integration, depending on the feature complexity and security requirements:

#### Features Using WebView Integration

The following features use embedded WebView components instead of native API integration:

1. **User Authentication & Login**
   - **Why WebView**: Handles complex OAuth flows, multi-factor authentication, and session management securely
   - **Implementation**: Embedded web authentication page with automatic API key generation
   - **Security**: Prevents credential exposure to the mobile app and maintains Bull Bitcoin's security standards

2. **KYC (Know Your Customer) Process**
   - **Why WebView**: Extremely complex compliance workflows involving document uploads, identity verification, and regulatory requirements
   - **Implementation**: Full KYC web application embedded in WebView
   - **Complexity**: Requires deep knowledge of international compliance regulations and Bull Bitcoin's internal verification processes

3. **Account Security Settings**
   - **Why WebView**: Sensitive operations like 2FA setup, password changes, and security preferences
   - **Implementation**: Security settings web interface embedded in WebView
   - **Security**: Critical security operations handled by Bull Bitcoin's secure web infrastructure

#### Features Using Native API Integration

The following features use direct API calls for optimal mobile experience:

1. **Bitcoin Buy/Sell Orders**
   - **Why Native**: Real-time order management with mobile-optimized UI
   - **Implementation**: JSON-RPC API calls with custom Flutter interfaces

2. **Order Management & Tracking**
   - **Why Native**: Real-time status updates and mobile-friendly order tracking
   - **Implementation**: Native API calls with Flutter state management

3. **Real-time Pricing & Rate Conversion**
   - **Why Native**: Frequent updates and seamless integration with wallet balance displays
   - **Implementation**: Direct API calls with local caching and streaming updates

4. **User Profile & Balance Information**
   - **Why Native**: Core wallet functionality requiring tight integration
   - **Implementation**: Native API calls with local state management

5. **Fiat Payment Processing**
   - **Why Native**: Transaction flows that integrate with wallet operations
   - **Implementation**: API-based order creation and confirmation

6. **Withdrawal Orders**
   - **Why Native**: Financial operations requiring mobile-optimized confirmation flows
   - **Implementation**: Native API calls with secure confirmation processes

#### Rationale for Hybrid Approach

**Security Considerations:**
- **WebView for Authentication**: Prevents credential handling in mobile app code, reducing attack surface
- **WebView for Compliance**: Ensures regulatory requirements are met through Bull Bitcoin's certified web infrastructure
- **Native for Transactions**: Provides transparent, auditable transaction flows while maintaining security

**Complexity Management:**
- **WebView for Complex Workflows**: Features like KYC require extensive domain knowledge of compliance regulations, document processing, and verification workflows that would be impractical to implement natively
- **WebView for Regulatory Compliance**: Bull Bitcoin's web interfaces are continuously updated to meet evolving regulatory requirements across multiple jurisdictions
- **Native for Core Functionality**: Trading and wallet operations benefit from native mobile UX and real-time performance

**Development Efficiency:**
- **Reduced Implementation Complexity**: Developers can focus on core wallet functionality while leveraging Bull Bitcoin's proven web interfaces for complex workflows
- **Automatic Updates**: WebView-integrated features automatically receive updates without requiring app store releases
- **Consistent User Experience**: Users get the same verified, compliant experience across web and mobile platforms

This hybrid approach allows wallet developers to integrate Bull Bitcoin's full feature set while maintaining security, compliance, and development efficiency.

### Supported Features

- User authentication and API key management
- Bitcoin buy/sell orders
- Fiat payment processing
- Withdrawal orders
- Real-time pricing in multiple currencies
- KYC (Know Your Customer) process
- User profile and balance management
- Order history and tracking
- Multi-network support (Bitcoin, Lightning, Liquid)

### Supported Networks

- **Bitcoin Mainnet/Testnet**: On-chain transactions
- **Lightning Network**: Instant payments
- **Liquid Network**: Faster settlements

### Supported Currencies

- USD (United States Dollar)
- CAD (Canadian Dollar)
- EUR (Euro)
- MXN (Mexican Peso)
- CRC (Costa Rican Colón)

## Architecture

The integration follows a layered architecture:

```
lib/
├── core/
│   └── exchange/
│       ├── data/
│       │   ├── datasources/     # API communication
│       │   ├── models/          # Data transfer objects
│       │   ├── mappers/         # Data transformation
│       │   └── repository/      # Repository implementations
│       └── domain/
│           ├── entity/          # Business models
│           ├── repositories/    # Repository contracts
│           ├── usecases/        # Business logic
│           └── errors/          # Domain errors
└── features/
    ├── buy/                     # Buy Bitcoin feature
    ├── sell/                    # Sell Bitcoin feature
    ├── withdraw/                # Withdrawal feature
    ├── pay/                     # Payment feature
    └── exchange/                # Exchange management
```

## API Documentation

This section provides comprehensive documentation for all Bull Bitcoin API endpoints used in the integration.

### Base URLs

- **Mainnet**: `https://api.bullbitcoin.com`
- **Testnet**: `https://api05.bullbitcoin.dev`

### Authentication

All authenticated endpoints require an API key in the request headers:

```http
X-API-Key: your_api_key_here
```

### Request Format

All API requests use JSON-RPC 2.0 format:

```json
{
  "jsonrpc": "2.0",
  "id": "request_id",
  "method": "method_name",
  "params": {
    // method parameters
  }
}
```

### Response Format

All API responses follow JSON-RPC 2.0 format:

```json
{
  "jsonrpc": "2.0",
  "id": "request_id",
  "result": {
    // response data
  }
}
```

Error responses:

```json
{
  "jsonrpc": "2.0",
  "id": "request_id",
  "error": {
    "code": -32000,
    "message": "Error message",
    "data": {
      // error details
    }
  }
}
```

### Pricing Endpoints

#### Get Bitcoin Price

**Endpoint**: `POST /public/price`  
**Authentication**: None required  
**Description**: Get current Bitcoin price in specified fiat currency  
**App Usage**: Used for real-time price display in wallet UI and order amount calculations

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "getRate",
  "params": {
    "element": {
      "fromCurrency": "BTC",
      "toCurrency": "USD"
    }
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "element": {
      "indexPrice": 5000000,
      "precision": 2,
      "fromCurrency": "BTC",
      "toCurrency": "USD"
    }
  }
}
```

**Supported Currencies**: USD, CAD, EUR, MXN, CRC

### User Management Endpoints

#### Get User Summary

**Endpoint**: `POST /ak/api-users`  
**Authentication**: Required  
**Description**: Get user profile, balances, and settings  
**App Usage**: Called on app startup and after login to populate user dashboard, account balances, and DCA settings

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "getUserSummary",
  "params": {}
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "userNumber": 12345,
    "groups": ["verified"],
    "profile": {
      "firstName": "John",
      "lastName": "Doe"
    },
    "email": "john.doe@example.com",
    "balances": [
      {
        "amount": 1000.50,
        "currencyCode": "USD"
      },
      {
        "amount": 0.025,
        "currencyCode": "BTC"
      }
    ],
    "language": "en",
    "currency": "USD",
    "dca": {
      "isActive": true,
      "frequency": "weekly",
      "amount": 100.0,
      "address": "bc1qexample..."
    },
    "autoBuy": {
      "isActive": false,
      "addresses": {
        "bitcoin": null,
        "lightning": null,
        "liquid": null
      }
    }
  }
}
```

### Order Management Endpoints

#### Create Buy Order

**Endpoint**: `POST /ak/api-orders`  
**Authentication**: Required  
**Description**: Create a new buy order  
**App Usage**: Called when user taps "Continue" on buy screen after entering amount and Bitcoin address

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "createOrderBuy",
  "params": {
    "fiatCurrency": "USD",
    "fiatAmount": 100.0,
    "network": "bitcoin",
    "isOwner": true,
    "address": "bc1qexample..."
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "result": {
    "orderId": "order_123456789",
    "orderType": "Buy Bitcoin",
    "orderNumber": 12345,
    "exchangeRateAmount": 50000.0,
    "exchangeRateCurrency": "USD",
    "payinAmount": 100.0,
    "payinCurrency": "USD",
    "payoutAmount": 0.002,
    "payoutCurrency": "BTC",
    "orderStatus": "In progress",
    "payinStatus": "Awaiting payment",
    "payoutStatus": "Not started",
    "createdAt": "2024-01-15T10:30:00Z",
    "confirmationDeadline": "2024-01-15T11:30:00Z",
    "bitcoinAddress": "bc1qexample...",
    "triggerType": "manual"
  }
}
```

### Order Status Values

#### Order Status
- `"In progress"` - Order is being processed
- `"Awaiting confirmation"` - Order needs user confirmation
- `"Completed"` - Order has been completed
- `"Canceled"` - Order was canceled
- `"Payment deadline expired"` - Order expired due to timeout
- `"Rejected"` - Order was rejected

#### Network Values

- `"bitcoin"` - Bitcoin mainnet/testnet
- `"lightning"` - Lightning Network
- `"liquid"` - Liquid Network

### Rate Limiting

API requests are rate limited to prevent abuse:
- **Public endpoints**: 100 requests per minute
- **Authenticated endpoints**: 1000 requests per minute per API key

This comprehensive guide provides everything needed to integrate Bull Bitcoin exchange features into a Flutter/Dart wallet application. The implementation follows clean architecture principles, includes proper error handling, and provides examples for all major features including buy/sell orders, user management, pricing, and WebView integration for authentication and KYC processes.

## Dependencies

Add the following dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  # Core Flutter
  flutter:
    sdk: flutter
  
  # State Management
  flutter_bloc: ^8.1.6
  
  # Dependency Injection
  get_it: ^7.2.0
  
  # HTTP Client
  dio: ^5.2.1+1
  
  # Code Generation
  freezed: ^3.0.0
  freezed_annotation: ^3.0.0
  
  # Secure Storage
  flutter_secure_storage: ^9.1.0
  
  # WebView (for authentication)
  webview_flutter: ^4.10.0
  webview_flutter_android: ^4.3.4
  webview_flutter_wkwebview: ^3.18.5
  webview_cookie_manager:
    git:
      url: https://github.com/fryette/webview_cookie_manager.git
      ref: main
  
  # Environment Configuration
  flutter_dotenv: ^5.2.1
  
  # Utilities
  crypto: ^3.0.6
  convert: ^3.1.2

dev_dependencies:
  # Code Generation
  build_runner: ^2.4.9
  json_annotation: ^4.9.0
```

## Environment Configuration

Create a `.env` file in your project root:

```env
# Bull Bitcoin API URLs
BB_API_URL=https://api.bullbitcoin.com
BB_API_TEST_URL=https://api05.bullbitcoin.dev

# Authentication URLs
BB_AUTH_URL=accounts.bullbitcoin.com
BB_AUTH_TEST_URL=accounts05.bullbitcoin.dev

# Basic Authentication (if required)
BASIC_AUTH_USERNAME=your_username
BASIC_AUTH_PASSWORD=your_password
```

Load the environment in your `main.dart`:

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}
```

## Authentication

### API Key Storage

```dart
// lib/core/exchange/data/datasources/bullbitcoin_api_key_datasource.dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BullbitcoinApiKeyDatasource {
  static const String _apiKeyStorageKey = 'exchange_api_key';
  static const String _apiKeyTestnetStorageKey = 'exchange_api_key_testnet';

  final FlutterSecureStorage _secureStorage;

  BullbitcoinApiKeyDatasource({
    required FlutterSecureStorage secureStorage,
  }) : _secureStorage = secureStorage;

  Future<void> store(
    ExchangeApiKeyModel apiKey, {
    required bool isTestnet,
  }) async {
    final jsonString = jsonEncode(apiKey.toJson());
    final key = isTestnet ? _apiKeyTestnetStorageKey : _apiKeyStorageKey;
    await _secureStorage.write(key: key, value: jsonString);
  }

  Future<ExchangeApiKeyModel?> get({required bool isTestnet}) async {
    final key = isTestnet ? _apiKeyTestnetStorageKey : _apiKeyStorageKey;
    final jsonString = await _secureStorage.read(key: key);

    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }

    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return ExchangeApiKeyModel.fromJson(json);
  }

  Future<void> delete({required bool isTestnet}) async {
    final key = isTestnet ? _apiKeyTestnetStorageKey : _apiKeyStorageKey;
    await _secureStorage.delete(key: key);
  }
}
```

### API Key Model

```dart
// lib/core/exchange/data/models/api_key_model.dart
class ExchangeApiKeyModel {
  final String id;
  final String key;
  final String name;
  final String userId;
  final bool isActive;
  final int? lastUsedAt;
  final int createdAt;
  final int updatedAt;
  final int? expiresAt;

  ExchangeApiKeyModel({
    required this.id,
    required this.key,
    required this.name,
    required this.userId,
    required this.isActive,
    this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
  });

  factory ExchangeApiKeyModel.fromJson(Map<String, dynamic> json) {
    return ExchangeApiKeyModel(
      id: json['id'] as String,
      key: json['key'] as String,
      name: json['name'] as String,
      userId: json['userId'] as String,
      isActive: json['isActive'] as bool,
      lastUsedAt: json['lastUsedAt'] as int?,
      createdAt: json['createdAt'] is String
          ? DateTime.parse(json['createdAt'] as String).millisecondsSinceEpoch
          : json['createdAt'] as int,
      updatedAt: json['updatedAt'] is String
          ? DateTime.parse(json['updatedAt'] as String).millisecondsSinceEpoch
          : json['updatedAt'] as int,
      expiresAt: json['expiresAt'] != null
          ? (json['expiresAt'] is String
              ? DateTime.parse(json['expiresAt'] as String).millisecondsSinceEpoch
              : json['expiresAt'] as int)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key': key,
      'name': name,
      'userId': userId,
      'isActive': isActive,
      'lastUsedAt': lastUsedAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'expiresAt': expiresAt,
    };
  }
}
```

## Core API Client

### API Constants

```dart
// lib/core/utils/constants.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiServiceConstants {
  // Bull Bitcoin API URLs
  static String bbApiUrl = dotenv.env['BB_API_URL'] ?? 'https://api.bullbitcoin.com';
  static String bbApiTestUrl = dotenv.env['BB_API_TEST_URL'] ?? 'https://api05.bullbitcoin.dev';
  
  // Authentication URLs
  static String bbAuthUrl = 'https://${dotenv.env['BB_AUTH_URL']}';
  static String bbAuthTestUrl = 'https://${dotenv.env['BB_AUTH_TEST_URL']}';
  
  // KYC URLs
  static String bbKycUrl = 'https://app.bullbitcoin.com/kyc';
  static String bbKycTestUrl = 'https://bbx05.bullbitcoin.dev/kyc';
}
```

### Main API Datasource

```dart
// lib/core/exchange/data/datasources/bullbitcoin_api_datasource.dart
import 'dart:math' show pow;
import 'package:dio/dio.dart';

abstract class BitcoinPriceDatasource {
  Future<List<String>> get availableCurrencies;
  Future<double> getPrice(String currencyCode);
}

class BullbitcoinApiDatasource implements BitcoinPriceDatasource {
  final Dio _http;
  final _pricePath = '/public/price';
  final _usersPath = '/ak/api-users';
  final _ordersPath = '/ak/api-orders';
  final _recipientsPath = '/ak/api-recipients';

  BullbitcoinApiDatasource({required Dio bullbitcoinApiHttpClient})
      : _http = bullbitcoinApiHttpClient;

  @override
  Future<List<String>> get availableCurrencies async {
    return ['USD', 'CAD', 'MXN', 'CRC', 'EUR'];
  }

  @override
  Future<double> getPrice(String currencyCode) async {
    try {
      final resp = await _http.post(
        _pricePath,
        data: {
          'id': 1,
          'jsonrpc': '2.0',
          'method': 'getRate',
          'params': {
            'element': {
              'fromCurrency': 'BTC',
              'toCurrency': currencyCode.toUpperCase(),
            },
          },
        },
      );

      if (resp.statusCode != 200) {
        throw Exception('Failed to fetch price');
      }

      final data = resp.data as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>;
      final element = result['element'] as Map<String, dynamic>;

      final price = (element['indexPrice'] as num).toDouble();
      final precision = element['precision'] as int? ?? 2;

      // Convert price based on precision
      final rate = price / pow(10, precision);
      return rate;
    } catch (e) {
      throw Exception('Failed to get price: $e');
    }
  }

  // User Management
  Future<UserSummaryModel?> getUserSummary(String apiKey) async {
    final resp = await _http.post(
      _usersPath,
      data: {
        'id': 1,
        'jsonrpc': '2.0',
        'method': 'getUserSummary',
        'params': {},
      },
      options: Options(headers: {'X-API-Key': apiKey}),
    );

    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch user summary');
    }

    return UserSummaryModel.fromJson(
      resp.data['result'] as Map<String, dynamic>,
    );
  }

  // Buy Orders
  Future<OrderModel> createBuyOrder({
    required String apiKey,
    required FiatCurrency fiatCurrency,
    required OrderAmount orderAmount,
    required Network network,
    required bool isOwner,
    required String address,
  }) async {
    final params = {
      'fiatCurrency': fiatCurrency.code,
      'network': network.value,
      'isOwner': isOwner,
      'address': address,
    };

    if (orderAmount.isFiat) {
      params['fiatAmount'] = orderAmount.amount;
    } else if (orderAmount.isBitcoin) {
      params['bitcoinAmount'] = orderAmount.amount;
    }

    final resp = await _http.post(
      _ordersPath,
      data: {
        'jsonrpc': '2.0',
        'id': '0',
        'method': 'createOrderBuy',
        'params': params,
      },
      options: Options(headers: {'X-API-Key': apiKey}),
    );

    if (resp.statusCode != 200) {
      throw Exception('Failed to create buy order');
    }

    final error = resp.data['error'];
    if (error != null) {
      _handleOrderError(error);
    }

    return OrderModel.fromJson(resp.data['result'] as Map<String, dynamic>);
  }

  // Additional methods for sell orders, payments, etc...
  
  // Error Handling
  void _handleOrderError(Map<String, dynamic> error) {
    final reason = error['data']['reason'];
    final limitReason = reason['limit'];
    
    if (limitReason != null) {
      final isBelowLimit =
          limitReason['conditionalOperator'] == 'GREATER_THAN_OR_EQUAL';
      final limitAmount = limitReason['amount'] as String;
      final limitCurrency = limitReason['currencyCode'] as String;
      
      if (isBelowLimit) {
        throw BullBitcoinApiMinAmountException(
          minAmount: double.parse(limitAmount),
          currency: limitCurrency,
        );
      } else {
        throw BullBitcoinApiMaxAmountException(
          maxAmount: double.parse(limitAmount),
          currency: limitCurrency,
        );
      }
    }
  }
}

// Custom Exceptions
class BullBitcoinApiMinAmountException implements Exception {
  final double minAmount;
  final String currency;

  BullBitcoinApiMinAmountException({
    required this.minAmount,
    required this.currency,
  });

  @override
  String toString() => 'Minimum amount: $minAmount $currency';
}

class BullBitcoinApiMaxAmountException implements Exception {
  final double maxAmount;
  final String currency;

  BullBitcoinApiMaxAmountException({
    required this.maxAmount,
    required this.currency,
  });

  @override
  String toString() => 'Maximum amount: $maxAmount $currency';
}
```

#### Save User Preferences

**Endpoint**: `POST /ak/api-users`  
**Authentication**: Required  
**Description**: Update user language and currency preferences  
**App Usage**: Called when user changes language or preferred currency in settings screen

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "saveUserPreferences",
  "params": {
    "userPreferences": {
      "language": "en",
      "currency": "USD"
    }
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "success": true
  }
}
```

#### Create Sell Order

**Endpoint**: `POST /ak/api-orders`  
**Authentication**: Required  
**Description**: Create a sell order to convert Bitcoin to fiat balance  
**App Usage**: Called when user creates a sell order to convert Bitcoin to fiat balance in their account

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "sellToBalance",
  "params": {
    "fiatCurrency": "USD",
    "bitcoinAmount": 0.001,
    "bitcoinNetwork": "bitcoin"
  }
}
```

**Response**: Same format as buy order response with `orderType: "Sell Bitcoin"`

#### Create Payment Order

**Endpoint**: `POST /ak/api-orders`  
**Authentication**: Required  
**Description**: Create a payment order to send fiat to a recipient  
**App Usage**: Called when user creates a payment to send fiat directly to a recipient using Bitcoin as funding

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "sellToRecipient",
  "params": {
    "fiatAmount": 50.0,
    "recipientId": "recipient_123",
    "paymentProcessor": "interac",
    "bitcoinNetwork": "bitcoin"
  }
}
```

**Response**: Same format as buy order response with `orderType: "Fiat Payment"`

#### Create Withdrawal Order

**Endpoint**: `POST /ak/api-orders`  
**Authentication**: Required  
**Description**: Create a withdrawal order to send fiat to a recipient  
**App Usage**: Called when user withdraws fiat balance from their account to a recipient

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "createWithdrawalOrder",
  "params": {
    "fiatAmount": 100.0,
    "recipientId": "recipient_456",
    "paymentProcessor": "interac"
  }
}
```

**Response**: Same format as buy order response with `orderType: "Withdraw"`

#### Confirm Order

**Endpoint**: `POST /ak/api-orders`  
**Authentication**: Required  
**Description**: Confirm a pending order  
**App Usage**: Called when user taps "Confirm Order" button on order confirmation screen

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "confirmOrderSummary",
  "params": {
    "orderId": "order_123456789"
  }
}
```

**Response**: Same format as order creation response with updated status

#### Get Order Summary

**Endpoint**: `POST /ak/api-orders`  
**Authentication**: Required  
**Description**: Get details of a specific order  
**App Usage**: Called when user taps on an order in the order history to view details

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "getOrderSummary",
  "params": {
    "orderId": "order_123456789"
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "result": {
    "element": {
      // Same order object format as creation response
    }
  }
}
```

#### List Order Summaries

**Endpoint**: `POST /ak/api-orders`  
**Authentication**: Required  
**Description**: Get list of user's orders  
**App Usage**: Called to populate the order history screen with user's past and current orders

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "listOrderSummaries",
  "params": {
    "sortBy": {
      "id": "createdAt",
      "sort": "desc"
    }
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "result": {
    "elements": [
      {
        // Order object format
      },
      {
        // Another order object
      }
    ]
  }
}
```

#### Refresh Order

**Endpoint**: `POST /ak/api-orders`  
**Authentication**: Required  
**Description**: Refresh order status and details  
**App Usage**: Called periodically to update order status in real-time and when user pulls to refresh order details

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "refreshOrderSummary",
  "params": {
    "orderId": "order_123456789"
  }
}
```

**Response**: Same format as order creation response with updated information

#### Accelerate Order (Express Processing)

**Endpoint**: `POST /ak/api-orders`  
**Authentication**: Required  
**Description**: Accelerate order processing for faster execution  
**App Usage**: Called when user taps "Accelerate" button to pay additional fees for faster order processing

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "unbatchAndExpressOrder",
  "params": {
    "orderId": "order_123456789"
  }
}
```

**Response**: Same format as order creation response with updated processing status

### Recipient Management Endpoints

#### List Recipients

**Endpoint**: `POST /ak/api-recipients`  
**Authentication**: Required  
**Description**: Get list of user's recipients  
**App Usage**: Called to populate recipient selection screens for payments and withdrawals

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "listRecipients",
  "params": {}
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "result": {
    "elements": [
      {
        "id": "recipient_123",
        "name": "John Smith",
        "type": "interac",
        "details": {
          "email": "john@example.com"
        }
      }
    ]
  }
}
```

#### List Fiat Recipients

**Endpoint**: `POST /ak/api-recipients`  
**Authentication**: Required  
**Description**: Get list of fiat payment recipients  
**App Usage**: Called specifically for fiat payment flows to show only relevant recipients

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": "0",
  "method": "listRecipientsFiat",
  "params": {}
}
```

**Response**: Same format as `listRecipients`

#### Get Funding Details

**Endpoint**: `POST /ak/api-recipients`  
**Authentication**: Required  
**Description**: Get funding details for a specific payment method  
**App Usage**: Called to show users where to send funding payments (e.g., Interac e-Transfer email address)

### Payin Status
- `"Not started"` - Payment not initiated
- `"Awaiting payment"` - Waiting for payment
- `"In progress"` - Payment being processed
- `"Under review"` - Payment under manual review
- `"Awaiting confirmation"` - Payment needs confirmation
- `"Completed"` - Payment completed
- `"Rejected"` - Payment rejected

### Payout Status
- `"Not started"` - Payout not initiated
- `"In progress"` - Payout being processed
- `"Scheduled"` - Payout scheduled
- `"Awaiting claim"` - Payout waiting to be claimed
- `"Completed"` - Payout completed
- `"Canceled"` - Payout canceled

### Payment Processors

- `"interac"` - Interac e-Transfer (Canada)
- `"wire"` - Wire transfer
- `"sepa"` - SEPA transfer (Europe)

### Error Codes

#### Common Error Codes
- `-32000` - Server error with additional data
- `-32600` - Invalid request
- `-32601` - Method not found
- `-32602` - Invalid parameters
- `-32603` - Internal error

#### Business Logic Errors
- Amount below minimum limit
- Amount above maximum limit
- Insufficient balance
- Invalid recipient
- Order not found
- Order already confirmed
- Invalid network
- Invalid currency

### Webhook Notifications

Bull Bitcoin can send webhook notifications for order status updates. Contact support to configure webhooks for your integration.

**Webhook Payload Example**:
```json
{
  "event": "order.status_changed",
  "data": {
    "orderId": "order_123456789",
    "oldStatus": "In progress",
    "newStatus": "Completed",
    "timestamp": "2024-01-15T12:00:00Z"
  }
}
```

### Testing

Use the testnet environment for development and testing:
- **Base URL**: `https://api05.bullbitcoin.dev`
- **Auth URL**: `https://accounts05.bullbitcoin.dev`
- **KYC URL**: `https://bbx05.bullbitcoin.dev/kyc`

Test orders will not process real money and Bitcoin addresses should use testnet format (starting with `tb1` or `2`).

## Data Models

### Domain Entities

```dart
// lib/core/exchange/domain/entity/order.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'order.freezed.dart';

enum FiatCurrency {
  usd('USD', decimals: 2),
  cad('CAD', decimals: 2),
  crc('CRC', decimals: 2),
  eur('EUR', decimals: 2),
  mxn('MXN', decimals: 2);

  const FiatCurrency(this.code, {required this.decimals});
  final String code;
  final int decimals;

  static FiatCurrency fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'USD':
        return FiatCurrency.usd;
      case 'CAD':
        return FiatCurrency.cad;
      case 'CRC':
        return FiatCurrency.crc;
      case 'EUR':
        return FiatCurrency.eur;
      case 'MXN':
        return FiatCurrency.mxn;
      default:
        throw Exception('Unknown FiatCurrency: $code');
    }
  }
}

enum Network {
  lightning,
  bitcoin,
  liquid;

  String get value {
    switch (this) {
      case Network.lightning:
        return 'lightning';
      case Network.bitcoin:
        return 'bitcoin';
      case Network.liquid:
        return 'liquid';
    }
  }
}

sealed class OrderAmount {
  final double amount;
  const OrderAmount(this.amount);

  bool get isFiat => this is FiatAmount;
  bool get isBitcoin => this is BitcoinAmount;
}

class FiatAmount extends OrderAmount {
  const FiatAmount(super.amount);
}

class BitcoinAmount extends OrderAmount {
  const BitcoinAmount(super.amount);
}

enum OrderType {
  buy('Buy Bitcoin'),
  sell('Sell Bitcoin'),
  fiatPayment('Fiat Payment'),
  funding('Funding'),
  withdraw('Withdraw'),
  reward('Reward'),
  refund('Refund'),
  balanceAdjustment('Balance Adjustment');

  final String value;
  const OrderType(this.value);
}

enum OrderStatus {
  canceled('Canceled'),
  expired('Payment deadline expired'),
  inProgress('In progress'),
  awaitingConfirmation('Awaiting confirmation'),
  completed('Completed'),
  rejected('Rejected');

  final String value;
  const OrderStatus(this.value);
}

@freezed
sealed class Order with _$Order {
  const factory Order.buy({
    required String orderId,
    required int orderNumber,
    required OrderStatus status,
    required double exchangeRateAmount,
    required String exchangeRateCurrency,
    required double payinAmount,
    required String payinCurrency,
    required double payoutAmount,
    required String payoutCurrency,
    required DateTime createdAt,
    DateTime? completedAt,
    String? bitcoinAddress,
    String? lightningInvoice,
    String? liquidAddress,
    String? bitcoinTransactionId,
    String? liquidTransactionId,
    required bool isTestnet,
  }) = BuyOrder;

  const factory Order.sell({
    required String orderId,
    required int orderNumber,
    required OrderStatus status,
    required double exchangeRateAmount,
    required String exchangeRateCurrency,
    required double payinAmount,
    required String payinCurrency,
    required double payoutAmount,
    required String payoutCurrency,
    required DateTime createdAt,
    DateTime? completedAt,
    String? bitcoinAddress,
    String? lightningInvoice,
    String? liquidAddress,
    required bool isTestnet,
  }) = SellOrder;

  const factory Order.fiatPayment({
    required String orderId,
    required int orderNumber,
    required OrderStatus status,
    required double exchangeRateAmount,
    required String exchangeRateCurrency,
    required double payinAmount,
    required String payinCurrency,
    required double payoutAmount,
    required String payoutCurrency,
    required DateTime createdAt,
    DateTime? completedAt,
    String? recipientName,
    required bool isTestnet,
  }) = FiatPaymentOrder;

  const factory Order.withdraw({
    required String orderId,
    required int orderNumber,
    required OrderStatus status,
    required double exchangeRateAmount,
    required String exchangeRateCurrency,
    required double payinAmount,
    required String payinCurrency,
    required double payoutAmount,
    required String payoutCurrency,
    required DateTime createdAt,
    DateTime? completedAt,
    String? recipientName,
    required bool isTestnet,
  }) = WithdrawOrder;
}
```

### Data Transfer Objects

```dart
// lib/core/exchange/data/models/order_model.dart
class OrderModel {
  final String orderId;
  final String orderType;
  final int orderNumber;
  final double exchangeRateAmount;
  final String exchangeRateCurrency;
  final double payinAmount;
  final String payinCurrency;
  final double payoutAmount;
  final String payoutCurrency;
  final String orderStatus;
  final String createdAt;
  final String? completedAt;
  final String? bitcoinAddress;
  final String? lightningInvoice;
  final String? liquidAddress;
  final String? bitcoinTransactionId;
  final String? liquidTransactionId;
  // ... other fields

  OrderModel({
    required this.orderId,
    required this.orderType,
    required this.orderNumber,
    required this.exchangeRateAmount,
    required this.exchangeRateCurrency,
    required this.payinAmount,
    required this.payinCurrency,
    required this.payoutAmount,
    required this.payoutCurrency,
    required this.orderStatus,
    required this.createdAt,
    this.completedAt,
    this.bitcoinAddress,
    this.lightningInvoice,
    this.liquidAddress,
    this.bitcoinTransactionId,
    this.liquidTransactionId,
    // ... other fields
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      orderId: json['orderId'] as String,
      orderType: json['orderType'] as String,
      orderNumber: json['orderNumber'] as int,
      exchangeRateAmount: (json['exchangeRateAmount'] as num).toDouble(),
      exchangeRateCurrency: json['exchangeRateCurrency'] as String,
      payinAmount: (json['payinAmount'] as num).toDouble(),
      payinCurrency: json['payinCurrency'] as String,
      payoutAmount: (json['payoutAmount'] as num).toDouble(),
      payoutCurrency: json['payoutCurrency'] as String,
      orderStatus: json['orderStatus'] as String,
      createdAt: json['createdAt'] as String,
      completedAt: json['completedAt'] as String?,
      bitcoinAddress: json['bitcoinAddress'] as String?,
      lightningInvoice: json['lightningInvoice'] as String?,
      liquidAddress: json['liquidAddress'] as String?,
      bitcoinTransactionId: json['bitcoinTransactionId'] as String?,
      liquidTransactionId: json['liquidTransactionId'] as String?,
      // ... other fields
    );
  }

  Order toEntity({required bool isTestnet}) {
    final status = OrderStatus.values.firstWhere(
      (e) => e.value == orderStatus,
      orElse: () => OrderStatus.inProgress,
    );

    final createdAtDateTime = DateTime.parse(createdAt);
    final completedAtDateTime = completedAt != null ? DateTime.parse(completedAt!) : null;

    switch (orderType.toLowerCase()) {
      case 'buy':
        return Order.buy(
          orderId: orderId,
          orderNumber: orderNumber,
          status: status,
          exchangeRateAmount: exchangeRateAmount,
          exchangeRateCurrency: exchangeRateCurrency,
          payinAmount: payinAmount,
          payinCurrency: payinCurrency,
          payoutAmount: payoutAmount,
          payoutCurrency: payoutCurrency,
          createdAt: createdAtDateTime,
          completedAt: completedAtDateTime,
          bitcoinAddress: bitcoinAddress,
          lightningInvoice: lightningInvoice,
          liquidAddress: liquidAddress,
          bitcoinTransactionId: bitcoinTransactionId,
          liquidTransactionId: liquidTransactionId,
          isTestnet: isTestnet,
        );
      case 'sell':
        return Order.sell(
          orderId: orderId,
          orderNumber: orderNumber,
          status: status,
          exchangeRateAmount: exchangeRateAmount,
          exchangeRateCurrency: exchangeRateCurrency,
          payinAmount: payinAmount,
          payinCurrency: payinCurrency,
          payoutAmount: payoutAmount,
          payoutCurrency: payoutCurrency,
          createdAt: createdAtDateTime,
          completedAt: completedAtDateTime,
          bitcoinAddress: bitcoinAddress,
          lightningInvoice: lightningInvoice,
          liquidAddress: liquidAddress,
          isTestnet: isTestnet,
        );
      // ... other order types
      default:
        throw Exception('Unknown order type: $orderType');
    }
  }
}
```

## Repository Pattern

### Repository Interface

```dart
// lib/core/exchange/domain/repositories/exchange_order_repository.dart
abstract class ExchangeOrderRepository {
  Future<BuyOrder> placeBuyOrder({
    required String toAddress,
    required OrderAmount orderAmount,
    required FiatCurrency currency,
    required Network network,
    required bool isOwner,
  });

  Future<SellOrder> placeSellOrder({
    required OrderAmount orderAmount,
    required FiatCurrency currency,
    required Network network,
  });

  Future<FiatPaymentOrder> placePayOrder({
    required OrderAmount orderAmount,
    required String recipientId,
    required String paymentProcessor,
    required Network network,
  });

  Future<WithdrawOrder> placeWithdrawalOrder({
    required double fiatAmount,
    required String recipientId,
    required String paymentProcessor,
  });

  Future<BuyOrder> confirmBuyOrder(String orderId);
  Future<WithdrawOrder> confirmWithdrawOrder(String orderId);
  Future<BuyOrder> refreshBuyOrder(String orderId);
  Future<SellOrder> refreshSellOrder(String orderId);
  Future<BuyOrder> accelerateBuyOrder(String orderId);
  Future<Order> getOrder(String orderId);
  Future<Order?> getOrderByTxId(String txId);
  Future<List<Order>> getOrders({int? limit, int? offset, OrderType? type});
}
```

### Repository Implementation

```dart
// lib/core/exchange/data/repository/exchange_order_repository_impl.dart
class ExchangeOrderRepositoryImpl implements ExchangeOrderRepository {
  final BullbitcoinApiDatasource _bullbitcoinApiDatasource;
  final BullbitcoinApiKeyDatasource _bullbitcoinApiKeyDatasource;
  final bool _isTestnet;

  ExchangeOrderRepositoryImpl({
    required BullbitcoinApiDatasource bullbitcoinApiDatasource,
    required BullbitcoinApiKeyDatasource bullbitcoinApiKeyDatasource,
    required bool isTestnet,
  }) : _bullbitcoinApiDatasource = bullbitcoinApiDatasource,
       _bullbitcoinApiKeyDatasource = bullbitcoinApiKeyDatasource,
       _isTestnet = isTestnet;

  @override
  Future<BuyOrder> placeBuyOrder({
    required String toAddress,
    required OrderAmount orderAmount,
    required FiatCurrency currency,
    required Network network,
    required bool isOwner,
  }) async {
    final apiKeyModel = await _getValidApiKey();

    try {
      final orderModel = await _bullbitcoinApiDatasource.createBuyOrder(
        apiKey: apiKeyModel.key,
        fiatCurrency: currency,
        orderAmount: orderAmount,
        network: network,
        isOwner: isOwner,
        address: toAddress,
      );

      final order = orderModel.toEntity(isTestnet: _isTestnet);
      if (order is! BuyOrder) {
        throw Exception('Expected BuyOrder but got ${order.runtimeType}');
      }
      return order;
    } on BullBitcoinApiMinAmountException catch (e) {
      throw BuyError.belowMinAmount(
        minAmountSat: (e.minAmount * 100000000).round(),
      );
    } on BullBitcoinApiMaxAmountException catch (e) {
      throw BuyError.aboveMaxAmount(
        maxAmountSat: (e.maxAmount * 100000000).round(),
      );
    } catch (e) {
      throw BuyError.unexpected(message: e.toString());
    }
  }

  Future<ExchangeApiKeyModel> _getValidApiKey() async {
    final apiKeyModel = await _bullbitcoinApiKeyDatasource.get(
      isTestnet: _isTestnet,
    );

    if (apiKeyModel == null) {
      throw ApiKeyException(
        'API key not found. Please login to your Bull Bitcoin account.',
      );
    }

    if (!apiKeyModel.isActive) {
      throw ApiKeyException(
        'API key is inactive. Please login again to your Bull Bitcoin account.',
      );
    }

    return apiKeyModel;
  }

  // Implement other methods...
}
```

## Use Cases

### Buy Order Use Case

```dart
// lib/features/buy/domain/create_buy_order_usecase.dart
class CreateBuyOrderUsecase {
  final ExchangeOrderRepository _mainnetExchangeOrderRepository;
  final ExchangeOrderRepository _testnetExchangeOrderRepository;
  final SettingsRepository _settingsRepository;

  CreateBuyOrderUsecase({
    required ExchangeOrderRepository mainnetExchangeOrderRepository,
    required ExchangeOrderRepository testnetExchangeOrderRepository,
    required SettingsRepository settingsRepository,
  }) : _mainnetExchangeOrderRepository = mainnetExchangeOrderRepository,
       _testnetExchangeOrderRepository = testnetExchangeOrderRepository,
       _settingsRepository = settingsRepository;

  Future<BuyOrder> execute({
    required String toAddress,
    required OrderAmount orderAmount,
    required FiatCurrency currency,
    required bool isLiquid,
    required bool isOwner,
  }) async {
    try {
      final settings = await _settingsRepository.fetch();
      final isTestnet = settings.environment.isTestnet;
      final repo = isTestnet
          ? _testnetExchangeOrderRepository
          : _mainnetExchangeOrderRepository;
      final network = isLiquid ? Network.liquid : Network.bitcoin;
      
      final order = await repo.placeBuyOrder(
        toAddress: toAddress,
        orderAmount: orderAmount,
        currency: currency,
        network: network,
        isOwner: isOwner,
      );
      
      return order;
    } on BuyError {
      rethrow;
    } catch (e) {
      throw BuyError.unexpected(message: '$e');
    }
  }
}
```

### Pricing Use Case

```dart
// lib/core/exchange/domain/usecases/convert_sats_to_currency_amount_usecase.dart
class ConvertSatsToCurrencyAmountUsecase {
  final ExchangeRateRepository _mainnetExchangeRateRepository;
  final ExchangeRateRepository _testnetExchangeRateRepository;
  final SettingsRepository _settingsRepository;

  ConvertSatsToCurrencyAmountUsecase({
    required ExchangeRateRepository mainnetExchangeRateRepository,
    required ExchangeRateRepository testnetExchangeRateRepository,
    required SettingsRepository settingsRepository,
  }) : _mainnetExchangeRateRepository = mainnetExchangeRateRepository,
       _testnetExchangeRateRepository = testnetExchangeRateRepository,
       _settingsRepository = settingsRepository;

  Future<double> execute({
    required String currencyCode,
    int satoshis = 100000000, // 1 BTC in satoshis
  }) async {
    try {
      final settings = await _settingsRepository.fetch();
      final isTestnet = settings.environment.isTestnet;
      final repo = isTestnet
          ? _testnetExchangeRateRepository
          : _mainnetExchangeRateRepository;

      final rate = await repo.getPrice(currencyCode);
      final btcAmount = satoshis / 100000000.0;
      return rate * btcAmount;
    } catch (e) {
      throw ConvertSatsToCurrencyAmountException(
        'Failed to convert satoshis to currency: $e',
      );
    }
  }
}
```

## Order Management

### Complete Buy Order Flow

```dart
class BuyOrderManager {
  final CreateBuyOrderUsecase _createBuyOrderUsecase;
  final ConfirmBuyOrderUsecase _confirmBuyOrderUsecase;
  final RefreshBuyOrderUsecase _refreshBuyOrderUsecase;

  BuyOrderManager({
    required CreateBuyOrderUsecase createBuyOrderUsecase,
    required ConfirmBuyOrderUsecase confirmBuyOrderUsecase,
    required RefreshBuyOrderUsecase refreshBuyOrderUsecase,
  }) : _createBuyOrderUsecase = createBuyOrderUsecase,
       _confirmBuyOrderUsecase = confirmBuyOrderUsecase,
       _refreshBuyOrderUsecase = refreshBuyOrderUsecase;

  Future<BuyOrder> createAndConfirmBuyOrder({
    required String toAddress,
    required double fiatAmount,
    required FiatCurrency currency,
    required bool isLiquid,
  }) async {
    // Step 1: Create the order
    final order = await _createBuyOrderUsecase.execute(
      toAddress: toAddress,
      orderAmount: FiatAmount(fiatAmount),
      currency: currency,
      isLiquid: isLiquid,
      isOwner: true,
    );

    print('Order created: ${order.orderId}');
    print('Amount: ${order.payinAmount} ${order.payinCurrency}');
    print('Bitcoin amount: ${order.payoutAmount} ${order.payoutCurrency}');
    print('Rate: ${order.exchangeRateAmount} ${order.exchangeRateCurrency}');

    // Step 2: Confirm the order
    final confirmedOrder = await _confirmBuyOrderUsecase.execute(
      orderId: order.orderId,
    );

    print('Order confirmed: ${confirmedOrder.orderId}');
    print('Status: ${confirmedOrder.status}');

    return confirmedOrder;
  }

  Future<BuyOrder> trackOrderProgress(String orderId) async {
    BuyOrder order;
    
    do {
      await Future.delayed(const Duration(seconds: 30));
      order = await _refreshBuyOrderUsecase.execute(orderId: orderId);
      print('Order ${order.orderId} status: ${order.status}');
    } while (order.status == OrderStatus.inProgress);

    return order;
  }
}
```

## User Management

### User Summary Management

```dart
// lib/core/exchange/domain/usecases/get_exchange_user_summary_usecase.dart
class GetExchangeUserSummaryUsecase {
  final ExchangeUserRepository _mainnetExchangeUserRepository;
  final ExchangeUserRepository _testnetExchangeUserRepository;
  final SettingsRepository _settingsRepository;

  GetExchangeUserSummaryUsecase({
    required ExchangeUserRepository mainnetExchangeUserRepository,
    required ExchangeUserRepository testnetExchangeUserRepository,
    required SettingsRepository settingsRepository,
  }) : _mainnetExchangeUserRepository = mainnetExchangeUserRepository,
       _testnetExchangeUserRepository = testnetExchangeUserRepository,
       _settingsRepository = settingsRepository;

  Future<UserSummary> execute() async {
    final settings = await _settingsRepository.fetch();
    final isTestnet = settings.environment.isTestnet;
    final repo = isTestnet
        ? _testnetExchangeUserRepository
        : _mainnetExchangeUserRepository;

    return await repo.getUserSummary();
  }
}

// Usage Example
class UserManager {
  final GetExchangeUserSummaryUsecase _getUserSummaryUsecase;

  UserManager({required GetExchangeUserSummaryUsecase getUserSummaryUsecase})
      : _getUserSummaryUsecase = getUserSummaryUsecase;

  Future<void> displayUserInfo() async {
    try {
      final userSummary = await _getUserSummaryUsecase.execute();
      
      print('User: ${userSummary.profile.firstName} ${userSummary.profile.lastName}');
      print('Email: ${userSummary.email}');
      print('User Number: ${userSummary.userNumber}');
      print('Groups: ${userSummary.groups.join(', ')}');
      
      print('\nBalances:');
      for (final balance in userSummary.balances) {
        print('  ${balance.currencyCode}: ${balance.amount}');
      }
      
      print('\nDCA Settings:');
      print('  Active: ${userSummary.dca.isActive}');
      if (userSummary.dca.isActive) {
        print('  Frequency: ${userSummary.dca.frequency}');
        print('  Amount: ${userSummary.dca.amount}');
        print('  Address: ${userSummary.dca.address}');
      }
    } catch (e) {
      print('Error fetching user summary: $e');
    }
  }
}
```

## Pricing and Rates

### Real-time Price Updates

```dart
class PriceManager {
  final ConvertSatsToCurrencyAmountUsecase _convertSatsToCurrencyUsecase;
  final GetAvailableCurrenciesUsecase _getAvailableCurrenciesUsecase;

  PriceManager({
    required ConvertSatsToCurrencyAmountUsecase convertSatsToCurrencyUsecase,
    required GetAvailableCurrenciesUsecase getAvailableCurrenciesUsecase,
  }) : _convertSatsToCurrencyUsecase = convertSatsToCurrencyUsecase,
       _getAvailableCurrenciesUsecase = getAvailableCurrenciesUsecase;

  Future<Map<String, double>> getAllPrices() async {
    final currencies = await _getAvailableCurrenciesUsecase.execute();
    final prices = <String, double>{};

    for (final currency in currencies) {
      try {
        final price = await _convertSatsToCurrencyUsecase.execute(
          currencyCode: currency.code,
          satoshis: 100000000, // 1 BTC
        );
        prices[currency.code] = price;
      } catch (e) {
        print('Failed to get price for ${currency.code}: $e');
      }
    }

    return prices;
  }

  Stream<Map<String, double>> getPriceStream({
    Duration interval = const Duration(seconds: 30),
  }) async* {
    while (true) {
      try {
        final prices = await getAllPrices();
        yield prices;
      } catch (e) {
        print('Error fetching prices: $e');
      }
      await Future.delayed(interval);
    }
  }

  Future<double> convertSatsToFiat({
    required int satoshis,
    required String currencyCode,
  }) async {
    return await _convertSatsToCurrencyUsecase.execute(
      currencyCode: currencyCode,
      satoshis: satoshis,
    );
  }

  Future<int> convertFiatToSats({
    required double fiatAmount,
    required String currencyCode,
  }) async {
    final oneBtcInFiat = await _convertSatsToCurrencyUsecase.execute(
      currencyCode: currencyCode,
      satoshis: 100000000,
    );
    
    final btcAmount = fiatAmount / oneBtcInFiat;
    return (btcAmount * 100000000).round();
  }
}
```

## WebView Integration

### Authentication WebView

```dart
// lib/features/exchange/ui/screens/exchange_auth_screen.dart
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart';

class ExchangeAuthScreen extends StatefulWidget {
  const ExchangeAuthScreen({super.key});

  @override
  State<ExchangeAuthScreen> createState() => _ExchangeAuthScreenState();
}

class _ExchangeAuthScreenState extends State<ExchangeAuthScreen> {
  late final WebViewController _controller = WebViewController();
  late final WebviewCookieManager _cookieManager = WebviewCookieManager();
  late final String _bbAuthUrl;
  bool _isGeneratingApiKey = false;

  @override
  void initState() {
    super.initState();

    // Determine URL based on environment
    final isTestnet = /* your testnet detection logic */;
    _bbAuthUrl = isTestnet
        ? ApiServiceConstants.bbAuthTestUrl
        : ApiServiceConstants.bbAuthUrl;

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (UrlChange change) async {
            final url = change.url;
            if (url == null) return;

            // Check for session cookie
            final bbSessionCookie = await _tryGetBBSessionCookie(url);
            if (bbSessionCookie == null) return;

            try {
              setState(() => _isGeneratingApiKey = true);

              // Generate API key via JavaScript injection
              final apiKeyData = await _generateApiKey();
              
              // Store API key using your exchange cubit/bloc
              await context.read<ExchangeCubit>().storeApiKey(apiKeyData);
              
            } catch (e) {
              await _handleLoginError();
            } finally {
              if (mounted) {
                setState(() => _isGeneratingApiKey = false);
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_bbAuthUrl));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _isGeneratingApiKey
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: _controller),
    );
  }

  Future<String?> _tryGetBBSessionCookie(String url) async {
    final cookies = await _cookieManager.getCookies(url);
    for (final cookie in cookies) {
      if (cookie.name == 'bb_session') {
        return cookie.value;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _generateApiKey() async {
    final url = '$_bbAuthUrl/api/generate-api-key';

    final result = await _controller.runJavaScriptReturningResult('''
      (function() {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', '$url', false);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.withCredentials = true;
        try {
          xhr.send(JSON.stringify({ 
            apiKeyName: 'wallet-key-' + new Date().getTime() 
          }));
          if (xhr.status >= 200 && xhr.status < 300) {
            return xhr.responseText;
          } else {
            return JSON.stringify({ 
              error: 'Request failed with status: ' + xhr.status 
            });
          }
        } catch (e) {
          return JSON.stringify({error: 'XHR Error: ' + e.toString()});
        }
      })();
    ''') as String;

    // Parse the JavaScript result
    String jsonString = result;
    if (jsonString.startsWith('"') && jsonString.endsWith('"')) {
      jsonString = jsonString
          .substring(1, jsonString.length - 1)
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', '\\');
    }

    return json.decode(jsonString) as Map<String, dynamic>;
  }

  Future<void> _handleLoginError() async {
    await Future.wait([
      _controller.clearCache(),
      _controller.clearLocalStorage(),
      _cookieManager.clearCookies(),
    ]);
    
    await _controller.reload();

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login Failed'),
        content: const Text('An error occurred, please try logging in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
```

### KYC WebView

```dart
// lib/features/exchange/ui/screens/exchange_kyc_screen.dart
class ExchangeKycScreen extends StatefulWidget {
  const ExchangeKycScreen({super.key});

  @override
  State<ExchangeKycScreen> createState() => _ExchangeKycScreenState();
}

class _ExchangeKycScreenState extends State<ExchangeKycScreen> {
  late final WebViewController _controller = WebViewController();
  late final String _bbKycUrl;

  @override
  void initState() {
    super.initState();

    final isTestnet = /* your testnet detection logic */;
    _bbKycUrl = isTestnet
        ? ApiServiceConstants.bbKycTestUrl
        : ApiServiceConstants.bbKycUrl;

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (UrlChange change) {
            final url = Uri.tryParse(change.url ?? '');
            if (url == null) return;

            final isKyc = url.path.startsWith('/kyc');
            final isLogin = url.path.contains('/login');

            if (!isKyc && !isLogin) {
              // User left KYC flow - refresh user summary and close
              context.read<ExchangeCubit>().fetchUserSummary();
              Navigator.of(context).pop();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_bbKycUrl));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: WebViewWidget(controller: _controller));
  }
}
```

## Error Handling

### Domain Errors

```dart
// lib/core/exchange/domain/errors/buy_error.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'buy_error.freezed.dart';

@freezed
sealed class BuyError with _$BuyError {
  const factory BuyError.unauthenticated() = UnauthenticatedBuyError;
  const factory BuyError.belowMinAmount({required int minAmountSat}) = BelowMinAmountBuyError;
  const factory BuyError.aboveMaxAmount({required int maxAmountSat}) = AboveMaxAmountBuyError;
  const factory BuyError.insufficientFunds() = InsufficientFundsBuyError;
  const factory BuyError.orderNotFound() = OrderNotFoundBuyError;
  const factory BuyError.orderAlreadyConfirmed() = OrderAlreadyConfirmedBuyError;
  const factory BuyError.unexpected({required String message}) = UnexpectedBuyError;
}

// Similar error classes for SellError, WithdrawError, PayError
```

### Error Handling in Use Cases

```dart
class CreateBuyOrderUsecase {
  // ... constructor and fields

  Future<BuyOrder> execute({
    required String toAddress,
    required OrderAmount orderAmount,
    required FiatCurrency currency,
    required bool isLiquid,
    required bool isOwner,
  }) async {
    try {
      final settings = await _settingsRepository.fetch();
      final isTestnet = settings.environment.isTestnet;
      final repo = isTestnet
          ? _testnetExchangeOrderRepository
          : _mainnetExchangeOrderRepository;
      final network = isLiquid ? Network.liquid : Network.bitcoin;
      
      final order = await repo.placeBuyOrder(
        toAddress: toAddress,
        orderAmount: orderAmount,
        currency: currency,
        network: network,
        isOwner: isOwner,
      );
      
      return order;
    } on BuyError {
      rethrow; // Re-throw domain errors as-is
    } catch (e) {
      // Convert unexpected errors to domain errors
      throw BuyError.unexpected(message: '$e');
    }
  }
}
```

### Error Handling in UI

```dart
class BuyOrderWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BuyBloc, BuyState>(
      listener: (context, state) {
        final error = state.createOrderBuyError;
        if (error != null) {
          _showErrorDialog(context, error);
        }
      },
      builder: (context, state) {
        return Column(
          children: [
            // Your UI components
            if (state.isCreatingOrder)
              const CircularProgressIndicator(),
            ElevatedButton(
              onPressed: state.isCreatingOrder
                  ? null
                  : () => context.read<BuyBloc>().add(
                        const BuyEvent.createOrder(),
                      ),
              child: const Text('Create Order'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(BuildContext context, BuyError error) {
    final message = error.when(
      unauthenticated: () => 'Please log in to your Bull Bitcoin account.',
      belowMinAmount: (minAmountSat) =>
          'Minimum order amount is ${minAmountSat / 100000000} BTC.',
      aboveMaxAmount: (maxAmountSat) =>
          'Maximum order amount is ${maxAmountSat / 100000000} BTC.',
      insufficientFunds: () => 'Insufficient funds in your account.',
      orderNotFound: () => 'Order not found.',
      orderAlreadyConfirmed: () => 'Order has already been confirmed.',
      unexpected: (message) => 'An unexpected error occurred: $message',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
```

## Testing

### Unit Tests for Use Cases

```dart
// test/features/buy/domain/create_buy_order_usecase_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockExchangeOrderRepository extends Mock implements ExchangeOrderRepository {}
class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  group('CreateBuyOrderUsecase', () {
    late CreateBuyOrderUsecase usecase;
    late MockExchangeOrderRepository mockMainnetRepo;
    late MockExchangeOrderRepository mockTestnetRepo;
    late MockSettingsRepository mockSettingsRepo;

    setUp(() {
      mockMainnetRepo = MockExchangeOrderRepository();
      mockTestnetRepo = MockExchangeOrderRepository();
      mockSettingsRepo = MockSettingsRepository();
      
      usecase = CreateBuyOrderUsecase(
        mainnetExchangeOrderRepository: mockMainnetRepo,
        testnetExchangeOrderRepository: mockTestnetRepo,
        settingsRepository: mockSettingsRepo,
      );
    });

    test('should create buy order successfully on mainnet', () async {
      // Arrange
      final settings = Settings(environment: Environment.mainnet);
      final expectedOrder = BuyOrder(
        orderId: 'test-order-id',
        orderNumber: 12345,
        status: OrderStatus.inProgress,
        exchangeRateAmount: 50000.0,
        exchangeRateCurrency: 'USD',
        payinAmount: 100.0,
        payinCurrency: 'USD',
        payoutAmount: 0.002,
        payoutCurrency: 'BTC',
        createdAt: DateTime.now(),
        isTestnet: false,
      );

      when(() => mockSettingsRepo.fetch()).thenAnswer((_) async => settings);
      when(() => mockMainnetRepo.placeBuyOrder(
            toAddress: any(named: 'toAddress'),
            orderAmount: any(named: 'orderAmount'),
            currency: any(named: 'currency'),
            network: any(named: 'network'),
            isOwner: any(named: 'isOwner'),
          )).thenAnswer((_) async => expectedOrder);

      // Act
      final result = await usecase.execute(
        toAddress: 'bc1qtest123',
        orderAmount: const FiatAmount(100.0),
        currency: FiatCurrency.usd,
        isLiquid: false,
        isOwner: true,
      );

      // Assert
      expect(result, equals(expectedOrder));
      verify(() => mockMainnetRepo.placeBuyOrder(
            toAddress: 'bc1qtest123',
            orderAmount: const FiatAmount(100.0),
            currency: FiatCurrency.usd,
            network: Network.bitcoin,
            isOwner: true,
          )).called(1);
    });

    test('should use testnet repository when in testnet environment', () async {
      // Arrange
      final settings = Settings(environment: Environment.testnet);
      final expectedOrder = BuyOrder(
        orderId: 'test-order-id',
        orderNumber: 12345,
        status: OrderStatus.inProgress,
        exchangeRateAmount: 50000.0,
        exchangeRateCurrency: 'USD',
        payinAmount: 100.0,
        payinCurrency: 'USD',
        payoutAmount: 0.002,
        payoutCurrency: 'BTC',
        createdAt: DateTime.now(),
        isTestnet: true,
      );

      when(() => mockSettingsRepo.fetch()).thenAnswer((_) async => settings);
      when(() => mockTestnetRepo.placeBuyOrder(
            toAddress: any(named: 'toAddress'),
            orderAmount: any(named: 'orderAmount'),
            currency: any(named: 'currency'),
            network: any(named: 'network'),
            isOwner: any(named: 'isOwner'),
          )).thenAnswer((_) async => expectedOrder);

      // Act
      final result = await usecase.execute(
        toAddress: 'tb1qtest123',
        orderAmount: const FiatAmount(100.0),
        currency: FiatCurrency.usd,
        isLiquid: false,
        isOwner: true,
      );

      // Assert
      expect(result, equals(expectedOrder));
      verify(() => mockTestnetRepo.placeBuyOrder(
            toAddress: 'tb1qtest123',
            orderAmount: const FiatAmount(100.0),
            currency: FiatCurrency.usd,
            network: Network.bitcoin,
            isOwner: true,
          )).called(1);
    });

    test('should throw BuyError.unexpected when repository throws unexpected error', () async {
      // Arrange
      final settings = Settings(environment: Environment.mainnet);
      when(() => mockSettingsRepo.fetch()).thenAnswer((_) async => settings);
      when(() => mockMainnetRepo.placeBuyOrder(
            toAddress: any(named: 'toAddress'),
            orderAmount: any(named: 'orderAmount'),
            currency: any(named: 'currency'),
            network: any(named: 'network'),
            isOwner: any(named: 'isOwner'),
          )).thenThrow(Exception('Network error'));

      // Act & Assert
      expect(
        () => usecase.execute(
          toAddress: 'bc1qtest123',
          orderAmount: const FiatAmount(100.0),
          currency: FiatCurrency.usd,
          isLiquid: false,
          isOwner: true,
        ),
        throwsA(isA<BuyError>()),
      );
    });
  });
}
```

### Integration Tests

```dart
// integration_test/bull_bitcoin_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Bull Bitcoin Integration Tests', () {
    testWidgets('complete buy order flow', (WidgetTester tester) async {
      // This test requires a testnet environment and valid API credentials
      
      // 1. Initialize app
      await tester.pumpWidget(MyApp());
      await tester.pumpAndSettle();

      // 2. Navigate to exchange auth
      await tester.tap(find.text('Exchange'));
      await tester.pumpAndSettle();

      // 3. Complete authentication (would require manual intervention in real test)
      // This part would typically be mocked or require a test account

      // 4. Navigate to buy screen
      await tester.tap(find.text('Buy Bitcoin'));
      await tester.pumpAndSettle();

      // 5. Enter buy amount
      await tester.enterText(find.byKey(const Key('buy_amount_field')), '10.00');
      await tester.pumpAndSettle();

      // 6. Select currency
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();

      // 7. Enter Bitcoin address
      await tester.enterText(
        find.byKey(const Key('bitcoin_address_field')),
        'tb1qtest123...',
      );
      await tester.pumpAndSettle();

      // 8. Create order
      await tester.tap(find.text('Create Order'));
      await tester.pumpAndSettle();

      // 9. Verify order creation
      expect(find.text('Order Created'), findsOneWidget);
      expect(find.textContaining('Order ID:'), findsOneWidget);

      // 10. Confirm order
      await tester.tap(find.text('Confirm Order'));
      await tester.pumpAndSettle();

      // 11. Verify order confirmation
      expect(find.text('Order Confirmed'), findsOneWidget);
    });
  });
}
```

## Complete Implementation Example

### Dependency Injection Setup

```dart
// lib/core/exchange/exchange_locator.dart
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ExchangeLocator {
  static void registerDependencies() {
    final locator = GetIt.instance;

    // Secure Storage
    locator.registerLazySingleton<FlutterSecureStorage>(
      () => const FlutterSecureStorage(),
    );

    // API Key Datasource
    locator.registerLazySingleton<BullbitcoinApiKeyDatasource>(
      () => BullbitcoinApiKeyDatasource(
        secureStorage: locator<FlutterSecureStorage>(),
      ),
    );

    // API Datasources
    locator.registerLazySingleton<BullbitcoinApiDatasource>(
      () => BullbitcoinApiDatasource(
        bullbitcoinApiHttpClient: Dio(
          BaseOptions(baseUrl: ApiServiceConstants.bbApiUrl),
        ),
      ),
      instanceName: 'mainnet',
    );

    locator.registerLazySingleton<BullbitcoinApiDatasource>(
      () => BullbitcoinApiDatasource(
        bullbitcoinApiHttpClient: Dio(
          BaseOptions(baseUrl: ApiServiceConstants.bbApiTestUrl),
        ),
      ),
      instanceName: 'testnet',
    );

    // Repositories
    locator.registerLazySingleton<ExchangeOrderRepository>(
      () => ExchangeOrderRepositoryImpl(
        bullbitcoinApiDatasource: locator<BullbitcoinApiDatasource>(
          instanceName: 'mainnet',
        ),
        bullbitcoinApiKeyDatasource: locator<BullbitcoinApiKeyDatasource>(),
        isTestnet: false,
      ),
      instanceName: 'mainnet',
    );

    locator.registerLazySingleton<ExchangeOrderRepository>(
      () => ExchangeOrderRepositoryImpl(
        bullbitcoinApiDatasource: locator<BullbitcoinApiDatasource>(
          instanceName: 'testnet',
        ),
        bullbitcoinApiKeyDatasource: locator<BullbitcoinApiKeyDatasource>(),
        isTestnet: true,
      ),
      instanceName: 'testnet',
    );

    // Use Cases
    locator.registerFactory<CreateBuyOrderUsecase>(
      () => CreateBuyOrderUsecase(
        mainnetExchangeOrderRepository: locator<ExchangeOrderRepository>(
          instanceName: 'mainnet',
        ),
        testnetExchangeOrderRepository: locator<ExchangeOrderRepository>(
          instanceName: 'testnet',
        ),
        settingsRepository: locator<SettingsRepository>(),
      ),
    );

    // Add other use cases...
  }
}
```

### Main Application Setup

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Register dependencies
  ExchangeLocator.registerDependencies();
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => ExchangeCubit(
            getExchangeUserSummaryUsecase: GetIt.instance<GetExchangeUserSummaryUsecase>(),
            saveExchangeApiKeyUsecase: GetIt.instance<SaveExchangeApiKeyUsecase>(),
            saveUserPreferencesUsecase: GetIt.instance<SaveUserPreferencesUsecase>(),
            deleteExchangeApiKeyUsecase: GetIt.instance<DeleteExchangeApiKeyUsecase>(),
          ),
        ),
        BlocProvider(
          create: (context) => BuyBloc(
            createBuyOrderUsecase: GetIt.instance<CreateBuyOrderUsecase>(),
            confirmBuyOrderUsecase: GetIt.instance<ConfirmBuyOrderUsecase>(),
            refreshBuyOrderUsecase: GetIt.instance<RefreshBuyOrderUsecase>(),
            // ... other dependencies
          ),
        ),
        // Add other BLoCs...
      ],
      child: MaterialApp(
        title: 'Bull Bitcoin Wallet',
        theme: ThemeData(
          primarySwatch: Colors.orange,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
```

### Usage Example

```dart
// lib/screens/buy_screen.dart
class BuyScreen extends StatefulWidget {
  @override
  _BuyScreenState createState() => _BuyScreenState();
}

class _BuyScreenState extends State<BuyScreen> {
  final _amountController = TextEditingController();
  final _addressController = TextEditingController();
  FiatCurrency _selectedCurrency = FiatCurrency.usd;
  bool _isLiquid = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buy Bitcoin')),
      body: BlocConsumer<BuyBloc, BuyState>(
        listener: (context, state) {
          if (state.createOrderBuyError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${state.createOrderBuyError}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          
          if (state.buyOrder != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Order created: ${state.buyOrder!.orderId}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                
                DropdownButtonFormField<FiatCurrency>(
                  value: _selectedCurrency,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    border: OutlineInputBorder(),
                  ),
                  items: FiatCurrency.values.map((currency) {
                    return DropdownMenuItem(
                      value: currency,
                      child: Text(currency.code),
                    );
                  }).toList(),
                  onChanged: (currency) {
                    if (currency != null) {
                      setState(() => _selectedCurrency = currency);
                    }
                  },
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Bitcoin Address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                
                SwitchListTile(
                  title: const Text('Use Liquid Network'),
                  value: _isLiquid,
                  onChanged: (value) => setState(() => _isLiquid = value),
                ),
                const SizedBox(height: 32),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: state.isCreatingOrder ? null : _createOrder,
                    child: state.isCreatingOrder
                        ? const CircularProgressIndicator()
                        : const Text('Create Buy Order'),
                  ),
                ),
                
                if (state.buyOrder != null) ...[
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Order ID: ${state.buyOrder!.orderId}'),
                          Text('Status: ${state.buyOrder!.status}'),
                          Text('Amount: ${state.buyOrder!.payinAmount} ${state.buyOrder!.payinCurrency}'),
                          Text('Bitcoin: ${state.buyOrder!.payoutAmount} ${state.buyOrder!.payoutCurrency}'),
                          Text('Rate: ${state.buyOrder!.exchangeRateAmount} ${state.buyOrder!.exchangeRateCurrency}'),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: state.isConfirmingOrder ? null : _confirmOrder,
                              child: state.isConfirmingOrder
                                  ? const CircularProgressIndicator()
                                  : const Text('Confirm Order'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _createOrder() {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (_addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a Bitcoin address')),
      );
      return;
    }

    context.read<BuyBloc>().add(
      BuyEvent.createOrder(
        toAddress: _addressController.text,
        orderAmount: FiatAmount(amount),
        currency: _selectedCurrency,
        isLiquid: _isLiquid,
        isOwner: true,
      ),
    );
  }

  void _confirmOrder() {
    final buyOrder = context.read<BuyBloc>().state.buyOrder;
    if (buyOrder != null) {
      context.read<BuyBloc>().add(
        BuyEvent.confirmOrder(orderId: buyOrder.orderId),
      );
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _addressController.dispose();
    super.dispose();
  }
}
```

This comprehensive guide provides everything needed to integrate Bull Bitcoin exchange features into a Flutter/Dart wallet application. The implementation follows clean architecture principles, includes proper error handling, and provides examples for all major features including buy/sell orders, user management, pricing, and WebView integration for authentication and KYC processes.

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

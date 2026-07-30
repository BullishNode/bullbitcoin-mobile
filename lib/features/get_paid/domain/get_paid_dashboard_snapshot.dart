/// The only Donation Page facts the Get Paid hub renders.
class GetPaidPaymentPageSnapshot {
  final String publicUrl;
  final bool isArchived;

  const GetPaidPaymentPageSnapshot({
    required this.publicUrl,
    required this.isArchived,
  });
}

/// The only Point of Sale facts the Get Paid hub renders.
class GetPaidPosTerminalSnapshot {
  final String terminalUrl;
  final bool isArchived;

  const GetPaidPosTerminalSnapshot({
    required this.terminalUrl,
    required this.isArchived,
  });
}

/// The only BTCPay fact the Get Paid hub renders.
class GetPaidBtcpayConnectionSnapshot {
  final String serverUrl;

  const GetPaidBtcpayConnectionSnapshot({required this.serverUrl});
}

/// Fiat-settlement slots owned by the Get Paid dashboard contract.
enum GetPaidDashboardSettlementProduct { lightningAddress, paymentPage, pos }

enum GetPaidDashboardSettlementMode { bitcoinOnly, mixed, fiatOnly }

/// The presentation-safe portion of one product's settlement configuration.
class GetPaidDashboardSettlementConfig {
  final int fiatPercentage;
  final String? currencyCode;

  const GetPaidDashboardSettlementConfig({
    required this.fiatPercentage,
    required this.currencyCode,
  });

  GetPaidDashboardSettlementMode get mode {
    if (fiatPercentage <= 0) {
      return GetPaidDashboardSettlementMode.bitcoinOnly;
    }
    if (fiatPercentage >= 100) {
      return GetPaidDashboardSettlementMode.fiatOnly;
    }
    return GetPaidDashboardSettlementMode.mixed;
  }
}

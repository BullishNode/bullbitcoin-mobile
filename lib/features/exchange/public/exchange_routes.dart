/// Stable route names and paths exposed by the exchange feature.
enum ExchangeRoute {
  exchangeHome('/exchange'),
  exchangeLanding('/exchange/landing'),
  exchangeLoginForSupport('/exchange/login-support'),
  exchangeAuth('/exchange/auth'),
  exchangeKyc('kyc');

  const ExchangeRoute(this.path);

  final String path;
}

/// Stable route names and paths exposed by the exchange-support feature.
enum ExchangeSupportChatRoute {
  supportChat('/exchange/support-chat');

  const ExchangeSupportChatRoute(this.path);

  final String path;
}

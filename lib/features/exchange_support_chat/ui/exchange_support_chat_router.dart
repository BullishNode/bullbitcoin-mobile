export 'package:bb_mobile/features/exchange_support_chat/public/exchange_support_chat_routes.dart';

import 'package:bb_mobile/features/exchange_support_chat/public/exchange_support_chat_routes.dart';
import 'package:bb_mobile/features/exchange_support_chat/ui/screens/exchange_support_chat_screen.dart';
import 'package:go_router/go_router.dart';

class ExchangeSupportChatRouter {
  static final route = GoRoute(
    name: ExchangeSupportChatRoute.supportChat.name,
    path: ExchangeSupportChatRoute.supportChat.path,
    builder: (context, state) {
      final fromExchange = state.uri.queryParameters['from'] == 'exchange';
      return ExchangeSupportChatScreen(fromExchange: fromExchange);
    },
  );
}

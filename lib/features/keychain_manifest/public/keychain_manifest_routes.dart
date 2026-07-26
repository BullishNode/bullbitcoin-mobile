import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/ui/screens/nostr_keys_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class KeychainManifestRoutes {
  static const nostrKeysName = 'nostrKeys';

  static final nostrKeys = GoRoute(
    name: nostrKeysName,
    path: 'nostr-keys',
    builder: (_, _) => BlocProvider(
      create: (_) => locator<NostrKeysCubit>(),
      child: const NostrKeysScreen(),
    ),
  );
}

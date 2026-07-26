import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/ui/screens/nostr_key_detail_screen.dart';
import 'package:bb_mobile/features/keychain_manifest/ui/screens/nostr_key_form_screen.dart';
import 'package:bb_mobile/features/keychain_manifest/ui/screens/nostr_keys_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class KeychainManifestRoutes {
  static const nostrKeysName = 'nostrKeys';
  static const nostrKeyCreateName = 'nostrKeyCreate';
  static const nostrKeyEditName = 'nostrKeyEdit';
  static const nostrKeyDetailName = 'nostrKeyDetail';

  static final nostrKeys = GoRoute(
    name: nostrKeysName,
    path: 'nostr-keys',
    builder: (_, _) => BlocProvider(
      create: (_) => locator<NostrKeysCubit>(),
      child: const NostrKeysScreen(),
    ),
    // Nested so the list stays the parent in the back stack. Each child builds
    // its own cubit: go_router builds a child route outside the parent
    // builder's provider, and the list reloads when a child pops.
    routes: [
      GoRoute(
        name: nostrKeyCreateName,
        path: 'create',
        builder: (_, _) => BlocProvider(
          create: (_) => locator<NostrKeysCubit>(),
          child: const NostrKeyFormScreen(),
        ),
      ),
      GoRoute(
        name: nostrKeyEditName,
        path: 'edit',
        builder: (_, state) => BlocProvider(
          create: (_) => locator<NostrKeysCubit>(),
          child: NostrKeyFormScreen(
            record: state.extra! as KeychainManifestNostrKeyRecord,
          ),
        ),
      ),
      GoRoute(
        name: nostrKeyDetailName,
        path: 'detail',
        builder: (_, state) => BlocProvider(
          create: (_) => locator<NostrKeysCubit>(),
          child: NostrKeyDetailScreen(
            record: state.extra! as KeychainManifestNostrKeyRecord,
          ),
        ),
      ),
    ],
  );
}

import 'package:bb_mobile/core/mixins/privacy_screen.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class NostrKeysScreen extends StatefulWidget {
  const NostrKeysScreen({super.key});

  @override
  State<NostrKeysScreen> createState() => _NostrKeysScreenState();
}

class _NostrKeysScreenState extends State<NostrKeysScreen> with PrivacyScreen {
  final _revealedNsecs = <String, String>{};

  @override
  void initState() {
    super.initState();
    enableScreenPrivacy();
    context.read<NostrKeysCubit>().load();
  }

  @override
  void dispose() {
    disableScreenPrivacy();
    _revealedNsecs.clear();
    super.dispose();
  }

  Future<void> _createKey() async {
    final purpose = await _purposeDialog();
    if (purpose == null) return;
    final created = await context.read<NostrKeysCubit>().create(purpose);
    if (!mounted || !created) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.loc.settingsNostrKeysCreated)),
    );
  }

  Future<void> _editPurpose(KeychainManifestNostrKeyRecord key) async {
    final purpose = await _purposeDialog(
      initial: key.nostrKeyMaterialization.purpose,
    );
    if (purpose == null ||
        purpose.trim() == key.nostrKeyMaterialization.purpose) {
      return;
    }
    await context.read<NostrKeysCubit>().updatePurpose(
      key: key,
      purpose: purpose,
    );
  }

  Future<void> _reveal(KeychainManifestNostrKeyRecord key) async {
    final nsec = await context.read<NostrKeysCubit>().reveal(key);
    if (!mounted || nsec == null) return;
    setState(() => _revealedNsecs[key.entryId] = nsec);
  }

  void _showFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.loc.settingsNostrKeysFailure)),
    );
  }

  Future<String?> _purposeDialog({String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.settingsNostrKeysPurpose),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(
            hintText: context.loc.settingsNostrKeysPurposeHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: Text(context.loc.settingsNostrKeysSave),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<NostrKeysCubit, NostrKeysState>(
      listenWhen: (previous, current) =>
          previous.failureRevision != current.failureRevision,
      listener: (_, _) => _showFailure(),
      child: BlocBuilder<NostrKeysCubit, NostrKeysState>(
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(context.loc.settingsNostrKeysTitle)),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: state.loading || state.busy ? null : _createKey,
            icon: const Icon(Icons.add),
            label: Text(context.loc.settingsNostrKeysCreate),
          ),
          body: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.keys.isEmpty
              ? Center(child: Text(context.loc.settingsNostrKeysEmpty))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: state.keys.length,
                  separatorBuilder: (_, index) => const Divider(),
                  itemBuilder: (context, index) => _keyTile(state.keys[index]),
                ),
        ),
      ),
    );
  }

  Widget _keyTile(KeychainManifestNostrKeyRecord key) {
    final materialization = key.nostrKeyMaterialization;
    final nsec = _revealedNsecs[key.entryId];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key),
              title: Text(materialization.purpose),
              subtitle: Text(materialization.publicKeyHex),
              trailing: IconButton(
                tooltip: context.loc.settingsNostrKeysSave,
                icon: const Icon(Icons.edit),
                onPressed: () => _editPurpose(key),
              ),
            ),
            Text(
              key.entry.bip85DerivationPath,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (nsec == null)
              OutlinedButton.icon(
                onPressed: () => _reveal(key),
                icon: const Icon(Icons.visibility),
                label: Text(context.loc.settingsNostrKeysShowPrivate),
              )
            else
              ExcludeSemantics(child: SelectableText(nsec)),
            if (nsec != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: nsec)),
                  icon: const Icon(Icons.copy),
                  label: Text(context.loc.settingsNostrKeysCopy),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

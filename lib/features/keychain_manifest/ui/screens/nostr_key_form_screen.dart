import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/inputs/text_input.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_key_l10n.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

/// Create or rename a user Nostr key.
///
/// One form serves both: [record] null means create, otherwise the fields are
/// prefilled and submitting edits that key. There is deliberately no derivation
/// path input — the path is allocated by the domain, never chosen here.
class NostrKeyFormScreen extends StatefulWidget {
  const NostrKeyFormScreen({super.key, this.record});

  final KeychainManifestNostrKeyRecord? record;

  @override
  State<NostrKeyFormScreen> createState() => _NostrKeyFormScreenState();
}

class _NostrKeyFormScreenState extends State<NostrKeyFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    final materialization = widget.record?.nostrKeyMaterialization;
    _name = TextEditingController(text: materialization?.purpose ?? '');
    _description = TextEditingController(
      text: materialization?.description ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cubit = context.read<NostrKeysCubit>();
    final record = widget.record;
    final submitted = record == null
        ? await cubit.create(_name.text, description: _description.text)
        : await cubit.updateKey(
            key: record,
            name: _name.text,
            description: _description.text,
          );
    if (!mounted || !submitted) return;
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NostrKeysCubit, NostrKeysState>(
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: Text(
            _isEdit
                ? context.loc.settingsNostrKeysEditTitle
                : context.loc.settingsNostrKeysCreate,
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _field(
                context,
                label: context.loc.settingsNostrKeysName,
                hint: context.loc.settingsNostrKeysPurposeHint,
                controller: _name,
                maxLength:
                    KeychainManifestNostrKeyMaterialization.maxPurposeLength,
                uiKey: const Key('nostr_key_name_field'),
                // Single line: the entity rejects control characters, so a
                // typed newline would fail the write rather than the field.
                maxLines: 1,
                error: switch (state.formError) {
                  NostrKeyFormError.nameRequired ||
                  NostrKeyFormError.nameTooLong => state.formError,
                  _ => null,
                },
              ),
              const Gap(24),
              _field(
                context,
                label: context.loc.settingsNostrKeysDescription,
                hint: context.loc.settingsNostrKeysDescriptionHint,
                controller: _description,
                maxLength: KeychainManifestNostrKeyMaterialization
                    .maxDescriptionLength,
                uiKey: const Key('nostr_key_description_field'),
                // Two lines of room, but still newline-free for the same
                // control-character reason as the name field.
                maxLines: 2,
                error: state.formError == NostrKeyFormError.descriptionTooLong
                    ? state.formError
                    : null,
              ),
              const Gap(32),
              BBButton.big(
                label: context.loc.settingsNostrKeysSave,
                onPressed: _submit,
                disabled: state.busy,
                bgColor: context.appColors.primary,
                textColor: context.appColors.onPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required String label,
    required String hint,
    required TextEditingController controller,
    required int maxLength,
    required Key uiKey,
    required NostrKeyFormError? error,
    int? maxLines,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BBText(
          label,
          style: context.font.bodyLarge,
          color: context.appColors.onSurface,
        ),
        const Gap(8),
        BBInputText(
          uiKey: uiKey,
          controller: controller,
          value: controller.text,
          hint: hint,
          maxLength: maxLength,
          maxLines: maxLines,
          onChanged: (_) => context.read<NostrKeysCubit>().clearFormError(),
        ),
        if (error != null) ...[
          const Gap(8),
          BBText(
            error.toTranslated(context),
            style: context.font.bodySmall,
            color: context.appColors.error,
          ),
        ],
      ],
    );
  }
}

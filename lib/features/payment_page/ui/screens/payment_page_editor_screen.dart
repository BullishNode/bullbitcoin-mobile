import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/loading/loading_box_content.dart';
import 'package:bb_mobile/core/widgets/loading/loading_line_content.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/core/widgets/bottom_sheet/x.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_activation_offer.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_entry_tile.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page_error.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page_validation.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_exception_l10n.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

class PaymentPageEditorScreen extends StatefulWidget {
  const PaymentPageEditorScreen({super.key});

  @override
  State<PaymentPageEditorScreen> createState() =>
      _PaymentPageEditorScreenState();
}

class _PaymentPageEditorScreenState extends State<PaymentPageEditorScreen> {
  final _header = TextEditingController();
  final _description = TextEditingController();
  final _website = TextEditingController();
  final _twitter = TextEditingController();
  final _instagram = TextEditingController();
  final _alias = TextEditingController();
  final _nym = TextEditingController();
  final _nymFormKey = GlobalKey<FormState>();

  /// The edit form is collapsed behind an Edit button on an existing (live or
  /// archived) page; creation stays form-first. A failed save keeps it open.
  bool _editing = false;

  /// True once the user opts out of the default (the claimed nym) and reveals
  /// the one-time permanent alias field.
  bool _claimingAlias = false;

  /// Snapshot of the editable fields captured when Edit is opened, so a cancel
  /// can detect unsaved changes and confirm before discarding them.
  _EditSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    context.read<PaymentPageCubit>().load();
  }

  @override
  void dispose() {
    _header.dispose();
    _description.dispose();
    _website.dispose();
    _twitter.dispose();
    _instagram.dispose();
    _alias.dispose();
    _nym.dispose();
    super.dispose();
  }

  void _syncControllers(PaymentPageState state) {
    if (_header.text != state.header) _header.text = state.header;
    if (_description.text != state.description) {
      _description.text = state.description;
    }
    if (_website.text != state.website) _website.text = state.website;
    if (_twitter.text != state.twitter) _twitter.text = state.twitter;
    if (_instagram.text != state.instagram) _instagram.text = state.instagram;
    if (_alias.text != state.aliasDraft) _alias.text = state.aliasDraft;
    if (_nym.text != state.nymDraft) _nym.text = state.nymDraft;
    // A draft alias carried in state (a failed claim, a restored form) means the
    // alias branch was already taken — don't hide it behind the choice again.
    if (state.aliasDraft.isNotEmpty) _claimingAlias = true;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PaymentPageCubit, PaymentPageState>(
      // Offer the fiat chooser exactly once, on the creation transition from the
      // create form to a live (edit) page — never on later edits of an existing
      // page, and never on a reload (which passes through `loading` first).
      listenWhen: (previous, current) =>
          previous.status == PaymentPageStatus.create &&
          current.status == PaymentPageStatus.edit,
      listener: (context, _) => offerFiatSettlementAfterActivation(
        context,
        FiatSettlementProduct.paymentPage,
      ),
      child: BlocConsumer<PaymentPageCubit, PaymentPageState>(
        listenWhen: (previous, current) =>
            previous.failure != current.failure && current.failure != null,
        listener: (context, state) {
          final failure = state.failure;
          if (failure == null) return;
          SnackBarUtils.showSnackBar(context, failure.toTranslated(context));
        },
        builder: (context, state) {
          _syncControllers(state);
          final hasUnsavedChanges =
              _editing && _snapshot != null && !_snapshot!.matches(state);
          return PopScope(
            canPop: !state.submitting && !hasUnsavedChanges,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              if (state.submitting) {
                SnackBarUtils.showSnackBar(
                  context,
                  context.loc.paymentPageOperationInProgress,
                );
                return;
              }
              if (!hasUnsavedChanges) return;
              final discarded = await _cancelEdit(
                context.read<PaymentPageCubit>(),
                state,
              );
              if (!discarded || !mounted) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pop();
              });
            },
            child: Scaffold(
              appBar: AppBar(title: Text(context.loc.paymentPageScreenTitle)),
              body: SafeArea(child: _body(context, state)),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, PaymentPageState state) {
    final cubit = context.read<PaymentPageCubit>();
    final body = switch (state.status) {
      PaymentPageStatus.loading => const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LoadingBoxContent(height: 72),
            LoadingLineContent(),
            LoadingLineContent(width: 220),
          ],
        ),
      ),
      PaymentPageStatus.unsupported => _unsupportedView(context, state),
      PaymentPageStatus.needsNym => _needsNymView(context, state, cubit),
      PaymentPageStatus.loadFailed => _loadFailedView(context, state, cubit),
      PaymentPageStatus.archived => _archivedView(context, state, cubit),
      PaymentPageStatus.create ||
      PaymentPageStatus.edit => _editorForm(context, state, cubit),
    };
    if (!state.walletBehaviorUnavailable) return body;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: GetPaidWalletBehaviorUnavailableWarning(
            onRetry: cubit.retryWalletBehavior,
            isRetrying: state.walletBehaviorSaving,
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _unsupportedView(BuildContext context, PaymentPageState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusNotice(
          icon: Icons.visibility_off_outlined,
          title: context.loc.paymentPagePermanentNamesUnavailableTitle,
          body: context.loc.paymentPagePermanentNamesUnavailableBody,
        ),
        if (state.walletBehavior != null)
          GetPaidWalletBehaviorCard(
            behavior: state.walletBehavior!,
            saving: state.walletBehaviorSaving,
            onAutoSweepChanged: (value) =>
                context.read<PaymentPageCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  autoSweepEnabled: value,
                ),
            onHideOnHomeChanged: (value) =>
                context.read<PaymentPageCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  hideOnHome: value,
                ),
          ),
      ],
    );
  }

  /// No nym yet: the shared minimal claim step, in-flow. A successful claim
  /// reloads into the create form, so the user continues into the Donation Page
  /// without being sent to Lightning Address settings.
  Widget _needsNymView(
    BuildContext context,
    PaymentPageState state,
    PaymentPageCubit cubit,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GetPaidNymClaimStep(
          formKey: _nymFormKey,
          controller: _nym,
          submitting: state.claimingNym,
          errorText: _nymClaimFailureMessage(context, state),
          onChanged: cubit.nymDraftChanged,
          onSubmit: () => _claimNym(cubit),
          validator: (value) => _nymValidationMessage(context, value ?? ''),
        ),
        if (state.walletBehavior != null)
          GetPaidWalletBehaviorCard(
            behavior: state.walletBehavior!,
            saving: state.walletBehaviorSaving,
            onAutoSweepChanged: (value) =>
                context.read<PaymentPageCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  autoSweepEnabled: value,
                ),
            onHideOnHomeChanged: (value) =>
                context.read<PaymentPageCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  hideOnHome: value,
                ),
          ),
      ],
    );
  }

  Future<void> _claimNym(PaymentPageCubit cubit) async {
    if (!_nymFormKey.currentState!.validate()) return;
    await cubit.claimNym();
  }

  /// The local syntax + reserved-name prefilter, as the field's own validator.
  String? _nymValidationMessage(BuildContext context, String value) {
    try {
      validatePaymentPageNymClaim(value);
      return null;
    } on PaymentPageException catch (e) {
      return e.kind == PaymentPageErrorKind.nymReserved
          ? context.loc.getPaidNymReserved
          : context.loc.getPaidNymInvalid;
    }
  }

  /// A claim rejection stated above the field. Everything else stays on the
  /// screen's failure snackbar.
  String? _nymClaimFailureMessage(
    BuildContext context,
    PaymentPageState state,
  ) {
    if (state.invalidField != PaymentPageField.nym) return null;
    return switch (state.failure?.kind) {
      PaymentPageErrorKind.nymTaken => context.loc.getPaidNymTaken,
      PaymentPageErrorKind.nymReserved => context.loc.getPaidNymReserved,
      PaymentPageErrorKind.nymInvalid => context.loc.getPaidNymInvalid,
      _ => null,
    };
  }

  Widget _loadFailedView(
    BuildContext context,
    PaymentPageState state,
    PaymentPageCubit cubit,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusNotice(
          icon: Icons.error_outline,
          title: context.loc.paymentPageLoadFailedTitle,
          body: context.loc.paymentPageLoadFailedBody,
        ),
        const Gap(24),
        BBButton.big(
          label: context.loc.paymentPageRetryButton,
          iconData: Icons.refresh,
          iconFirst: true,
          onPressed: cubit.load,
          bgColor: context.appColors.secondary,
          textColor: context.appColors.onSecondary,
        ),
        // The behavior controls only need the local wallet, so they stay
        // reachable even while the server-backed page load is failing.
        if (state.walletBehavior != null)
          GetPaidWalletBehaviorCard(
            behavior: state.walletBehavior!,
            saving: state.walletBehaviorSaving,
            onAutoSweepChanged: (value) =>
                context.read<PaymentPageCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  autoSweepEnabled: value,
                ),
            onHideOnHomeChanged: (value) =>
                context.read<PaymentPageCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  hideOnHome: value,
                ),
          ),
      ],
    );
  }

  Widget _archivedView(
    BuildContext context,
    PaymentPageState state,
    PaymentPageCubit cubit,
  ) {
    return _editorForm(context, state, cubit, isArchived: true);
  }

  Widget _editorForm(
    BuildContext context,
    PaymentPageState state,
    PaymentPageCubit cubit, {
    bool isArchived = false,
  }) {
    final isCreate = state.status == PaymentPageStatus.create;
    // Creation is form-first; an existing page keeps the form collapsed behind
    // the Edit button until the user chooses to edit.
    final showForm = isCreate || _editing;
    final naming = _namingStep(context, state, cubit);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // An archived page leads with why it is off; a live page leads with the
        // thing the owner came for — its link, as a scannable QR.
        if (isArchived) ...[
          _StatusNotice(
            icon: Icons.pause_circle_outline,
            title: context.loc.paymentPageArchivedTitle,
            body: context.loc.paymentPageArchivedBody,
          ),
          const Gap(20),
        ] else if (isCreate) ...[
          Text(
            context.loc.paymentPageRoutingNotice,
            style: context.font.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          const Gap(20),
        ],
        if (state.submissionUncertain) ...[
          _Banner(
            icon: Icons.help_outline,
            text: context.loc.paymentPageSubmissionUncertain,
          ),
          const Gap(16),
        ],
        if (naming != null) ...[naming, const Gap(24)],
        // Status + link — the shareable page, presented as a scannable QR.
        if (!isCreate && state.publicUrl != null) ...[
          _shareSection(context, state.publicUrl!),
          const Gap(24),
        ],
        // The routing notice explains where the money lands, so on a live page
        // it belongs with the wallet story, under the link.
        if (!isCreate && !isArchived) ...[
          Text(
            context.loc.paymentPageRoutingNotice,
            style: context.font.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          const Gap(24),
        ],
        // Fiat conversion.
        if (!isCreate) ...[
          const FiatSettlementEntryTile(
            product: FiatSettlementProduct.paymentPage,
          ),
        ],
        // Edit — the form, collapsed behind a button on an existing page.
        const Gap(24),
        if (showForm)
          ..._editFields(context, state, cubit, isCreate: isCreate)
        else
          BBButton.big(
            key: const Key('payment_page_edit_button'),
            label: context.loc.getPaidEditButton,
            iconData: Icons.edit_outlined,
            iconFirst: true,
            onPressed: () => _beginEdit(state),
            bgColor: context.appColors.secondary,
            textColor: context.appColors.onSecondary,
          ),
        // Advanced settings — the shared sheet (turn on/off + wallet behavior).
        if (!isCreate) ...[
          const Gap(24),
          _AdvancedSettingsButton(
            online: !isArchived,
            onlineSaving: state.submitting,
            onOnlineChanged: (online) =>
                _setOnline(cubit: cubit, state: state, online: online),
          ),
        ],
      ],
    );
  }

  /// The editable page fields plus the primary save action. On an existing page
  /// this block is revealed by the Edit button and offers a Cancel that
  /// confirms before discarding unsaved changes; creation stays form-first.
  List<Widget> _editFields(
    BuildContext context,
    PaymentPageState state,
    PaymentPageCubit cubit, {
    required bool isCreate,
  }) {
    final isArchived = state.isArchived;
    return [
      _byteCountedField(
        context: context,
        controller: _header,
        label: context.loc.paymentPageHeaderLabel,
        hint: context.loc.paymentPageHeaderHint,
        value: state.header,
        maxBytes: paymentPageHeaderMaxBytes,
        enabled: !state.submitting,
        onChanged: cubit.headerChanged,
        errorText: state.invalidField == PaymentPageField.header
            ? context.loc.paymentPageHeaderError
            : null,
      ),
      const Gap(16),
      _characterCountedDescriptionField(
        context: context,
        controller: _description,
        label: context.loc.paymentPageDescriptionLabel,
        hint: context.loc.paymentPageDescriptionHint,
        value: state.description,
        enabled: !state.submitting,
        onChanged: cubit.descriptionChanged,
        errorText: state.invalidField == PaymentPageField.description
            ? context.loc.paymentPageDescriptionError
            : null,
      ),
      const Gap(16),
      // Display currency is intentionally not collected here: the payer chooses
      // their currency on the hosted page, so the merchant never picks one. The
      // server still requires a `display_currency`, so a sensible default is
      // sent silently in the payload (see PaymentPageCubit / state defaults).
      TextField(
        controller: _website,
        enabled: !state.submitting,
        keyboardType: TextInputType.url,
        autocorrect: false,
        onChanged: cubit.websiteChanged,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: context.loc.paymentPageWebsiteLabel,
          errorText: state.invalidField == PaymentPageField.website
              ? context.loc.paymentPageWebsiteError
              : null,
        ),
      ),
      const Gap(16),
      TextField(
        controller: _twitter,
        enabled: !state.submitting,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: cubit.twitterChanged,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: context.loc.paymentPageTwitterLabel,
          errorText: state.invalidField == PaymentPageField.twitter
              ? context.loc.paymentPageTwitterError
              : null,
        ),
      ),
      const Gap(16),
      TextField(
        controller: _instagram,
        enabled: !state.submitting,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: cubit.instagramChanged,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: context.loc.paymentPageInstagramLabel,
          errorText: state.invalidField == PaymentPageField.instagram
              ? context.loc.paymentPageInstagramError
              : null,
        ),
      ),
      const Gap(24),
      BBButton.big(
        label: state.submitting
            ? context.loc.paymentPageSubmitting
            : isArchived
            ? context.loc.paymentPageSaveAndTurnOnButton
            : isCreate
            ? context.loc.paymentPageCreateButton
            : context.loc.paymentPageSaveButton,
        onPressed: () => _saveFromEditor(cubit),
        // Always tappable: save() validates on tap and surfaces the specific
        // invalid field, rather than silently disabling with no feedback.
        disabled: state.submitting,
        bgColor: context.appColors.primary,
        textColor: context.appColors.onPrimary,
      ),
      // Creation has nothing to cancel back to; an existing page can collapse
      // the editor (confirming first if there are unsaved changes).
      if (!isCreate) ...[
        const Gap(8),
        TextButton(
          key: const Key('payment_page_cancel_edit'),
          onPressed: state.submitting ? null : () => _cancelEdit(cubit, state),
          child: Text(context.loc.getPaidCancelButton),
        ),
      ],
    ];
  }

  /// The naming step, shown only while creating and only while the name is
  /// still open — the nym is claimed but no alias is. With both already claimed
  /// there is nothing to choose, so nothing is asked: offering "use my nym
  /// instead" needs the server's per-surface advertised-name preference
  /// capability and is out of scope until that wire contract exists.
  Widget? _namingStep(
    BuildContext context,
    PaymentPageState state,
    PaymentPageCubit cubit,
  ) {
    if (state.status != PaymentPageStatus.create) return null;
    if (state.permanentAlias != null) return null;
    if (!_claimingAlias) {
      return GetPaidNameChoice(
        nym: state.nym,
        body: context.loc.paymentPageNameChoiceBody,
        onChooseAlias: () => setState(() => _claimingAlias = true),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('payment_page_alias_field'),
          controller: _alias,
          enabled: !state.submitting,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 32,
          onChanged: cubit.aliasDraftChanged,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: context.loc.paymentPageAliasLabel,
            helperText: context.loc.paymentPageAliasHelper,
            // Permanence is the point of this field: state it in full rather
            // than letting the character counter ellipsize it.
            helperMaxLines: 3,
            counterText: '',
            errorText: state.invalidField == PaymentPageField.alias
                ? (state.aliasTakenFailure
                      ? context.loc.paymentPageAliasTaken
                      : context.loc.paymentPageAliasInvalid)
                : null,
            errorMaxLines: 2,
          ),
        ),
        TextButton(
          key: const Key('payment_page_use_nym_instead'),
          onPressed: state.submitting ? null : () => _useNym(cubit),
          child: Text(context.loc.getPaidNameChoiceUseNym),
        ),
      ],
    );
  }

  /// Back out of the alias branch to the default: no alias is claimed, so the
  /// surface keeps advertising the server-returned nym URLs. Any typed draft is
  /// dropped so the save omits it.
  void _useNym(PaymentPageCubit cubit) {
    cubit.aliasDraftChanged('');
    setState(() => _claimingAlias = false);
  }

  Widget _byteCountedField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required String hint,
    required String value,
    required int maxBytes,
    required bool enabled,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        hintText: hint,
        errorText: errorText,
        counterText: context.loc.paymentPageByteCounter(
          paymentPageByteLength(value),
          maxBytes,
        ),
      ),
    );
  }

  Widget _characterCountedDescriptionField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required String hint,
    required String value,
    required bool enabled,
    required ValueChanged<String> onChanged,
    String? errorText,
  }) {
    final byteCount = paymentPageByteLength(value);
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: 3,
      onChanged: onChanged,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        helperText: hint,
        errorText: byteCount > paymentPageDescriptionMaxBytes
            ? context.loc.paymentPageDescriptionByteLimit(
                byteCount,
                paymentPageDescriptionMaxBytes,
              )
            : errorText,
        errorMaxLines: 2,
        counterText: context.loc.paymentPageByteCounter(
          paymentPageCharacterLength(value),
          paymentPageDescriptionMaxCharacters,
        ),
      ),
    );
  }

  /// The page's public link, presented exactly as the POS terminal link is: QR
  /// first, then copy, open and download.
  Widget _shareSection(BuildContext context, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.loc.paymentPageShareLabel,
          style: context.font.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        const Gap(8),
        GetPaidLinkQr(
          url: url,
          openLabel: context.loc.paymentPageOpenLink,
          downloadFileName: 'donation-page-qr.png',
        ),
      ],
    );
  }

  /// Runs the save. A first alias claim is NOT confirmed by a dialog: the alias
  /// branch of the naming choice states the permanence on the field itself.
  Future<void> _save(PaymentPageCubit cubit) => cubit.save();

  /// Save initiated from the revealed editor: on success the form collapses
  /// back to the summary; a failed save keeps the editor open so the user can
  /// correct and retry.
  Future<void> _saveFromEditor(PaymentPageCubit cubit) async {
    await _save(cubit);
    if (!mounted) return;
    final after = cubit.state;
    if (after.failure == null && !after.submitting) {
      setState(() {
        _editing = false;
        _snapshot = null;
      });
    }
  }

  void _beginEdit(PaymentPageState state) {
    setState(() {
      _snapshot = _EditSnapshot.of(state);
      _editing = true;
    });
  }

  Future<bool> _cancelEdit(
    PaymentPageCubit cubit,
    PaymentPageState state,
  ) async {
    if (_snapshot != null && !_snapshot!.matches(state)) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.loc.getPaidDiscardChangesTitle),
          content: Text(dialogContext.loc.getPaidDiscardChangesBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.loc.getPaidDiscardChangesKeep),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogContext.loc.getPaidDiscardChangesDiscard),
            ),
          ],
        ),
      );
      if (!mounted || discard != true) return false;
      // Reload restores the persisted values, discarding the unsaved edits.
      await cubit.load();
      if (!mounted) return false;
    }
    setState(() {
      _editing = false;
      _snapshot = null;
    });
    return true;
  }

  Future<void> _setOnline({
    required PaymentPageCubit cubit,
    required PaymentPageState state,
    required bool online,
  }) async {
    if (online) {
      await _save(cubit);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.loc.paymentPageTurnOffConfirmTitle),
        content: Text(dialogContext.loc.paymentPageTurnOffConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.loc.paymentPageTurnOffConfirmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.loc.paymentPageTurnOffConfirmSubmit),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (!state.isOnline) return;
    await cubit.setOnline(false);
  }
}

/// Snapshot of the editable page fields, used to detect unsaved changes when
/// the user cancels out of the revealed editor.
class _EditSnapshot {
  final String header;
  final String description;
  final String displayCurrency;
  final String website;
  final String twitter;
  final String instagram;
  final String aliasDraft;

  const _EditSnapshot({
    required this.header,
    required this.description,
    required this.displayCurrency,
    required this.website,
    required this.twitter,
    required this.instagram,
    required this.aliasDraft,
  });

  factory _EditSnapshot.of(PaymentPageState state) => _EditSnapshot(
    header: state.header,
    description: state.description,
    displayCurrency: state.displayCurrency,
    website: state.website,
    twitter: state.twitter,
    instagram: state.instagram,
    aliasDraft: state.aliasDraft,
  );

  bool matches(PaymentPageState state) =>
      header == state.header &&
      description == state.description &&
      displayCurrency == state.displayCurrency &&
      website == state.website &&
      twitter == state.twitter &&
      instagram == state.instagram &&
      aliasDraft == state.aliasDraft;
}

/// Opens the shared Advanced Settings sheet for the Donation Page. The sheet
/// lives in a modal route whose context has no provider, so the cubit is carried
/// into it explicitly and its contents are rebuilt from state: a wallet-behavior
/// write made from inside the sheet has to be visible in the sheet that made it.
class _AdvancedSettingsButton extends StatelessWidget {
  final bool online;
  final bool onlineSaving;
  final ValueChanged<bool> onOnlineChanged;

  const _AdvancedSettingsButton({
    required this.online,
    required this.onlineSaving,
    required this.onOnlineChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PaymentPageCubit>();
    return Align(
      alignment: Alignment.center,
      child: TextButton(
        key: const Key('payment_page_advanced_settings_button'),
        onPressed: () => BlurredBottomSheet.show(
          context: context,
          child: BlocProvider<PaymentPageCubit>.value(
            value: cubit,
            child: BlocBuilder<PaymentPageCubit, PaymentPageState>(
              builder: (context, state) {
                final behavior = state.walletBehavior;
                return GetPaidAdvancedSettingsSheet(
                  onlineSwitchKey: const Key('payment_page_online_switch'),
                  onlineTitle: context.loc.paymentPageOnlineToggleLabel,
                  onlineSubtitle: context.loc.paymentPageOnlineToggleBody,
                  online: online,
                  onlineSaving: onlineSaving,
                  onlineSavingLabel: context.loc.paymentPageSubmitting,
                  onOnlineChanged: onOnlineChanged,
                  walletBehavior: behavior,
                  walletBehaviorSaving: state.walletBehaviorSaving,
                  onAutoSweepChanged: (value) => cubit.updateWalletBehavior(
                    walletId: behavior!.walletId,
                    autoSweepEnabled: value,
                  ),
                  onHideOnHomeChanged: (value) => cubit.updateWalletBehavior(
                    walletId: behavior!.walletId,
                    hideOnHome: value,
                  ),
                );
              },
            ),
          ),
        ),
        child: Text(
          context.loc.getPaidAdvancedSettingsButton,
          style: TextStyle(color: context.appColors.error),
        ),
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _StatusNotice({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.appColors.primary, size: 48),
        const Gap(16),
        Text(title, style: context.font.titleLarge),
        const Gap(8),
        Text(
          body,
          style: context.font.bodyMedium?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Banner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.appColors.textMuted, size: 20),
        const Gap(8),
        Expanded(
          child: Text(
            text,
            style: context.font.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

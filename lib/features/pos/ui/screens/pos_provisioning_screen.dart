import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/loading/loading_box_content.dart';
import 'package:bb_mobile/core/widgets/loading/loading_line_content.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/core/widgets/bottom_sheet/x.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_activation_offer.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_entry_tile.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/pos/domain/pos_error.dart';
import 'package:bb_mobile/features/pos/domain/pos_validation.dart';
import 'package:bb_mobile/features/pos/presentation/pos_cubit.dart';
import 'package:bb_mobile/features/pos/presentation/pos_exception_l10n.dart';
import 'package:bb_mobile/features/pos/presentation/pos_state.dart';
import 'package:bb_mobile/features/pos/ui/widgets/pos_staff_instructions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

/// The Point of Sale provisioning screen (ISS-C-05 legacy `core/widgets`). It
/// collects a label + display currency, states the ROUTE-3W routing notice, and
/// - for an existing POS - surfaces the shareable terminal URL (copy + external
/// open only, DG-P4). It renders NO in-app terminal and NO invoice UI (DELTA 2).
class PosProvisioningScreen extends StatefulWidget {
  const PosProvisioningScreen({super.key});

  @override
  State<PosProvisioningScreen> createState() => _PosProvisioningScreenState();
}

class _PosProvisioningScreenState extends State<PosProvisioningScreen> {
  final _label = TextEditingController();
  final _alias = TextEditingController();
  final _nym = TextEditingController();
  final _nymFormKey = GlobalKey<FormState>();

  /// True once the user opts out of the default (the claimed nym) and reveals
  /// the one-time permanent alias field.
  bool _claimingAlias = false;

  /// The edit form is collapsed behind an Edit button on an existing (live or
  /// archived) POS; creation stays form-first. A failed save keeps it open.
  bool _editing = false;

  /// Snapshot of the editable fields captured when Edit is opened, so a cancel
  /// can detect unsaved changes and confirm before discarding them.
  _EditSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    context.read<PosCubit>().load();
  }

  @override
  void dispose() {
    _label.dispose();
    _alias.dispose();
    _nym.dispose();
    super.dispose();
  }

  void _syncControllers(PosState state) {
    if (_label.text != state.label) _label.text = state.label;
    if (_alias.text != state.aliasDraft) _alias.text = state.aliasDraft;
    if (_nym.text != state.nymDraft) _nym.text = state.nymDraft;
    // A draft alias carried in state (a failed provision, a restored form) means
    // the alias branch was already taken - don't hide it behind the choice again.
    if (state.aliasDraft.isNotEmpty) _claimingAlias = true;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PosCubit, PosState>(
      // Offer the fiat chooser exactly once, on the provisioning transition from
      // the create form to a live (edit) terminal — never on later edits of an
      // existing POS, and never on a reload (which passes through `loading`).
      listenWhen: (previous, current) =>
          previous.status == PosStatus.create &&
          current.status == PosStatus.edit,
      listener: (context, _) => offerFiatSettlementAfterActivation(
        context,
        FiatSettlementProduct.pos,
      ),
      child: BlocConsumer<PosCubit, PosState>(
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
                  context.loc.posOperationInProgress,
                );
                return;
              }
              if (!hasUnsavedChanges) return;
              final discarded = await _cancelEdit(
                context.read<PosCubit>(),
                state,
              );
              if (!discarded || !mounted) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pop();
              });
            },
            child: Scaffold(
              appBar: AppBar(title: Text(context.loc.posScreenTitle)),
              body: SafeArea(child: _body(context, state)),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, PosState state) {
    final cubit = context.read<PosCubit>();
    final body = switch (state.status) {
      PosStatus.loading => const Padding(
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
      PosStatus.unsupported => _unsupportedView(context, state),
      PosStatus.needsNym => _needsNymView(context, state, cubit),
      PosStatus.loadFailed => _loadFailedView(context, state, cubit),
      PosStatus.archived => _archivedView(context, state, cubit),
      PosStatus.create || PosStatus.edit => _form(context, state, cubit),
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

  Widget _unsupportedView(BuildContext context, PosState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusNotice(
          icon: Icons.visibility_off_outlined,
          title: context.loc.posPermanentNamesUnavailableTitle,
          body: context.loc.posPermanentNamesUnavailableBody,
        ),
        if (state.walletBehavior != null)
          GetPaidWalletBehaviorCard(
            behavior: state.walletBehavior!,
            saving: state.walletBehaviorSaving,
            onAutoSweepChanged: (value) =>
                context.read<PosCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  autoSweepEnabled: value,
                ),
            onHideOnHomeChanged: (value) =>
                context.read<PosCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  hideOnHome: value,
                ),
          ),
      ],
    );
  }

  /// No nym yet: the shared minimal claim step, in-flow. A successful claim
  /// reloads into the create form, so the user continues into the Point of Sale
  /// without being sent to Lightning Address settings.
  Widget _needsNymView(BuildContext context, PosState state, PosCubit cubit) {
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
                context.read<PosCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  autoSweepEnabled: value,
                ),
            onHideOnHomeChanged: (value) =>
                context.read<PosCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  hideOnHome: value,
                ),
          ),
      ],
    );
  }

  Future<void> _claimNym(PosCubit cubit) async {
    if (!_nymFormKey.currentState!.validate()) return;
    await cubit.claimNym();
  }

  /// The local syntax + reserved-name prefilter, as the field's own validator.
  String? _nymValidationMessage(BuildContext context, String value) {
    try {
      validatePosNymClaim(value);
      return null;
    } on PosException catch (e) {
      return e.kind == PosErrorKind.nymReserved
          ? context.loc.getPaidNymReserved
          : context.loc.getPaidNymInvalid;
    }
  }

  /// A claim rejection stated above the field. Everything else stays on the
  /// screen's failure snackbar.
  String? _nymClaimFailureMessage(BuildContext context, PosState state) {
    if (state.invalidField != PosField.nym) return null;
    return switch (state.failure?.kind) {
      PosErrorKind.nymTaken => context.loc.getPaidNymTaken,
      PosErrorKind.nymReserved => context.loc.getPaidNymReserved,
      PosErrorKind.nymInvalid => context.loc.getPaidNymInvalid,
      _ => null,
    };
  }

  Widget _loadFailedView(BuildContext context, PosState state, PosCubit cubit) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusNotice(
          icon: Icons.error_outline,
          title: context.loc.posLoadFailedTitle,
          body: context.loc.posLoadFailedBody,
        ),
        const Gap(24),
        BBButton.big(
          label: context.loc.posRetryButton,
          iconData: Icons.refresh,
          iconFirst: true,
          onPressed: cubit.load,
          bgColor: context.appColors.secondary,
          textColor: context.appColors.onSecondary,
        ),
        // The behavior controls only need the local wallet, so they stay
        // reachable even while the server-backed POS load is failing.
        if (state.walletBehavior != null)
          GetPaidWalletBehaviorCard(
            behavior: state.walletBehavior!,
            saving: state.walletBehaviorSaving,
            onAutoSweepChanged: (value) =>
                context.read<PosCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  autoSweepEnabled: value,
                ),
            onHideOnHomeChanged: (value) =>
                context.read<PosCubit>().updateWalletBehavior(
                  walletId: state.walletBehavior!.walletId,
                  hideOnHome: value,
                ),
          ),
      ],
    );
  }

  Widget _archivedView(BuildContext context, PosState state, PosCubit cubit) {
    return _managedView(context, state, cubit, isArchived: true);
  }

  Widget _form(BuildContext context, PosState state, PosCubit cubit) {
    return _managedView(context, state, cubit);
  }

  /// The create / edit / archived management surface. A provisioned terminal
  /// leads with the thing the owner came for — its link, as a scannable QR —
  /// then Fiat conversion, Instructions for staff, Edit (collapsed form) and
  /// Advanced Settings. Creation stays form-first.
  Widget _managedView(
    BuildContext context,
    PosState state,
    PosCubit cubit, {
    bool isArchived = false,
  }) {
    final isCreate = state.status == PosStatus.create;
    final showForm = isCreate || _editing;
    final naming = _namingStep(context, state, cubit);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // An archived POS leads with why it is off; a live one leads with its
        // terminal link.
        if (isArchived) ...[
          _StatusNotice(
            icon: Icons.pause_circle_outline,
            title: context.loc.posArchivedTitle,
            body: context.loc.posArchivedBody,
          ),
          const Gap(20),
        ] else if (isCreate) ...[
          Text(
            context.loc.posRoutingNotice,
            style: context.font.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          const Gap(20),
        ],
        if (state.submissionUncertain) ...[
          _Banner(
            icon: Icons.help_outline,
            text: context.loc.posSubmissionUncertain,
          ),
          const Gap(16),
        ],
        if (naming != null) ...[naming, const Gap(24)],
        // Status + link — the shareable terminal, presented as a scannable QR.
        if (!isCreate && state.terminalUrl != null) ...[
          Text(
            context.loc.posShareLabel,
            style: context.font.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          const Gap(8),
          GetPaidLinkQr(
            url: state.terminalUrl!,
            openLabel: context.loc.posOpenLink,
            downloadFileName: 'pos-terminal-qr.png',
          ),
          const Gap(24),
        ],
        // The routing notice explains where the money lands, so on a live
        // terminal it belongs with the wallet story, under the link.
        if (!isCreate && !isArchived) ...[
          Text(
            context.loc.posRoutingNotice,
            style: context.font.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          const Gap(24),
        ],
        // Fiat conversion.
        if (!isCreate) ...[
          const FiatSettlementEntryTile(product: FiatSettlementProduct.pos),
        ],
        // Instructions for staff — POS only, between Fiat and Edit.
        if (!isCreate) ...[const Gap(24), const PosStaffInstructions()],
        // Edit — the form, collapsed behind a button on an existing POS.
        const Gap(24),
        if (showForm)
          ..._editFields(context, state, cubit, isCreate: isCreate)
        else
          BBButton.big(
            key: const Key('pos_edit_button'),
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

  /// The editable POS fields plus the primary provision action. On an existing
  /// POS this block is revealed by the Edit button and offers a Cancel that
  /// confirms before discarding unsaved changes; creation stays form-first.
  List<Widget> _editFields(
    BuildContext context,
    PosState state,
    PosCubit cubit, {
    required bool isCreate,
  }) {
    return [
      TextField(
        controller: _label,
        enabled: !state.submitting,
        onChanged: cubit.labelChanged,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: context.loc.posLabelFieldLabel,
          hintText: context.loc.posLabelFieldHint,
          errorText: state.invalidField == PosField.label
              ? context.loc.posLabelError
              : null,
          counterText: context.loc.posByteCounter(
            posByteLength(state.label),
            posLabelMaxBytes,
          ),
        ),
      ),
      const Gap(16),
      _currencyField(context, state, cubit),
      const Gap(24),
      BBButton.big(
        label: state.submitting
            ? context.loc.posSubmitting
            : isCreate
            ? context.loc.posCreateButton
            : context.loc.posSaveButton,
        onPressed: () => _provisionFromEditor(cubit),
        // Always tappable: provision() validates on tap and surfaces the
        // specific invalid field, rather than silently disabling.
        disabled: state.submitting,
        bgColor: context.appColors.primary,
        textColor: context.appColors.onPrimary,
      ),
      // Creation has nothing to cancel back to; an existing POS can collapse
      // the editor (confirming first if there are unsaved changes).
      if (!isCreate) ...[
        const Gap(8),
        TextButton(
          key: const Key('pos_cancel_edit'),
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
  Widget? _namingStep(BuildContext context, PosState state, PosCubit cubit) {
    if (state.status != PosStatus.create) return null;
    if (state.permanentAlias != null) return null;
    if (!_claimingAlias) {
      return GetPaidNameChoice(
        nym: state.nym,
        body: context.loc.posNameChoiceBody,
        onChooseAlias: () => setState(() => _claimingAlias = true),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('pos_alias_field'),
          controller: _alias,
          enabled: !state.submitting,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 32,
          onChanged: cubit.aliasDraftChanged,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: context.loc.posAliasLabel,
            helperText: context.loc.posAliasHelper,
            // Permanence is the point of this field: state it in full rather
            // than letting the character counter ellipsize it.
            helperMaxLines: 3,
            counterText: '',
            errorText: state.invalidField == PosField.alias
                ? context.loc.posAliasInvalid
                : null,
            errorMaxLines: 2,
          ),
        ),
        TextButton(
          key: const Key('pos_use_nym_instead'),
          onPressed: state.submitting ? null : () => _useNym(cubit),
          child: Text(context.loc.getPaidNameChoiceUseNym),
        ),
      ],
    );
  }

  /// Back out of the alias branch to the default: no alias is claimed, so the
  /// surface keeps advertising the server-returned nym URLs. Any typed draft is
  /// dropped so the save omits it.
  void _useNym(PosCubit cubit) {
    cubit.aliasDraftChanged('');
    setState(() => _claimingAlias = false);
  }

  Widget _currencyField(BuildContext context, PosState state, PosCubit cubit) {
    if (state.currenciesUnavailable) {
      return Row(
        children: [
          Expanded(
            child: _InfoRow(
              label: context.loc.posCurrencyLabel,
              value: context.loc.posCurrenciesUnavailable(
                state.displayCurrency.isEmpty
                    ? posFallbackCurrency
                    : state.displayCurrency,
              ),
            ),
          ),
          TextButton(
            onPressed: cubit.retryCurrencies,
            child: Text(context.loc.posRetryCurrencies),
          ),
        ],
      );
    }

    final codes = <String>{
      ...state.currencies.map((c) => c.code),
      if (state.displayCurrency.isNotEmpty) state.displayCurrency,
    }.toList();
    return DropdownButtonFormField<String>(
      initialValue: state.displayCurrency.isEmpty
          ? null
          : state.displayCurrency,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: context.loc.posCurrencyLabel,
        errorText: state.invalidField == PosField.displayCurrency
            ? context.loc.posCurrencyError
            : null,
      ),
      items: [
        for (final code in codes)
          DropdownMenuItem(value: code, child: Text(code)),
      ],
      onChanged: state.submitting
          ? null
          : (value) {
              if (value != null) cubit.displayCurrencyChanged(value);
            },
    );
  }

  /// Runs the provision. A first alias claim is NOT confirmed by a dialog: the
  /// alias branch of the naming choice states the permanence on the field.
  Future<void> _provision(PosCubit cubit) => cubit.provision();

  /// Provision initiated from the revealed editor: on success the form
  /// collapses back to the summary; a failed provision keeps the editor open so
  /// the user can correct and retry.
  Future<void> _provisionFromEditor(PosCubit cubit) async {
    await _provision(cubit);
    if (!mounted) return;
    final after = cubit.state;
    if (after.failure == null && !after.submitting) {
      setState(() {
        _editing = false;
        _snapshot = null;
      });
    }
  }

  void _beginEdit(PosState state) {
    setState(() {
      _snapshot = _EditSnapshot.of(state);
      _editing = true;
    });
  }

  Future<bool> _cancelEdit(PosCubit cubit, PosState state) async {
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
    required PosCubit cubit,
    required PosState state,
    required bool online,
  }) async {
    if (online) {
      await _provision(cubit);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.loc.posTurnOffConfirmTitle),
        content: Text(dialogContext.loc.posTurnOffConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.loc.posTurnOffConfirmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.loc.posTurnOffConfirmSubmit),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (!state.isOnline) return;
    await cubit.setOnline(false);
  }
}

/// Snapshot of the editable POS fields, used to detect unsaved changes when the
/// user cancels out of the revealed editor.
class _EditSnapshot {
  final String label;
  final String displayCurrency;
  final String aliasDraft;

  const _EditSnapshot({
    required this.label,
    required this.displayCurrency,
    required this.aliasDraft,
  });

  factory _EditSnapshot.of(PosState state) => _EditSnapshot(
    label: state.label,
    displayCurrency: state.displayCurrency,
    aliasDraft: state.aliasDraft,
  );

  bool matches(PosState state) =>
      label == state.label &&
      displayCurrency == state.displayCurrency &&
      aliasDraft == state.aliasDraft;
}

/// Opens the shared Advanced Settings sheet for the Point of Sale. The sheet
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
    final cubit = context.read<PosCubit>();
    return Align(
      alignment: Alignment.center,
      child: TextButton(
        key: const Key('pos_advanced_settings_button'),
        onPressed: () => BlurredBottomSheet.show(
          context: context,
          child: BlocProvider<PosCubit>.value(
            value: cubit,
            child: BlocBuilder<PosCubit, PosState>(
              builder: (context, state) {
                final behavior = state.walletBehavior;
                return GetPaidAdvancedSettingsSheet(
                  onlineSwitchKey: const Key('pos_online_switch'),
                  onlineTitle: context.loc.posOnlineToggleLabel,
                  onlineSubtitle: context.loc.posOnlineToggleBody,
                  online: online,
                  onlineSaving: onlineSaving,
                  onlineSavingLabel: context.loc.posSubmitting,
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.font.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        const Gap(4),
        Text(value, style: context.font.bodyLarge),
      ],
    );
  }
}

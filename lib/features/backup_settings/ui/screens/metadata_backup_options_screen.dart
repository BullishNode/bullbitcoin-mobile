import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/navbar/top_bar.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/features/backup_settings/presentation/backup_settings_failure_l10n.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_state.dart';
import 'package:bb_mobile/features/backup_settings/ui/widgets/wallet_backup_controls.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Everything the Get Paid metadata backup can be told to do, on its own
/// surface: the automatic-backup toggle, an immediate write, deletion of the
/// remote copy, the last result, and the recovery retry.
///
/// The Backup Settings screen keeps only the one-line summary; every action
/// lives here. Pushed as its own route, so it resolves its own cubit rather
/// than reading the one the parent screen provides. This is also the landing
/// surface for the unified backup contract work, so it stays self-contained.
class MetadataBackupOptionsScreen extends StatelessWidget {
  const MetadataBackupOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => locator<WalletBackupSettingsCubit>()..load(),
      child: const _Screen(),
    );
  }
}

class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) {
    return BlocListener<WalletBackupSettingsCubit, WalletBackupSettingsState>(
      listenWhen: (previous, current) =>
          previous.failureRevision != current.failureRevision,
      listener: (context, state) {
        final failure = state.failure;
        if (failure == null) return;
        SnackBarUtils.showSnackBar(context, failure.toTranslated(context));
      },
      child: Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: true,
          automaticallyImplyLeading: false,
          flexibleSpace: TopBar(
            title: context.loc.backupSettingsMetadataBackup,
            onBack: () => context.pop(),
          ),
        ),
        body: const SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: WalletBackupControls(),
            ),
          ),
        ),
      ),
    );
  }
}

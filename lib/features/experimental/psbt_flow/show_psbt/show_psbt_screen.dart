import 'package:bb_mobile/features/experimental/broadcast_signed_tx/router.dart';
import 'package:bb_mobile/features/experimental/psbt_flow/show_bbqr/show_bbqr_widget.dart';
import 'package:bb_mobile/features/experimental/psbt_flow/show_psbt/show_psbt_cubit.dart';
import 'package:bb_mobile/features/experimental/psbt_flow/show_psbt/show_psbt_state.dart';
import 'package:bb_mobile/ui/components/buttons/button.dart';
import 'package:bb_mobile/ui/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ShowPsbtScreen extends StatelessWidget {
  final String psbt;

  const ShowPsbtScreen({super.key, required this.psbt});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ShowPsbtCubit()..generateBbqr(psbt),
      child: const _ShowPsbtView(),
    );
  }
}

class _ShowPsbtView extends StatelessWidget {
  const _ShowPsbtView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PSBT'),
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
      ),
      body: BlocBuilder<ShowPsbtCubit, ShowPsbtState>(
        builder: (context, state) {
          if (state.error != null) {
            return Center(
              child: Text(
                state.error!,
                style: context.font.bodyMedium?.copyWith(
                  color: context.colour.error,
                ),
              ),
            );
          }

          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 500,
                  child: ShowBbqrWidget(parts: state.bbqrParts),
                ),
                BBButton.big(
                  label: 'Next',
                  bgColor: context.colour.secondary,
                  textColor: context.colour.onPrimary,
                  onPressed: () {
                    context.pushNamed(
                      BroadcastSignedTxRoute.broadcastHome.name,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

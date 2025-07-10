import 'package:bb_mobile/features/experimental/broadcast_signed_tx/presentation/broadcast_signed_tx_cubit.dart';
import 'package:bb_mobile/features/experimental/broadcast_signed_tx/presentation/broadcast_signed_tx_state.dart';
import 'package:bb_mobile/features/experimental/scanner/scanner_widget.dart';
import 'package:bb_mobile/ui/components/text/text.dart';
import 'package:bb_mobile/ui/themes/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ScanTxPage extends StatelessWidget {
  const ScanTxPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<BroadcastSignedTxCubit, BroadcastSignedTxState>(
        builder: (context, state) {
          final cubit = context.read<BroadcastSignedTxCubit>();

          return Stack(
            fit: StackFit.expand,
            children: [
              ScannerWidget(
                onScanned: cubit.onScanned,
                scanDelay:
                    state
                            .bbqr
                            .parts
                            .isNotEmpty // if scanning bbqr, reduce delay
                        ? const Duration(milliseconds: 50)
                        : const Duration(milliseconds: 100),
              ),

              Positioned(
                bottom: MediaQuery.of(context).size.height * 0.02,
                left: 0,
                right: 0,
                child: Center(
                  child: IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(
                      CupertinoIcons.xmark_circle,
                      color: context.colour.onPrimary,
                      size: 64,
                    ),
                  ),
                ),
              ),

              if (state.bbqr.isScanningBbqr)
                Positioned(
                  bottom: MediaQuery.of(context).size.height * 0.2,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: BBText(
                      '${state.bbqr.parts.length} / ${state.bbqr.options!.total}',
                      style: context.font.labelMedium,
                      color: context.colour.onPrimary,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

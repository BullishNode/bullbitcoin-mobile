import 'package:bb_mobile/features/experimental/psbt_flow/show_bbqr/show_bbqr_cubit.dart';
import 'package:bb_mobile/features/experimental/psbt_flow/show_bbqr/show_bbqr_state.dart';
import 'package:bb_mobile/ui/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ShowBbqrWidget extends StatelessWidget {
  final List<String> parts;

  const ShowBbqrWidget({super.key, required this.parts});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ShowBbqrCubit(parts: parts),
      child: const _ShowBbqrView(),
    );
  }
}

class _ShowBbqrView extends StatelessWidget {
  const _ShowBbqrView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShowBbqrCubit, ShowBbqrState>(
      builder: (context, state) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            QrImageView(data: state.parts[state.currentIndex]),
            const SizedBox(height: 16),
            Text(
              'Part ${state.currentIndex + 1} of ${state.parts.length}',
              style: context.font.bodyMedium?.copyWith(
                color: context.colour.secondary,
              ),
            ),
          ],
        );
      },
    );
  }
}

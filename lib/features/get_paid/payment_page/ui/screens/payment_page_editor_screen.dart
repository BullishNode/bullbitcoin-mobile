import 'package:bb_mobile/core/widgets/inputs/utf8_byte_limit_formatter.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/payment_page_constants.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_state.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentPageEditorScreen extends StatefulWidget {
  final String nym;
  final Future<List<int>?> Function()? pickImageBytes;

  const PaymentPageEditorScreen({
    super.key,
    required this.nym,
    this.pickImageBytes,
  });

  @override
  State<PaymentPageEditorScreen> createState() =>
      _PaymentPageEditorScreenState();
}

class _PaymentPageEditorScreenState extends State<PaymentPageEditorScreen> {
  final _headerController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _websiteController = TextEditingController();
  final _twitterController = TextEditingController();
  final _instagramController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<PaymentPageCubit>().load(nym: widget.nym);
  }

  @override
  void dispose() {
    _headerController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    _twitterController.dispose();
    _instagramController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PaymentPageCubit, PaymentPageState>(
      listenWhen: (previous, current) =>
          previous.page != current.page ||
          (!previous.saved && current.saved) ||
          (!previous.archived && current.archived),
      listener: (context, state) {
        _syncControllers(state);
        if ((state.saved || state.archived) && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Payment Page')),
        body: SafeArea(
          child: BlocBuilder<PaymentPageCubit, PaymentPageState>(
            builder: (context, state) {
              if (state.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.nym.isEmpty) {
                return const _EmptyNymView();
              }
              return _PaymentPageForm(
                state: state,
                headerController: _headerController,
                descriptionController: _descriptionController,
                websiteController: _websiteController,
                twitterController: _twitterController,
                instagramController: _instagramController,
                pickImageBytes: widget.pickImageBytes ?? _pickImageBytes,
              );
            },
          ),
        ),
      ),
    );
  }

  void _syncControllers(PaymentPageState state) {
    _setText(_headerController, state.header);
    _setText(_descriptionController, state.description);
    _setText(_websiteController, state.website);
    _setText(_twitterController, state.twitter);
    _setText(_instagramController, state.instagram);
  }

  void _setText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }

  Future<List<int>?> _pickImageBytes() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    return file?.readAsBytes();
  }
}

class _PaymentPageForm extends StatefulWidget {
  final PaymentPageState state;
  final TextEditingController headerController;
  final TextEditingController descriptionController;
  final TextEditingController websiteController;
  final TextEditingController twitterController;
  final TextEditingController instagramController;
  final Future<List<int>?> Function() pickImageBytes;

  const _PaymentPageForm({
    required this.state,
    required this.headerController,
    required this.descriptionController,
    required this.websiteController,
    required this.twitterController,
    required this.instagramController,
    required this.pickImageBytes,
  });

  @override
  State<_PaymentPageForm> createState() => _PaymentPageFormState();
}

class _PaymentPageFormState extends State<_PaymentPageForm> {
  List<int>? _pendingImageBytes;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          state.hasExistingPage ? 'Edit ${state.nym}' : 'Create ${state.nym}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (state.hasExistingPage) ...[
          _StoreUrlSection(url: state.page!.publicUrl),
          const SizedBox(height: 16),
        ],
        if (state.error != null) ...[
          Text(
            state.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: widget.headerController,
          decoration: const InputDecoration(labelText: 'Page title'),
          enabled: !state.isBusy,
          maxLength: paymentPageHeaderMaxBytes,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          buildCounter: _byteCounter(
            widget.headerController,
            paymentPageHeaderMaxBytes,
          ),
          inputFormatters: _byteLimit(paymentPageHeaderMaxBytes),
          onChanged: context.read<PaymentPageCubit>().setHeader,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          enabled: !state.isBusy,
          maxLength: paymentPageDescriptionMaxBytes,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          buildCounter: _byteCounter(
            widget.descriptionController,
            paymentPageDescriptionMaxBytes,
          ),
          inputFormatters: _byteLimit(paymentPageDescriptionMaxBytes),
          maxLines: 4,
          onChanged: context.read<PaymentPageCubit>().setDescription,
        ),
        const SizedBox(height: 12),
        _ImageSection(
          state: state,
          pendingImageBytes: _pendingImageBytes,
          pickImageBytes: widget.pickImageBytes,
          onImagePicked: (bytes) async {
            final cubit = context.read<PaymentPageCubit>();
            if (!cubit.validateImageBytes(bytes)) return;
            if (state.hasExistingPage) {
              await cubit.uploadImage(bytes);
              return;
            }
            setState(() => _pendingImageBytes = bytes);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.websiteController,
          decoration: const InputDecoration(labelText: 'Website'),
          enabled: !state.isBusy,
          keyboardType: TextInputType.url,
          maxLength: paymentPageWebsiteMaxBytes,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          buildCounter: _byteCounter(
            widget.websiteController,
            paymentPageWebsiteMaxBytes,
          ),
          inputFormatters: _byteLimit(paymentPageWebsiteMaxBytes),
          onChanged: context.read<PaymentPageCubit>().setWebsite,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.twitterController,
          decoration: const InputDecoration(labelText: 'Twitter'),
          enabled: !state.isBusy,
          // Server regex is ASCII-only, so character length equals byte length.
          maxLength: paymentPageSocialHandleMaxChars,
          onChanged: context.read<PaymentPageCubit>().setTwitter,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.instagramController,
          decoration: const InputDecoration(labelText: 'Instagram'),
          enabled: !state.isBusy,
          // Server regex is ASCII-only, so character length equals byte length.
          maxLength: paymentPageSocialHandleMaxChars,
          onChanged: context.read<PaymentPageCubit>().setInstagram,
        ),
        if (state.hasExistingPage) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: state.displayCurrency,
            decoration: const InputDecoration(labelText: 'Display currency'),
            key: ValueKey(state.displayCurrency),
            items: paymentPageSupportedDisplayCurrencies
                .map(
                  (currency) =>
                      DropdownMenuItem(value: currency, child: Text(currency)),
                )
                .toList(growable: false),
            onChanged: state.isBusy || state.isSaving
                ? null
                : (value) {
                    if (value == null) return;
                    context.read<PaymentPageCubit>().setDisplayCurrency(value);
                  },
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: state.isBusy
              ? null
              : state.hasExistingPage && !state.enabled
              ? context.read<PaymentPageCubit>().publish
              : () => context.read<PaymentPageCubit>().save(
                  imageBytes: _pendingImageBytes,
                ),
          child: Text(
            state.isSaving
                ? 'Saving...'
                : state.hasExistingPage
                ? state.enabled
                      ? 'Save'
                      : 'Publish'
                : 'Create',
          ),
        ),
        if (state.hasExistingPage && state.enabled) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: state.isBusy
                ? null
                : context.read<PaymentPageCubit>().archive,
            child: Text(state.isArchiving ? 'Deactivating...' : 'Deactivate'),
          ),
        ],
        if (state.saved || state.archived) ...[
          const SizedBox(height: 12),
          Text(state.saved ? 'Saved' : 'Deactivated'),
        ],
      ],
    );
  }

  InputCounterWidgetBuilder _byteCounter(
    TextEditingController controller,
    int maxBytes,
  ) {
    return (context, {required currentLength, required isFocused, maxLength}) {
      final bytes = bullnymUtf8ByteLength(controller.text);
      return Text(
        '$bytes/$maxBytes bytes',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: bytes > maxBytes ? Theme.of(context).colorScheme.error : null,
        ),
      );
    };
  }

  List<TextInputFormatter> _byteLimit(int maxBytes) {
    return [Utf8ByteLimitFormatter(maxBytes)];
  }
}

class _ImageSection extends StatelessWidget {
  final PaymentPageState state;
  final List<int>? pendingImageBytes;
  final Future<List<int>?> Function() pickImageBytes;
  final Future<void> Function(List<int> bytes) onImagePicked;

  const _ImageSection({
    required this.state,
    required this.pendingImageBytes,
    required this.pickImageBytes,
    required this.onImagePicked,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = _imageUrl(state);
    final imageBytes = pendingImageBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 1200 / 630,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imageUrl == null
                      ? imageBytes == null
                            ? const ColoredBox(
                                color: Colors.black12,
                                child: Icon(Icons.image),
                              )
                            : Image.memory(
                                Uint8List.fromList(imageBytes),
                                fit: BoxFit.cover,
                              )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.image),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: state.isBusy
              ? null
              : () async {
                  final bytes = await pickImageBytes();
                  if (bytes == null || !context.mounted) return;
                  await onImagePicked(bytes);
                },
          child: Text(state.isUploadingImage ? 'Uploading...' : 'OG image'),
        ),
      ],
    );
  }

  String? _imageUrl(PaymentPageState state) {
    final page = state.page;
    final ogSha256 = page?.ogSha256;
    if (page == null || ogSha256 == null) return null;

    final pageUri = Uri.tryParse(page.publicUrl);
    final origin = pageUri != null && pageUri.hasScheme && pageUri.hasAuthority
        ? pageUri.origin
        : bullnymDefaultBaseUrl;

    return '$origin/img/${state.nym}/og.jpg?v=$ogSha256';
  }
}

class _StoreUrlSection extends StatelessWidget {
  final String url;

  const _StoreUrlSection({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Store URL', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final uri = Uri.tryParse(url);
                    if (uri == null) return;
                    final opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && context.mounted) {
                      SnackBarUtils.showSnackBar(
                        context,
                        'Could not open store URL',
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Text(
                      url,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy store URL',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyNymView extends StatelessWidget {
  const _EmptyNymView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Choose a Bullnym name before creating a payment page',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

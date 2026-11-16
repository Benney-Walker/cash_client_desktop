import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kyc_drop_target.dart';
import 'kyc_image_picker.dart';
import 'member_models.dart';

/// What has been entered for an ID document: the document type, the ID
/// number and the picture. Kept outside [KycDocumentFields] so the screen
/// that owns it can read it, keep it across steps and clear it.
class KycDocumentDraft extends ChangeNotifier {
  KycDocumentType? _type;
  KycImage? _image;
  String? _imageProblem;

  /// Typed in capitals; read through [build].
  final idNumber = TextEditingController();

  KycDocumentType? get type => _type;
  set type(KycDocumentType? value) {
    _type = value;
    notifyListeners();
  }

  KycImage? get image => _image;
  set image(KycImage? value) {
    _image = value;
    notifyListeners();
  }

  /// Why the last chosen or dropped file couldn't be used, if it couldn't.
  String? get imageProblem => _imageProblem;

  /// Nothing has been entered.
  bool get isEmpty =>
      _type == null && _image == null && idNumber.text.trim().isEmpty;

  /// Takes the result of choosing or dropping a file: keeps a usable image,
  /// and shows the problem when there is one.
  void takePicked((KycImage?, String?) result) {
    final (image, problem) = result;
    if (image != null) _image = image;
    _imageProblem = problem;
    notifyListeners();
  }

  /// The document to send. Only call after the fields' form validated.
  KycDocument build() => KycDocument(
        type: _type!,
        idNumber: KycDocumentType.normalize(idNumber.text),
        image: _image!,
      );

  void clear() {
    _type = null;
    _image = null;
    _imageProblem = null;
    idNumber.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    idNumber.dispose();
    super.dispose();
  }
}

/// The ID document fields: document type, ID number and a picture that can
/// be chosen with the file dialog or dragged in. Put it inside a [Form];
/// its checks mirror the backend's (`IdNumberRules`, `KycUploadRules`).
///
/// Keys, for tests: `<keyPrefix>.documentType`, `.idNumber`,
/// `.chooseImage`, `.chosenImage`, `.replaceImage`, `.removeImage` and
/// `.imageProblem`.
class KycDocumentFields extends StatefulWidget {
  const KycDocumentFields({
    super.key,
    required this.draft,
    required this.keyPrefix,
    this.pickImage = pickKycImageFile,
    this.acceptDrops = true,
  });

  final KycDocumentDraft draft;
  final String keyPrefix;

  /// Replaced in tests; the real one opens the system file dialog.
  final PickKycImage pickImage;

  /// Off in widget tests, where the drag-and-drop plugin isn't available.
  final bool acceptDrops;

  @override
  State<KycDocumentFields> createState() => _KycDocumentFieldsState();
}

class _KycDocumentFieldsState extends State<KycDocumentFields> {
  KycDocumentDraft get _draft => widget.draft;
  String get _k => widget.keyPrefix;

  Future<void> _choose() async {
    final result = await widget.pickImage();
    if (result == null || !mounted) return;
    _draft.takePicked(result);
  }

  Future<void> _dropped(List<XFile> files) async {
    final result = await checkDroppedImage(files);
    if (!mounted || (result.$1 == null && result.$2 == null)) return;
    _draft.takePicked(result);
  }

  Widget _pictureArea(KycImage? image, {required bool hovering}) {
    return image == null
        ? _ChooseImageBox(keyPrefix: _k, onTap: _choose, hovering: hovering)
        : _ChosenImage(
            keyPrefix: _k,
            image: image,
            hovering: hovering,
            onReplace: _choose,
            onRemove: () => _draft.image = null,
          );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _draft,
      builder: (context, _) {
        final type = _draft.type;
        final image = _draft.image;
        final imageProblem = _draft.imageProblem;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<KycDocumentType>(
                    key: Key('$_k.documentType'),
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Document'),
                    items: [
                      for (final option in KycDocumentType.values)
                        DropdownMenuItem(
                          value: option,
                          child: Text(option.label),
                        ),
                    ],
                    onChanged: (value) => _draft.type = value,
                    validator: (value) =>
                        value == null ? 'Choose the document' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: Key('$_k.idNumber'),
                    controller: _draft.idNumber,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(50),
                      _UpperCaseFormatter(),
                    ],
                    decoration: InputDecoration(
                      labelText: 'ID number',
                      hintText: type?.example,
                    ),
                    validator: (value) =>
                        type == null ? null : type.problemWith(value ?? ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormField<KycImage>(
              validator: (_) => _draft.image == null
                  ? 'Choose a picture of the ID document'
                  : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.acceptDrops)
                    KycDropTarget(
                      onDropped: _dropped,
                      builder: (context, hovering) =>
                          _pictureArea(image, hovering: hovering),
                    )
                  else
                    _pictureArea(image, hovering: false),
                  // The "choose a picture" error only matters while none is
                  // chosen; it would otherwise linger until the next check.
                  for (final problem in [
                    imageProblem,
                    if (image == null) field.errorText,
                  ])
                    if (problem != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        problem,
                        key: problem == imageProblem
                            ? Key('$_k.imageProblem')
                            : null,
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.error),
                      ),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Capitals as the user types, the way the backend stores ID numbers.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// The empty picture area: a large target that opens the file dialog.
class _ChooseImageBox extends StatelessWidget {
  const _ChooseImageBox({
    required this.keyPrefix,
    required this.onTap,
    required this.hovering,
  });

  final String keyPrefix;
  final VoidCallback onTap;

  /// A file is being dragged over the box.
  final bool hovering;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.primaryContainer.withValues(alpha: hovering ? 0.8 : 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.primary, width: hovering ? 3 : 1.5),
      ),
      child: InkWell(
        key: Key('$keyPrefix.chooseImage'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              Icon(
                hovering ? Icons.file_download_outlined : Icons.upload_file_outlined,
                size: 32,
                color: scheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                hovering
                    ? 'Drop to use this picture'
                    : 'Drag a picture of the ID here, or choose a file',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'JPEG or PNG, 5 MB at most',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen picture, with its name and size, so staff can check it's
/// the right card and readable before sending it.
class _ChosenImage extends StatelessWidget {
  const _ChosenImage({
    required this.keyPrefix,
    required this.image,
    required this.hovering,
    required this.onReplace,
    required this.onRemove,
  });

  final String keyPrefix;
  final KycImage image;

  /// A file is being dragged over the picture, to replace it.
  final bool hovering;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      key: Key('$keyPrefix.chosenImage'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: hovering
            ? Border.all(color: scheme.primary, width: 3)
            : Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              image.bytes,
              width: 180,
              height: 112,
              fit: BoxFit.cover,
              semanticLabel: 'Picture of the ID document',
              errorBuilder: (context, error, stackTrace) => Container(
                width: 180,
                height: 112,
                color: scheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  image.fileName,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  hovering
                      ? 'Drop to replace this picture'
                      : '${image.type.label} · ${image.sizeLabel}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      key: Key('$keyPrefix.replaceImage'),
                      onPressed: onReplace,
                      child: const Text('Replace'),
                    ),
                    TextButton(
                      key: Key('$keyPrefix.removeImage'),
                      onPressed: onRemove,
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


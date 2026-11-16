import 'package:file_selector/file_selector.dart';

import 'member_models.dart';

/// Opens a file and checks it as an ID image. Returns null when the user
/// cancels; otherwise the image or a message saying why it can't be used.
typedef PickKycImage = Future<(KycImage?, String?)?> Function();

/// The system "Open" dialog, limited to JPEG and PNG files.
Future<(KycImage?, String?)?> pickKycImageFile() async {
  const images = XTypeGroup(
    label: 'JPEG or PNG images',
    extensions: ['jpg', 'jpeg', 'png'],
    mimeTypes: ['image/jpeg', 'image/png'],
    uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
  );
  final file = await openFile(acceptedTypeGroups: const [images]);
  if (file == null) return null;
  // Check the size before reading, so a huge file isn't loaded for nothing.
  if (await file.length() > KycImage.maxBytes) {
    return (null, 'That file is larger than 5 MB. Choose a smaller one.');
  }
  return KycImage.check(file.name, await file.readAsBytes());
}

/// Checks files dropped onto the ID picture area. One picture only.
Future<(KycImage?, String?)> checkDroppedImage(List<XFile> files) async {
  if (files.isEmpty) return (null, null);
  if (files.length > 1) {
    return (null, 'Drop one picture at a time.');
  }
  final file = files.single;
  if (await file.length() > KycImage.maxBytes) {
    return (null, 'That file is larger than 5 MB. Choose a smaller one.');
  }
  return KycImage.check(file.name, await file.readAsBytes());
}

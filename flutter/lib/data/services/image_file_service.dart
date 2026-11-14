import 'package:file_selector/file_selector.dart';

class ImageFileService {
  const ImageFileService();

  static const _imageTypes = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png', 'webp'],
    uniformTypeIdentifiers: [
      'public.jpeg',
      'public.png',
      'org.webmproject.webp',
    ],
  );

  Future<String?> selectImage() async {
    final image = await openFile(acceptedTypeGroups: const [_imageTypes]);
    return image?.path;
  }
}

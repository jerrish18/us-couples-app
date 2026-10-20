import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

Future<String?> pickPhoto({
  required String coupleId,
  ImageSource source = ImageSource.gallery,
}) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    requestFullMetadata: false,
  );
  if (picked == null) return null;
  return preparePhoto(picked.path, coupleId: coupleId);
}

Future<String> preparePhoto(String path, {required String coupleId}) async {
  final root = await getApplicationSupportDirectory();
  final folder = await Directory('${root.path}/us-media/$coupleId')
      .create(recursive: true);
  final out = '${folder.path}/${const Uuid().v4()}.jpg';
  final compressed = await FlutterImageCompress.compressAndGetFile(
    path,
    out,
    minWidth: 1280,
    minHeight: 1280,
    quality: 72,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
  if (compressed == null) throw StateError('Could not compress photo');
  if (await File(out).length() > 2097152) {
    await File(out).delete();
    throw StateError('Please choose a smaller photo.');
  }
  return out;
}

const maxVideoBytes = 50 * 1024 * 1024;
Future<String> prepareVideo(String path, {required String coupleId}) async {
  final source = File(path);
  if (await source.length() > maxVideoBytes)
    throw StateError('Choose a video up to 50 MB. Try a shorter recording.');
  final extension = path.split('.').last.toLowerCase();
  if (!['mp4', 'mov', 'm4v', '3gp'].contains(extension))
    throw StateError('Choose an MP4, MOV, M4V or 3GP video.');
  final root = await getApplicationSupportDirectory();
  final folder = await Directory('${root.path}/us-media/$coupleId')
      .create(recursive: true);
  return (await source.copy('${folder.path}/${const Uuid().v4()}.$extension'))
      .path;
}

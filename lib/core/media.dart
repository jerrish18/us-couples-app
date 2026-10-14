import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

Future<String?> pickPhoto() async {
  final source=await ImagePicker().pickImage(source:ImageSource.gallery);
  if(source==null)return null;
  final root=await getApplicationSupportDirectory();
  final out='${root.path}/${const Uuid().v4()}.jpg';
  final compressed=await FlutterImageCompress.compressAndGetFile(source.path,out,minWidth:1280,minHeight:1280,
    quality:72,format:CompressFormat.jpeg,keepExif:false);
  if(compressed==null)throw StateError('Could not compress photo');
  if(await File(out).length()>2097152){await File(out).delete();throw StateError('Please choose a smaller photo.');}
  return out;
}

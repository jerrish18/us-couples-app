import 'dart:io';

/// Queued capture files are deleted after upload; a stale local path is not a
/// usable playback source. Keep resolution separate so the upload handoff can
/// be tested without Android's decoder.
Future<String?> existingVideoFile(String? path) async {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  try {
    return await file.exists() && await file.length() > 0 ? path : null;
  } on FileSystemException {
    return null;
  }
}

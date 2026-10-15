import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/space.dart';

Future<void> exportBackup(UsSpace space) async {
  final cid = space.session.coupleId;
  if (cid == null) throw StateError('Pair first');
  final root = await getTemporaryDirectory();
  final dir = await Directory(
    '${root.path}/us-backup-${DateTime.now().millisecondsSinceEpoch}',
  ).create();
  final messages = <Map<String, dynamic>>[],
      memories = <Map<String, dynamic>>[];
  for (final entry in {'messages': messages, 'memories': memories}.entries) {
    var offset = 0;
    while (true) {
      final page = await space.session.client
          .from(entry.key)
          .select()
          .eq('couple_id', cid)
          .order('created_at')
          .range(offset, offset + 499);
      entry.value.addAll(List<Map<String, dynamic>>.from(page));
      if (page.length < 500) break;
      offset += 500;
    }
  }
  final metadata = File('${dir.path}/Our-story.json');
  await metadata.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'space_name': space.session.couple?['name'],
      'messages': messages,
      'memories': memories,
    }),
  );
  final zipPath = '${dir.path}/Us-Private-Backup.zip';
  final encoder = ZipFileEncoder();
  encoder.create(zipPath);
  await encoder.addFile(metadata, 'Our-story.json');
  final client = HttpClient();
  try {
    final unique = <String>{};
    for (final item in [...messages, ...memories]) {
      final path = item['media_path'] as String?;
      if (path == null || !unique.add(path)) continue;
      final id = item['id'] as String, ext = path.split('.').last;
      final destination = File('${dir.path}/$id.$ext');
      final request = await client.getUrl(
        Uri.parse(await space.mediaUrl(path)),
      );
      final response = await request.close();
      if (response.statusCode != 200)
        throw StateError('Could not export a photo or voice note');
      await response.pipe(destination.openWrite());
      await encoder.addFile(destination, 'media/$id.$ext');
      await destination.delete();
    }
  } finally {
    client.close();
    encoder.close();
  }
  await SharePlus.instance.share(
    ShareParams(files: [XFile(zipPath)], text: 'Our private Us backup'),
  );
}

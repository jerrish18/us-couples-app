import '../../core/space.dart';

class UsAi {
  UsAi(this.space);
  final UsSpace space;
  Future<List<Map<String, dynamic>>> preferences() async =>
      List<Map<String, dynamic>>.from(
        await space.session.client
            .from('ai_preferences')
            .select()
            .eq('couple_id', space.session.coupleId!),
      );
  Future<void> consent({required bool enabled, required bool history}) async {
    await space.session.client.from('ai_preferences').upsert({
      'couple_id': space.session.coupleId,
      'user_id': space.session.userId,
      'enabled': enabled,
      'share_history': enabled && history,
    });
  }

  Future<Map<String, dynamic>> ask({
    required String task,
    required String prompt,
    required String language,
    List<String> ids = const [],
    DateTime? from,
    DateTime? until,
  }) async {
    final uid = space.session.userId, cid = space.session.coupleId;
    final response = await space.session.client.functions.invoke(
      'us-ai',
      body: {
        'task': task,
        'prompt': prompt,
        'language': language,
        'message_ids': ids,
        'from': from?.toUtc().toIso8601String(),
        'until': until?.toUtc().toIso8601String(),
      },
    );
    if (uid != space.session.userId || cid != space.session.coupleId)
      throw StateError('Your account changed. Result discarded.');
    final data = Map<String, dynamic>.from(response.data as Map);
    if (response.status != 200 || data['error'] != null)
      throw StateError(data['error']?.toString() ?? 'AI unavailable.');
    return data;
  }
}

const aiTasks = <String, String>{
  'reply': 'Help me reply',
  'rewrite': 'Rewrite my message',
  'together': 'Ask AI together',
  'summary': 'Catch me up',
  'plans': 'Turn chat into plans',
  'search': 'Find past conversations',
  'date': 'Date planner',
  'expense': 'Draft an expense',
  'caption': 'Memory captions',
};

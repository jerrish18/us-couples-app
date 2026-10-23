import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/space.dart';

class UsAi {
  UsAi(this.space);
  final UsSpace space;
  Future<List<Map<String, dynamic>>> preferences() async {
    final uid = space.session.userId, cid = space.session.coupleId;
    final rows = await space.session.client
        .from('ai_preferences')
        .select()
        .eq('couple_id', cid!);
    if (uid != space.session.userId || cid != space.session.coupleId) {
      throw StateError('Your account changed. Please reopen AI.');
    }
    return List<Map<String, dynamic>>.from(rows);
  }

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
    double? budget,
    int? minutes,
    bool publish = false,
  }) async {
    final problem = aiInputError(
      task: task,
      prompt: prompt,
      ids: ids,
      from: from,
      until: until,
      budget: budget,
      minutes: minutes,
    );
    if (problem != null) throw StateError(problem);
    final uid = space.session.userId, cid = space.session.coupleId;
    try {
      final response = await space.session.client.functions
          .invoke(
            'us-ai',
            body: {
              // Old servers reject ask instead of accidentally publishing a draft.
              'task': task == 'together' && !publish ? 'ask' : task,
              'prompt': prompt,
              'language': language,
              'message_ids': ids,
              'from': from?.toUtc().toIso8601String(),
              'until': until?.toUtc().toIso8601String(),
              'budget': budget,
              'minutes': minutes,
              'publish': publish,
            },
          )
          .timeout(const Duration(seconds: 50));
      if (uid != space.session.userId || cid != space.session.coupleId)
        throw StateError('Your account changed. Result discarded.');
      if (response.data is! Map)
        throw StateError('AI returned an invalid response. Please try again.');
      final data = Map<String, dynamic>.from(response.data as Map);
      if (response.status != 200 || data['error'] != null)
        throw StateError(data['error']?.toString() ?? 'AI unavailable.');
      return data;
    } on FunctionException catch (e) {
      throw StateError(
        e.details is Map
            ? '${e.details['error'] ?? 'AI is unavailable. Please try later.'}'
            : 'Could not reach AI. Check your connection and try again.',
      );
    } on TimeoutException {
      throw StateError(
        'AI took too long. Your draft is safe. Please try later.',
      );
    }
  }
}

const aiHistoryTasks = {'reply', 'together', 'summary', 'plans', 'search'};

String? aiInputError({
  required String task,
  required String prompt,
  List<String> ids = const [],
  DateTime? from,
  DateTime? until,
  double? budget,
  int? minutes,
}) {
  if (prompt.trim().isEmpty)
    return 'Write what you would like help with in the message box.';
  if (utf8.encode(prompt.trim()).length > 1500) {
    return 'Shorten your request to 1,500 bytes (Tamil characters use more than one byte). Your draft is unchanged.';
  }
  if (['reply', 'plans'].contains(task) && ids.isEmpty)
    return 'Choose at least one saved text message for context.';
  if (task == 'summary' &&
      (from == null ||
          until == null ||
          !until.isAfter(from) ||
          until.difference(from) > const Duration(days: 31))) {
    return 'Choose a summary range of up to 31 days, with the end after the start.';
  }
  if (task == 'date' &&
      (budget == null ||
          !budget.isFinite ||
          budget < 1 ||
          budget > 100000 ||
          minutes == null ||
          minutes < 30 ||
          minutes > 1440)) {
    return 'Enter a budget from ₹1 to ₹100,000 and 30 to 1,440 minutes.';
  }
  return null;
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

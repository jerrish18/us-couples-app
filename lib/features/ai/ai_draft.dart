/// Turn structured AI output into useful, editable chat text, never JSON.
String aiDraftText(Map<String, dynamic> result, {int suggestion = 0}) {
  final suggestions = (result['suggestions'] as List? ?? [])
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .toList();
  if (suggestions.isNotEmpty)
    return suggestions[suggestion.clamp(0, suggestions.length - 1)].trim();
  final draft = result['draft'] as Map?;
  final itinerary = result['itinerary'] as List? ?? [];
  final parts = <String>[];
  if (draft != null && draft['kind'] != null && draft['kind'] != 'none') {
    for (final key in ['title', 'starts_at', 'place']) {
      final value = '${draft[key] ?? ''}'.trim();
      if (value.isNotEmpty) parts.add(value);
    }
    if (draft['kind'] == 'expense') {
      parts.add('₹${draft['amount']} · ${draft['category']}');
      for (final key in ['spent_on', 'outing']) {
        final value = '${draft[key] ?? ''}'.trim();
        if (value.isNotEmpty) parts.add(value);
      }
    }
    final notes = '${draft['notes'] ?? ''}'.trim();
    if (notes.isNotEmpty) parts.add(notes);
  } else {
    final answer = '${result['answer'] ?? ''}'.trim();
    if (answer.isNotEmpty) parts.add(answer);
  }
  for (final item in itinerary.whereType<Map>()) {
    parts.add(
      '${item['activity']} · ${item['minutes']} min · estimated ₹${item['estimated_cost']} for two',
    );
  }
  final budget = result['budget'];
  if (budget is Map)
    parts.add(
      'Estimated total: ₹${budget['total']} · ${budget['total_minutes']} min',
    );
  return parts.join('\n');
}

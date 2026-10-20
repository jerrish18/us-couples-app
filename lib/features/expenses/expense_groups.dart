enum ExpenseGrouping { date, category, outing }

const expenseCategories = [
  'Food',
  'Travel',
  'Shopping',
  'Stay',
  'Entertainment',
  'Bills',
  'Gifts',
  'Other',
];
String expenseDate(Map<String, dynamic> row) =>
    '${row['spent_on'] ?? row['created_at'] ?? ''}'.split('T').first;
String expenseGroup(Map<String, dynamic> row, ExpenseGrouping grouping) =>
    switch (grouping) {
      ExpenseGrouping.date => expenseDate(row),
      ExpenseGrouping.category => row['category'] as String? ?? 'Other',
      ExpenseGrouping.outing =>
        (row['outing'] as String? ?? '').trim().isEmpty
            ? 'Everyday expenses'
            : (row['outing'] as String).trim(),
    };
Map<String, List<Map<String, dynamic>>> groupExpenses(
  List<Map<String, dynamic>> rows,
  ExpenseGrouping grouping, {
  String query = '',
}) {
  final result = <String, List<Map<String, dynamic>>>{};
  final sorted = List<Map<String, dynamic>>.from(rows)
    ..sort((a, b) => expenseDate(b).compareTo(expenseDate(a)));
  for (final row in sorted) {
    if (!'${row['title']} ${row['category'] ?? ''} ${row['outing'] ?? ''}'
        .toLowerCase()
        .contains(query.toLowerCase().trim()))
      continue;
    (result[expenseGroup(row, grouping)] ??= []).add(row);
  }
  return result;
}

int expensePaise(Map<String, dynamic> row) =>
    ((row['amount'] as num).toDouble() * 100).round();

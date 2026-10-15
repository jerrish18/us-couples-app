import 'package:home_widget/home_widget.dart';

class UsWidget {
  static Future<void> update(
    Map<String, dynamic>? couple,
    Map<String, dynamic>? partner,
  ) async {
    await HomeWidget.saveWidgetData<String>(
      'together_since',
      couple?['together_since'] as String? ?? '',
    );
    await HomeWidget.saveWidgetData<String>(
      'partner_mood',
      partner?['mood'] as String? ?? '',
    );
    await HomeWidget.saveWidgetData<String>(
      'mood_date',
      partner?['mood_date'] as String? ?? '',
    );
    await HomeWidget.updateWidget(androidName: 'UsWidgetProvider');
  }

  static Future<void> clear() => update(null, null);
}

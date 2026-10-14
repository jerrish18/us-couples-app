import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import 'config.dart';
import 'session.dart';
import 'local_database.dart';
import 'reminder_dates.dart';

@pragma('vm:entry-point')
Future<void> receiveBackground(RemoteMessage message) async {
  await Firebase.initializeApp(options:firebaseOptions);await UsNotifications.initialize();
  await UsNotifications.show(message.data);
}
@pragma('vm:entry-point')
void notificationBackgroundAction(NotificationResponse response){unawaited(UsNotifications.missBack(response));}

class UsNotifications {
  static final plugin=FlutterLocalNotificationsPlugin();
  static final taps=StreamController<String>.broadcast();
  static bool _initialized=false;
  static String? initialRoute;
  static const storage=FlutterSecureStorage();
  static Future<void> initialize() async {
    if(_initialized)return;
    tzdata.initializeTimeZones();
    await plugin.initialize(const InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse:(r){if(r.actionId=='miss_back')unawaited(missBack(r));
        else {final data=_payload(r.payload);final route=_route(data['route']);initialRoute=route;taps.add(route);}},
      onDidReceiveBackgroundNotificationResponse:notificationBackgroundAction);
    final android=plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for(final c in const [AndroidNotificationChannel('us_chat','Messages',description:'Messages from your person',importance:Importance.high),
      AndroidNotificationChannel('us_love','Miss Me',description:'A little love from your person',importance:Importance.high),
      AndroidNotificationChannel('us_dates','Dates and reminders',description:'Your shared dates and milestones',importance:Importance.high)]){
      await android?.createNotificationChannel(c);
    }
    final launch=await plugin.getNotificationAppLaunchDetails();
    if(launch?.didNotificationLaunchApp==true)initialRoute=_route(_payload(launch?.notificationResponse?.payload)['route']);
    _initialized=true;
  }
  static Map<String,dynamic> _payload(String? value){try{return Map<String,dynamic>.from(jsonDecode(value??'{}') as Map);}catch(_){return {};}}
  static String _route(dynamic value)=>['/','/chat','/calendar','/memories'].contains(value)?value as String:'/';
  static Future<void> bind(UsSession session) async {
    FirebaseMessaging.onBackgroundMessage(receiveBackground);
    FirebaseMessaging.onMessage.listen((message)=>show(message.data));
    FirebaseMessaging.onMessageOpenedApp.listen((message){initialRoute=_route(message.data['route']);taps.add(initialRoute!);});
    final initial=await FirebaseMessaging.instance.getInitialMessage();if(initial!=null)initialRoute=_route(initial.data['route']);
    FirebaseMessaging.instance.onTokenRefresh.listen((token)=>_register(session,token));
  }
  static Future<void> requestPermission(UsSession session) async {
    await FirebaseMessaging.instance.requestPermission();
    final token=await FirebaseMessaging.instance.getToken();if(token!=null)await _register(session,token);
  }
  static Future<void> _register(UsSession session,String token) async {
    if(session.userId==null)return;
    try{
      final existing=await session.client.from('device_tokens').select('token').eq('token',token).eq('user_id',session.userId!).maybeSingle();
      if(existing==null)await session.client.from('device_tokens').insert({'token':token,'user_id':session.userId,'updated_at':DateTime.now().toUtc().toIso8601String()});
      else await session.client.from('device_tokens').update({'updated_at':DateTime.now().toUtc().toIso8601String()}).eq('token',token).eq('user_id',session.userId!);
    }on PostgrestException catch(e){if(e.code=='23505')await FirebaseMessaging.instance.deleteToken();}
    catch(_){/* Retry registration when the app resumes. */}
  }
  static Future<void> unregister(UsSession session) async {
    final token=await FirebaseMessaging.instance.getToken();
    if(token!=null&&session.userId!=null)await session.client.from('device_tokens').delete().eq('token',token).eq('user_id',session.userId!);
    await plugin.cancelAll();await FirebaseMessaging.instance.deleteToken();
  }
  static Future<void> show(Map<String,dynamic> data) async {
    await initialize();
    final channel=data['kind']=='message'?'us_chat':data['kind']=='miss_me'?'us_love':'us_dates';
    await plugin.show(stableNotificationId((data['event_id']??data['entity_id']??DateTime.now().toString()).toString()),
      (data['title']??'Us').toString(),(data['body']??'Your person sent you something.').toString(),
      NotificationDetails(android:AndroidNotificationDetails(channel,channel=='us_chat'?'Messages':channel=='us_love'?'Miss Me':'Dates and reminders',
        importance:Importance.high,priority:Priority.high,actions:data['kind']=='miss_me'?
          const [AndroidNotificationAction('miss_back','Miss you too ❤️',showsUserInterface:false,cancelNotification:true)]:null)),
      payload:jsonEncode(data));
  }
  static Future<void> missBack(NotificationResponse response) async {
    if(response.actionId!='miss_back')return;
    try {
      try{Supabase.instance.client;}catch(_){await Supabase.initialize(url:supabaseUrl,publishableKey:supabaseKey,
        authOptions:FlutterAuthClientOptions(localStorage:SecureSessionStorage()));}
      final client=Supabase.instance.client,uid=Supabase.instance.client.auth.currentUser?.id;
      if(uid==null)return;
      final saved=await storage.read(key:'us.couple.$uid');if(saved==null)return;
      final cid=(jsonDecode(saved) as Map)['id'] as String;
      final data=_payload(response.payload),event=(data['event_id']??'').toString();if(event.isEmpty)return;
      final id=const Uuid().v5(Uuid.NAMESPACE_URL,'us-miss-back-$uid-$event');
      final row={'id':id,'couple_id':cid,'sender_id':uid,'body':'Miss you too ❤️','created_at':DateTime.now().toUtc().toIso8601String()};
      final db=LocalDatabase(uid);
      try{
        if(!(await db.pending()).any((t)=>t.taskId==id))await db.enqueue('messages',row);
        try{await client.from('messages').upsert(row,onConflict:'id',ignoreDuplicates:true);await db.complete(id);}catch(_){/* Durable queue sends on next app connection. */}
      }finally{await db.close();}
    }catch(_){/* The action must not leak account details in a notification. */}
  }
  static Future<void> reminders(Map<String,List<Map<String,dynamic>>> rows,Map<String,dynamic> preferences,String timezone) async {
    await initialize();
    final old=(await storage.read(key:'us.reminder.ids')??'').split(',').map(int.tryParse).whereType<int>();
    for(final id in old){await plugin.cancel(id);}
    if(preferences['reminders']==false){await storage.write(key:'us.reminder.ids',value:'');return;}
    final ids=<int>[];tz.Location location;try{location=tz.getLocation(timezone);}catch(_){location=tz.getLocation('Asia/Kolkata');}
    Future<void> schedule(String key,String title,String body,DateTime due) async {
      if(due.isBefore(DateTime.now()))return;
      final id=stableNotificationId(key);ids.add(id);
      await plugin.zonedSchedule(id,title,body,tz.TZDateTime.from(due,location),
        const NotificationDetails(android:AndroidNotificationDetails('us_dates','Dates and reminders',importance:Importance.high)),
        androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,payload:jsonEncode({'route':'/calendar'}));
    }
    for(final date in rows['dates']??<Map<String,dynamic>>[]){
      final when=DateTime.tryParse(date['starts_at'] as String? ?? '');if(when==null)continue;
      for(final hours in [24,1])await schedule('date:${date['id']}:$hours','A little time for us',
        '${date['title']} is ${hours==24?'tomorrow':'in one hour'}.',when.subtract(Duration(hours:hours)));
    }
    final now=tz.TZDateTime.now(location);
    for(final date in rows['anniversaries']??<Map<String,dynamic>>[]){
      final original=DateTime.tryParse(date['event_date'] as String? ?? '');if(original==null)continue;
      final annual=nextAnnualDate(original,now);
      final day=date['yearly']==true?annual:original;
      final due=tz.TZDateTime(location,day.year,day.month,day.day,9);
      await schedule('anniversary:${date['id']}:${day.year}',date['title'] as String,'A special day for the two of you.',due);
    }
    await storage.write(key:'us.reminder.ids',value:ids.join(','));
  }
}

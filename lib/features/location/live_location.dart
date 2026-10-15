import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/session.dart';

final locationProvider=Provider<LiveLocation>((ref){final service=LiveLocation(ref.read(sessionProvider));ref.onDispose(service.dispose);return service;});
/// Positions are ephemeral and deliberately never enter the offline database/queue.
class LiveLocation extends ChangeNotifier {
  LiveLocation(this.session){session.addListener(_sessionChanged);_sessionChanged();_clock=Timer.periodic(const Duration(seconds:5),(_){
    if(until!=null&&!until!.isAfter(DateTime.now()))unawaited(stop());
    if(!_dead)notifyListeners();
  });}
  final UsSession session;
  RealtimeChannel? _channel;StreamSubscription<Position>? _positions;Timer? _clock;
  String? _uid,_cid;DateTime? until,lastSent;String? error;
  bool starting=false,_dead=false,_uploading=false;
  final Map<String,Map<String,dynamic>> locations={};
  bool get sharing=>until?.isAfter(DateTime.now())??false;
  List<Map<String,dynamic>> get active=>locations.values.where((r)=>(DateTime.tryParse(r['expires_at'] as String? ?? '')?.isAfter(DateTime.now())??false)).toList();
  void _notify(){if(!_dead)notifyListeners();}
  void _sessionChanged(){
    if(_uid==session.userId&&_cid==session.coupleId)return;
    unawaited(_positions?.cancel());_positions=null;until=null;locations.clear();
    if(_channel!=null)unawaited(session.client.removeChannel(_channel!));
    _uid=session.userId;_cid=session.coupleId;
    if(_uid==null||_cid==null)return;
    // A fresh app launch never silently resumes an earlier sharing session.
    unawaited(session.client.rpc('stop_location').then((_){}).catchError((_){}));
    _channel=session.client.channel('locations:$_cid:$_uid').onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',table:'live_locations',
      callback:(_)=>unawaited(refresh())).subscribe();
    unawaited(refresh());_notify();
  }
  Future<void> refresh() async {
    final cid=_cid;if(cid==null)return;
    try{final data=await session.client.from('live_locations').select().eq('couple_id',cid);
      if(_dead||cid!=_cid)return;locations.clear();for(final row in data){locations[row['user_id'] as String]=Map<String,dynamic>.from(row);}_notify();
    }catch(_){error='Waiting for a connection. Positions may be out of date.';_notify();}
  }
  Future<void> start(Duration duration) async {
    if(starting)return;starting=true;error=null;_notify();
    try{
      if(session.partnerId==null)throw StateError('Invite your partner before sharing.');
      if(!await Geolocator.isLocationServiceEnabled())throw StateError('Turn on your phone’s Location setting first.');
      var permission=await Geolocator.checkPermission();
      if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();
      if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever)throw StateError('Allow location in Android Settings → Apps → Us → Permissions. Choose Precise for better accuracy.');
      await _positions?.cancel();
      until=DateTime.now().add(duration);lastSent=null;
      final position=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.best,timeLimit:Duration(seconds:30)));
      await _send(position);
      _positions=Geolocator.getPositionStream(locationSettings:AndroidSettings(accuracy:LocationAccuracy.bestForNavigation,distanceFilter:5,intervalDuration:const Duration(seconds:5),
        foregroundNotificationConfig:const ForegroundNotificationConfig(notificationTitle:'Us · Live location is on',notificationText:'Your partner can see your position. Open Us → Live location to stop.',enableWakeLock:true,setOngoing:true)))
        .listen((p)=>unawaited(_send(p)),onError:(Object _){error='GPS paused. Check Location and battery settings.';_notify();});
    }catch(e){await stop();error=e is StateError?e.message.toString():'Could not get your position. Try outdoors with Location on.';}
    finally{starting=false;_notify();}
  }
  Future<void> _send(Position p) async {
    if(!sharing||_uploading||_cid==null||_dead)return;
    if(lastSent!=null&&DateTime.now().difference(lastSent!).inSeconds<5)return;
    if(p.timestamp.isBefore(DateTime.now().subtract(const Duration(minutes:1))))return;
    _uploading=true;
    try{await session.client.rpc('share_location',params:{'p_couple':_cid,'p_lat':p.latitude,'p_lng':p.longitude,'p_accuracy':p.accuracy,'p_until':until!.toUtc().toIso8601String()});
      lastSent=DateTime.now();error=null;await refresh();
    }catch(_){error='Sharing paused while offline. Your partner sees the last update time.';}
    finally{_uploading=false;_notify();}
  }
  Future<void> stop() async {
    until=null;await _positions?.cancel();_positions=null;
    locations.remove(_uid);_notify();
    try{await session.client.rpc('stop_location');error=null;}
    catch(_){error='Stopped on this phone. Connect once to remove the last shared position immediately; it also expires automatically.';}
    _notify();
  }
  @override void dispose(){_dead=true;session.removeListener(_sessionChanged);_clock?.cancel();unawaited(_positions?.cancel());if(_channel!=null)unawaited(session.client.removeChannel(_channel!));super.dispose();}
}

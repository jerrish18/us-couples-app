import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
/// Receiving a share only opens a draft. Upload always requires Send.
class ShareInbox {
 static final changes=StreamController<List<SharedMediaFile>>.broadcast();
 static List<SharedMediaFile> pending=[];
 static StreamSubscription<List<SharedMediaFile>>? _subscription;
 static Future<void> initialize() async {
  _subscription??=ReceiveSharingIntent.instance.getMediaStream().listen(_receive,onError:(Object _){});
  _receive(await ReceiveSharingIntent.instance.getInitialMedia());
 }
 static void _receive(List<SharedMediaFile> files){if(files.isEmpty)return;pending=files.take(5).toList();changes.add(pending);}
 static void clear(){pending=[];ReceiveSharingIntent.instance.reset();}
}

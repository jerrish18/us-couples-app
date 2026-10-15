import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/space.dart';
class VoiceBubble extends StatefulWidget {
 const VoiceBubble({super.key,required this.space,required this.message});final UsSpace space;final Map<String,dynamic> message;
 @override State<VoiceBubble> createState()=>_VoiceBubbleState();
}
class _VoiceBubbleState extends State<VoiceBubble>{
 final _player=AudioPlayer();bool _loaded=false,_busy=false;double _speed=1;
 @override void dispose(){unawaited(_player.dispose());super.dispose();}
 Future<void> _toggle() async {
  if(_busy)return;setState(()=>_busy=true);
  try{
   if(!_loaded){await _player.setFilePath(widget.message['_local_file'] as String? ?? await widget.space.mediaFile(widget.message['media_path'] as String));_loaded=true;}
   if(_player.playing){await _player.pause();}else{if(_player.processingState==ProcessingState.completed)await _player.seek(Duration.zero);unawaited(_player.play());}
  }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not play this voice note. Try again when connected.')));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 String _time(Duration d)=>'${d.inMinutes}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
 @override Widget build(BuildContext context)=>SizedBox(width:238,child:Column(mainAxisSize:MainAxisSize.min,children:[
 Row(children:[StreamBuilder<PlayerState>(stream:_player.playerStateStream,builder:(c,s)=>IconButton(tooltip:'Play or pause voice note',onPressed:_busy?null:_toggle,icon:Icon(s.data?.playing==true&&s.data?.processingState!=ProcessingState.completed?Icons.pause_circle_filled:Icons.play_circle_fill),iconSize:36)),
 const Expanded(child:Text('Voice note')),TextButton(onPressed:(){setState(()=>_speed=_speed==1?1.5:_speed==1.5?2:1);_player.setSpeed(_speed);},child:Text('${_speed}×'))]),
 StreamBuilder<Duration>(stream:_player.positionStream,builder:(c,s){final pos=s.data??Duration.zero,total=_player.duration??Duration.zero;
 return Column(children:[Slider(value:pos.inMilliseconds.toDouble().clamp(0,total.inMilliseconds.toDouble()),max:total.inMilliseconds>0?total.inMilliseconds.toDouble():1,onChanged:!_loaded?null:(v)=>_player.seek(Duration(milliseconds:v.round()))),Text('${_time(pos)} / ${_time(total)}',style:Theme.of(context).textTheme.labelSmall)]);}),
 ]));
}

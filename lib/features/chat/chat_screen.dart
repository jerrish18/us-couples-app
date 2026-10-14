import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';
import '../../core/space.dart';
import '../../core/media.dart';
import '../../core/ui.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override ConsumerState<ChatScreen> createState()=>_ChatScreenState();
}
class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text=TextEditingController(),_scroll=ScrollController();
  final _recorder=AudioRecorder(),_player=AudioPlayer();
  bool _recording=false,_sending=false;Map<String,dynamic>? _reply;Timer? _recordLimit;
  final Set<String> _marking={};
  @override void dispose(){_text.dispose();_scroll.dispose();_recordLimit?.cancel();_recorder.dispose();_player.dispose();super.dispose();}
  Future<void> _send(UsSpace space,{String? file,String? kind}) async {
    if(_sending)return;setState(()=>_sending=true);
    try{await space.send(_text.text,file:file,kind:kind,replyTo:_reply?['id'] as String?);
      _text.clear();await space.typing(false);if(mounted)setState(()=>_reply=null);
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not save this message. Please try again.')));}
    finally{if(mounted)setState(()=>_sending=false);}
  }
  Future<void> _voice(UsSpace space) async {
    try{
      if(_recording){final path=await _recorder.stop();_recordLimit?.cancel();if(mounted)setState(()=>_recording=false);
        if(path!=null)await _send(space,file:path,kind:'voice');return;}
      if(!await _recorder.hasPermission())return;
      final root=await getApplicationSupportDirectory();
      final folder=await Directory('${root.path}/us-media/${space.session.coupleId}').create(recursive:true);
      await _recorder.start(const RecordConfig(encoder:AudioEncoder.aacLc,bitRate:48000,sampleRate:22050,numChannels:1),path:'${folder.path}/${const Uuid().v4()}.m4a');
      if(mounted)setState(()=>_recording=true);
      _recordLimit=Timer(const Duration(minutes:3),()=>_voice(space));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not record. Check microphone permission.')));}
  }
  Future<void> _play(UsSpace space,Map<String,dynamic> message) async {
    await safely(context,() async {await _player.stop();
      if(message['_local_file']!=null)await _player.setFilePath(message['_local_file'] as String);
      else await _player.setFilePath(await space.mediaFile(message['media_path'] as String));
      unawaited(_player.play());});
  }
  void _read(UsSpace space,List<Map<String,dynamic>> messages) {
    final states=space.rows['message_states']??[];
    for(final m in messages.where((m)=>m['sender_id']!=space.session.userId&&m['_pending']!=true)){
      final id=m['id'] as String;
      if(_marking.contains(id)||states.any((s)=>s['message_id']==id&&s['user_id']==space.session.userId&&s['read_at']!=null))continue;
      _marking.add(id);unawaited(space.messageState(id).catchError((_){_marking.remove(id);}));
    }
  }
  @override Widget build(BuildContext context){final space=ref.watch(spaceProvider);
    return ListenableBuilder(listenable:space,builder:(context,_) {
      final states=space.rows['message_states']??[];
      final hidden=states.where((s)=>s['user_id']==space.session.userId&&s['hidden']==true).map((s)=>s['message_id']).toSet();
      final messages=space.items.where((m)=>!hidden.contains(m['id'])).toList()
        ..sort((a,b)=>(a['created_at'] as String).compareTo(b['created_at'] as String));
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_read(space,messages);});
      return Column(children:[
        ListTile(dense:true,leading:Icon(Icons.circle,size:12,color:space.partnerOnline?Colors.green:Colors.grey),
          title:Text(space.partnerTyping?'Your person is typing…':space.partnerOnline?'Your person is here':space.partner?['last_seen']==null?'A little space for your words':'Last seen ${displayDate(space.partner!['last_seen'] as String)} ${displayTime(space.partner!['last_seen'] as String)}'),
          subtitle:space.queued>0?Text('${space.queued} message${space.queued==1?'':'s'} waiting to sync'):null,
          trailing:IconButton(tooltip:'Retry sending',onPressed:space.sync,icon:const Icon(Icons.sync))),
        Expanded(child:messages.isEmpty?const Center(child:EmptyCard('Say something sweet','Your conversation begins here.',icon:Icons.chat_bubble_outline)):
          ListView.builder(controller:_scroll,reverse:true,padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),itemCount:messages.length,itemBuilder:(context,index){
            final m=messages[messages.length-index-1],mine=m['sender_id']==space.session.userId;
            final reactions=(space.rows['reactions']??[]).where((r)=>r['message_id']==m['id']).length;
            final read=states.any((s)=>s['message_id']==m['id']&&s['user_id']==space.session.partnerId&&s['read_at']!=null);
            final replied=messages.where((r)=>r['id']==m['reply_to']).firstOrNull;
            return Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:310),child:Padding(
              padding:const EdgeInsets.only(bottom:12),child:GestureDetector(onDoubleTap:()=>safely(context,()=>space.react(m['id'] as String)),
                onLongPress:()=>showModalBottomSheet<void>(context:context,builder:(sheet)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
                  ListTile(leading:const Icon(Icons.reply),title:const Text('Reply'),onTap:(){Navigator.pop(sheet);setState(()=>_reply=m);}),
                  ListTile(leading:const Icon(Icons.favorite_outline),title:const Text('Heart'),onTap:(){Navigator.pop(sheet);safely(context,()=>space.react(m['id'] as String));}),
                  if(m['_pending']!=true)ListTile(leading:const Icon(Icons.visibility_off_outlined),title:const Text('Delete for me'),onTap:(){Navigator.pop(sheet);safely(context,()=>space.messageState(m['id'] as String,hidden:true));}),
                ]))),child:Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:mine?Theme.of(context).colorScheme.primaryContainer:Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius:BorderRadius.circular(22)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    if(m['reply_to']!=null)Container(padding:const EdgeInsets.all(10),margin:const EdgeInsets.only(bottom:10),decoration:BoxDecoration(
                      border:Border(left:BorderSide(color:Theme.of(context).colorScheme.primary,width:3))),child:Text(replied?['body'] as String? ?? 'Photo or voice note',maxLines:2,overflow:TextOverflow.ellipsis)),
                    if(m['media_kind']=='photo')PrivatePhoto(space,m['media_path'] as String,localFile:m['_local_file'] as String?),
                    if(m['media_kind']=='voice')TextButton.icon(onPressed:()=>_play(space,m),icon:const Icon(Icons.play_arrow),label:const Text('Voice note')),
                    if(m['body']!=null)Padding(padding:const EdgeInsets.only(top:4),child:SelectableText(m['body'] as String,style:const TextStyle(fontSize:16))),
                    const SizedBox(height:6),Text('${displayTime(m['created_at'] as String)}${mine?' · ${m['_pending']==true?'Waiting':read?'Read':'Sent'}':''}${reactions>0?' · ❤️ $reactions':''}',style:Theme.of(context).textTheme.labelSmall),
                  ]))))));
          })),
        if(_reply!=null)ListTile(dense:true,title:const Text('Replying to'),subtitle:Text(_reply!['body'] as String? ?? 'Photo or voice note',maxLines:1,overflow:TextOverflow.ellipsis),
          trailing:IconButton(onPressed:()=>setState(()=>_reply=null),icon:const Icon(Icons.close))),
        if(_recording)const Padding(padding:EdgeInsets.all(8),child:Text('Recording · tap stop to send · maximum 3 minutes')),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(8,4,8,8),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          IconButton(tooltip:'Share photo',onPressed:_sending||_recording?null:() async {await safely(context,() async {final path=await pickPhoto(coupleId:space.session.coupleId!);if(path!=null)await _send(space,file:path,kind:'photo');});},icon:const Icon(Icons.add_photo_alternate_outlined)),
          Expanded(child:TextField(controller:_text,minLines:1,maxLines:4,maxLength:8000,buildCounter:(_, {required currentLength,required isFocused,maxLength})=>null,
            onChanged:(_)=>space.typing(true),decoration:const InputDecoration(hintText:'A little hello…'))),
          IconButton(tooltip:_recording?'Stop and send voice note':'Record voice note',onPressed:_sending?null:()=>_voice(space),icon:Icon(_recording?Icons.stop_circle:Icons.mic_none)),
          IconButton(tooltip:'Send message',onPressed:_sending||_recording?null:()=>_send(space),icon:const Icon(Icons.send_rounded)),
        ]))),
      ]);
    });
  }
}

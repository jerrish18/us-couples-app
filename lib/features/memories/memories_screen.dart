import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/space.dart';
import '../../core/media.dart';
import '../../core/ui.dart';
class MemoriesScreen extends ConsumerStatefulWidget {
 const MemoriesScreen({super.key});@override ConsumerState<MemoriesScreen> createState()=>_MemoriesScreenState();
}
class _MemoriesScreenState extends ConsumerState<MemoriesScreen>{
 String? _collection;
 Future<void> _add(UsSpace space) async {
  await safely(context,() async {final path=await pickPhoto(coupleId:space.session.coupleId!);if(path==null||!mounted)return;
   final caption=await askText(context,'Keep this little moment',hint:'A caption for your memory',max:4000,lines:2);if(caption==null||!mounted)return;
   final date=await pickDateTime(context,time:false);if(date==null)return;
   await space.send(caption,file:path,kind:'photo',memory:true,caption:caption,memoryDate:date,collectionId:_collection);
  });
 }
 @override Widget build(BuildContext context){final space=ref.watch(spaceProvider);
 return ListenableBuilder(listenable:space,builder:(context,_){final collections=space.rows['memory_collections']??[];
 final memories=(space.rows['memories']??[]).where((m)=>_collection==null||m['collection_id']==_collection).toList()..sort((a,b)=>(b['memory_date'] as String).compareTo(a['memory_date'] as String));
 return RefreshIndicator(onRefresh:space.refresh,child:ListView(padding:const EdgeInsets.all(20),children:[
 Text('The moments we keep.',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:16),
 FilledButton.icon(onPressed:()=>_add(space),icon:const Icon(Icons.add_photo_alternate_outlined),label:const Text('Keep a memory')),
 const SizedBox(height:14),Wrap(spacing:8,runSpacing:8,children:[ChoiceChip(label:const Text('All moments'),selected:_collection==null,onSelected:(_)=>setState(()=>_collection=null)),for(final c in collections)ChoiceChip(label:Text(c['title'] as String),selected:_collection==c['id'],onSelected:(_)=>setState(()=>_collection=c['id'] as String)),ActionChip(avatar:const Icon(Icons.add,size:18),label:const Text('Collection'),onPressed:()=>context.push('/collections'))]),
 const SizedBox(height:20),if(memories.isEmpty)const EmptyCard('Our little moments','Photos and stories, held privately for the two of you.',icon:Icons.photo_library_outlined),
 ...memories.map((m){final hearts=(space.rows['reactions']??[]).where((r)=>r['memory_id']==m['id']).length;
 return Card(margin:const EdgeInsets.only(bottom:20),clipBehavior:Clip.antiAlias,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 GestureDetector(onDoubleTap:()=>safely(context,()=>space.react(m['id'] as String,memory:true)),onTap:()=>showDialog<void>(context:context,builder:(c)=>Dialog.fullscreen(child:Scaffold(appBar:AppBar(title:const Text('A little moment')),body:Center(child:InteractiveViewer(maxScale:5,child:PrivatePhoto(space,m['media_path'] as String,localFile:m['_local_file'] as String?,height:MediaQuery.sizeOf(c).height*.75)))))),child:PrivatePhoto(space,m['media_path'] as String,localFile:m['_local_file'] as String?,height:280)),
 Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(m['caption'] as String,style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:8),
 Row(children:[Expanded(child:Text(displayDate(m['memory_date'] as String))),if(m['_pending']==true)const Text('Waiting to sync'),
 if(m['author_id']==space.session.userId&&m['_pending']!=true)PopupMenuButton<String>(tooltip:'Move to collection',onSelected:(v)=>safely(context,()=>space.update('memories',m['id'] as String,{'collection_id':v=='none'?null:v})),itemBuilder:(_)=>[const PopupMenuItem(value:'none',child:Text('No collection')),for(final c in collections)PopupMenuItem(value:c['id'] as String,child:Text(c['title'] as String))],icon:const Icon(Icons.drive_file_move_outline)),
 IconButton(tooltip:'Heart memory',onPressed:()=>safely(context,()=>space.react(m['id'] as String,memory:true)),icon:const Icon(Icons.favorite_outline)),Text('$hearts')]),
 ])),
 ]));}),
 ]));});}
}

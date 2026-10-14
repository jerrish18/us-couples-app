import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/space.dart';
import '../../core/media.dart';
import '../../core/ui.dart';

class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});
  Future<void> _add(BuildContext context,UsSpace space) async {
    await safely(context,() async {final path=await pickPhoto();if(path==null||!context.mounted)return;
      final caption=await askText(context,'Keep this little moment',hint:'A caption for your memory',max:4000,lines:2);
      if(caption==null||!context.mounted)return;
      final date=await pickDateTime(context,time:false);if(date==null)return;
      await space.send(caption,file:path,kind:'photo',memory:true,caption:caption,memoryDate:date);
    });
  }
  @override Widget build(BuildContext context,WidgetRef ref){final space=ref.watch(spaceProvider);
    return ListenableBuilder(listenable:space,builder:(context,_) {
      final memories=List<Map<String,dynamic>>.from(space.rows['memories']??[])..sort((a,b)=>(b['memory_date'] as String).compareTo(a['memory_date'] as String));
      return RefreshIndicator(onRefresh:space.refresh,child:ListView(padding:const EdgeInsets.all(20),children:[
        FilledButton.icon(onPressed:()=>_add(context,space),icon:const Icon(Icons.add_photo_alternate_outlined),label:const Text('Keep a memory')),
        const SizedBox(height:20),if(memories.isEmpty)const EmptyCard('Our little moments','Photos and stories, held privately for the two of you.',icon:Icons.photo_library_outlined),
        ...memories.map((memory){final hearts=(space.rows['reactions']??[]).where((r)=>r['memory_id']==memory['id']).length;
          return Card(margin:const EdgeInsets.only(bottom:20),clipBehavior:Clip.antiAlias,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            GestureDetector(onDoubleTap:()=>safely(context,()=>space.react(memory['id'] as String,memory:true)),
              child:PrivatePhoto(space,memory['media_path'] as String,localFile:memory['_local_file'] as String?,height:280)),
            Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(memory['caption'] as String,style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:8),
              Row(children:[Expanded(child:Text(displayDate(memory['memory_date'] as String))),
                if(memory['_pending']==true)const Text('Waiting to sync'),
                IconButton(tooltip:'Heart memory',onPressed:()=>safely(context,()=>space.react(memory['id'] as String,memory:true)),icon:const Icon(Icons.favorite_outline)),Text('$hearts')]),
            ])),
          ]));}),
      ]));
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/space.dart';
import '../../core/ui.dart';

class TogetherScreen extends ConsumerWidget {
 const TogetherScreen({super.key,required this.kind});final String kind;
 Future<void> _add(BuildContext context,UsSpace space) async {
  final title=await askText(context,kind=='letters'?'A letter for your person':kind=='expenses'?'What did you pay for?':'Name this collection',max:kind=='letters'?120:100);
  if(title==null||!context.mounted)return;
  if(kind=='collections'){await safely(context,()=>space.add('memory_collections',{'title':title}));return;}
  if(kind=='expenses'){
   final amount=await askText(context,'Amount in ₹',hint:'For example, 450.50',max:12);final value=double.tryParse(amount??'');
   if(!context.mounted)return;if(value==null||value<=0){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter an amount greater than zero.')));return;}
   await safely(context,()=>space.add('expenses',{'title':title,'amount':value,'currency':'INR'}));return;
  }
  final when=await askText(context,'Open when…',hint:'You miss me, you need a smile…',max:200);if(when==null||!context.mounted)return;
  final body=await askText(context,'Your letter',lines:6,max:8000);if(body==null||!context.mounted)return;
  final locked=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Save it for a date?'),content:const Text('You can lock the letter until a future date, or let your partner open it whenever they need it.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Anytime')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Choose a date'))]));
  if(locked==null||!context.mounted)return;
  DateTime? unlock;if(locked){unlock=await pickDateTime(context);if(unlock==null||!context.mounted)return;}
  await safely(context,() async {await space.session.client.rpc('write_letter',params:{'p_couple':space.session.coupleId,'p_title':title,'p_when':when,'p_body':body,'p_unlock':unlock?.toUtc().toIso8601String()});await space.refresh();});
 }
 @override Widget build(BuildContext context,WidgetRef ref){final space=ref.watch(spaceProvider);final table=kind=='collections'?'memory_collections':kind;
 return Scaffold(appBar:AppBar(title:Text(kind=='letters'?'Open when… letters':kind=='expenses'?'Shared expenses':'Memory collections')),
 floatingActionButton:FloatingActionButton.extended(onPressed:()=>_add(context,space),icon:const Icon(Icons.add),label:Text(kind=='letters'?'Write a letter':kind=='expenses'?'Add expense':'New collection')),
 body:ListenableBuilder(listenable:space,builder:(context,_){final rows=List<Map<String,dynamic>>.from(space.rows[table]??[])..sort((a,b)=>'${b['created_at']}'.compareTo('${a['created_at']}'));
 final expenses=rows.where((r)=>r['currency']=='INR');final paidMe=expenses.where((r)=>r['author_id']==space.session.userId).fold<double>(0,(v,r)=>v+(r['amount'] as num).toDouble());final paidPartner=expenses.where((r)=>r['author_id']!=space.session.userId).fold<double>(0,(v,r)=>v+(r['amount'] as num).toDouble());final balance=(paidMe-paidPartner)/2;
 return RefreshIndicator(onRefresh:space.refresh,child:ListView(padding:const EdgeInsets.fromLTRB(20,12,20,110),children:[
 Text(kind=='letters'?'Little words, for the right moment.':kind=='expenses'?'A little less “who paid?”':'Make room for every chapter.',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:18),
 if(kind=='expenses')Card(color:Theme.of(context).colorScheme.primaryContainer,child:Padding(padding:const EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Split equally · ₹${((paidMe+paidPartner)/2).toStringAsFixed(2)} each'),const SizedBox(height:8),Text(balance.abs()<.01?'You’re even':balance>0?'Your person owes you ₹${balance.toStringAsFixed(2)}':'You owe ₹${(-balance).toStringAsFixed(2)}',style:Theme.of(context).textTheme.titleLarge),const Text('Records only. No bank connection or payments.')]))),
 if(rows.isEmpty)const EmptyCard('Something lovely starts here','Tap the button below to add your first one.'),
 for(final r in rows)Padding(padding:const EdgeInsets.only(top:12),child:Card(child:ListTile(
 leading:Icon(kind=='letters'?Icons.mail_outline:kind=='expenses'?Icons.receipt_long_outlined:Icons.collections_bookmark_outlined),
 title:Text(r['title'] as String),subtitle:Text(kind=='letters'?'Open when ${r['open_when']}\n${r['author_id']==space.session.userId?'Written by you':'From your person'}${r['unlock_at']!=null?' · Opens ${displayDate(r['unlock_at'] as String)}':''}':kind=='expenses'?'₹${(r['amount'] as num).toStringAsFixed(2)} · ${r['author_id']==space.session.userId?'Paid by you':'Paid by your person'}':'${(space.rows['memories']??[]).where((m)=>m['collection_id']==r['id']).length} memories · add photos from Memories'),
 onTap:kind!='letters'?null:()=>safely(context,() async {
  final result=await space.session.client.from('letter_contents').select('body').eq('id',r['id'] as String).maybeSingle();if(!context.mounted)return;
  await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text(r['title'] as String),content:SingleChildScrollView(child:SelectableText(result?['body'] as String? ?? 'This letter is sealed until ${displayDate(r['unlock_at'] as String?)}. A little patience, a little love.')),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Close'))]));
 }),
 trailing:r['author_id']==space.session.userId&&kind!='collections'?IconButton(tooltip:'Delete',icon:const Icon(Icons.delete_outline),onPressed:() async {final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Delete this item?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Keep')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))]));if(yes==true&&context.mounted)await safely(context,()=>space.remove(table,r['id'] as String));}):null,
 ))),
 ]));}));}
}

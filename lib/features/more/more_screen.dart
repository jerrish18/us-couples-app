import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../core/settings.dart';
import '../../core/space.dart';
import '../../core/ui.dart';
import '../../core/media.dart';
import '../../core/notifications.dart';
import 'backup.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});
  @override ConsumerState<MoreScreen> createState()=>_MoreScreenState();
}
class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _exporting=false;
  Future<void> _text(UsSpace space,String field,String title,{int max=60}) async {
    final value=await askText(context,title,initial:space.me?[field] as String? ?? '',max:max);
    if(value!=null&&mounted)await safely(context,()=>space.profile({field:value}));
  }
  Future<void> _timezone(UsSpace space) async {
    final controller=TextEditingController();String query='';
    final result=await showModalBottomSheet<String>(context:context,isScrollControlled:true,builder:(c)=>StatefulBuilder(builder:(c,set)=>
      SafeArea(child:SizedBox(height:MediaQuery.sizeOf(c).height*.75,child:Column(children:[
        Padding(padding:const EdgeInsets.all(20),child:TextField(controller:controller,decoration:const InputDecoration(labelText:'Find a time zone',hintText:'Kolkata, London, New York…'),onChanged:(v)=>set(()=>query=v.toLowerCase().replaceAll(' ','_')))),
        Expanded(child:ListView(children:tz.timeZoneDatabase.locations.keys.where((z)=>z.toLowerCase().contains(query)).map((z)=>ListTile(title:Text(z.replaceAll('_',' ')),onTap:()=>Navigator.pop(c,z))).toList())),
      ])))));
    Future<void>.delayed(const Duration(milliseconds:350),controller.dispose);
    if(result!=null&&mounted)await safely(context,() async {await space.profile({'timezone':result});await space.setPreferences({'timezone':result});});
  }
  Future<void> _quiet(UsSpace space) async {
    final start=await showTimePicker(context:context,initialTime:const TimeOfDay(hour:22,minute:0));if(start==null||!mounted)return;
    final end=await showTimePicker(context:context,initialTime:const TimeOfDay(hour:8,minute:0));if(end==null||!mounted)return;
    String value(TimeOfDay t)=>'${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}:00';
    await safely(context,()=>space.setPreferences({'quiet_start':value(start),'quiet_end':value(end)}));
  }
  Future<void> _delete(UsSpace space) async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Delete our space?'),
      content:const Text('This permanently removes both people’s shared messages, memories, lists, dates, journal entries, and uploaded files. Your sign-in accounts remain. Export a backup first if you want to keep your story.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Keep our space')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete all space data'))]));
    if(yes!=true||!mounted)return;
    await safely(context,() async {final response=await space.session.client.functions.invoke('delete-space',body:{'couple_id':space.session.coupleId});
      if(response.status!=200 && response.status!=202)throw StateError('Deletion not completed');
      await space.eraseLocal();await space.session.refresh();
      try{await UsNotifications.unregister(space.session);}catch(_){/* Retry cleanup on the next launch. */}
      if(response.status==202&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Deletion started. Remaining files will be removed automatically.')));});
  }
  @override Widget build(BuildContext context){final space=ref.watch(spaceProvider),settings=ref.watch(settingsProvider);
    return ListenableBuilder(listenable:space,builder:(context,_)=>ListView(padding:const EdgeInsets.fromLTRB(20,10,20,30),children:[
      Card(child:Column(children:[
        ListTile(leading:const Icon(Icons.checklist),title:const Text('Our lists'),subtitle:const Text('Bucket list, to-do, grocery'),trailing:const Icon(Icons.chevron_right),onTap:()=>context.push('/lists')),
        ListTile(leading:const Icon(Icons.menu_book_outlined),title:const Text('Our journal'),subtitle:const Text('Private pages, shared when you choose'),trailing:const Icon(Icons.chevron_right),onTap:()=>context.push('/journal')),
      ])),const SizedBox(height:16),Text('Make it yours',style:Theme.of(context).textTheme.titleLarge),
      ListTile(leading:const Icon(Icons.person_outline),title:const Text('My name'),subtitle:Text(space.me?['display_name'] as String? ?? 'Your person'),onTap:()=>_text(space,'display_name','Your name')),
      ListTile(leading:const Icon(Icons.favorite_outline),title:const Text('Partner nickname'),subtitle:Text(space.me?['nickname'] as String? ?? 'What I call my person'),onTap:()=>_text(space,'nickname','What do you call your person?')),
      ListTile(leading:const Icon(Icons.photo_camera_outlined),title:const Text('My profile photo'),onTap:()=>safely(context,() async {
        final file=await pickPhoto();if(file==null)return;
        final path='${space.session.coupleId}/${space.session.userId}/avatar-${DateTime.now().millisecondsSinceEpoch}.jpg';
        await space.session.client.storage.from('couple-media').uploadBinary(path,await File(file).readAsBytes(),fileOptions:const FileOptions(contentType:'image/jpeg'));
        await space.profile({'avatar_path':path});
      })),
      ListTile(leading:const Icon(Icons.edit_outlined),title:const Text('Space name'),subtitle:Text(space.session.couple?['name'] as String? ?? 'Us'),onTap:() async {
        final name=await askText(context,'Our space name',initial:space.session.couple?['name'] as String? ?? 'Us',max:60);
        if(name!=null&&mounted)await safely(context,() async {await space.session.client.from('couples').update({'name':name}).eq('id',space.session.coupleId!);await space.session.refresh();});}),
      ListTile(leading:const Icon(Icons.calendar_today_outlined),title:const Text('Together since'),subtitle:Text(displayDate(space.session.couple?['together_since'] as String?)),onTap:() async {
        final date=await pickDateTime(context,time:false);if(date!=null&&mounted)await safely(context,() async {
          await space.session.client.from('couples').update({'together_since':date.toIso8601String().substring(0,10)}).eq('id',space.session.coupleId!);await space.session.refresh();});}),
      ListTile(leading:const Icon(Icons.location_city),title:const Text('My city'),subtitle:Text(space.me?['city'] as String? ?? 'Chennai'),onTap:()=>_text(space,'city','Your city')),
      ListTile(leading:const Icon(Icons.public),title:const Text('My time zone'),subtitle:Text(space.me?['timezone'] as String? ?? 'Asia/Kolkata'),onTap:()=>_timezone(space)),
      const Divider(),Text('Comfort and privacy',style:Theme.of(context).textTheme.titleLarge),
      ListenableBuilder(listenable:settings,builder:(context,_)=>Column(children:[
        DropdownButtonFormField<ThemeMode>(initialValue:settings.theme,decoration:const InputDecoration(labelText:'Theme'),items:const [
          DropdownMenuItem(value:ThemeMode.system,child:Text('Follow my phone')),DropdownMenuItem(value:ThemeMode.light,child:Text('Light')),DropdownMenuItem(value:ThemeMode.dark,child:Text('Dark'))],
          onChanged:(v){if(v!=null)settings.setTheme(v);}),
        SwitchListTile(title:const Text('App lock'),subtitle:const Text('Device security or your private app PIN'),value:settings.locked,onChanged:(v) async {
          if(v){final pin=await askText(context,'Choose a 4–8 digit app PIN',max:8,obscure:true);
            if(pin==null||!RegExp(r'^\d{4,8}$').hasMatch(pin))return;await settings.setLock(true,newPin:pin);}
          else await settings.setLock(false);
        }),
      ])),
      ...{'messages':'Message notifications','miss_me':'Miss Me notifications','dates':'Date invitations and replies','reminders':'Dates and anniversary reminders','nudges':'Gentle daily nudge (optional)'}.entries.map((e)=>
        SwitchListTile(title:Text(e.value),value:space.preferences[e.key] as bool? ?? e.key!='nudges',onChanged:(v)=>safely(context,()=>space.setPreferences({e.key:v})))),
      ListTile(leading:const Icon(Icons.bedtime_outlined),title:const Text('Quiet hours'),subtitle:Text(space.preferences['quiet_start']==null?'Off':'${space.preferences['quiet_start']} – ${space.preferences['quiet_end']}'),
        onTap:()=>_quiet(space),trailing:space.preferences['quiet_start']==null?null:IconButton(tooltip:'Turn quiet hours off',onPressed:()=>safely(context,()=>space.setPreferences({'quiet_start':null,'quiet_end':null})),icon:const Icon(Icons.close))),
      const Divider(),ListTile(leading:const Icon(Icons.download_outlined),title:Text(_exporting?'Saving your story…':'Export chat and memories'),
        subtitle:const Text('Includes photos and voice notes. Save the backup privately.'),onTap:_exporting?null:() async {
          setState(()=>_exporting=true);await safely(context,()=>exportBackup(space));if(mounted)setState(()=>_exporting=false);}),
      ListTile(leading:const Icon(Icons.logout),title:const Text('Sign out'),onTap:()=>safely(context,() async {
        await UsNotifications.unregister(space.session);await space.session.client.auth.signOut();})),
      ListTile(leading:const Icon(Icons.link_off,color:Colors.red),title:const Text('Unlink and delete our space'),onTap:()=>_delete(space)),
      const SizedBox(height:20),const Text('Just the two of you. No ads, analytics, games, or public profiles.',textAlign:TextAlign.center),
    ]));
  }
}

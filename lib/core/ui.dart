import 'package:flutter/material.dart';
import 'dart:io';
import 'space.dart';

Future<void> safely(BuildContext context,Future<void> Function() action) async {
  try{await action();}catch(_){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content:Text('Could not save. Check your connection and try again.')));}
}
Future<String?> askText(BuildContext context,String title,{String hint='',String initial='',int max=500,int lines=1,bool obscure=false}) async {
  final controller=TextEditingController(text:initial);
  final result=await showDialog<String>(context:context,builder:(context)=>AlertDialog(
    title:Text(title),content:TextField(controller:controller,autofocus:true,maxLength:max,minLines:obscure?1:lines,maxLines:obscure?1:lines+2,
      obscureText:obscure,autocorrect:!obscure,enableSuggestions:!obscure,keyboardType:obscure?TextInputType.number:TextInputType.text,
      decoration:InputDecoration(hintText:hint)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:(){final text=controller.text.trim();if(text.isNotEmpty)Navigator.pop(context,text);},child:const Text('Save'))]));
  // Dispose after the dialog's exit animation no longer uses the controller.
  Future<void>.delayed(const Duration(milliseconds:350),controller.dispose);
  return result;
}
Future<DateTime?> pickDateTime(BuildContext context,{DateTime? initial,bool time=true}) async {
  final seed=initial??DateTime.now().add(const Duration(hours:2));
  final day=await showDatePicker(context:context,initialDate:seed,firstDate:DateTime(1900),lastDate:DateTime(2200));
  if(day==null||!context.mounted)return null;
  if(!time)return day;
  final clock=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(seed));
  return clock==null?null:DateTime(day.year,day.month,day.day,clock.hour,clock.minute);
}
String displayDate(String? text){final d=DateTime.tryParse(text??'')?.toLocal();if(d==null)return '';
 return '${d.day}/${d.month}/${d.year}';}
String displayTime(String? text){final d=DateTime.tryParse(text??'')?.toLocal();if(d==null)return '';
 return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';}
class EmptyCard extends StatelessWidget {
  const EmptyCard(this.title,this.message,{super.key,this.icon=Icons.favorite_outline});
  final String title,message;final IconData icon;
  @override
  Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(28),child:Column(children:[
    Icon(icon,size:42,color:Theme.of(context).colorScheme.primary),const SizedBox(height:16),
    Text(title,style:Theme.of(context).textTheme.titleLarge,textAlign:TextAlign.center),const SizedBox(height:8),
    Text(message,textAlign:TextAlign.center)])));
}
class PrivatePhoto extends StatefulWidget {
  const PrivatePhoto(this.space,this.path,{super.key,this.localFile,this.height=220});
  final UsSpace space;final String path;final String? localFile;final double height;
  @override
  State<PrivatePhoto> createState()=>_PrivatePhotoState();
}
class _PrivatePhotoState extends State<PrivatePhoto> {
  late Future<String> _url;
  @override void initState(){super.initState();_url=widget.space.mediaFile(widget.path);}
  @override void didUpdateWidget(covariant PrivatePhoto old){super.didUpdateWidget(old);if(old.path!=widget.path)_url=widget.space.mediaFile(widget.path);}
  @override Widget build(BuildContext context)=>ClipRRect(borderRadius:BorderRadius.circular(20),child:
    widget.localFile!=null&&File(widget.localFile!).existsSync()?Image.file(File(widget.localFile!),height:widget.height,width:double.infinity,fit:BoxFit.cover):
    FutureBuilder<String>(future:_url,builder:(context,snapshot)=>snapshot.hasData
      ?Image.file(File(snapshot.data!),height:widget.height,width:double.infinity,fit:BoxFit.cover,
        errorBuilder:(_,e,st)=>_placeholder()) : _placeholder()));
  Widget _placeholder()=>SizedBox(height:widget.height,child:const Center(child:Icon(Icons.image_outlined,size:46)));
}

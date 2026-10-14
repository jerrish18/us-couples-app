import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'ui.dart';

final settingsProvider=Provider<DeviceSettings>((ref){final value=DeviceSettings();ref.onDispose(value.dispose);return value;});
class DeviceSettings extends ChangeNotifier {
  DeviceSettings(){load();}
  final storage=const FlutterSecureStorage();
  ThemeMode theme=ThemeMode.system;
  bool ready=false,locked=false;
  String? pin;
  Future<void> load() async {theme=ThemeMode.values[(int.tryParse(await storage.read(key:'us.theme')??'0')??0).clamp(0,ThemeMode.values.length-1)];
    locked=await storage.read(key:'us.lock')=='true';pin=await storage.read(key:'us.pin');ready=true;notifyListeners();}
  Future<void> setTheme(ThemeMode value) async {theme=value;await storage.write(key:'us.theme',value:value.index.toString());notifyListeners();}
  Future<void> setLock(bool value,{String? newPin}) async {locked=value;if(newPin!=null){pin=newPin;await storage.write(key:'us.pin',value:newPin);}
    await storage.write(key:'us.lock',value:value.toString());notifyListeners();}
}
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key,required this.child});final Widget child;
  @override ConsumerState<AppLockGate> createState()=>_AppLockGateState();
}
class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _unlocked=false,_busy=false;DateTime? _paused;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.paused)_paused=DateTime.now();
    if(state==AppLifecycleState.resumed && _paused!=null && DateTime.now().difference(_paused!).inSeconds>15 && mounted)
      setState(()=>_unlocked=false);
  }
  Future<void> _unlock(bool pin) async {
    if(_busy)return;setState(()=>_busy=true);
    final settings=ref.read(settingsProvider);bool result=false;
    try{
      if(pin){final entered=await askText(context,'Your app PIN',hint:'Enter your PIN',max:8,obscure:true);result=entered!=null&&entered==settings.pin;}
      else result=await LocalAuthentication().authenticate(localizedReason:'Open your private Us space',
        options:const AuthenticationOptions(stickyAuth:true));
    }catch(_){/* The PIN remains available if device authentication is unavailable. */}
    if(mounted)setState((){_unlocked=result;_busy=false;});
  }
  @override Widget build(BuildContext context){final settings=ref.watch(settingsProvider);
    return ListenableBuilder(listenable:settings,builder:(context,_) {
      if(!settings.ready)return const Scaffold(body:Center(child:CircularProgressIndicator()));
      if(!settings.locked||_unlocked)return widget.child;
      return Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.lock_outline,size:64),const SizedBox(height:24),Text('Your space is private',style:Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height:24),FilledButton(onPressed:_busy?null:()=>_unlock(false),child:const Text('Unlock with device security')),
        if(settings.pin!=null)TextButton(onPressed:_busy?null:()=>_unlock(true),child:const Text('Use app PIN')),
      ])))));
    });
  }
}

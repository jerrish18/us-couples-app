package com.jerrish18.us

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.*
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.media.AudioFormat
import androidx.core.content.ContextCompat
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.io.File
import kotlin.math.min

/** Engine-scoped audio hooks. Never use the plugin's cross-engine singleton. */
class EchoPhoneNative(private val context:Context, engine:FlutterEngine) : EventChannel.StreamHandler, MethodChannel.MethodCallHandler {
    companion object { @Volatile var current:EchoPhoneNative?=null }
    private val owner=engine
    fun attachedTo(engine:FlutterEngine):Boolean=owner===engine
    private val main=Handler(Looper.getMainLooper())
    private val channel=MethodChannel(engine.dartExecutor.binaryMessenger,"us/echo-phone")
    private var sink:EventChannel.EventSink?=null
    private val rtc=engine.plugins.get(FlutterWebRTCPlugin::class.java) as? FlutterWebRTCPlugin
    private var tts:TextToSpeech?=null
    private var ttsReady=false
    private val voiceWaiters=mutableListOf<Pair<String,MethodChannel.Result>>()
    private var language="English"
    private var voiceStyle="default"
    @Volatile private var ai=false
    @Volatile private var listenAfter=Long.MAX_VALUE
    private var attached=false
    @Volatile private var generation=0
    private var next=0
    private data class Speech(val generation:Int,val result:MethodChannel.Result,val file:File,var rate:Int=16000,var format:Int=AudioFormat.ENCODING_PCM_16BIT,var channels:Int=1,var bytes:Int=0,val cacheText:String?=null,val chunks:MutableList<FloatArray> = mutableListOf())
    private data class PreparedSpeech(val rate:Int,val chunks:List<FloatArray>)
    private val prepared=mutableMapOf<String,PreparedSpeech>()
    private val speaking=mutableMapOf<String,Speech>()
    private val output=EchoPcmQueue()
    private val gate=EchoVoiceGate({
        output.clear()
        main.post { if(ai){cancelSpeech();emit(mapOf("event" to "barge"))} }
    },{bytes->emit(mapOf("event" to "utterance","audio" to bytes))})
    private val capture=object:AudioProcessingAdapter.ExternalAudioFrameProcessing {
        override fun initialize(rate:Int,channels:Int) {}
        override fun reset(rate:Int) {}
        override fun process(bands:Int,frames:Int,buffer:ByteBuffer) {if(ai)output.replaceMicrophone(buffer,frames)}
    }
    private val render=object:AudioProcessingAdapter.ExternalAudioFrameProcessing {
        override fun initialize(rate:Int,channels:Int) {}
        override fun reset(rate:Int) {}
        override fun process(bands:Int,frames:Int,buffer:ByteBuffer) {
            if(!ai)return
            val view=buffer.duplicate().apply{clear()}.order(ByteOrder.nativeOrder()).asFloatBuffer()
            if(frames<1||view.capacity()<1)return
            val rate=frames*100
            val mono=FloatArray(160){i->view.get(min((i*rate/16000),min(frames,view.capacity())-1))}
            // The receptionist hears the caller; no room-speaker playback while AI answers.
            for(i in 0 until view.capacity())view.put(i,0f)
            if(SystemClock.elapsedRealtime()>=listenAfter)gate.process(mono)
        }
    }
    init {current=this;channel.setMethodCallHandler(this);EventChannel(engine.dartExecutor.binaryMessenger,"us/echo-phone-events").setStreamHandler(this)}
    override fun onListen(args:Any?,events:EventChannel.EventSink){sink=events}
    override fun onCancel(args:Any?){sink=null}
    fun emit(value:Map<String,Any>) {main.post{sink?.success(value)}}
    private fun capabilities():Map<String,Any> {
        val memory=ActivityManager.MemoryInfo();(context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        val disk=StatFs(context.filesDir.absolutePath)
        return mapOf("supported" to (Build.VERSION.SDK_INT>=28&&Build.SUPPORTED_ABIS.any{it=="arm64-v8a"||it=="x86_64"}),
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}","ram" to memory.totalMem,"availableRam" to memory.availMem,
            "freeStorage" to disk.availableBytes,"notificationsAllowed" to androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled(),"readyService" to EchoPhoneService.running)
    }
    override fun onMethodCall(call:MethodCall,result:MethodChannel.Result) {
        try {when(call.method){
            "capabilities"->result.success(capabilities())
            "prepareVoice"->{
                val style=call.argument<String>("voice")?:"default"
                val selected=call.argument<String>("language")?:"English"
                if(style!=voiceStyle||selected!=language)prepared.clear()
                voiceStyle=style
                prepareVoice(selected,result)
            }
            "testVoice"->{
                check(ttsReady)
                val id="${generation}-${++next}"
                val file=File.createTempFile("echo-probe-",".wav",context.cacheDir)
                synchronized(speaking){speaking[id]=Speech(generation,result,file)}
                val text=if(language=="English")"I am ECHO, an AI assistant." else "நான் ஏஐ உதவியாளர் எக்கோ."
                if(tts!!.synthesizeToFile(text,Bundle(),file,id)!=TextToSpeech.SUCCESS)finish(id,"Offline voice did not start")
            }
            "previewVoice"->{check(ttsReady);tts!!.speak(if(language=="English")"Hello. I am ECHO, your AI assistant." else "வணக்கம். நான் உங்கள் ஏஐ உதவியாளர் எக்கோ.",TextToSpeech.QUEUE_FLUSH,Bundle(),"preview");result.success(null)}
            "cacheVoice"->{
                check(ttsReady&&!ai)
                val text=call.argument<String>("text")?.take(600)?:error("Missing phrase")
                if(prepared.containsKey(text))result.success(null)else{
                    check(prepared.size<6)
                    val id="${generation}-${++next}"
                    val file=File.createTempFile("echo-prepared-",".wav",context.cacheDir)
                    synchronized(speaking){speaking[id]=Speech(generation,result,file,cacheText=text)}
                    if(tts!!.synthesizeToFile(text,Bundle(),file,id)!=TextToSpeech.SUCCESS)finish(id,"Offline phrase could not start")
                }
            }
            "installVoice"->{context.startActivity(Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));result.success(null)}
            "startReady"->{ContextCompat.startForegroundService(context,Intent(context,EchoPhoneService::class.java));result.success(null)}
            "stopReady"->{context.stopService(Intent(context,EchoPhoneService::class.java));result.success(null)}
            "arm"->{
                check(ttsReady){"Prepare an offline voice first"}
                val controller=rtc?.audioProcessingController?:error("Call audio is not initialized")
                check(attached.not()){ "ECHO audio is already active" }
                output.clear(generation);gate.clear();listenAfter=Long.MAX_VALUE;ai=true
                controller.capturePostProcessing.addProcessor(capture);controller.renderPreProcessing.addProcessor(render);attached=true
                result.success(null)
            }
            "speak"->speak(call,result)
            "erase"->{cancelSpeech();gate.clear();result.success(null)}
            "interrupt"->{cancelSpeech();result.success(null)}
            "takeover"->{cancelSpeech();ai=false;listenAfter=Long.MAX_VALUE;gate.clear();result.success(null)}
            "release"->{release();result.success(null)}
            else->result.notImplemented()
        }}catch(_:Exception){result.error("echo_phone","Could not complete on-phone AI audio. Answer normally or try setup again.",null)}
    }
    private fun prepareVoice(selected:String,result:MethodChannel.Result) {
        language=selected
        if(ttsReady){selectVoice(selected,result);return}
        voiceWaiters.add(selected to result)
        if(tts!=null)return
        tts=TextToSpeech(context){status->main.post{
            ttsReady=status==TextToSpeech.SUCCESS
            if(!ttsReady){tts?.shutdown();tts=null}
            if(ttsReady)tts?.setOnUtteranceProgressListener(listener)
            val waiters=voiceWaiters.toList();voiceWaiters.clear()
            for((lang,r) in waiters){if(ttsReady)selectVoice(lang,r)else r.error("tts_unavailable","Install an offline English/Tamil text-to-speech engine.",null)}
        }}
    }
    private fun selectVoice(selected:String,result:MethodChannel.Result) {
        val code=if(selected=="English")"en" else "ta"
        val voice=tts?.voices?.filter{it.locale.language==code&&!it.isNetworkConnectionRequired&&!(it.features?.contains("notInstalled")?:false)}?.sortedBy{if(it.locale.country=="IN")0 else 1}?.firstOrNull()
        if(voice==null){result.error("missing_voice","Install an offline ${if(code=="ta")"Tamil" else "English"} voice in Android speech settings.",null);return}
        tts?.voice=voice
        tts?.setSpeechRate(when(voiceStyle){"soft"->.90f;"bright"->1.02f;else->.95f})
        tts?.setPitch(when(voiceStyle){"soft"->.92f;"bright"->1.08f;else->1f})
        result.success(mapOf("offline" to true,"voice" to voice.name))
    }
    private fun speak(call:MethodCall,result:MethodChannel.Result) {
        check(ai&&ttsReady){"ECHO is not answering"}
        val text=call.argument<String>("text")?.take(600)?:""
        if(call.argument<Boolean>("disclosure")==true)listenAfter=SystemClock.elapsedRealtime()+2200
        val cached=prepared[text]
        if(cached!=null){for(chunk in cached.chunks)output.add(chunk,cached.rate,generation);result.success(null);return}
        val id="${generation}-${++next}"
        val file=File.createTempFile("echo-voice-",".wav",context.cacheDir)
        synchronized(speaking){speaking[id]=Speech(generation,result,file)}
        if(tts!!.synthesizeToFile(text,Bundle(),file,id)!=TextToSpeech.SUCCESS)finish(id,"Offline speech could not start")
    }
    private val listener=object:UtteranceProgressListener(){
        override fun onStart(id:String){}
        override fun onBeginSynthesis(id:String,rate:Int,format:Int,channels:Int){synchronized(speaking){speaking[id]?.apply{this.rate=rate;this.format=format;this.channels=channels}}}
        override fun onAudioAvailable(id:String,audio:ByteArray){
            val item=synchronized(speaking){speaking[id]}?:return
            if(item.generation!=generation)return
            item.bytes+=audio.size
            if(!ai&&item.cacheText==null)return
            try {
                val pcm=ByteBuffer.wrap(audio).order(ByteOrder.LITTLE_ENDIAN)
                val count=audio.size/(if(item.format==AudioFormat.ENCODING_PCM_FLOAT)4 else if(item.format==AudioFormat.ENCODING_PCM_8BIT)1 else 2)/item.channels
                val mono=FloatArray(count)
                for(i in 0 until count){var sum=0f;repeat(item.channels){sum+=if(item.format==AudioFormat.ENCODING_PCM_FLOAT)pcm.float*32767 else if(item.format==AudioFormat.ENCODING_PCM_8BIT)((pcm.get().toInt() and 255)-128)*256f else pcm.short.toFloat()};mono[i]=sum/item.channels}
                if(item.cacheText!=null){
                    check(item.bytes<=48000*4*20){"Prepared speech exceeded the duration limit"}
                    item.chunks.add(mono)
                }else output.add(mono,item.rate,item.generation)
            }catch(_:Exception){main.post{cancelSpeech();emit(mapOf("event" to "speechError"))}}
        }
        override fun onDone(id:String){finish(id,null)}
        @Deprecated("Android callback") override fun onError(id:String){finish(id,"Offline speech failed")}
        override fun onError(id:String,errorCode:Int){finish(id,"Offline speech failed")}
    }
    private fun finish(id:String,error:String?){
        val item=synchronized(speaking){speaking.remove(id)}?:return
        item.file.delete()
        main.post{
            if(error==null&&item.generation==generation&&item.bytes>0){
                if(item.cacheText!=null)prepared[item.cacheText]=PreparedSpeech(item.rate,item.chunks.toList())
                item.result.success(null)
            }else item.result.error("tts_failed",error?:"Speech interrupted",null)
        }
    }
    private fun cancelSpeech(){
        generation++;output.clear(generation);tts?.stop()
        val old=synchronized(speaking){val values=speaking.values.toList();speaking.clear();values}
        for(item in old){item.file.delete();item.result.error("tts_cancelled","Speech interrupted",null)}
    }
    private fun release(){
        // Remove the microphone replacement only after AI generation is stopped.
        cancelSpeech();ai=false;listenAfter=Long.MAX_VALUE;gate.clear()
        if(attached){rtc?.audioProcessingController?.capturePostProcessing?.removeProcessor(capture);rtc?.audioProcessingController?.renderPreProcessing?.removeProcessor(render);attached=false}
    }
}

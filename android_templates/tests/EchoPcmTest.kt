package com.jerrish18.us
import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class EchoPcmTest {
 @Test fun microphoneIsReplacedWithSilenceWhenSpeechFails() {
   val b=ByteBuffer.allocate(480*4).order(ByteOrder.nativeOrder())
   repeat(480){b.putFloat(10000f)}
   EchoPcmQueue().replaceMicrophone(b,480)
   b.rewind();val floats=b.asFloatBuffer();repeat(480){assertEquals(0f,floats.get(it),0f)}
 }
 @Test fun speechResamplesAndClearsWithoutLeakingMic() {
   val q=EchoPcmQueue();q.add(floatArrayOf(100f,200f,300f),16000)
   assertEquals(100f,q.next(48000),.1f);assertEquals(133.333f,q.next(48000),.1f)
   q.clear();assertEquals(0f,q.next(48000),0f)
 }
 @Test fun utteranceIsBoundedAndInterruptionHappensOnce() {
   var barges=0;val utterances=mutableListOf<ByteArray>()
   val gate=EchoVoiceGate({barges++},{utterances.add(it)})
   repeat(20){gate.process(FloatArray(160){2000f})}
   assertEquals(1,barges)
   repeat(60){gate.process(FloatArray(160))}
   assertEquals(1,utterances.size);assertEquals(12800*2,utterances[0].size)
   assertEquals(2000,ByteBuffer.wrap(utterances[0]).order(ByteOrder.LITTLE_ENDIAN).short.toInt())
 }
 @Test fun interruptedSpeechCannotArriveLate() {
   val q=EchoPcmQueue();q.clear(2);q.add(floatArrayOf(3000f),16000,1)
   assertEquals(0f,q.next(16000),0f)
   q.add(floatArrayOf(1000f),16000,2);assertEquals(1000f,q.next(16000),0f)
 }
 @Test fun silentCallerDoesNotCreateFakeMessages() {
   var messages=0;val gate=EchoVoiceGate({fail("silence interrupted")},{messages++})
   repeat(400){gate.process(FloatArray(160))};assertEquals(0,messages)
 }
 @Test fun speechQueueCannotGrowWithoutBound() {
   val q=EchoPcmQueue(100);q.add(FloatArray(100),16000)
   try{q.add(floatArrayOf(1f),16000);fail("accepted unbounded audio")}catch(_:IllegalArgumentException){}
 }
}

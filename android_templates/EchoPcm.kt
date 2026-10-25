package com.jerrish18.us

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sqrt

/** Pure PCM helpers shared by the native call hooks and JVM regression tests. */
class EchoPcmQueue(private val maxSamples: Int = 960000) {
    private data class Chunk(val data: FloatArray, val rate: Int)
    private val chunks = ArrayDeque<Chunk>()
    private var queued = 0
    private var position = 0.0
    private var epoch = 0
    @Synchronized fun clear(newEpoch:Int?=null) { chunks.clear(); queued=0; position=0.0;if(newEpoch!=null)epoch=newEpoch }
    @Synchronized fun add(data: FloatArray, rate: Int, expectedEpoch:Int?=null) {
        if(expectedEpoch!=null&&expectedEpoch!=epoch)return
        require(rate in 8000..48000)
        require(queued+data.size <= maxSamples) { "Speech queue full" }
        if(data.isNotEmpty()) { chunks.add(Chunk(data,rate));queued+=data.size }
    }
    @Synchronized fun next(rate: Int): Float {
        while(chunks.isNotEmpty()) {
            val c=chunks.first
            val i=position.toInt()
            if(i>=c.data.size) { chunks.removeFirst();queued-=c.data.size;position-=c.data.size;continue }
            val fraction=(position-i).toFloat()
            val value=c.data[i]*(1-fraction)+c.data[min(i+1,c.data.lastIndex)]*fraction
            position+=c.rate.toDouble()/rate
            return value
        }
        position=0.0;return 0f
    }
    @Synchronized fun size(): Int = queued
    /** PCM in WebRTC's AudioBuffer is FloatS16, not normalized float audio. */
    fun replaceMicrophone(buffer:ByteBuffer, frames:Int) {
        val samples=buffer.duplicate().apply{clear()}.order(ByteOrder.nativeOrder()).asFloatBuffer()
        val rate=frames*100
        for(i in 0 until samples.capacity()) samples.put(i,if(i<frames) next(rate) else 0f)
    }
}

class EchoVoiceGate(private val onBarge:()->Unit, private val onSpeech:(ByteArray)->Unit) {
    private val data=ShortArray(16000*12)
    private var length=0
    private var voiced=0
    private var silence=0
    private var interrupted=false
    @Synchronized fun clear(){data.fill(0);length=0;voiced=0;silence=0;interrupted=false}
    @Synchronized fun process(samples:FloatArray) {
        val rms=if(samples.isEmpty())0.0 else sqrt(samples.sumOf{it.toDouble()*it}/samples.size)
        if(rms>450) {voiced+=samples.size;silence=0} else if(voiced>0) silence+=samples.size
        if(voiced>0) {
            for(value in samples) {if(length<data.size)data[length++]=value.toInt().coerceIn(-32768,32767).toShort()}
        }
        if(voiced>=3200&&!interrupted){interrupted=true;onBarge()}
        if(length>=data.size||silence>=9600) {
            if(voiced>=3200){val bytes=ByteBuffer.allocate(length*2).order(ByteOrder.LITTLE_ENDIAN);for(i in 0 until length)bytes.putShort(data[i]);onSpeech(bytes.array())}
            clear()
        }
    }
}

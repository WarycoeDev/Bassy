package com.example.bassy

import android.media.audiofx.EnvironmentalReverb
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val reverbs = HashMap<String, EnvironmentalReverb>()
    private var level = 0.0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bassy/reverb")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "attach" -> {
                            val key = call.argument<String>("key")!!
                            val session = call.argument<Int>("sessionId")!!
                            level = call.argument<Double>("level") ?: level
                            reverbs.remove(key)?.release()
                            val fx = EnvironmentalReverb(0, session)
                            reverbs[key] = fx
                            apply(fx)
                            result.success(null)
                        }
                        "setLevel" -> {
                            level = call.argument<Double>("level") ?: 0.0
                            reverbs.values.forEach { apply(it) }
                            result.success(null)
                        }
                        "release" -> {
                            reverbs.values.forEach { it.release() }
                            reverbs.clear()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("REVERB", e.message, null)
                }
            }
    }

    private fun apply(fx: EnvironmentalReverb) {
        try {
            if (level <= 0.001) {
                fx.enabled = false
                return
            }
            fx.setDecayTime(2200)
            fx.setDecayHFRatio(800.toShort())
            fx.setDensity(1000.toShort())
            fx.setDiffusion(1000.toShort())
            fx.setReflectionsDelay(20)
            fx.setReverbDelay(40)
            fx.setRoomLevel(0.toShort())
            fx.setRoomHFLevel((-1000).toShort())
            fx.setReflectionsLevel((-9000 + level * 8500).toInt().toShort())
            fx.setReverbLevel((-9000 + level * 9500).toInt().toShort())
            fx.enabled = true
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        reverbs.values.forEach { it.release() }
        reverbs.clear()
        super.onDestroy()
    }
}
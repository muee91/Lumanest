package com.muee.lumanest

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import com.amap.api.location.AMapLocation
import com.amap.api.location.AMapLocationClient
import com.amap.api.location.AMapLocationClientOption
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val locationLogTag = "LumaNestAmapLocation"
    private val locationChannel = "com.muee.lumanest/amap_location"
    private val feedbackChannel = "com.lumanest/feedback"
    private var activeClient: AMapLocationClient? = null
    private var timeoutHandler: Handler? = null
    private var soundPool: SoundPool? = null
    private val soundIds = mutableMapOf<String, Int>()
    private val streamIds = mutableMapOf<String, Int>()
    private var soundEnabled = true
    private var hapticEnabled = true

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCurrentPosition" -> requestAmapPosition(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, feedbackChannel)
            .setMethodCallHandler { call, result -> handleFeedback(call, result) }
    }

    private fun handleFeedback(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "preload" -> {
                val sounds = call.argument<List<String>>("sounds").orEmpty()
                preloadSounds(sounds)
                result.success(null)
            }
            "setEnabled" -> {
                soundEnabled = call.argument<Boolean>("soundEnabled") ?: true
                hapticEnabled = call.argument<Boolean>("hapticEnabled") ?: true
                result.success(null)
            }
            "play" -> {
                val sound = call.argument<String>("sound")
                val volume = (call.argument<Number>("volume")?.toFloat() ?: 1f)
                    .coerceIn(0f, 1f)
                if (soundEnabled && sound != null) playSound(sound, volume)
                result.success(null)
            }
            "stop" -> {
                call.argument<String>("sound")?.let(::stopSound)
                result.success(null)
            }
            "haptic" -> {
                if (hapticEnabled) vibrate(call.argument<String>("type"))
                result.success(null)
            }
            "dispose" -> {
                releaseFeedback()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureSoundPool(): SoundPool {
        soundPool?.let { return it }
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        return SoundPool.Builder()
            .setMaxStreams(5)
            .setAudioAttributes(attributes)
            .build()
            .also { soundPool = it }
    }

    private fun preloadSounds(sounds: List<String>) {
        val pool = ensureSoundPool()
        for (sound in sounds.distinct()) {
            if (soundIds.containsKey(sound)) continue
            try {
                assets.openFd("flutter_assets/assets/audio/$sound").use { descriptor ->
                    soundIds[sound] = pool.load(descriptor, 1)
                }
            } catch (error: Exception) {
                Log.w("LumaNestFeedback", "Unable to preload $sound", error)
            }
        }
    }

    private fun playSound(sound: String, volume: Float) {
        if (!soundIds.containsKey(sound)) preloadSounds(listOf(sound))
        val soundId = soundIds[sound] ?: return
        val streamId = ensureSoundPool().play(soundId, volume, volume, 1, 0, 1f)
        if (streamId != 0) streamIds[sound] = streamId
    }

    private fun stopSound(sound: String) {
        streamIds.remove(sound)?.let { soundPool?.stop(it) }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(type: String?) {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (!vibrator.hasVibrator()) return
        val pattern = if (type == "warning") longArrayOf(0, 38, 55, 38) else longArrayOf(0, 24, 45, 32)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            vibrator.vibrate(pattern, -1)
        }
    }

    private fun releaseFeedback() {
        streamIds.clear()
        soundIds.clear()
        soundPool?.release()
        soundPool = null
    }

    private fun requestAmapPosition(call: MethodCall, result: MethodChannel.Result) {
        finishActiveRequest()
        try {
            val apiKey = call.argument<String>("apiKey")?.trim()
            if (apiKey.isNullOrEmpty()) {
                result.success(null)
                return
            }
            Log.i(locationLogTag, "AMap location requested")
            AMapLocationClient.updatePrivacyShow(applicationContext, true, true)
            AMapLocationClient.updatePrivacyAgree(applicationContext, true)
            AMapLocationClient.setApiKey(apiKey)
            val client = AMapLocationClient(applicationContext)
            val option = AMapLocationClientOption().apply {
                locationMode = AMapLocationClientOption.AMapLocationMode.Hight_Accuracy
                isOnceLocation = true
                isOnceLocationLatest = true
                isNeedAddress = false
                isLocationCacheEnable = true
                isGpsFirst = false
                setWifiActiveScan(true)
                setWifiScan(true)
                setSensorEnable(true)
                httpTimeOut = 5_000
            }
            activeClient = client
            client.setLocationOption(option)
            client.setLocationListener { location ->
                finishActiveRequest()
                if (location == null || location.errorCode != AMapLocation.LOCATION_SUCCESS) {
                    Log.w(
                        locationLogTag,
                        "AMap location failed: code=${location?.errorCode}, info=${location?.errorInfo}",
                    )
                    result.success(null)
                    return@setLocationListener
                }
                Log.i(
                    locationLogTag,
                    "AMap location succeeded: type=${location.locationType}, accuracy=${location.accuracy}",
                )
                result.success(
                    mapOf(
                        "latitude" to location.latitude,
                        "longitude" to location.longitude,
                        "accuracy" to location.accuracy.toDouble(),
                        "altitude" to location.altitude,
                        "timestamp" to location.time,
                    ),
                )
            }
            timeoutHandler = Handler(Looper.getMainLooper()).also { handler ->
                handler.postDelayed({
                    if (activeClient === client) {
                        finishActiveRequest()
                        result.success(null)
                    }
                }, 6_000)
            }
            client.startLocation()
        } catch (error: Exception) {
            Log.w(locationLogTag, "AMap location request threw", error)
            finishActiveRequest()
            result.success(null)
        }
    }

    private fun finishActiveRequest() {
        timeoutHandler?.removeCallbacksAndMessages(null)
        timeoutHandler = null
        activeClient?.apply {
            stopLocation()
            onDestroy()
        }
        activeClient = null
    }

    override fun onDestroy() {
        finishActiveRequest()
        releaseFeedback()
        super.onDestroy()
    }
}

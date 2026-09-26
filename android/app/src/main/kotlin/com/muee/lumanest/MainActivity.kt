package com.muee.lumanest

import android.os.Handler
import android.os.Looper
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
    private var activeClient: AMapLocationClient? = null
    private var timeoutHandler: Handler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCurrentPosition" -> requestAmapPosition(call, result)
                    else -> result.notImplemented()
                }
            }
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
                // SDK 11 no longer exposes the deprecated active-scan toggle.
                // Keep the bounded, one-shot Wi-Fi lookup below; do not enable
                // the newer process-wide always-scan setting for this request.
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
        super.onDestroy()
    }
}

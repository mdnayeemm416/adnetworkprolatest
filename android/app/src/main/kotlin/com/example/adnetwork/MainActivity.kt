package com.example.adnetwork

import android.content.Context
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val VPN_CHANNEL = "com.example.adnetwork/vpn_dns"
    private val PIP_CHANNEL = "com.example.adnetwork/pip"
    private var pipChannel: MethodChannel? = null

    override fun getRenderMode(): RenderMode {
        return RenderMode.texture
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        Log.d("MainActivity", "onPictureInPictureModeChanged: $isInPictureInPictureMode")
        try {
            pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to notify Dart onPipModeChanged: $e")
        }
        if (isInPictureInPictureMode) {
            resumePipRendering()
        }
    }

    override fun onPause() {
        super.onPause()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) {
            resumePipRendering()
        }
    }

    private fun resumePipRendering() {
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                flutterEngine?.lifecycleChannel?.appIsResumed()
                resumeWebViews(window.decorView)
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to resume rendering in PiP: $e")
            }
        }, 50)
    }

    private fun resumeWebViews(view: View?) {
        if (view == null) return
        if (view is android.webkit.WebView) {
            try {
                view.onResume()
                view.resumeTimers()
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to resume WebView: $e")
            }
        } else if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                resumeWebViews(view.getChildAt(i))
            }
        }
    }

    override fun onStop() {
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(supported)
                }
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val aspectRatio = Rational(9, 16)
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(aspectRatio)
                                .build()
                            val entered = enterPictureInPictureMode(params)
                            result.success(entered)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "enterPip failed: $e")
                            result.error("PIP_ERROR", e.message, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "exitPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) {
                        val intent = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                        }
                        startActivity(intent)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkVpnDns" -> {
                    val isVpn = isVpnActive(this)
                    val isDns = isPrivateDnsActive(this)
                    val response = mapOf(
                        "isVpnActive" to isVpn,
                        "isPrivateDnsActive" to isDns
                    )
                    result.success(response)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isVpnActive(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activeNetwork = cm.activeNetwork ?: return false
            val capabilities = cm.getNetworkCapabilities(activeNetwork) ?: return false
            return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        } else {
            val networks = cm.allNetworks
            for (network in networks) {
                val capabilities = cm.getNetworkCapabilities(network)
                if (capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                    return true
                }
            }
        }
        return false
    }

    private fun isPrivateDnsActive(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val activeNetwork = cm.activeNetwork ?: return false
            val linkProperties = cm.getLinkProperties(activeNetwork) ?: return false
            return linkProperties.isPrivateDnsActive
        }
        return false
    }
}

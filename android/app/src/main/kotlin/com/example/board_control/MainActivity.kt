package com.example.board_control

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "board_control/network"
    private val prefsName = "board_control_prefs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindToWifi" -> bindToWifi(result)
                    "unbindProcessNetwork" -> unbindProcessNetwork(result)
                    "saveSerial" -> saveSerial(call, result)
                    "getSerial" -> getSerial(result)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 把当前进程的网络流量绑定到 WiFi 网络。
     *
     * 主板 WiFi 是无外网的热点，安卓会把它判定为「无网络」，
     * 默认把流量切到蜂窝数据，导致 App 连不上主板。
     * 这里主动把进程绑定到 WiFi，App 的 socket 就会强制走 WiFi。
     */
    private fun bindToWifi(result: MethodChannel.Result) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        // 1) 先看当前是否已连上 WiFi，有就直接绑定。
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                bind(cm, network, result)
                return
            }
        }

        // 2) 当前没有 WiFi，注册回调，等 WiFi 可用时再绑定。
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                bind(cm, network, result)
                cm.unregisterNetworkCallback(this)
            }

            override fun onUnavailable() {
                result.error("NO_WIFI", "未检测到 WiFi 网络", null)
                cm.unregisterNetworkCallback(this)
            }
        }
        cm.registerNetworkCallback(request, callback)
    }

    private fun bind(
        cm: ConnectivityManager,
        network: Network,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            cm.bindProcessToNetwork(network)
        }
        // Android 6.0 以下不支持进程级绑定，直接走默认网络。
        result.success(true)
    }

    /**
     * 解除进程网络绑定，让 socket 回到系统默认网络（蜂窝 / 其它能上网的 WiFi）。
     *
     * WiFi 直连会把进程持久绑定到无外网的主板热点；之后切换到能上网的网络时，
     * 进程仍绑在已失效的网络上，导致远程 frp 连接失败。远程连接前调用本方法解绑。
     */
    private fun unbindProcessNetwork(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.bindProcessToNetwork(null)
        }
        result.success(true)
    }

    private fun saveSerial(call: MethodCall, result: MethodChannel.Result) {
        val serial = call.argument<String>("serial")
        if (serial.isNullOrBlank()) {
            result.success(false)
            return
        }
        getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString("last_frp_serial", serial)
            .apply()
        result.success(true)
    }

    private fun getSerial(result: MethodChannel.Result) {
        val serial = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString("last_frp_serial", null)
        result.success(serial)
    }
}

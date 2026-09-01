package com.example.board_control

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "board_control/network"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindToWifi" -> bindToWifi(result)
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
}

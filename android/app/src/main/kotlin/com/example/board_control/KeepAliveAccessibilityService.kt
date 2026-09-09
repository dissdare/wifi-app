package com.example.board_control

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/**
 * 空实现的无障碍服务，唯一作用是让系统把本应用进程视为「活跃」，
 * 提升后台存活优先级，避免切到其它 App 后被系统杀掉导致 SSH 连接断开。
 *
 * 不读取任何屏幕内容、不消费任何事件，对系统干预最小。
 */
class KeepAliveAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 什么都不做：只保活，不取词、不拦截。
    }

    override fun onInterrupt() {
        // 什么都不做。
    }
}

package com.zevapp.app

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Enable true Edge-to-Edge window display across all Android versions
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }
}

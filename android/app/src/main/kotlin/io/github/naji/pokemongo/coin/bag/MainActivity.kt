package io.github.naji.pokemongo.coin.bag

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import io.github.naji.pokemongo.coin.bag.ui.StatusScreen
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val bleClient by lazy { BleClient(applicationContext) }
    private var scanJob: Job? = null
    private var permissionDenied by mutableStateOf(false)

    private val requiredPermissions: Array<String>
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        if (grants.values.all { it }) {
            permissionDenied = false
            startScanIfNeeded()
        } else {
            permissionDenied = true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val state by bleClient.state.collectAsState()
            val log by bleClient.log.collectAsState()
            StatusScreen(state = state, permissionDenied = permissionDenied, log = log)
        }
    }

    override fun onResume() {
        super.onResume()
        if (hasAllPermissions()) {
            permissionDenied = false
            startScanIfNeeded()
        } else {
            permissionLauncher.launch(requiredPermissions)
        }
    }

    override fun onPause() {
        super.onPause()
        scanJob?.cancel()
        bleClient.cancel()
    }

    private fun hasAllPermissions(): Boolean =
        requiredPermissions.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

    private fun startScanIfNeeded() {
        if (scanJob?.isActive == true) return
        scanJob = lifecycleScope.launch { bleClient.run() }
    }
}

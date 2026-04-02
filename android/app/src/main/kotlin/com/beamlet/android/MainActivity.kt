package com.beamlet.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.beamlet.android.data.auth.AuthRepository
import com.beamlet.android.data.auth.AuthState
import com.beamlet.android.data.contacts.ContactRepository
import com.beamlet.android.data.files.FileRepository
import com.beamlet.android.data.nearby.NearbyService
import com.beamlet.android.push.BeamletFirebaseService
import com.beamlet.android.ui.navigation.BeamletNavHost
import com.beamlet.android.ui.setup.SetupViewModel
import com.beamlet.android.ui.theme.BeamletTheme
import com.google.firebase.messaging.FirebaseMessaging
import com.google.gson.Gson
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject lateinit var authRepository: AuthRepository
    @Inject lateinit var fileRepository: FileRepository
    @Inject lateinit var contactRepository: ContactRepository
    @Inject lateinit var nearbyService: NearbyService
    @Inject lateinit var gson: Gson

    private val setupViewModel: SetupViewModel by viewModels()

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                registerFcmToken()
            }
        }

    private val requestBlePermissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
            if (results.values.all { it }) {
                nearbyService.start()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Request notification permission on Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        // Handle deep link from intent
        handleDeepLink(intent)

        // Handle notification tap
        val pendingFileIdFromIntent = intent.getStringExtra(BeamletFirebaseService.EXTRA_FILE_ID)

        setContent {
            BeamletTheme {
                val authState by authRepository.authState.collectAsState()
                val isAuthenticated = authState is AuthState.Authenticated

                var pendingFileId by remember { mutableStateOf(pendingFileIdFromIntent) }

                // Register FCM and start BLE when authenticated
                LaunchedEffect(isAuthenticated) {
                    if (isAuthenticated) {
                        registerFcmToken()
                        startNearbyIfPermitted()
                    }
                }

                BeamletNavHost(
                    isAuthenticated = isAuthenticated,
                    fileRepository = fileRepository,
                    authRepository = authRepository,
                    contactRepository = contactRepository,
                    gson = gson,
                    pendingFileId = pendingFileId,
                    onPendingFileHandled = { pendingFileId = null },
                    setupViewModel = setupViewModel,
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    private fun handleDeepLink(intent: Intent) {
        val data = intent.data ?: return

        when (data.scheme) {
            "beamlet" -> {
                // beamlet://invite?url=...&token=...
                val serverUrl = data.getQueryParameter("url")
                val inviteToken = data.getQueryParameter("token")
                if (serverUrl != null && inviteToken != null) {
                    if (authRepository.isAuthenticated) {
                        // Existing user: redeem as existing user
                        redeemInviteAsExistingUser(inviteToken)
                    } else {
                        setupViewModel.handleDeepLink(serverUrl, inviteToken)
                    }
                }
            }

            "https" -> {
                // https://host/invite/{token}
                val pathSegments = data.pathSegments
                if (pathSegments.size >= 2 && pathSegments[0] == "invite") {
                    val inviteToken = pathSegments[1]
                    val serverUrl = "${data.scheme}://${data.host}"
                    if (authRepository.isAuthenticated) {
                        redeemInviteAsExistingUser(inviteToken)
                    } else {
                        setupViewModel.handleDeepLink(serverUrl, inviteToken)
                    }
                }
            }
        }
    }

    private fun redeemInviteAsExistingUser(inviteToken: String) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                contactRepository.redeemInviteAsExistingUser(inviteToken)
                Log.d("MainActivity", "Redeemed invite as existing user")
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to redeem invite", e)
            }
        }
    }

    private fun startNearbyIfPermitted() {
        val blePermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            )
        } else {
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
            )
        }

        val allGranted = blePermissions.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

        if (allGranted) {
            nearbyService.start()
        } else {
            requestBlePermissions.launch(blePermissions)
        }
    }

    override fun onDestroy() {
        nearbyService.stop()
        super.onDestroy()
    }

    private fun registerFcmToken() {
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            authRepository.storeFcmToken(token)
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    contactRepository.registerDevice(token)
                } catch (e: Exception) {
                    Log.e("MainActivity", "Failed to register FCM token", e)
                }
            }
        }
    }
}

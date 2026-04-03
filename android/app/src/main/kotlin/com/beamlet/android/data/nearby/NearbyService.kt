package com.beamlet.android.data.nearby

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.ParcelUuid
import android.util.Log
import com.beamlet.android.data.api.ContactDto
import com.beamlet.android.data.auth.AuthRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NearbyService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val contactRepository: com.beamlet.android.data.contacts.ContactRepository,
) {
    private val _nearbyUsers = MutableStateFlow<List<NearbyUser>>(emptyList())
    val nearbyUsers: StateFlow<List<NearbyUser>> = _nearbyUsers.asStateFlow()

    private val _mode = MutableStateFlow(DiscoverabilityMode.CONTACTS_ONLY)
    val mode: StateFlow<DiscoverabilityMode> = _mode.asStateFlow()

    private var scope: CoroutineScope? = null
    private var pruneJob: Job? = null
    private var scanRestartJob: Job? = null

    private val bluetoothManager: BluetoothManager? by lazy {
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    }

    private var gattServer: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var scanner: BluetoothLeScanner? = null
    private var isAdvertising = false
    private var isScanning = false

    private var contactIDs: Set<String> = emptySet()
    private var contactNames: Map<String, String> = emptyMap()
    private val discoveredPeers = ConcurrentHashMap<String, NearbyUser>()
    private val connectedGatts: MutableSet<BluetoothGatt> = Collections.synchronizedSet(mutableSetOf())
    private val pendingPayloads = ConcurrentHashMap<String, ByteArray>()

    // ---- Public API ----

    fun start() {
        Log.d(TAG, "start() called, scope=${scope != null}")
        if (scope != null) return
        if (!hasBluetoothPermissions()) {
            Log.w(TAG, "Missing Bluetooth permissions, cannot start NearbyService")
            return
        }

        val adapter = bluetoothManager?.adapter ?: run {
            Log.w(TAG, "BluetoothAdapter not available")
            return
        }
        if (!adapter.isEnabled) {
            Log.w(TAG, "Bluetooth is not enabled")
            return
        }

        advertiser = adapter.bluetoothLeAdvertiser
        scanner = adapter.bluetoothLeScanner

        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        startGattServer()
        restartAdvertising()
        startScanning()

        scanRestartJob = scope?.launch {
            while (isActive) {
                delay(SCAN_RESTART_INTERVAL_MS)
                restartScanning()
            }
        }

        pruneJob = scope?.launch {
            while (isActive) {
                delay(PRUNE_INTERVAL_MS)
                pruneStaleUsers()
            }
        }
    }

    fun stop() {
        stopScanning()
        stopAdvertising()
        stopGattServer()
        disconnectAllGatts()
        discoveredPeers.clear()
        pendingPayloads.clear()
        _nearbyUsers.value = emptyList()
        scope?.cancel()
        scope = null
        pruneJob = null
        scanRestartJob = null
    }

    fun updateContacts(contacts: List<ContactDto>) {
        contactIDs = contacts.map { it.id }.toSet()
        contactNames = contacts.associate { it.id to it.name }
    }

    fun forceRescan() {
        if (scope != null) {
            Log.d(TAG, "Force rescan triggered")
            restartScanning()
        }
    }

    fun setMode(mode: DiscoverabilityMode) {
        _mode.value = mode
        restartAdvertising()
    }

    // ---- BLE Peripheral (Advertising / GATT Server) ----

    @SuppressLint("MissingPermission")
    private fun startGattServer() {
        val server = bluetoothManager?.openGattServer(context, gattServerCallback) ?: return

        val characteristic = BluetoothGattCharacteristic(
            CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ,
        )

        val service = BluetoothGattService(
            SERVICE_UUID,
            BluetoothGattService.SERVICE_TYPE_PRIMARY,
        )
        service.addCharacteristic(characteristic)
        server.addService(service)

        gattServer = server
    }

    @SuppressLint("MissingPermission")
    private fun stopGattServer() {
        gattServer?.close()
        gattServer = null
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (characteristic.uuid == CHARACTERISTIC_UUID) {
                val payload = buildAdvertisingPayload()
                gattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    if (offset > 0) payload.copyOfRange(offset, payload.size) else payload,
                )
            } else {
                gattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_FAILURE,
                    0,
                    null,
                )
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun restartAdvertising() {
        stopAdvertising()

        val currentMode = _mode.value
        if (currentMode == DiscoverabilityMode.OFF) return

        val adv = advertiser ?: return

        // Update the GATT characteristic value so read requests return fresh payload
        gattServer?.getService(SERVICE_UUID)
            ?.getCharacteristic(CHARACTERISTIC_UUID)
            ?.value = buildAdvertisingPayload()

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .setIncludeDeviceName(false)
            .build()

        adv.startAdvertising(settings, data, advertiseCallback)
    }

    @SuppressLint("MissingPermission")
    private fun stopAdvertising() {
        if (isAdvertising) {
            advertiser?.stopAdvertising(advertiseCallback)
            isAdvertising = false
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            isAdvertising = true
            Log.d(TAG, "BLE advertising started")
        }

        override fun onStartFailure(errorCode: Int) {
            isAdvertising = false
            Log.e(TAG, "BLE advertising failed with error code: $errorCode")
        }
    }

    private fun buildAdvertisingPayload(): ByteArray {
        val userID = authRepository.userId ?: return byteArrayOf()
        return when (_mode.value) {
            DiscoverabilityMode.OFF -> byteArrayOf()
            DiscoverabilityMode.CONTACTS_ONLY -> {
                byteArrayOf(0x01) + discoveryHash(userID)
            }
            DiscoverabilityMode.EVERYONE -> {
                byteArrayOf(0x02) + userID.toByteArray(Charsets.UTF_8)
            }
        }
    }

    // ---- BLE Central (Scanning) ----

    @SuppressLint("MissingPermission")
    private fun startScanning() {
        val sc = scanner ?: return

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        Log.d(TAG, "Starting BLE scan with UUID filter")
        sc.startScan(listOf(filter), settings, scanCallback)
        isScanning = true
    }

    @SuppressLint("MissingPermission")
    private fun stopScanning() {
        if (isScanning) {
            scanner?.stopScan(scanCallback)
            isScanning = false
        }
    }

    @SuppressLint("MissingPermission")
    private fun restartScanning() {
        stopScanning()
        startScanning()
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            Log.d(TAG, "Scan result: ${result.device.address} rssi=${result.rssi}")
            if (result.rssi < RSSI_THRESHOLD) return

            val device = result.device
            val address = device.address
            // Avoid duplicate connections
            if (connectedGatts.any { it.device.address == address }) return

            val gatt = device.connectGatt(context, false, gattCallback)
            if (gatt != null) {
                connectedGatts.add(gatt)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            isScanning = false
            Log.e(TAG, "BLE scan failed with error code: $errorCode")
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                pendingPayloads.remove(gatt.device.address)
                connectedGatts.remove(gatt)
                gatt.close()
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            Log.d(TAG, "Services discovered for ${gatt.device.address}, status=$status, services=${gatt.services.map { it.uuid }}")
            if (status != BluetoothGatt.GATT_SUCCESS) {
                gatt.disconnect()
                return
            }

            val service = gatt.getService(SERVICE_UUID)
            val characteristic = service?.getCharacteristic(CHARACTERISTIC_UUID)
            Log.d(TAG, "Service=${service != null}, Characteristic=${characteristic != null}")

            if (characteristic != null) {
                gatt.readCharacteristic(characteristic)
            } else {
                gatt.disconnect()
            }
        }

        // Deprecated overload (Android < 13)
        @Suppress("DEPRECATION")
        @SuppressLint("MissingPermission")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            Log.d(TAG, "Characteristic read (deprecated): status=$status, uuid=${characteristic.uuid}, valueLen=${characteristic.value?.size}")
            handleCharacteristicData(gatt, characteristic.value, status)
        }

        // New overload (Android 13+)
        @SuppressLint("MissingPermission")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            Log.d(TAG, "Characteristic read (new): status=$status, uuid=${characteristic.uuid}, valueLen=${value.size}")
            handleCharacteristicData(gatt, value, status)
        }

        @SuppressLint("MissingPermission")
        private fun handleCharacteristicData(gatt: BluetoothGatt, data: ByteArray?, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS || data == null || data.isEmpty()) {
                Log.w(TAG, "Characteristic read failed or empty, disconnecting")
                gatt.disconnect()
                return
            }

            Log.d(TAG, "Got payload: ${data.size} bytes, mode=0x${String.format("%02x", data[0])}")
            pendingPayloads[gatt.device.address] = data
            gatt.readRemoteRssi()
        }

        @SuppressLint("MissingPermission")
        override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
            val addr = gatt.device.address
            Log.d(TAG, "Remote RSSI for $addr: rssi=$rssi, status=$status, pendingKeys=${pendingPayloads.keys}")
            val data = pendingPayloads.remove(addr)
            Log.d(TAG, "Pending data for $addr: ${data?.size ?: "null"}")
            if (data != null && status == BluetoothGatt.GATT_SUCCESS) {
                handleDiscoveredPayload(data, rssi)
            }
            gatt.disconnect()
        }
    }

    // ---- Payload Parsing / Discovery ----

    private fun handleDiscoveredPayload(data: ByteArray, rssi: Int) {
        if (rssi < RSSI_THRESHOLD) return
        if (data.isEmpty()) return

        val modeByte = data[0]
        val userID = authRepository.userId // may be null, that's ok
        Log.d(TAG, "handleDiscoveredPayload: mode=${modeByte}, rssi=$rssi, dataLen=${data.size}, myUserId=$userID")

        when (modeByte) {
            MODE_CONTACTS_ONLY -> {
                val hash = data.copyOfRange(1, data.size)
                for (contactID in contactIDs) {
                    if (discoveryHash(contactID).contentEquals(hash)) {
                        val name = contactNames[contactID] ?: "Unknown"
                        addNearbyUser(NearbyUser(id = contactID, name = name, isContact = true))
                        return
                    }
                }
            }
            MODE_EVERYONE -> {
                val peerID = String(data, 1, data.size - 1, Charsets.UTF_8)
                Log.d(TAG, "MODE_EVERYONE: peerID='$peerID', myUserID='$userID', equal=${peerID == userID}")
                if (peerID.isEmpty() || (userID != null && peerID == userID)) return

                val contactName = contactNames[peerID]
                if (contactName != null) {
                    addNearbyUser(NearbyUser(id = peerID, name = contactName, isContact = true))
                } else {
                    // Check if we already have this peer with a resolved name
                    val existing = discoveredPeers[peerID]
                    if (existing != null && existing.name != peerID) {
                        addNearbyUser(NearbyUser(id = peerID, name = existing.name, isContact = false))
                    } else {
                        // Add with placeholder name, then resolve via API
                        addNearbyUser(NearbyUser(id = peerID, name = "Nearby", isContact = false))
                        scope?.launch {
                            try {
                                val profile = contactRepository.getProfile(peerID)
                                val name = profile.name ?: peerID
                                addNearbyUser(NearbyUser(id = peerID, name = name, isContact = false))
                            } catch (_: Exception) { }
                        }
                    }
                }
            }
        }
    }

    private fun addNearbyUser(user: NearbyUser) {
        Log.d(TAG, "Adding nearby user: ${user.name} (${user.id}), isContact=${user.isContact}")
        val updated = user.copy(lastSeen = Instant.now())
        discoveredPeers[user.id] = updated
        publishUsers()
    }

    private fun pruneStaleUsers() {
        val cutoff = Instant.now().minusSeconds(STALENESS_SECONDS)
        val removed = discoveredPeers.entries.removeAll { it.value.lastSeen.isBefore(cutoff) }
        if (removed) {
            publishUsers()
        }
    }

    private fun publishUsers() {
        _nearbyUsers.value = discoveredPeers.values
            .sortedWith(compareByDescending<NearbyUser> { it.isContact }.thenBy { it.name })
            .toList()
    }

    @SuppressLint("MissingPermission")
    private fun disconnectAllGatts() {
        for (gatt in connectedGatts) {
            gatt.disconnect()
            gatt.close()
        }
        connectedGatts.clear()
    }

    // ---- Discovery Hash ----

    private fun discoveryHash(id: String): ByteArray {
        val dateString = todayString()
        val input = "$id$dateString".toByteArray(Charsets.UTF_8)
        val digest = MessageDigest.getInstance("SHA-256").digest(input)
        return digest.copyOfRange(0, 8)
    }

    // ---- Permissions ----

    private fun hasBluetoothPermissions(): Boolean {
        val permissions = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            listOf(
                android.Manifest.permission.BLUETOOTH_ADVERTISE,
                android.Manifest.permission.BLUETOOTH_CONNECT,
                android.Manifest.permission.BLUETOOTH_SCAN,
                android.Manifest.permission.ACCESS_FINE_LOCATION, // Samsung requires this
            )
        } else {
            listOf(
                android.Manifest.permission.BLUETOOTH,
                android.Manifest.permission.BLUETOOTH_ADMIN,
                android.Manifest.permission.ACCESS_FINE_LOCATION,
            )
        }
        return permissions.all {
            context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    companion object {
        private const val TAG = "NearbyService"

        val SERVICE_UUID: UUID = UUID.fromString("B3AE0001-1E70-4000-8000-00805F9B34FB")
        val CHARACTERISTIC_UUID: UUID = UUID.fromString("B3AE0002-1E70-4000-8000-00805F9B34FB")

        private const val RSSI_THRESHOLD = -70
        private const val STALENESS_SECONDS = 15L
        private const val PRUNE_INTERVAL_MS = 5_000L
        private const val SCAN_RESTART_INTERVAL_MS = 10_000L

        private const val MODE_CONTACTS_ONLY: Byte = 0x01
        private const val MODE_EVERYONE: Byte = 0x02

        private val dayFormatter: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneOffset.UTC)

        private fun todayString(): String =
            dayFormatter.format(Instant.now())
    }
}

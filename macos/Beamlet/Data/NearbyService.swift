import Foundation
import CoreBluetooth
import CryptoKit

@Observable
class NearbyService: NSObject {
    private(set) var nearbyUsers: [NearbyUser] = []

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var discoveryCharacteristic: CBMutableCharacteristic?
    private var connectedPeripherals: Set<CBPeripheral> = []
    private var scanTimer: Timer?

    private let userID: String
    private let api: BeamletAPI
    private var contactIDs: Set<String> = []
    private var contactNames: [String: String] = [:]
    private var discoveredPeers: [String: NearbyUser] = [:]
    private var resolvedProfiles: [String: String] = [:]

    var mode: DiscoverabilityMode {
        didSet {
            mode.save()
            restartAdvertising()
        }
    }

    static let serviceUUID = CBUUID(string: "B3AE0001-1E70-4000-8000-00805F9B34FB")
    static let characteristicUUID = CBUUID(string: "B3AE0002-1E70-4000-8000-00805F9B34FB")

    init(userID: String, api: BeamletAPI) {
        self.userID = userID
        self.api = api
        self.mode = DiscoverabilityMode.load()
        super.init()
    }

    func start() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)

        // Restart scanning every 10 seconds to pick up devices that
        // restarted their app or came into range after initial scan
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.restartScanning()
        }
    }

    func stop() {
        scanTimer?.invalidate()
        scanTimer = nil
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        for peripheral in connectedPeripherals {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripherals.removeAll()
        nearbyUsers = []
        discoveredPeers = [:]
        centralManager = nil
        peripheralManager = nil
    }

    private func restartScanning() {
        guard centralManager?.state == .poweredOn else { return }
        centralManager?.stopScan()
        centralManager?.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func updateContacts(_ contacts: [BeamletUser]) {
        contactIDs = Set(contacts.map(\.id))
        contactNames = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0.name) })
    }

    // MARK: - Discovery Hash

    private func discoveryHash(for id: String) -> Data {
        let dateString = Self.todayString()
        let input = Data("\(id)\(dateString)".utf8)
        let hash = SHA256.hash(data: input)
        return Data(hash.prefix(8))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func todayString() -> String {
        dayFormatter.string(from: Date())
    }

    // MARK: - Advertising

    private func restartAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()

        guard mode != .off, peripheralManager?.state == .poweredOn else { return }

        let characteristic = CBMutableCharacteristic(
            type: Self.characteristicUUID,
            properties: .read,
            value: advertisingPayload(),
            permissions: .readable
        )
        discoveryCharacteristic = characteristic

        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager?.add(service)
    }

    private func advertisingPayload() -> Data {
        switch mode {
        case .off:
            return Data()
        case .contactsOnly:
            return Data([0x01]) + discoveryHash(for: userID)
        case .everyone:
            return Data([0x02]) + Data(userID.utf8)
        }
    }

    // MARK: - Scanning / Resolving

    private func handleDiscoveredPayload(_ data: Data, rssi: NSNumber) {
        guard rssi.intValue > -70 else { return }
        guard let modeByte = data.first else { return }

        if modeByte == 0x01 {
            let hash = data.dropFirst()
            for contactID in contactIDs {
                if discoveryHash(for: contactID) == hash {
                    let name = contactNames[contactID] ?? "Unknown"
                    addNearbyUser(NearbyUser(id: contactID, name: name, isContact: true))
                    return
                }
            }
        } else if modeByte == 0x02 {
            let peerID = String(data: data.dropFirst(), encoding: .utf8) ?? ""
            guard !peerID.isEmpty, peerID != userID else { return }

            if let name = contactNames[peerID] {
                addNearbyUser(NearbyUser(id: peerID, name: name, isContact: true))
            } else if let cached = resolvedProfiles[peerID] {
                addNearbyUser(NearbyUser(id: peerID, name: cached, isContact: false))
            } else {
                Task {
                    if let profile = try? await api.getProfile(userID: peerID) {
                        resolvedProfiles[peerID] = profile.name
                        await MainActor.run {
                            addNearbyUser(NearbyUser(id: peerID, name: profile.name, isContact: false))
                        }
                    }
                }
            }
        }
    }

    private func addNearbyUser(_ user: NearbyUser) {
        var updated = user
        updated.lastSeen = Date()
        discoveredPeers[user.id] = updated
        pruneStaleUsers()
    }

    private func pruneStaleUsers() {
        let cutoff = Date().addingTimeInterval(-15)
        discoveredPeers = discoveredPeers.filter { $0.value.lastSeen > cutoff }
        nearbyUsers = Array(discoveredPeers.values).sorted { a, b in
            if a.isContact != b.isContact { return a.isContact }
            return a.name < b.name
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension NearbyService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        connectedPeripherals.insert(peripheral)
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.remove(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.remove(peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension NearbyService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.readRSSI()
        objc_setAssociatedObject(peripheral, &AssociatedKeys.discoveryData, data, .OBJC_ASSOCIATION_RETAIN)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let data = objc_getAssociatedObject(peripheral, &AssociatedKeys.discoveryData) as? Data {
            handleDiscoveredPayload(data, rssi: RSSI)
        }
        centralManager?.cancelPeripheralConnection(peripheral)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension NearbyService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            restartAdvertising()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if error == nil {
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
                CBAdvertisementDataLocalNameKey: "Beamlet"
            ])
        }
    }
}

// MARK: - Associated Object Key

private enum AssociatedKeys {
    static var discoveryData = "discoveryData"
}

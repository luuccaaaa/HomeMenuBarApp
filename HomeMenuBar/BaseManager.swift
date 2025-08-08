import Foundation
import HomeKit

class BaseManager: NSObject, HMHomeManagerDelegate, HMAccessoryDelegate, mac2iOS, HMHomeDelegate {
    
    /// HomeKit
    var homeManager: HMHomeManager?
    var macOSController: iOS2Mac?
    var homeUniqueIdentifier: UUID? {
        didSet {
            SettingsManager.shared.lastHomeUUID = homeUniqueIdentifier?.uuidString
        }
    }
    
    /// Information to bridge iOS and macOS
    var accessories: [AccessoryInfoProtocol] = []
    var serviceGroups: [ServiceGroupInfoProtocol] = []
    var rooms: [RoomInfoProtocol] = []
    var actionSets: [ActionSetInfoProtocol] = []
    var homes: [HomeInfoProtocol] = []
    
    // MARK: - HomeKit loading state
    var initialHomeListReceived: Bool = false
    var homeFetchRetryCount: Int = 0
    private let maxHomeFetchRetries: Int = 10
    private let homeFetchRetryDelay: TimeInterval = 0.5

    /// init
    override init() {
        super.init()
        if let lastHomeUUIDString = SettingsManager.shared.lastHomeUUID {
            if let uuid = UUID(uuidString: lastHomeUUIDString) {
                self.homeUniqueIdentifier = uuid
            }
        }
        loadPlugin()
        homeManager = HMHomeManager()
        homeManager?.delegate = self
        
        // Start a timer to ensure macOSBridge connection stays active
        startConnectionMonitor()
    }
    
    /// Load the macOS plug‑in bundle and connect it to this manager.
    func loadPlugin() {
        let bundleFile = "macOSBridge.bundle"
        let possibleBundleURLs = [
            Bundle.main.builtInPlugInsURL?.appendingPathComponent(bundleFile),
            Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/\(bundleFile)"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleFile)"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/\(bundleFile)"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(bundleFile)")
        ].compactMap { $0 }

        HMLog.menuDebug("Searching for macOSBridge bundle in \(possibleBundleURLs.count) locations")
        
        for (index, url) in possibleBundleURLs.enumerated() {
            HMLog.menuDebug("Checking location \(index + 1): \(url.path)")
            
            guard FileManager.default.fileExists(atPath: url.path) else {
                HMLog.menuDebug("Bundle file does not exist at: \(url.path)")
                continue
            }
            
            guard let loadedBundle = Bundle(url: url) else {
                HMLog.error(.menu, "Failed to create bundle from URL: \(url.path)")
                continue
            }
            
            HMLog.menuDebug("Bundle loaded successfully: \(loadedBundle.bundleIdentifier ?? "unknown")")
            HMLog.menuDebug("Principal class: \(String(describing: loadedBundle.principalClass))")
            
            guard let pluginClass = loadedBundle.principalClass as? iOS2Mac.Type else {
                HMLog.menuDebug("Principal class is not of type iOS2Mac: \(String(describing: loadedBundle.principalClass))")
                continue
            }
            
            HMLog.menuDebug("Successfully loaded macOSBridge plugin")
            macOSController = pluginClass.init()
            macOSController?.iosListener = self
            return
        }

        HMLog.error(.menu, "Failed to load macOSBridge bundle from any location")
    }

    /// Fetch information from HomeKit and refresh the menu bar on macOS.
    func fetchFromHomeKitAndReloadMenuExtra() {
        let lastUUID = SettingsManager.shared.lastHomeUUID ?? "nil"
        HMLog.menuDebug("Starting HomeKit refresh... selected home UUID (persisted): \(lastUUID)")
        
        // Perform the refresh directly without rebooting to avoid infinite loops
        performHomeKitRefresh()
    }
    
    private func performHomeKitRefresh() {
        guard let hm = self.homeManager else { return }

        // If homes are not loaded yet, avoid showing error and retry a few times
        if hm.homes.isEmpty {
            HMLog.menuDebug("HomeKit homes not yet loaded (initialHomeListReceived=\(initialHomeListReceived)) - deferring error and retrying...")
            if !initialHomeListReceived && homeFetchRetryCount < maxHomeFetchRetries {
                homeFetchRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + homeFetchRetryDelay) { [weak self] in
                    self?.performHomeKitRefresh()
                }
                return
            }
            // If we've received an update callback and still no homes, then show error
            if initialHomeListReceived {
                HMLog.error(.homekit, "No HomeKit homes found after initial load.")
                macOSController?.openNoHomeError()
                macOSController?.reloadMenuExtra()
            }
            return
        }

        // Prefer persisted home if present, otherwise fall back to first available home
        let chosenHome = hm.usedHome(with: self.homeUniqueIdentifier) ?? hm.homes.first!
        let home = chosenHome
        home.delegate = self

        // Log which home is actually being used
        HMLog.menuDebug("Using Home: \(home.name) (\(home.uniqueIdentifier))")

        // Ensure the stored UUID matches the active home.
        self.homeUniqueIdentifier = home.uniqueIdentifier
        SettingsManager.shared.lastHomeUUID = home.uniqueIdentifier.uuidString

        homes = hm.homes.map { HomeInfo(name: $0.name, uniqueIdentifier: $0.uniqueIdentifier) }
        
        // Debug: Log all accessories and their services
        HMLog.menuDebug("Found \(home.accessories.count) accessories:")
        for accessory in home.accessories {
            HMLog.menuDebug("Accessory: \(accessory.name) (\(accessory.uniqueIdentifier))")
            HMLog.menuDebug("  Services (\(accessory.services.count)):")
            for service in accessory.services {
                    HMLog.menuDebug("    - \(service.name) (\(service.serviceType)) - Supported: \(service.isSupported)")
            }
        }
        
        // Build accessories list scoped to the current home, with an extra safety filter to avoid cross-home leakage
        let rawAccessories = home.accessories.map { AccessoryInfo(accessory: $0, home: home) }
        accessories = rawAccessories.filter { acc in
            guard let accHome = acc.home else { return true } // if not set, keep for now
            return accHome.uniqueIdentifier == home.uniqueIdentifier
        }
        
        // Ensure all ServiceInfo objects have the correct type set
        for accessory in accessories {
            for service in accessory.services {
                if let serviceInfo = service as? ServiceInfo {
                    // If the type is unknown, try to infer it from the service name or characteristics
                    if serviceInfo.type == .unknown {
                        let inferredType = SharedUtilities.inferServiceType(from: serviceInfo)
                        if inferredType != .unknown {
                            serviceInfo.setType(inferredType)
                            HMLog.menuDebug("Fixed unknown type for service \(serviceInfo.name): \(inferredType.rawValue)")
                        }
                    }
                }
            }
        }
        
        // Debug: Log filtered accessories with service and characteristic details
        HMLog.menuDebug("After filtering, \(accessories.count) accessories remain:")
        for accessory in accessories {
            HMLog.menuDebug("Filtered Accessory: \(accessory.name) (\(accessory.uniqueIdentifier))")
            HMLog.menuDebug("  Services (\(accessory.services.count)):")
            for service in accessory.services {
                if let serviceInfo = service as? ServiceInfo {
                    HMLog.menuDebug("    - \(serviceInfo.name) (mapped: \(serviceInfo.type.rawValue)) - Supported: \(serviceInfo.isSupported)")
                    // Add debug logging for type information
                    HMLog.menuDebug("      Type details: \(serviceInfo.type.rawValue), isSupported: \(serviceInfo.isSupported)")
                    if !serviceInfo.characteristics.isEmpty {
                        for ch in serviceInfo.characteristics {
                            HMLog.menuDebug("        • Characteristic: \(ch.type.stringValue) (\(ch.uniqueIdentifier))")
                        }
                    } else {
                        HMLog.menuDebug("        • No characteristics after filtering")
                    }
                } else {
                    HMLog.menuDebug("    - \(service.name) (unknown type) - Supported: unknown")
                }
            }
        }
        
        // Extra: count sensors by mapped service type to validate detection paths
        let sensorServices = accessories.flatMap { $0.services }.compactMap { $0 as? ServiceInfo }.filter { s in
            switch s.type {
            case .temperatureSensor, .humiditySensor, .lightSensor, .airQualitySensor: return true
            default: return false
            }
        }
        HMLog.menuDebug("Sensor service summary: \(sensorServices.count) total; types: \(sensorServices.map { $0.type.rawValue })")

        // Assert all accessories belong to the selected home
        let mismatched = accessories.filter { $0.home?.uniqueIdentifier != home.uniqueIdentifier }
        if !mismatched.isEmpty {
            HMLog.error(.homekit, "Found \(mismatched.count) accessories not belonging to the selected home \(home.name). They will be ignored.")
            for a in mismatched {
                HMLog.error(.homekit, "Mismatched accessory: \(a.name) (\(a.uniqueIdentifier)) home=\(String(describing: a.home?.uniqueIdentifier)) expected=\(home.uniqueIdentifier)")
            }
        }

        // Subscribe to characteristic updates for each accessory.
        home.accessories.forEach { accessory in
            accessory.delegate = self
            Task {
                for service in accessory.services {
                    for characteristic in service.characteristics {
                        try? await characteristic.enableNotification(true)
                        try? await characteristic.readValue()
                    }
                }
            }
        }

        serviceGroups = home.serviceGroups.map { ServiceGroupInfo(serviceGroup: $0) }
        rooms = home.rooms.map { RoomInfo(name: $0.name, uniqueIdentifier: $0.uniqueIdentifier) }

        // Only include user-defined action sets (scenes).
        let allActionSets = home.actionSets
        actionSets = allActionSets.filter { $0.actionSetType == "HMActionSetTypeUserDefined" }
                                 .map { ActionSetInfo(actionSet: $0) }

        HMLog.info(.homekit, "HomeKit refresh completed - Found \(actionSets.count) scenes: \(actionSets.map { $0.name })")

        // Ensure default icons are assigned to scenes that don't have one
        SharedUtilities.ensureDefaultSceneIcons(for: actionSets)

        macOSController?.reloadMenuExtra()
    }

    // MARK: - Connection Management

    /// Periodically verifies that the plug‑in connection is still alive.
    private func startConnectionMonitor() {
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkAndMaintainConnection()
            }
        }
    }

    /// Reload the plug‑in if the connection disappears.
    func checkAndMaintainConnection() {
        if let controller = macOSController {
            controller.ensureConnection()
        } else {
            HMLog.info(.app, "macOSBridge connection lost - attempting to reload plugin")
            loadPlugin()
            if macOSController != nil {
                fetchFromHomeKitAndReloadMenuExtra()
            }
        }
    }

    // MARK: - HMAccessoryDelegate Methods
    
    func accessory(_ accessory: HMAccessory, didUpdateNameFor service: HMService) {
        HMLog.info(.homekit, "Service name updated for accessory \(accessory.name): \(service.name)")
        handleHomeKitUpdate(notification: .accessoryUpdated)
    }
    
    func accessory(_ accessory: HMAccessory, didUpdateNameFor characteristic: HMCharacteristic) {
        HMLog.info(.homekit, "Characteristic name updated for accessory \(accessory.name): \(characteristic.localizedDescription)")
        handleHomeKitUpdate(notification: .accessoryUpdated)
    }
    
    func accessoryDidUpdateName(_ accessory: HMAccessory) {
        HMLog.info(.homekit, "Accessory name updated: \(accessory.name)")
        handleHomeKitUpdate(notification: .accessoryUpdated)
    }
    
    func accessory(_ accessory: HMAccessory, didUpdateNameFor serviceGroup: HMServiceGroup) {
        HMLog.info(.homekit, "Service group name updated for accessory \(accessory.name): \(serviceGroup.name)")
        handleHomeKitUpdate(notification: .accessoryUpdated)
    }
    
    // MARK: - HMHomeDelegate Methods
    
    func home(_ home: HMHome, didAdd accessory: HMAccessory) {
        HMLog.info(.homekit, "Accessory added to home: \(accessory.name)")
        handleHomeKitUpdate(notification: .accessoryAdded)
    }
    
    func home(_ home: HMHome, didRemove accessory: HMAccessory) {
        HMLog.info(.homekit, "Accessory removed from home: \(accessory.name)")
        handleHomeKitUpdate(notification: .accessoryRemoved)
    }
    
    func home(_ home: HMHome, didAdd actionSet: HMActionSet) {
        HMLog.info(.homekit, "Action set added to home: \(actionSet.name)")
        handleHomeKitUpdate(notification: .sceneAdded)
    }
    
    func home(_ home: HMHome, didRemove actionSet: HMActionSet) {
        HMLog.info(.homekit, "Action set removed from home: \(actionSet.name)")
        handleHomeKitUpdate(notification: .sceneRemoved)
    }
    
    func home(_ home: HMHome, didUpdateNameFor actionSet: HMActionSet) {
        HMLog.info(.homekit, "Action set name updated: \(actionSet.name)")
        handleHomeKitUpdate(notification: .sceneUpdated)
    }

    // MARK: - Private Methods

    /// Enum to represent different types of HomeKit updates
    private enum HomeKitNotification {
        case accessoryAdded
        case accessoryRemoved
        case accessoryUpdated
        case sceneAdded
        case sceneRemoved
        case sceneUpdated
        case characteristicUpdated(HMCharacteristic)
    }

    private func handleHomeKitUpdate(notification: HomeKitNotification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch notification {
            case .characteristicUpdated(let characteristic):
                // This is now handled by the DeviceStateManager, so we don't need to do anything here.
                // The `accessory(_:service:didUpdateValueFor:)` method will push the update to the state manager.
                HMLog.menuDebug("Characteristic update handled by DeviceStateManager for \(characteristic.uniqueIdentifier)")
                break
            case .accessoryAdded, .accessoryRemoved, .accessoryUpdated, .sceneAdded, .sceneRemoved, .sceneUpdated:
                // For these notifications, a full reload is still appropriate.
                self.fetchFromHomeKitAndReloadMenuExtra()
            }
        }
    }
    
    deinit {
        // Remove HomeKit delegates
        homeManager?.delegate = nil
        // Note: homes and accessories are protocol types, not HomeKit objects
    }
}

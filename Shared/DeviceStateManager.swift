import Foundation

/// Centralized state management for HomeKit devices
/// This class manages the state of all devices and provides a single source of truth
@objc public class DeviceStateManager: NSObject {
    
    // MARK: - Singleton
    public static let shared = DeviceStateManager()
    
    // MARK: - State Storage
    private var deviceStates: [UUID: DeviceState] = [:]
    private let stateQueue = DispatchQueue(label: "com.homemenubar.deviceState", attributes: .concurrent)
    
    // MARK: - Observers
    // Store weak references to observers to avoid retain cycles and leaks
    private class WeakObserver {
        weak var value: StateObserver?
        init(_ value: StateObserver) { self.value = value }
    }
    private var stateObservers: [UUID: [WeakObserver]] = [:]
    
    // MARK: - Initialization
    private override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Update the state of a device
    /// - Parameters:
    ///   - deviceUUID: The UUID of the device
    ///   - characteristicUUID: The UUID of the characteristic being updated
    ///   - value: The new value
    ///   - valueType: The type of value (Bool, Double, etc.)
    public func updateDeviceState(deviceUUID: UUID, characteristicUUID: UUID, value: Any, valueType: CharacteristicType) {
        HMLog.menuDebug("DeviceStateManager: updateDeviceState - Device UUID: \(deviceUUID), Characteristic UUID: \(characteristicUUID), Value: \(value), Type: \(valueType.stringValue)")
        
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Get or create device state (DeviceState is a class; we mutate its properties)
            let deviceState = self.deviceStates[deviceUUID] ?? DeviceState(deviceUUID: deviceUUID)
            
            // Update the specific characteristic
            switch valueType {
            case .on:
                if let boolValue = value as? Bool {
                    deviceState.isOn = boolValue
                } else if let doubleValue = value as? Double {
                    deviceState.isOn = doubleValue > 0.5
                }
            case .brightness:
                if let doubleValue = value as? Double {
                    deviceState.brightness = doubleValue / 100.0 // Convert from percentage to 0-1
                }
            case .hue:
                if let doubleValue = value as? Double {
                    deviceState.hue = doubleValue / 360.0 // Convert from degrees to 0-1
                }
            case .saturation:
                if let doubleValue = value as? Double {
                    deviceState.saturation = doubleValue / 100.0 // Convert from percentage to 0-1
                }
            case .colorTemperature:
                if let doubleValue = value as? Double {
                    deviceState.colorTemperature = doubleValue // Store as-is (typically 50-400 mireds)
                }
            case .currentLightLevel:
                if let doubleValue = value as? Double {
                    deviceState.currentLightLevel = doubleValue // Store as-is (lux value)
                }
            case .currentTemperature:
                if let doubleValue = value as? Double {
                    deviceState.currentTemperature = doubleValue // °C
                }
            case .currentRelativeHumidity:
                if let doubleValue = value as? Double {
                    deviceState.currentRelativeHumidity = doubleValue // %
                }
            case .batteryLevel:
                if let doubleValue = value as? Double { deviceState.batteryLevel = doubleValue }
            case .chargingState:
                if let intValue = value as? Int { deviceState.isCharging = (intValue != 0) }
                else if let boolValue = value as? Bool { deviceState.isCharging = boolValue }
            case .contactState:
                if let boolValue = value as? Bool { deviceState.isContactDetected = boolValue }
            case .outletInUse:
                if let boolValue = value as? Bool { deviceState.isOutletInUse = boolValue }
            case .statusLowBattery:
                if let boolValue = value as? Bool { deviceState.isLowBattery = boolValue }
            case .outputState:
                if let boolValue = value as? Bool { deviceState.programmableSwitchOutputOn = boolValue }
            case .inputEvent:
                if let intValue = value as? Int { deviceState.lastInputEvent = intValue }
                else if let doubleValue = value as? Double { deviceState.lastInputEvent = Int(doubleValue) }
            case .powerModeSelection:
                if let intValue = value as? Int { deviceState.powerModeSelection = intValue }
                else if let doubleValue = value as? Double { deviceState.powerModeSelection = Int(doubleValue) }
            default:
                break
            }
            
            // Store updated state
            self.deviceStates[deviceUUID] = deviceState
            
            // Notify observers on main queue
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self._notifyObservers(for: deviceUUID, state: deviceState)
            }
        }
    }
    
    /// Get the current state of a device
    /// - Parameter deviceUUID: The UUID of the device
    /// - Returns: The current device state, or nil if not found
    public func getDeviceState(for deviceUUID: UUID) -> DeviceState? {
        return stateQueue.sync {
            return deviceStates[deviceUUID]
        }
    }
    
    /// Add an observer for device state changes
    /// - Parameters:
    ///   - deviceUUID: The UUID of the device to observe
    ///   - observer: The observer object
    public func addObserver(for deviceUUID: UUID, observer: StateObserver) {
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if self.stateObservers[deviceUUID] == nil {
                self.stateObservers[deviceUUID] = []
            }
            // Append as weak
            self.stateObservers[deviceUUID]?.append(WeakObserver(observer))
            // Prune any deallocated observers
            self.stateObservers[deviceUUID]?.removeAll { $0.value == nil }
        }
    }
    
    /// Remove an observer
    /// - Parameters:
    ///   - deviceUUID: The UUID of the device
    ///   - observer: The observer object to remove
    public func removeObserver(for deviceUUID: UUID, observer: StateObserver) {
        // Perform removal synchronously on the barrier queue to avoid racing with deallocation
        stateQueue.sync(flags: .barrier) {
            // Remove matching or nil observers
            if var list = self.stateObservers[deviceUUID] {
                list.removeAll { $0.value == nil || $0.value === observer }
                if list.isEmpty {
                    // Clean up empty bucket to avoid lingering keys
                    self.stateObservers.removeValue(forKey: deviceUUID)
                } else {
                    self.stateObservers[deviceUUID] = list
                }
            }
        }
    }
    
    /// Clear all states (useful for app restart)
    public func clearAllStates() {
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.deviceStates.removeAll()
            self.stateObservers.removeAll()
        }
    }
    
    // MARK: - Private Methods
    
    // Internal notify to avoid external visibility conflicts and to keep on main thread
    private func _notifyObservers(for deviceUUID: UUID, state: DeviceState) {
        guard var observers = stateObservers[deviceUUID] else {
            HMLog.menuDebug("DeviceStateManager: No observers found for device UUID: \(deviceUUID)")
            return
        }
        // Prune deallocated before notifying
        observers.removeAll { $0.value == nil }
        stateObservers[deviceUUID] = observers
        HMLog.menuDebug("DeviceStateManager: Notifying \(observers.count) observers for device UUID: \(deviceUUID)")
        for weakObs in observers {
            weakObs.value?.deviceStateDidChange(deviceUUID: deviceUUID, state: state)
        }
    }
}

// MARK: - Device State Model
@objc public class DeviceState: NSObject {
    public let deviceUUID: UUID
    public var isOn: Bool = false
    public var brightness: Double = 1.0
    public var hue: Double = 0.0
    public var saturation: Double = 1.0
    public var colorTemperature: Double = 2700.0 // Default warm white (2700K)
    public var currentLightLevel: Double = 0.0
    public var currentTemperature: Double = 0.0
    public var currentRelativeHumidity: Double = 0.0
    public var isReachable: Bool = true
    // Power and switches
    public var batteryLevel: Double = 0.0
    public var isCharging: Bool = false
    public var isContactDetected: Bool = false
    public var isOutletInUse: Bool = false
    public var isLowBattery: Bool = false
    public var programmableSwitchOutputOn: Bool = false
    public var lastInputEvent: Int = 0
    public var powerModeSelection: Int = 0
    
    public init(deviceUUID: UUID) {
        self.deviceUUID = deviceUUID
        super.init()
    }
    
    public override var description: String {
        return "DeviceState(deviceUUID: \(deviceUUID), isOn: \(isOn), brightness: \(brightness), hue: \(hue), saturation: \(saturation), colorTemperature: \(colorTemperature), currentLightLevel: \(currentLightLevel), currentTemperature: \(currentTemperature), currentRelativeHumidity: \(currentRelativeHumidity), batteryLevel: \(batteryLevel), isCharging: \(isCharging), isContactDetected: \(isContactDetected), isOutletInUse: \(isOutletInUse), isLowBattery: \(isLowBattery), programmableSwitchOutputOn: \(programmableSwitchOutputOn), lastInputEvent: \(lastInputEvent), powerModeSelection: \(powerModeSelection), isReachable: \(isReachable))"
    }
}

// MARK: - State Observer Protocol
@objc public protocol StateObserver: AnyObject {
    func deviceStateDidChange(deviceUUID: UUID, state: DeviceState)
}

import Foundation

// MARK: - Shared Utilities
public class SharedUtilities {
    // MARK: - Service Classification
    /// True if the service should be treated as a lightbulb (and not as a sensor)
    /// Classification rule:
    /// - Bulb traits: presence of hue/saturation/brightness/colorTemperature or on
    /// - Sensor traits: temperature/humidity/light level or any air‑quality related metrics
    /// Service is a bulb if it has any bulb trait and does NOT expose sensor traits.
    public static func isServiceLightbulb(_ service: ServiceInfoProtocol) -> Bool {
        var hasBulbTrait = false
        var hasSensorTrait = false
        for c in service.characteristics {
            switch c.type {
            case .hue, .saturation, .brightness, .colorTemperature, .on:
                hasBulbTrait = true
            case .currentTemperature, .currentRelativeHumidity, .currentLightLevel,
                 .airQuality, .airParticulateDensity, .airParticulateSize,
                 .smokeDetected, .carbonDioxideDetected, .carbonDioxideLevel, .carbonDioxidePeakLevel,
                 .carbonMonoxideDetected, .carbonMonoxideLevel, .carbonMonoxidePeakLevel,
                 .nitrogenDioxideDensity, .ozoneDensity, .pm10Density, .pm2_5Density,
                 .sulphurDioxideDensity, .vocDensity:
                hasSensorTrait = true
            default:
                break
            }
        }
        return hasBulbTrait && !hasSensorTrait
    }
    
    /// True if the service should be treated as a sensor (temperature, humidity, light, air quality)
    public static func isServiceSensor(_ service: ServiceInfoProtocol) -> Bool {
        for c in service.characteristics {
            switch c.type {
            case .currentTemperature, .currentRelativeHumidity, .currentLightLevel,
                 .airQuality, .airParticulateDensity, .airParticulateSize,
                 .smokeDetected, .carbonDioxideDetected, .carbonDioxideLevel, .carbonDioxidePeakLevel,
                 .carbonMonoxideDetected, .carbonMonoxideLevel, .carbonMonoxidePeakLevel,
                 .nitrogenDioxideDensity, .ozoneDensity, .pm10Density, .pm2_5Density,
                 .sulphurDioxideDensity, .vocDensity:
                return true
            default:
                continue
            }
        }
        return false
    }
    
    /// Infer service type from characteristics for macOS compatibility
    public static func inferServiceType(from service: ServiceInfoProtocol) -> ServiceType {
        var hasTemperatureSensor = false
        var hasHumiditySensor = false
        var hasLightSensor = false
        var hasAirQualitySensor = false
        var hasLightbulb = false
        var hasSwitch = false
        
        HMLog.menuDebug("inferServiceType: analyzing \(service.characteristics.count) characteristics for service \(service.name)")
        
        for c in service.characteristics {
            HMLog.menuDebug("inferServiceType: characteristic type: \(c.type.stringValue)")
            switch c.type {
            case .currentTemperature:
                hasTemperatureSensor = true
                HMLog.menuDebug("inferServiceType: found temperature sensor")
            case .currentRelativeHumidity:
                hasHumiditySensor = true
                HMLog.menuDebug("inferServiceType: found humidity sensor")
            case .currentLightLevel:
                hasLightSensor = true
                HMLog.menuDebug("inferServiceType: found light sensor")
            case .airQuality, .airParticulateDensity, .airParticulateSize,
                 .smokeDetected, .carbonDioxideDetected, .carbonDioxideLevel, .carbonDioxidePeakLevel,
                 .carbonMonoxideDetected, .carbonMonoxideLevel, .carbonMonoxidePeakLevel,
                 .nitrogenDioxideDensity, .ozoneDensity, .pm10Density, .pm2_5Density,
                 .sulphurDioxideDensity, .vocDensity:
                hasAirQualitySensor = true
                HMLog.menuDebug("inferServiceType: found air quality sensor")
            case .hue, .saturation, .brightness, .colorTemperature:
                hasLightbulb = true
                HMLog.menuDebug("inferServiceType: found lightbulb")
            case .on:
                // If it only has on/off, it might be a switch or outlet
                if !hasLightbulb {
                    hasSwitch = true
                    HMLog.menuDebug("inferServiceType: found switch")
                }
            default:
                break
            }
        }
        
        // Return the most specific type based on characteristics
        if hasAirQualitySensor {
            HMLog.menuDebug("inferServiceType: returning airQualitySensor")
            return .airQualitySensor
        } else if hasTemperatureSensor {
            HMLog.menuDebug("inferServiceType: returning temperatureSensor")
            return .temperatureSensor
        } else if hasHumiditySensor {
            HMLog.menuDebug("inferServiceType: returning humiditySensor")
            return .humiditySensor
        } else if hasLightSensor {
            HMLog.menuDebug("inferServiceType: returning lightSensor")
            return .lightSensor
        } else if hasLightbulb {
            HMLog.menuDebug("inferServiceType: returning lightbulb")
            return .lightbulb
        } else if hasSwitch {
            HMLog.menuDebug("inferServiceType: returning switch")
            return .switch
        }
        
        HMLog.menuDebug("inferServiceType: returning unknown")
        return .unknown
    }
    
    // MARK: - Characteristic Finding
    public static func findCharacteristic(by type: CharacteristicType, in characteristics: [CharacteristicInfoProtocol]) -> UUID? {
        // For on/off characteristics, we need to be more careful about which one we choose
        if type == .on {
            // Look for the primary on/off characteristic
            // Some devices have multiple on/off characteristics, and we want the writable one
            var onCharacteristics: [CharacteristicInfoProtocol] = []
            
            // First, collect all on/off characteristics
            for characteristic in characteristics {
                if characteristic.type == type {
                    onCharacteristics.append(characteristic)
                }
            }
            
            // If we have multiple on/off characteristics, we need to choose the right one
            if onCharacteristics.count > 1 {
                // For now, return the first one as a fallback
                // In a more sophisticated implementation, we could check properties like:
                // - Whether the characteristic is writable
                // - Whether it's the primary service characteristic
                // - Whether it has specific metadata indicating it's the control characteristic
                HMLog.debug(.app, "SharedUtilities: Found \(onCharacteristics.count) on/off characteristics, using the first one")
                return onCharacteristics.first?.uniqueIdentifier
            } else if onCharacteristics.count == 1 {
                return onCharacteristics.first?.uniqueIdentifier
            }
        } else {
            // For other characteristics, just return the first one of the specified type
            for characteristic in characteristics {
                if characteristic.type == type {
                    return characteristic.uniqueIdentifier
                }
            }
        }
        return nil
    }
    
    // MARK: - Service Support Checking
    public static func isServiceSupported(_ service: ServiceInfoProtocol) -> Bool {
        return service.isSupported
    }
    
    // MARK: - Device Hidden Status
    public static func isDeviceHidden(_ deviceID: String) -> Bool {
        let hiddenDevices = UserDefaults.standard.array(forKey: "HomeMenuBar_HiddenDevices") as? [String] ?? []
        return hiddenDevices.contains(deviceID)
    }
    
    // MARK: - Settings Keys
    public struct SettingsKeys {
        public static let groupByRoom = "HomeMenuBar_GroupByRoom"
        public static let showRoomNames = "HomeMenuBar_ShowRoomNames"
        public static let hiddenDevices = "HomeMenuBar_HiddenDevices"
        public static let showScenesInMenu = "HomeMenuBar_ShowScenesInMenu"
        public static let hiddenScenes = "HomeMenuBar_HiddenScenes"
        public static let sceneIcons = "HomeMenuBar_SceneIcons"
        public static let showAllHomeControl = "HomeMenuBar_ShowAllHomeControl"
        public static let showRoomAllControls = "HomeMenuBar_ShowRoomAllControls"
    }
    
    // MARK: - Settings Getters
    public static func getGroupByRoomSetting() -> Bool {
        return UserDefaults.standard.bool(forKey: SettingsKeys.groupByRoom)
    }
    
    public static func getShowRoomNamesSetting() -> Bool {
        return UserDefaults.standard.bool(forKey: SettingsKeys.showRoomNames)
    }
    
    public static func getShowScenesInMenuSetting() -> Bool {
        return UserDefaults.standard.bool(forKey: SettingsKeys.showScenesInMenu)
    }
    
    public static func getShowAllHomeControlSetting() -> Bool {
        return UserDefaults.standard.bool(forKey: SettingsKeys.showAllHomeControl)
    }
    
    public static func getShowRoomAllControlsSetting() -> Bool {
        return UserDefaults.standard.bool(forKey: SettingsKeys.showRoomAllControls)
    }
    
    // MARK: - First Time Setup
    public static func setupDefaultSettingsIfNeeded() {
        // Check if this is the first time the app is running
        let hasRunBefore = UserDefaults.standard.bool(forKey: "HomeMenuBar_HasRunBefore")
        
        if !hasRunBefore {
            debugLog("First time setup - setting default values if missing")
            
            // Only set defaults if missing, to respect any preconfigured values (e.g., MDM profiles)
            if UserDefaults.standard.object(forKey: SettingsKeys.groupByRoom) == nil {
                UserDefaults.standard.set(true, forKey: SettingsKeys.groupByRoom)
            }
            if UserDefaults.standard.object(forKey: SettingsKeys.showRoomNames) == nil {
                UserDefaults.standard.set(true, forKey: SettingsKeys.showRoomNames)
            }
            if UserDefaults.standard.object(forKey: SettingsKeys.showAllHomeControl) == nil {
                UserDefaults.standard.set(true, forKey: SettingsKeys.showAllHomeControl)
            }
            if UserDefaults.standard.object(forKey: SettingsKeys.showScenesInMenu) == nil {
                UserDefaults.standard.set(true, forKey: SettingsKeys.showScenesInMenu)
            }
            
            // Mark that the app has run before
            UserDefaults.standard.set(true, forKey: "HomeMenuBar_HasRunBefore")
            
            debugLog("Default settings applied (only where missing): groupByRoom, showRoomNames, showAllHomeControl, showScenesInMenu")
        }
    }
    
    // MARK: - Scene Icon Management
    public static func ensureDefaultSceneIcons(for scenes: [ActionSetInfoProtocol]) {
        var sceneIcons = UserDefaults.standard.dictionary(forKey: SettingsKeys.sceneIcons) as? [String: String] ?? [:]
        var hasChanges = false
        
        for scene in scenes {
            let sceneUUID = scene.uniqueIdentifier.uuidString
            if sceneIcons[sceneUUID] == nil {
                sceneIcons[sceneUUID] = "play.circle" // Default icon
                hasChanges = true
                debugLog("Assigned default icon 'play.circle' to scene '\(scene.name)'")
            }
        }
        
        if hasChanges {
            UserDefaults.standard.set(sceneIcons, forKey: SettingsKeys.sceneIcons)
            debugLog("Default scene icons applied and saved for \(hasChanges ? "some" : "no") scenes")
        }
    }
    
    // MARK: - Debug Logging
    public static func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        HMLog.debug(.app, "[\(fileName):\(line) \(function)] \(message)")
        #endif
    }
    
    public static func errorLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        HMLog.error(.app, "[\(fileName):\(line) \(function)] \(message)")
    }
}

import Foundation
import AppKit

extension NSMenuItem {
    @MainActor
    class func HomeMenus(serviceInfo: ServiceInfoProtocol, mac2ios: mac2iOS?) -> [NSMenuItem?] {
        // Prefer canonical type mapping from Shared layer when available
        let serviceType = (serviceInfo as? ServiceInfo)?.type ?? .unknown
        let serviceName = serviceInfo.name.lowercased()
        
        // Name hints used only as weak fallback when type is unknown
        let nameSuggestsLightbulb = (serviceName.contains("lamp") ||
                                     serviceName.contains("bulb") ||
                                     serviceName.contains("led")) &&
                                     !serviceName.contains("sensor")
        let nameSuggestsSensor = serviceName.contains("sensor") ||
                                 serviceName.contains("temperature") ||
                                 serviceName.contains("humidity")
        let nameSuggestsSwitch = serviceName.contains("switch") ||
                                 serviceName.contains("outlet") ||
                                 serviceName.contains("plug")
        
        // Inspect characteristics only to refine unknown/ambiguous types
        var hasColorCharacteristics = false
        var hasPrimarySensorCharacteristics = false   // temp/humidity/light level
        var hasAirQualityCharacteristics = false
        var hasOnOff = false
        
        HMLog.menuDebug("HomeMenus - Checking \(serviceInfo.characteristics.count) characteristics for service: \(serviceInfo.name)")
        
        for characteristic in serviceInfo.characteristics {
            HMLog.menuDebug("HomeMenus - Characteristic type: \(characteristic.type.stringValue)")
            switch characteristic.type {
            case .hue, .saturation, .brightness, .colorTemperature:
                hasColorCharacteristics = true
                HMLog.menuDebug("HomeMenus - Found color characteristic: \(characteristic.type.stringValue)")
            case .on:
                hasOnOff = true
                HMLog.menuDebug("HomeMenus - Found on/off characteristic")
            case .currentTemperature, .currentRelativeHumidity, .currentLightLevel:
                hasPrimarySensorCharacteristics = true
                HMLog.menuDebug("HomeMenus - Found sensor characteristic: \(characteristic.type.stringValue)")
            case .airQuality, .airParticulateDensity, .airParticulateSize,
                 .smokeDetected, .carbonDioxideDetected, .carbonDioxideLevel, .carbonDioxidePeakLevel,
                 .carbonMonoxideDetected, .carbonMonoxideLevel, .carbonMonoxidePeakLevel,
                 .nitrogenDioxideDensity, .ozoneDensity, .pm10Density, .pm2_5Density,
                 .sulphurDioxideDensity, .vocDensity:
                hasAirQualityCharacteristics = true
                HMLog.menuDebug("HomeMenus - Found air quality characteristic: \(characteristic.type.stringValue)")
            default:
                break
            }
        }
        
        // Prefer Shared.ServiceInfo.type for routing first, then fall back
        switch serviceType {
        case .airQualitySensor:
            return [SensorMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
        case .temperatureSensor, .humiditySensor, .lightSensor:
            return [SensorMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
        case .lightbulb:
            return [AdaptiveLightbulbMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
        case .switch:
            HMLog.menuDebug("Factory: routing service \(serviceInfo.name) to SwitchMenuItem (explicit type)")
            return [SwitchMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
        case .outlet:
            HMLog.menuDebug("Factory: routing service \(serviceInfo.name) to OutletMenuItem (explicit type)")
            return [OutletMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
        case .programmableSwitch:
            HMLog.menuDebug("Factory: routing service \(serviceInfo.name) to ProgrammableSwitchMenuItem (explicit type)")
            return [ProgrammableSwitchMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
        case .unknown:
            // Fallback routing for unknown types using characteristics, then weak name hints
            if hasAirQualityCharacteristics {
                return [SensorMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
            }
            if hasPrimarySensorCharacteristics || nameSuggestsSensor {
                return [SensorMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
            }
            if hasColorCharacteristics || (hasOnOff && nameSuggestsLightbulb) {
                return [AdaptiveLightbulbMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
            }
            // Prefer outlet UI if an outlet-in-use characteristic is present
            if serviceInfo.characteristics.contains(where: { $0.type == .outletInUse }) {
                HMLog.menuDebug("Factory: routing service \(serviceInfo.name) to OutletMenuItem (fallback by outletInUse)")
                return [OutletMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
            }
            // Then prefer explicit switch if we saw any on/off characteristic or name suggests
            if hasOnOff || nameSuggestsSwitch {
                HMLog.menuDebug("Factory: routing service \(serviceInfo.name) to SwitchMenuItem (fallback)")
                return [SwitchMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
            }
            return [ToggleMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)]
        }
    }
}

extension NSMenu {
    static func getSubItems(menu: NSMenu) -> [NSMenuItem] {
        var buffer: [NSMenuItem] = []
        
        for item in menu.items {
            buffer.append(item)
            if let submenu = item.submenu {
                buffer.append(contentsOf: getSubItems(menu: submenu))
            }
        }
        
        return buffer
    }
}

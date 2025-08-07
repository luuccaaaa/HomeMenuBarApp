import Foundation

#if !os(macOS)
import HomeKit
#endif

// Add availability checks for HomeKit APIs
@available(iOS 14.0, macOS 11.0, *)
public typealias HMHomeKitAvailable = Void

// MARK: - Communication Protocols
@objc(iOS2Mac)
public protocol iOS2Mac: NSObjectProtocol {
    init()
    func setReachablityOfMenuItemRelated(to uniqueIdentifier: UUID, using isReachable: Bool)
    func updateMenuItemsRelated(to uniqueIdentifier: UUID, value: Any)
    func bringToFront()
    func reloadMenuExtra()
    func centeringWindows()
    func openHomeKitAuthenticationError() -> Bool
    func openNoHomeError()
    func showLaunchView()
    func ensureConnection()
    var iosListener: mac2iOS? { get set }
}

/// Protocol implemented by the iOS target to receive requests from the macOS plug‑in.
@objc(mac2iOS)
public protocol mac2iOS: NSObjectProtocol {
    /// Request a characteristic to be refreshed from HomeKit.
    func readCharacteristic(of uniqueIdentifier: UUID)
    /// Write a new value to a characteristic.
    func setCharacteristic(of uniqueIdentifier: UUID, object: Any)
    /// Reset the HomeKit manager when the connection becomes invalid.
    func rebootHomeManager()
    /// Bring the iOS window to the foreground.
    func bringToFront()
    /// Collections mirrored to the macOS plug‑in.
    var homes: [HomeInfoProtocol] { get set }
    var homeUniqueIdentifier: UUID? { get set }
    var accessories: [AccessoryInfoProtocol] { get set }
    var serviceGroups: [ServiceGroupInfoProtocol] { get set }
    var rooms: [RoomInfoProtocol] { get set }
    var actionSets: [ActionSetInfoProtocol] { get set }
    /// Execute a predefined action set (scene).
    func executeActionSet(uniqueIdentifier: UUID)
    /// Request the host app to close specified windows.
    func close(windows: [Any])
    /// Fetch fresh data from HomeKit and reload the menu.
    func fetchFromHomeKitAndReloadMenuExtra()
}

// MARK: - Type Enums
public enum ServiceType: String, CaseIterable {
    case unknown = "unknown"
    case humiditySensor = "humiditySensor"
    case temperatureSensor = "temperatureSensor"
    case lightSensor = "lightSensor"
    case airQualitySensor = "airQualitySensor"
    case lightbulb = "lightbulb"
    case `switch` = "switch"
    case outlet = "outlet"
    
    public var isSupported: Bool {
        switch self {
        case .lightbulb,
             .humiditySensor,
             .temperatureSensor,
             .lightSensor,
             .airQualitySensor:
            return true
        default:
            return false
        }
    }
}

@objc public enum CharacteristicType: Int, CaseIterable {
    case unknown = 0
    case brightness = 1
    case hue = 2
    case saturation = 3
    case currentTemperature = 4
    case currentRelativeHumidity = 5
    case on = 6
    case targetTemperature = 7
    case targetRelativeHumidity = 8
    case currentLightLevel = 9
    case colorTemperature = 10
    
    // Air quality and related characteristics
    case airQuality = 11
    case airParticulateDensity = 12
    case airParticulateSize = 13
    case smokeDetected = 14
    case carbonDioxideDetected = 15
    case carbonDioxideLevel = 16
    case carbonDioxidePeakLevel = 17
    case carbonMonoxideDetected = 18
    case carbonMonoxideLevel = 19
    case carbonMonoxidePeakLevel = 20
    case nitrogenDioxideDensity = 21
    case ozoneDensity = 22
    case pm10Density = 23
    case pm2_5Density = 24
    case sulphurDioxideDensity = 25
    case vocDensity = 26
    
    public var isSupported: Bool {
        switch self {
        case .brightness, .hue, .saturation, .currentTemperature, .currentRelativeHumidity, .on, .targetTemperature, .targetRelativeHumidity, .currentLightLevel, .colorTemperature,
             .airQuality, .airParticulateDensity, .airParticulateSize, .smokeDetected, .carbonDioxideDetected, .carbonDioxideLevel, .carbonDioxidePeakLevel, .carbonMonoxideDetected, .carbonMonoxideLevel, .carbonMonoxidePeakLevel, .nitrogenDioxideDensity, .ozoneDensity, .pm10Density, .pm2_5Density, .sulphurDioxideDensity, .vocDensity:
            return true
        default:
            return false
        }
    }
    
    public var stringValue: String {
        switch self {
        case .unknown: return "unknown"
        case .brightness: return "brightness"
        case .hue: return "hue"
        case .saturation: return "saturation"
        case .currentTemperature: return "currentTemperature"
        case .currentRelativeHumidity: return "currentRelativeHumidity"
        case .on: return "on"
        case .targetTemperature: return "targetTemperature"
        case .targetRelativeHumidity: return "targetRelativeHumidity"
        case .currentLightLevel: return "currentLightLevel"
        case .colorTemperature: return "colorTemperature"
        case .airQuality: return "airQuality"
        case .airParticulateDensity: return "airParticulateDensity"
        case .airParticulateSize: return "airParticulateSize"
        case .smokeDetected: return "smokeDetected"
        case .carbonDioxideDetected: return "carbonDioxideDetected"
        case .carbonDioxideLevel: return "carbonDioxideLevel"
        case .carbonDioxidePeakLevel: return "carbonDioxidePeakLevel"
        case .carbonMonoxideDetected: return "carbonMonoxideDetected"
        case .carbonMonoxideLevel: return "carbonMonoxideLevel"
        case .carbonMonoxidePeakLevel: return "carbonMonoxidePeakLevel"
        case .nitrogenDioxideDensity: return "nitrogenDioxideDensity"
        case .ozoneDensity: return "ozoneDensity"
        case .pm10Density: return "pm10Density"
        case .pm2_5Density: return "pm2_5Density"
        case .sulphurDioxideDensity: return "sulphurDioxideDensity"
        case .vocDensity: return "vocDensity"
        }
    }
}

// MARK: - Info Protocols
@objc(HomeInfoProtocol)
public protocol HomeInfoProtocol: NSObjectProtocol {
    init()
    var name: String { get set }
    var uniqueIdentifier: UUID { get set }
}

@objc(RoomInfoProtocol)
public protocol RoomInfoProtocol: NSObjectProtocol {
    init()
    var name: String { get set }
    var uniqueIdentifier: UUID { get set }
}

@objc(ServiceGroupInfoProtocol)
public protocol ServiceGroupInfoProtocol: NSObjectProtocol {
    init()
    var name: String { get set }
    var uniqueIdentifier: UUID { get set }
}

@objc(ActionSetInfoProtocol)
public protocol ActionSetInfoProtocol: NSObjectProtocol {
    init()
    var name: String { get set }
    var uniqueIdentifier: UUID { get set }
    var targetValues: [Any] { get set }
}

@objc(AccessoryInfoProtocol)
public protocol AccessoryInfoProtocol: NSObjectProtocol {
    init()
    var home: HomeInfoProtocol? { get set }
    var room: RoomInfoProtocol? { get set }
    var name: String { get set }
    var uniqueIdentifier: UUID { get set }
    var hasCamera: Bool { get set }
    var services: [ServiceInfoProtocol] { get set }
}

@objc(ServiceInfoProtocol)
public protocol ServiceInfoProtocol: NSObjectProtocol {
    init()
    var name: String { get set }
    var uniqueIdentifier: UUID { get set }
    var isUserInteractive: Bool { get set }
    var characteristics: [CharacteristicInfoProtocol] { get set }
    var isSupported: Bool { get }
}

@objc(CharacteristicInfoProtocol)
public protocol CharacteristicInfoProtocol: NSObjectProtocol {
    init()
    var uniqueIdentifier: UUID { get set }
    var value: Any? { get set }
    var type: CharacteristicType { get }
}

// MARK: - Info Implementations
public class HomeInfo: NSObject, HomeInfoProtocol {
    public var name: String
    public var uniqueIdentifier: UUID
    
    required public override init() {
        self.name = ""
        self.uniqueIdentifier = UUID()
        super.init()
    }
    
    public init(name: String, uniqueIdentifier: UUID) {
        self.name = name
        self.uniqueIdentifier = uniqueIdentifier
        super.init()
    }
}

public class RoomInfo: NSObject, RoomInfoProtocol {
    public var name: String
    public var uniqueIdentifier: UUID
    
    required public override init() {
        self.name = ""
        self.uniqueIdentifier = UUID()
        super.init()
    }
    
    public init(name: String, uniqueIdentifier: UUID) {
        self.name = name
        self.uniqueIdentifier = uniqueIdentifier
        super.init()
    }
}

public class ServiceGroupInfo: NSObject, ServiceGroupInfoProtocol {
    public var name: String
    public var uniqueIdentifier: UUID
    
    required public override init() {
        self.name = ""
        self.uniqueIdentifier = UUID()
        super.init()
    }
    
    public init(name: String, uniqueIdentifier: UUID) {
        self.name = name
        self.uniqueIdentifier = uniqueIdentifier
        super.init()
    }
    
#if !os(macOS)
    public init(serviceGroup: HMServiceGroup) {
        self.name = serviceGroup.name
        self.uniqueIdentifier = serviceGroup.uniqueIdentifier
        super.init()
    }
#endif
}

public class ActionSetInfo: NSObject, ActionSetInfoProtocol {
    public var name: String
    public var uniqueIdentifier: UUID
    public var targetValues: [Any] = []
    
    required public override init() {
        self.name = ""
        self.uniqueIdentifier = UUID()
        super.init()
    }
    
    public init(name: String, uniqueIdentifier: UUID) {
        self.name = name
        self.uniqueIdentifier = uniqueIdentifier
        super.init()
    }
    
#if !os(macOS)
    public init(actionSet: HMActionSet) {
        self.name = actionSet.name
        self.uniqueIdentifier = actionSet.uniqueIdentifier
        self.targetValues = []
        super.init()
    }
#endif
}

public class AccessoryInfo: NSObject, AccessoryInfoProtocol {
    public var home: HomeInfoProtocol?
    public var room: RoomInfoProtocol?
    public var name: String
    public var uniqueIdentifier: UUID = UUID()
    public var services: [ServiceInfoProtocol] = []
    public var hasCamera: Bool = false
    
    required public override init() {
        self.name = ""
        super.init()
    }
    
#if !os(macOS)
    public init(accessory: HMAccessory) {
        uniqueIdentifier = accessory.uniqueIdentifier
        name = accessory.name
        
        if let tmp = accessory.room {
            room = RoomInfo(name: tmp.name, uniqueIdentifier: tmp.uniqueIdentifier)
        }
        
        if let cameraProfiles = accessory.cameraProfiles {
            hasCamera = (cameraProfiles.count > 0)
        }
        
        services = accessory
            .services
            .filter({ $0.isSupported })
            .map({ ServiceInfo(service: $0) })
            .compactMap({$0})
        
        super.init()
    }
    
    public init(accessory: HMAccessory, home: HMHome) {
        uniqueIdentifier = accessory.uniqueIdentifier
        name = accessory.name
        
        // Set the home property
        self.home = HomeInfo(name: home.name, uniqueIdentifier: home.uniqueIdentifier)
        
        if let tmp = accessory.room {
            room = RoomInfo(name: tmp.name, uniqueIdentifier: tmp.uniqueIdentifier)
        }
        
        if let cameraProfiles = accessory.cameraProfiles {
            hasCamera = (cameraProfiles.count > 0)
        }
        
        services = accessory
            .services
            .filter({ $0.isSupported })
            .map({ ServiceInfo(service: $0) })
            .compactMap({$0})
        
        super.init()
    }
#endif
}

public class ServiceInfo: NSObject, ServiceInfoProtocol {
    public var name: String
    public var uniqueIdentifier: UUID = UUID()
    public var isUserInteractive: Bool = false
    public var characteristics: [CharacteristicInfoProtocol] = []
    private var _type: ServiceType = .unknown
    
    required public override init() {
        self.name = ""
        super.init()
    }
    
    public var type: ServiceType {
        get { return _type }
        set { _type = newValue }
    }
    
    public var isSupported: Bool {
        return self.type.isSupported
    }
    
    // Add a method to set the type for macOS compatibility
    public func setType(_ type: ServiceType) {
        self._type = type
    }
    
#if !os(macOS)
    public init(service: HMService) {
        name = service.name
        uniqueIdentifier = service.uniqueIdentifier
        isUserInteractive = service.isUserInteractive
        _type = ServiceType(key: service.serviceType)
        characteristics = service.characteristics.map({ CharacteristicInfo(characteristic: $0) }).filter({ $0.isSupported })
        super.init()
    }
#endif
}

public class CharacteristicInfo: NSObject, CharacteristicInfoProtocol {
    public var uniqueIdentifier: UUID = UUID()
    public var value: Any?
    private var _type: CharacteristicType = .unknown
    
    required public override init() {
        super.init()
    }
    
    public var type: CharacteristicType {
        get { return _type }
        set { _type = newValue }
    }
    
    public var isSupported: Bool {
        return type.isSupported
    }
    
#if !os(macOS)
    public init(characteristic: HMCharacteristic) {
        super.init()
        uniqueIdentifier = characteristic.uniqueIdentifier
        value = characteristic.value
        _type = CharacteristicType(key: characteristic.characteristicType)
    }
#endif
}

// MARK: - Extensions for HomeKit Types
#if !os(macOS)
extension ServiceType {
    init(key: String) {
        switch key {
        case HMServiceTypeHumiditySensor:
            self = .humiditySensor
        case HMServiceTypeTemperatureSensor:
            self = .temperatureSensor
        case HMServiceTypeLightSensor:
            self = .lightSensor
        case HMServiceTypeAirQualitySensor:
            self = .airQualitySensor
        case HMServiceTypeLightbulb:
            self = .lightbulb
        case HMServiceTypeSwitch:
            self = .switch
        case HMServiceTypeOutlet:
            self = .outlet
        default:
            self = .unknown
        }
    }
}

extension CharacteristicType {
    init(key: String) {
        switch key {
        case HMCharacteristicTypeBrightness:
            self = .brightness
        case HMCharacteristicTypeHue:
            self = .hue
        case HMCharacteristicTypeSaturation:
            self = .saturation
        case HMCharacteristicTypeCurrentTemperature:
            self = .currentTemperature
        case HMCharacteristicTypeCurrentRelativeHumidity:
            self = .currentRelativeHumidity
        case HMCharacteristicTypePowerState:
            self = .on
        case HMCharacteristicTypeTargetTemperature:
            self = .targetTemperature
        case HMCharacteristicTypeTargetRelativeHumidity:
            self = .targetRelativeHumidity
        case HMCharacteristicTypeColorTemperature:
            self = .colorTemperature
        case HMCharacteristicTypeCurrentLightLevel:
            self = .currentLightLevel
            
        // Air quality and environment
        case HMCharacteristicTypeAirQuality:
            self = .airQuality
        case HMCharacteristicTypeAirParticulateDensity:
            self = .airParticulateDensity
        case HMCharacteristicTypeAirParticulateSize:
            self = .airParticulateSize
        case HMCharacteristicTypeSmokeDetected:
            self = .smokeDetected
        case HMCharacteristicTypeCarbonDioxideDetected:
            self = .carbonDioxideDetected
        case HMCharacteristicTypeCarbonDioxideLevel:
            self = .carbonDioxideLevel
        case HMCharacteristicTypeCarbonDioxidePeakLevel:
            self = .carbonDioxidePeakLevel
        case HMCharacteristicTypeCarbonMonoxideDetected:
            self = .carbonMonoxideDetected
        case HMCharacteristicTypeCarbonMonoxideLevel:
            self = .carbonMonoxideLevel
        case HMCharacteristicTypeCarbonMonoxidePeakLevel:
            self = .carbonMonoxidePeakLevel
        case HMCharacteristicTypeNitrogenDioxideDensity:
            self = .nitrogenDioxideDensity
        case HMCharacteristicTypeOzoneDensity:
            self = .ozoneDensity
        case HMCharacteristicTypePM10Density:
            self = .pm10Density
        case HMCharacteristicTypePM2_5Density:
            self = .pm2_5Density
        case HMCharacteristicTypeSulphurDioxideDensity:
            self = .sulphurDioxideDensity
        case HMCharacteristicTypeVolatileOrganicCompoundDensity:
            self = .vocDensity
            
        default:
            self = .unknown
        }
    }
}

extension HMService {
    public var isSupported: Bool {
        return ServiceType(key: self.serviceType).isSupported
    }
}

extension HMActionSet {
    public var isHomeKitScene: Bool {
        return self.actionSetType == "HMActionSetTypeHomeKitScene"
    }
}
#endif

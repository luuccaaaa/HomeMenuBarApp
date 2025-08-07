import Foundation
import AppKit
import CoreGraphics

// MARK: - Toggle Menu Item (for switches, outlets, lightbulbs)
class ToggleMenuItem: NSMenuItem, MenuItemFromUUID, ErrorMenuItem, StateObserver {
    var reachable: Bool = true
    internal var characteristicUUID: UUID?
    internal var mac2ios: mac2iOS?
    var deviceUUID: UUID = UUID() // This should be set during initialization
    
    init(serviceInfo: ServiceInfoProtocol, mac2ios: mac2iOS?) {
        super.init(title: serviceInfo.name, action: #selector(toggle), keyEquivalent: "")
        self.mac2ios = mac2ios
        self.target = self
        
        // Set the device UUID to the service's unique identifier
        self.deviceUUID = serviceInfo.uniqueIdentifier
        
        // Find the on/off characteristic - use the same logic as AdaptiveLightbulbMenuItem
        if let onOffUUID = SharedUtilities.findCharacteristic(by: .on, in: serviceInfo.characteristics) {
            self.characteristicUUID = onOffUUID
            HMLog.menuDebug("ToggleMenuItem: Device '\(serviceInfo.name)' using on/off characteristic: \(onOffUUID)")
        } else {
            // If no on/off characteristic found, use the first characteristic
            if let firstCharacteristic = serviceInfo.characteristics.first {
                self.characteristicUUID = firstCharacteristic.uniqueIdentifier
                HMLog.menuDebug("ToggleMenuItem: Device '\(serviceInfo.name)' using fallback characteristic: \(firstCharacteristic.uniqueIdentifier)")
            }
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Explicit cleanup to be called before menu teardown
    func cleanupOnRemoval() {
        DeviceStateManager.shared.removeObserver(for: deviceUUID, observer: self)
    }
    
    func bind(with uniqueIdentifier: UUID) -> Bool {
        // ToggleMenuItem only binds to its own characteristic
        return characteristicUUID == uniqueIdentifier
    }
    
    func UUIDs() -> [UUID] {
        return characteristicUUID.map { [$0] } ?? []
    }
    
    func update(value: Bool) {
        // Keep the title clean - no bullet points or status text
        // The icon (lightbulb) will show the state instead
        self.reachable = true
    }
    
    // MARK: - StateObserver Implementation
    public func deviceStateDidChange(deviceUUID: UUID, state: DeviceState) {
        // Update the menu item based on centralized state
        update(value: state.isOn)
    }
    

    
    @objc func toggle() {
        HMLog.menuDebug("toggle() called for menu item: \(self.title)")
        guard let uuid = characteristicUUID else { 
            HMLog.error(.menu, "No characteristic UUID found for menu item: \(self.title)")
            return 
        }
        
        HMLog.menuDebug("Characteristic UUID: \(uuid)")
        
        // Get current state from centralized state manager
        let currentState = DeviceStateManager.shared.getDeviceState(for: deviceUUID)
        let isCurrentlyOn = currentState?.isOn ?? false
        let newValue = !isCurrentlyOn
        
        HMLog.menuDebug("Current state: \(isCurrentlyOn), new value: \(newValue)")
        HMLog.menuDebug("Calling mac2ios?.setCharacteristic with UUID: \(uuid), value: \(newValue)")
        
        // Update centralized state immediately for responsive UI
        DeviceStateManager.shared.updateDeviceState(
            deviceUUID: deviceUUID,
            characteristicUUID: uuid,
            value: newValue,
            valueType: .on
        )
        
        mac2ios?.setCharacteristic(of: uuid, object: newValue)
    }
}

 // MARK: - Sensor Menu Item (for temperature, humidity, light level sensors)
 class SensorMenuItem: NSMenuItem, MenuItemFromUUID, ErrorMenuItem, StateObserver {
    var reachable: Bool = true
    private var characteristicUUID: UUID?
    var deviceUUID: UUID = UUID()
    private var mac2ios: mac2iOS?
    private var sensorType: CharacteristicType = .unknown
    private let baseTitle: String
    private var valueText: String = "Loading..."
    // Air quality: store additional discovered characteristics shown in a submenu on hover
    private var airQualityCharacteristics: [(type: CharacteristicType, uuid: UUID)] = []
    
    init(serviceInfo: ServiceInfoProtocol, mac2ios: mac2iOS?) {
        self.baseTitle = serviceInfo.name
        super.init(title: "", action: nil, keyEquivalent: "")
        self.mac2ios = mac2ios
        self.deviceUUID = serviceInfo.uniqueIdentifier
        
        // Check for specific sensor types first, then fall back to air quality if no specific sensor found
        if let uuid = SharedUtilities.findCharacteristic(by: .currentTemperature, in: serviceInfo.characteristics) {
            self.characteristicUUID = uuid
            self.sensorType = .currentTemperature
        } else if let uuid = SharedUtilities.findCharacteristic(by: .currentRelativeHumidity, in: serviceInfo.characteristics) {
            self.characteristicUUID = uuid
            self.sensorType = .currentRelativeHumidity
        } else if let uuid = SharedUtilities.findCharacteristic(by: .currentLightLevel, in: serviceInfo.characteristics) {
            self.characteristicUUID = uuid
            self.sensorType = .currentLightLevel
        } else if serviceInfo.characteristics.contains(where: { c in
            switch c.type {
            case .airQuality, .airParticulateDensity, .airParticulateSize,
                 .smokeDetected, .carbonDioxideDetected, .carbonDioxideLevel, .carbonDioxidePeakLevel,
                 .carbonMonoxideDetected, .carbonMonoxideLevel, .carbonMonoxidePeakLevel,
                 .nitrogenDioxideDensity, .ozoneDensity, .pm10Density, .pm2_5Density,
                 .sulphurDioxideDensity, .vocDensity:
                return true
            default:
                return false
            }
        }) {
            // Title becomes "Air Quality" and value in the main row is a summary (e.g., 'Good' or '—')
            self.sensorType = .airQuality
            // For the main row reads, prefer the dedicated airQuality characteristic if present,
            // otherwise bind to none (we'll populate value from submenu updates).
            if let aqUUID = SharedUtilities.findCharacteristic(by: .airQuality, in: serviceInfo.characteristics) {
                self.characteristicUUID = aqUUID
            } else {
                self.characteristicUUID = nil
            }
        } else if let first = serviceInfo.characteristics.first {
            self.characteristicUUID = first.uniqueIdentifier
            self.sensorType = first.type
        }
        
        // Collect any air quality–related characteristics for the submenu (include all, including PM2.5)
        airQualityCharacteristics = serviceInfo.characteristics.compactMap { c in
            let t = c.type
            switch t {
            case .airQuality, .airParticulateDensity, .airParticulateSize,
                 .smokeDetected, .carbonDioxideDetected, .carbonDioxideLevel, .carbonDioxidePeakLevel,
                 .carbonMonoxideDetected, .carbonMonoxideLevel, .carbonMonoxidePeakLevel,
                 .nitrogenDioxideDensity, .ozoneDensity, .pm10Density, .pm2_5Density,
                 .sulphurDioxideDensity, .vocDensity:
                // Include all AQ metrics in the submenu; main row stays "Air Quality"
                return (t, c.uniqueIdentifier)
            default:
                return nil
            }
        }
        
        // Build the view for all sensors using the same custom view class so layout is identical.
        buildCustomView()
        updateTitle(value: nil)
        
        // Only create a submenu for air quality sensor to display metrics on hover
        if sensorType == .airQuality && !airQualityCharacteristics.isEmpty {
            // Build submenu and keep layout consistent with other device parents (like bulbs)
            let submenu = buildAirQualitySubmenu()
            self.submenu = submenu
            self.isEnabled = true
        }
        
        // Request current values for displayed characteristic and AQ submenu
        requestInitialReads()

        DeviceStateManager.shared.addObserver(for: self.deviceUUID, observer: self)
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func bind(with uniqueIdentifier: UUID) -> Bool {
        // For Air Quality parent rows, also match any known AQ characteristic UUID so updates reach the submenu
        if sensorType == .airQuality {
            if airQualityCharacteristics.contains(where: { pair in
                pair.uuid == uniqueIdentifier || pair.uuid.uuidString.lowercased() == uniqueIdentifier.uuidString.lowercased()
            }) {
                return true
            }
        }
        return characteristicUUID == uniqueIdentifier
    }
    
    func UUIDs() -> [UUID] {
        return characteristicUUID.map { [$0] } ?? []
    }
    
    // Indicates whether this SensorMenuItem's "primary" characteristic matches the provided UUID.
    // Primary characteristic is the one used for the main row numeric display:
    // - Temperature: .currentTemperature
    // - Humidity: .currentRelativeHumidity
    // - Light: .currentLightLevel
    // - Air Quality: we do NOT treat any metric as primary for the parent row (submenu only)
    func isPrimaryBound(to uuid: UUID) -> Bool {
        guard let primary = characteristicUUID else { return false }
        // Only non-AQ sensors have a primary main-row value
        if sensorType == .airQuality { return false }
        return primary == uuid || primary.uuidString.lowercased() == uuid.uuidString.lowercased()
    }
    
    func update(value: Double) {
        updateTitle(value: value)
        self.reachable = true
    }
    
    // No centralized observer; UI updates come via macOSController updateMenuItemsRelated
    // Cleanup hook retained for symmetry with other items (no-op for sensors currently)
    func cleanupOnRemoval() {
        DeviceStateManager.shared.removeObserver(for: deviceUUID, observer: self)
    }

    public func deviceStateDidChange(deviceUUID: UUID, state: DeviceState) {
        // Update based on sensor type, regardless of whether the value is 0.0
        // (0.0 is a valid reading for sensors)
        switch sensorType {
        case .currentTemperature:
            update(value: state.currentTemperature)
        case .currentRelativeHumidity:
            update(value: state.currentRelativeHumidity)
        case .currentLightLevel:
            update(value: state.currentLightLevel)
        case .airQuality:
            // For air quality, we need to handle the airQuality characteristic specifically
            // This will be handled by the updateAirQualityValue method
            break
        default:
            break
        }
    }
    
    private func updateTitle(value: Double?) {
        // Update the value text based on the sensor type
        if let value = value {
            switch sensorType {
            case .currentTemperature:
                valueText = "\(String(format: "%.1f", value))°C"
            case .currentRelativeHumidity:
                valueText = "\(String(format: "%.0f", value))%"
            case .currentLightLevel:
                // Show as lux with 0 decimals, cap to a reasonable max for display
                let clamped = max(0, min(value, 100_000))
                valueText = "\(String(format: "%.0f", clamped)) lx"
            case .airQuality:
                // Map main row to AQ qualitative string (e.g., "Good") if the airQuality characteristic is present
                let idx = Int(value)
                switch idx {
                case 1: valueText = "Excellent"
                case 2: valueText = "Good"
                case 3: valueText = "Fair"
                case 4: valueText = "Inferior"
                case 5: valueText = "Poor"
                default: valueText = "Unknown"
                }
            default:
                valueText = String(format: "%.1f", value)
            }
        } else {
            valueText = "Loading..."
        }
        
        // Update the menu item title to show sensor type and value
        // Format: "Sensor Type (Value)" - e.g., "Temperature (23.5°C)"
        if sensorType == .airQuality {
            // For air quality, just show the qualitative value
            self.title = valueText
        } else {
            // For other sensors, show "Type (Value)" format
            self.title = "\(sensorDisplayName()) (\(valueText))"
        }
    }
    
    private func sensorDisplayName() -> String {
        switch sensorType {
        case .currentTemperature:
            return "Temperature"
        case .currentRelativeHumidity:
            return "Humidity"
        case .currentLightLevel:
            return "Light Level" // Changed from "Light" to "Light Level" for better clarity and alignment
        case .airQuality:
            return "Air Quality"
        default:
            return "Sensor"
        }
    }
    
    private func sensorSymbolName() -> String {
        switch sensorType {
        case .currentTemperature:
            return "thermometer"
        case .currentRelativeHumidity:
            return "humidity"
        case .currentLightLevel:
            return "sun.max" // Changed from "light.max" to "sun.max" for better alignment and recognition
        case .airQuality:
            return "aqi.medium" // SF Symbol representing air quality (fallback if unavailable)
        default:
            return "sensor"
        }
    }
    
    private func buildCustomView() {
        // Use standard NSMenuItem styling for all sensors to ensure proper alignment
        // This matches the styling of other menu items like lightbulbs
        self.view = nil
        
        // Set the title to include both sensor type and value
        updateTitle(value: nil) // This will set the initial "Loading..." state
        
        // Set the icon using SF Symbol
        self.image = NSImage(systemSymbolName: sensorSymbolName(), accessibilityDescription: nil)
        self.image?.isTemplate = true
        
        // Set proper target and action for styling, but make action do nothing
        self.isEnabled = true
        self.target = self
        self.action = #selector(sensorAction)
    }
    
    @objc private func sensorAction() {
        // Do nothing - sensors are read-only
        // This method exists only to provide proper menu item styling
    }
    

    
    private func requestInitialReads() {
        // Request the primary characteristic (if any)
        if let uuid = characteristicUUID {
            mac2ios?.readCharacteristic(of: uuid)
        }
        // Always request all the AQ submenu characteristics (if any)
        for entry in airQualityCharacteristics {
            mac2ios?.readCharacteristic(of: entry.uuid)
        }
    }
    
    // MARK: - Air Quality Submenu Helpers (class scope)
    private func buildAirQualitySubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        
        var entries: [(CharacteristicType, UUID)] = airQualityCharacteristics
        self.airQualityCharacteristics = entries
        
        // Ensure a stable ordering for AQ submenu entries; "Air Quality" first, others follow.
        let preferredOrder: [CharacteristicType] = [
            .airQuality,
            .pm2_5Density, .pm10Density,
            .carbonDioxideLevel, .carbonMonoxideLevel,
            .ozoneDensity, .nitrogenDioxideDensity, .sulphurDioxideDensity,
            .vocDensity
        ]
        entries.sort { a, b in
            let ia = preferredOrder.firstIndex(of: a.0) ?? Int.max
            let ib = preferredOrder.firstIndex(of: b.0) ?? Int.max
            return ia < ib
        }
        
        // Build a right-aligned value layout using attributedTitle with tab stops.
        for entry in entries {
            // Skip the parent "Air Quality" metric in the submenu, since it is now shown in the main row
            if entry.0 == .airQuality {
                continue
            }
            let item = NSMenuItem()
            let base = airQualityDisplayTitle(for: entry.0)
            // Initial placeholder value
            let value = "Loading..."
            // Add a thin leading spacer so the base label aligns with main menu item text (compensates chevron gutter)
            item.attributedTitle = makeRightAlignedMenuTitle(left: "  " + base, right: value)
            item.image = NSImage(systemSymbolName: airQualitySymbol(for: entry.0), accessibilityDescription: nil)
            item.image?.isTemplate = true
            item.isEnabled = true
            item.target = nil
            item.action = nil
            item.representedObject = ["uuid": entry.1.uuidString, "type": entry.0.stringValue, "base": base]
            item.state = .off
            submenu.addItem(item)
        }
        return submenu
    }
    
    private func airQualityDisplayTitle(for type: CharacteristicType) -> String {
        switch type {
        case .airQuality: return "Air Quality"
        case .airParticulateDensity: return "Particulate Density"
        case .airParticulateSize: return "Particulate Size"
        case .smokeDetected: return "Smoke Detected"
        case .carbonDioxideDetected: return "CO₂ Detected"
        case .carbonDioxideLevel: return "CO₂"
        case .carbonDioxidePeakLevel: return "CO₂ Peak Level"
        case .carbonMonoxideDetected: return "CO Detected"
        case .carbonMonoxideLevel: return "CO Level"
        case .carbonMonoxidePeakLevel: return "CO Peak Level"
        case .nitrogenDioxideDensity: return "NO₂"
        case .ozoneDensity: return "O₃"
        case .pm10Density: return "PM10"
        case .pm2_5Density: return "PM2.5"
        case .sulphurDioxideDensity: return "SO₂"
        case .vocDensity: return "VOC"
        default: return "Air Metric"
        }
    }
    
    private func airQualitySymbol(for type: CharacteristicType) -> String {
        switch type {
        case .airQuality: return "aqi.medium"
        case .airParticulateDensity, .pm10Density, .pm2_5Density: return "aqi.low"
        case .airParticulateSize: return "ruler"
        case .smokeDetected: return "smoke"
        case .carbonDioxideDetected, .carbonDioxideLevel, .carbonDioxidePeakLevel: return "leaf"
        case .carbonMonoxideDetected, .carbonMonoxideLevel, .carbonMonoxidePeakLevel: return "flame"
        case .nitrogenDioxideDensity, .ozoneDensity, .sulphurDioxideDensity, .vocDensity: return "wind"
        default: return "aqi.low"
        }
    }
    
    // Called by MacOSController.updateMenuItemsRelated when a value arrives
    // We update the submenu entries that match the characteristic UUID.
    func updateAirQualityValue(for characteristicUUID: UUID, value: Any) {
        guard let submenu = self.submenu else { return }
        
        // Normalize UUID string for robust matching (some bridges rebuild UUID instances)
        let incoming = characteristicUUID.uuidString.lowercased()
        
        // If the incoming value is for the main Air Quality characteristic, update parent title too
        if sensorType == .airQuality, let primary = self.characteristicUUID {
            let primaryStr = primary.uuidString.lowercased()
            if primaryStr == incoming {
                // Value can be Int or Double depending on bridge; normalize to Int
                let idx: Int
                if let intV = value as? Int {
                    idx = intV
                } else if let dblV = value as? Double {
                    idx = Int(dblV)
                } else {
                    idx = -1
                }
                switch idx {
                case 1: self.title = "Excellent"
                case 2: self.title = "Good"
                case 3: self.title = "Fair"
                case 4: self.title = "Inferior"
                case 5: self.title = "Poor"
                default: self.title = "Unknown"
                }
            }
        }
        
        // 1) Try to match existing submenu items by stored uuid string (case-insensitive)
        for item in submenu.items {
            if let payload = item.representedObject as? [String: String],
               let uuidStr = payload["uuid"]?.lowercased(),
               uuidStr == incoming {
                let base = payload["base"] ?? airQualityDisplayTitle(for: .unknown)
                let right = airQualityFormattedRightValue(for: base, value: value)
                item.attributedTitle = makeRightAlignedMenuTitle(left: "  " + base, right: right)
                item.isEnabled = true
                item.state = .off
                item.target = nil
                item.action = nil
                return
            }
        }
        
        // 2) If not found, infer type from our stored list and append a new row
        if let entryType = inferCharacteristicType(from: characteristicUUID) {
            let base = airQualityDisplayTitle(for: entryType)
            let newItem = NSMenuItem()
            let right = airQualityFormattedRightValue(for: base, value: value)
            newItem.attributedTitle = makeRightAlignedMenuTitle(left: "  " + base, right: right)
            newItem.image = NSImage(systemSymbolName: airQualitySymbol(for: entryType), accessibilityDescription: nil)
            newItem.image?.isTemplate = true
            newItem.isEnabled = true
            newItem.target = nil
            newItem.action = nil
            newItem.representedObject = ["uuid": incoming, "type": entryType.stringValue, "base": base]
            newItem.state = .off
            submenu.addItem(newItem)
            return
        }
        
        // 3) Last resort: update any item that has matching base title (handles cases where representedObject was stripped)
        let allTypes: [CharacteristicType] = [
            .airQuality, .airParticulateDensity, .airParticulateSize,
            .smokeDetected, .carbonDioxideDetected, .carbonDioxideLevel, .carbonDioxidePeakLevel,
            .carbonMonoxideDetected, .carbonMonoxideLevel, .carbonMonoxidePeakLevel,
            .nitrogenDioxideDensity, .ozoneDensity, .pm10Density, .pm2_5Density,
            .sulphurDioxideDensity, .vocDensity
        ]
        // Try each known AQ type; if its display title matches the item prefix, update it
        for t in allTypes {
            let base = airQualityDisplayTitle(for: t)
            if let item = submenu.items.first(where: { existing in
                if let payload = existing.representedObject as? [String: String], let storedBase = payload["base"] {
                    return storedBase == base
                }
                // Fallback if representedObject missing; try to parse attributed title string
                return existing.title.hasPrefix(base + ":") || existing.title == "\(base): Loading..."
            }) {
                let right = airQualityFormattedRightValue(for: base, value: value)
                item.attributedTitle = makeRightAlignedMenuTitle(left: "  " + base, right: right)
                item.isEnabled = true
                return
            }
        }
    }
    
    // Helper to map back type names from title (used for quick formatting). Titles are fixed strings from airQualityDisplayTitle.
    private func typeForTitle(_ title: String) -> CharacteristicType {
        switch title {
        case "Air Quality": return .airQuality
        case "Particulate Density": return .airParticulateDensity
        case "Particulate Size": return .airParticulateSize
        case "Smoke Detected": return .smokeDetected
        case "CO₂ Detected": return .carbonDioxideDetected
        case "CO₂ Level": return .carbonDioxideLevel
        case "CO₂ Peak Level": return .carbonDioxidePeakLevel
        case "CO Detected": return .carbonMonoxideDetected
        case "CO Level": return .carbonMonoxideLevel
        case "CO Peak Level": return .carbonMonoxidePeakLevel
        case "NO₂ Density": return .nitrogenDioxideDensity
        case "O₃ Density": return .ozoneDensity
        case "PM10 Density": return .pm10Density
        case "PM2.5 Density": return .pm2_5Density
        case "SO₂ Density": return .sulphurDioxideDensity
        case "VOC Density": return .vocDensity
        default: return .unknown
        }
    }
    
    // Build a right-aligned attributed title "left<TAB>right"
    private func makeRightAlignedMenuTitle(left: String, right: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        // Tab stop at ~220pt so the right part aligns; adjust to fit 240pt width with icon padding
        let tab = NSTextTab(textAlignment: .right, location: 220, options: [:])
        paragraph.tabStops = [tab]
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 13),
            .paragraphStyle: paragraph
        ]
        let result = NSMutableAttributedString(string: "\(left)\t\(right)", attributes: attrs)
        return result
    }
    
    // Compute only the right-side value text based on base label and value
    private func airQualityFormattedRightValue(for baseTitle: String, value: Any) -> String {
        let type = self.typeForTitle(baseTitle)
        switch type {
        case .airQuality:
            if let idx = value as? Int {
                switch idx {
                case 1: return "Excellent"
                case 2: return "Good"
                case 3: return "Fair"
                case 4: return "Inferior"
                case 5: return "Poor"
                default: return "Unknown"
                }
            }
            return "\(value)"
        case .smokeDetected, .carbonDioxideDetected, .carbonMonoxideDetected:
            let detected = (value as? Bool) ?? false
            return detected ? "Detected" : "Clear"
        case .airParticulateSize:
            return "\(value)"
        case .carbonDioxideLevel, .carbonDioxidePeakLevel,
             .carbonMonoxideLevel, .carbonMonoxidePeakLevel:
            if let d = value as? Double { return String(format: "%.0f ppm", d) }
            return "\(value)"
        case .nitrogenDioxideDensity, .ozoneDensity, .sulphurDioxideDensity, .vocDensity,
             .airParticulateDensity, .pm10Density, .pm2_5Density:
            if let d = value as? Double { return String(format: "%.2f µg/m³", d) }
            return "\(value)"
        default:
            return "\(value)"
        }
    }
    
    // Try to infer the CharacteristicType from a known list using stored pairs
    private func inferCharacteristicType(from uuid: UUID) -> CharacteristicType? {
        if let match = airQualityCharacteristics.first(where: { $0.uuid == uuid }) {
            return match.type
        }
        // Fallback: try matching by string (some bridges recreate UUID objects)
        if let match = airQualityCharacteristics.first(where: { $0.uuid.uuidString == uuid.uuidString }) {
            return match.type
        }
        return nil
    }
}
 
// MARK: - Adaptive Lightbulb Menu Item
class AdaptiveLightbulbMenuItem: ToggleMenuItem {
    deinit {
        // Ensure we unregister from centralized state updates to avoid leaks
        DeviceStateManager.shared.removeObserver(for: deviceUUID, observer: self)
    }
    
    // Stop timers and unregister observer proactively
    override func cleanupOnRemoval() {
        // AdaptiveLightbulbMenuItem does not own timers directly; ensure any subclass/state is clean
        DeviceStateManager.shared.removeObserver(for: deviceUUID, observer: self)
    }
    private var hueUUID: UUID?
    private var saturationUUID: UUID?
    private var brightnessUUID: UUID?
    private var colorTemperatureUUID: UUID?
    private var currentLightLevelUUID: UUID?
    private var onOffUUID: UUID?
    private var adaptiveSubmenu: NSMenu?
    
    // Color wheel properties
    private var selectedColor: NSColor = .white
    private var currentHue: CGFloat = 0.0
    private var currentSaturation: CGFloat = 1.0
    private var isDragging = false
    private var isDraggingBrightness = false
    private var isDraggingTemperature = false
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 0.3 // 300ms for smoother operation
    private var hasChangedSinceLastUpdate = false
    private var lastSentHue: CGFloat = -1
    private var lastSentSaturation: CGFloat = -1
    private var lastSentBrightness: CGFloat = -1
    private var lastSentTemperature: CGFloat = -1
    
    // User intent tracking - prevent HomeKit callbacks from overriding user actions
    private var userIntentActive = false
    private var userIntentTimer: Timer?
    private let userIntentTimeout: TimeInterval = 1.0 // 1 second to allow HomeKit to process
    
    // Capability flags
    private var hasColorSupport: Bool = false
    private var hasBrightnessSupport: Bool = false
    private var hasColorTemperatureSupport: Bool = false
    
    // UI elements
    private var colorWheel: ColorWheelControlView?
    private var brightnessSlider: NSSlider?
    private var temperatureSlider: NSSlider?
    private var toggleButton: NSTextField?
    
    override init(serviceInfo: ServiceInfoProtocol, mac2ios: mac2iOS?) {
        super.init(serviceInfo: serviceInfo, mac2ios: mac2ios)
        self.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil)
        
        // Set the device UUID to the service's unique identifier
        self.deviceUUID = serviceInfo.uniqueIdentifier
        
        HMLog.menuDebug("AdaptiveLightbulbMenuItem init - serviceInfo has \(serviceInfo.characteristics.count) characteristics")
        
        // Find characteristics by their proper type constants
        hueUUID = findCharacteristic(by: .hue, in: serviceInfo.characteristics)
        saturationUUID = findCharacteristic(by: .saturation, in: serviceInfo.characteristics)
        brightnessUUID = findCharacteristic(by: .brightness, in: serviceInfo.characteristics)
        colorTemperatureUUID = findCharacteristic(by: .colorTemperature, in: serviceInfo.characteristics)
        currentLightLevelUUID = findCharacteristic(by: .currentLightLevel, in: serviceInfo.characteristics)
        
        // Use the same on/off characteristic as the parent ToggleMenuItem
        onOffUUID = self.characteristicUUID
        
        // Determine which features are supported
        hasColorSupport = (hueUUID != nil && saturationUUID != nil)
        hasBrightnessSupport = (brightnessUUID != nil)
        hasColorTemperatureSupport = (colorTemperatureUUID != nil)
        
        HMLog.menuDebug("AdaptiveLightbulbMenuItem init - Found UUIDs: hue=\(hueUUID?.uuidString ?? "nil"), saturation=\(saturationUUID?.uuidString ?? "nil"), brightness=\(brightnessUUID?.uuidString ?? "nil"), colorTemperature=\(colorTemperatureUUID?.uuidString ?? "nil"), onOff=\(onOffUUID?.uuidString ?? "nil")")
        HMLog.menuDebug("AdaptiveLightbulbMenuItem: Device '\(serviceInfo.name)' - Color: \(hasColorSupport), Brightness: \(hasBrightnessSupport), ColorTemp: \(hasColorTemperatureSupport)")
        
        // Create adaptive submenu based on available characteristics
        createAdaptiveSubmenu()
        
        // Register for state updates
        HMLog.menuDebug("AdaptiveLightbulbMenuItem: Registering for state updates with device UUID: \(deviceUUID)")
        DeviceStateManager.shared.addObserver(for: deviceUUID, observer: self)
    }
    
    override func update(value: Bool) {
        // Update the icon based on power state
        let iconName = value ? "lightbulb.fill" : "lightbulb"
        self.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        
        // Call parent method (which now just sets reachable)
        super.update(value: value)
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func createAdaptiveSubmenu() {
        adaptiveSubmenu = NSMenu()
        
        // Create a ServiceInfo object with the characteristics
        let serviceInfo = ServiceInfo()
        serviceInfo.name = self.title
        
        // Add characteristics to the service info based on what's available
        if let hueUUID = hueUUID {
            let hueChar = CharacteristicInfo()
            hueChar.uniqueIdentifier = hueUUID
            hueChar.type = .hue
            serviceInfo.characteristics.append(hueChar)
        }
        if let saturationUUID = saturationUUID {
            let satChar = CharacteristicInfo()
            satChar.uniqueIdentifier = saturationUUID
            satChar.type = .saturation
            serviceInfo.characteristics.append(satChar)
        }
        if let brightnessUUID = brightnessUUID {
            let brightChar = CharacteristicInfo()
            brightChar.uniqueIdentifier = brightnessUUID
            brightChar.type = .brightness
            serviceInfo.characteristics.append(brightChar)
        }
        if let colorTemperatureUUID = colorTemperatureUUID {
            let tempChar = CharacteristicInfo()
            tempChar.uniqueIdentifier = colorTemperatureUUID
            tempChar.type = .colorTemperature
            serviceInfo.characteristics.append(tempChar)
        }
        
        // Add on/off characteristic to the service info
        if let onOffUUID = onOffUUID {
            let onOffChar = CharacteristicInfo()
            onOffChar.uniqueIdentifier = onOffUUID
            onOffChar.type = .on
            serviceInfo.characteristics.append(onOffChar)
        }
        
        // Create appropriate control based on available characteristics
        if hasColorSupport || hasBrightnessSupport || hasColorTemperatureSupport {
            // Use unified adaptive menu item for all supported characteristics
            let unifiedItem = UnifiedAdaptiveMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)
            unifiedItem.deviceUUID = self.deviceUUID
            DeviceStateManager.shared.addObserver(for: unifiedItem.deviceUUID, observer: unifiedItem)
            adaptiveSubmenu?.addItem(unifiedItem)
        } else {
            // No special controls - just on/off
            let simpleToggleItem = SimpleToggleMenuItem(serviceInfo: serviceInfo, mac2ios: mac2ios)
            simpleToggleItem.deviceUUID = self.deviceUUID
            DeviceStateManager.shared.addObserver(for: simpleToggleItem.deviceUUID, observer: simpleToggleItem)
            adaptiveSubmenu?.addItem(simpleToggleItem)
        }
        
        self.submenu = adaptiveSubmenu
    }
    
    // MARK: - Helper Functions
    /// Search the characteristic list for the requested type and return its UUID.
    private func findCharacteristic(by type: CharacteristicType, in characteristics: [CharacteristicInfoProtocol]) -> UUID? {
        return SharedUtilities.findCharacteristic(by: type, in: characteristics)
    }
    
    /// Get the characteristic type for a given UUID
    func getCharacteristicType(for uuid: UUID) -> CharacteristicType? {
        if uuid == hueUUID { return .hue }
        if uuid == saturationUUID { return .saturation }
        if uuid == brightnessUUID { return .brightness }
        if uuid == colorTemperatureUUID { return .colorTemperature }
        if uuid == onOffUUID { return .on }
        return nil
    }
}

// MARK: - Unified Adaptive Menu Item (shows all available controls)
class UnifiedAdaptiveMenuItem: NSMenuItem, MenuItemFromUUID, ErrorMenuItem, StateObserver {
    var reachable: Bool = true
    private var hueUUID: UUID?
    private var saturationUUID: UUID?
    private var brightnessUUID: UUID?
    private var colorTemperatureUUID: UUID?
    private var onOffUUID: UUID?
    private var mac2ios: mac2iOS?
    private var brightness: CGFloat = 0.8
    private var colorTemperature: CGFloat = 2700.0
    private var isOn: Bool = true
    var deviceUUID: UUID = UUID()
    
    // Color wheel properties
    private var selectedColor: NSColor = .white
    private var currentHue: CGFloat = 0.0
    private var currentSaturation: CGFloat = 1.0
    private var isDragging = false
    private var isDraggingBrightness = false
    private var isDraggingTemperature = false
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 0.3 // 300ms for smoother operation
    private var hasChangedSinceLastUpdate = false
    private var lastSentHue: CGFloat = -1
    private var lastSentSaturation: CGFloat = -1
    private var lastSentBrightness: CGFloat = -1
    private var lastSentTemperature: CGFloat = -1
    
    // User intent tracking - prevent HomeKit callbacks from overriding user actions
    private var userIntentActive = false
    private var userIntentTimer: Timer?
    private let userIntentTimeout: TimeInterval = 1.0 // 1 second to allow HomeKit to process
    
    // Capability flags
    private var hasColorSupport: Bool = false
    private var hasBrightnessSupport: Bool = false
    private var hasColorTemperatureSupport: Bool = false
    
    // UI elements
    private var colorWheel: ColorWheelControlView?
    private var brightnessSlider: NSSlider?
    private var temperatureSlider: NSSlider?
    private var toggleButton: NSTextField?
    
    init(serviceInfo: ServiceInfoProtocol, mac2ios: mac2iOS?) {
        super.init(title: "", action: nil, keyEquivalent: "")
        self.mac2ios = mac2ios
        self.target = self
        
        // Find characteristics
        hueUUID = findCharacteristic(by: .hue, in: serviceInfo.characteristics)
        saturationUUID = findCharacteristic(by: .saturation, in: serviceInfo.characteristics)
        brightnessUUID = findCharacteristic(by: .brightness, in: serviceInfo.characteristics)
        colorTemperatureUUID = findCharacteristic(by: .colorTemperature, in: serviceInfo.characteristics)
        onOffUUID = findCharacteristic(by: .on, in: serviceInfo.characteristics)
        
        // Determine capabilities
        hasColorSupport = hueUUID != nil && saturationUUID != nil
        hasBrightnessSupport = brightnessUUID != nil
        hasColorTemperatureSupport = colorTemperatureUUID != nil
        
        setupUnifiedView()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        // Stop timers and unregister observers
        deactivateUserIntent()
        DeviceStateManager.shared.removeObserver(for: deviceUUID, observer: self)
    }
    
    // Explicit cleanup to be called before menu teardown
    func cleanupOnRemoval() {
        stopPeriodicUpdates()
        deactivateUserIntent()
        DeviceStateManager.shared.removeObserver(for: deviceUUID, observer: self)
    }
    
    /// Get the characteristic type for a given UUID
    func getCharacteristicType(for uuid: UUID) -> CharacteristicType? {
        if uuid == hueUUID { return .hue }
        if uuid == saturationUUID { return .saturation }
        if uuid == brightnessUUID { return .brightness }
        if uuid == colorTemperatureUUID { return .colorTemperature }
        if uuid == onOffUUID { return .on }
        return nil
    }
    
    // MARK: - User Intent Management
    private func activateUserIntent() {
        userIntentActive = true
        
        // Cancel existing timer
        userIntentTimer?.invalidate()
        
        // Set timer to deactivate user intent after timeout
        userIntentTimer = Timer.scheduledTimer(withTimeInterval: userIntentTimeout, repeats: false) { [weak self] _ in
            self?.userIntentActive = false
            HMLog.menuDebug("User intent deactivated for unified item")
        }
        
        HMLog.menuDebug("User intent activated for unified item")
    }
    
    private func deactivateUserIntent() {
        userIntentActive = false
        userIntentTimer?.invalidate()
        userIntentTimer = nil
        HMLog.menuDebug("User intent deactivated for unified item")
    }
    
    private func setupUnifiedView() {
        var totalHeight: CGFloat = 50 // Start with toggle button height
        
        // Add height for each available control
        if hasColorSupport {
            totalHeight += 220 // Color wheel height
        }
        if hasBrightnessSupport {
            totalHeight += 30 // Brightness slider height
        }
        if hasColorTemperatureSupport {
            totalHeight += 30 // Temperature slider height
        }
        
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: totalHeight))
        var currentY: CGFloat = totalHeight - 30 // Start from top, leaving space for toggle
        
        // Add toggle button at the top
        let toggleLabel = NSTextField()
        toggleLabel.frame = NSRect(x: 20, y: currentY, width: 200, height: 20)
        toggleLabel.isEditable = false
        toggleLabel.isBordered = false
        toggleLabel.backgroundColor = NSColor.clear
        toggleLabel.font = NSFont.menuFont(ofSize: 13)
        toggleLabel.alignment = .center
        toggleLabel.isSelectable = false
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(toggleLabelClicked(_:)))
        toggleLabel.addGestureRecognizer(clickGesture)
        containerView.addSubview(toggleLabel)
        self.toggleButton = toggleLabel
        
        currentY -= 15 // Less spacing after toggle button
        
        // Add color wheel if supported
        if hasColorSupport {
            // Create color wheel directly instead of embedding IntegratedColorMenuItem
            let colorWheel = ColorWheelControlView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
            let wheelSize: CGFloat = 200
            let wheelX = (240 - wheelSize) / 2 // Center horizontally
            colorWheel.frame = NSRect(x: wheelX, y: currentY - 200, width: wheelSize, height: wheelSize)
            
            // Set up color wheel callbacks
            colorWheel.onColorChanged = { [weak self] color in
                self?.selectedColor = color
                HMLog.menuDebug("onColorChanged called for unified item")
                // Activate user intent to prevent HomeKit callbacks from overriding
                self?.activateUserIntent()
                // Trigger HomeKit updates
                self?.scheduleHomeKitUpdate()
            }
            
            // Track dragging state
            colorWheel.onDragStarted = { [weak self] in
                self?.isDragging = true
                self?.activateUserIntent()
                self?.startPeriodicUpdates()
            }
            
            colorWheel.onDragEnded = { [weak self] in
                self?.isDragging = false
                self?.stopPeriodicUpdates()
            }
            
            containerView.addSubview(colorWheel)
            self.colorWheel = colorWheel
            currentY -= 200
            currentY -= 15 // More spacing after color wheel
        }
        
        // Add temperature slider if supported
        if hasColorTemperatureSupport {
            let tempSlider = NSSlider()
            tempSlider.frame = NSRect(x: 40, y: currentY - 20, width: 160, height: 16)
            tempSlider.minValue = 50  // Warm white (2700K)
            tempSlider.maxValue = 400 // Cool white (6500K)
            tempSlider.doubleValue = colorTemperature
            tempSlider.target = self
            tempSlider.action = #selector(temperatureSliderChanged(_:))
            tempSlider.controlSize = .regular
            
            // Add mouse event handling for dragging state
            tempSlider.sendAction(on: [.leftMouseDown, .leftMouseUp, .leftMouseDragged])
            
            containerView.addSubview(tempSlider)
            self.temperatureSlider = tempSlider
            
            // Add thermometer.snowflake icon on the left (cool/blue)
            let tempMinImageView = NSImageView()
            tempMinImageView.frame = NSRect(x: 20, y: currentY - 20, width: 16, height: 16)
            tempMinImageView.image = NSImage(systemSymbolName: "thermometer.snowflake", accessibilityDescription: "Cool temperature")
            tempMinImageView.contentTintColor = NSColor.labelColor
            containerView.addSubview(tempMinImageView)
            
            // Add thermometer.sun.fill icon on the right (warm/yellow)
            let tempMaxImageView = NSImageView()
            tempMaxImageView.frame = NSRect(x: 204, y: currentY - 20, width: 16, height: 16)
            tempMaxImageView.image = NSImage(systemSymbolName: "thermometer.sun.fill", accessibilityDescription: "Warm temperature")
            tempMaxImageView.contentTintColor = NSColor.labelColor
            containerView.addSubview(tempMaxImageView)
            
            currentY -= 25
        }
        
        // Add brightness slider if supported
        if hasBrightnessSupport {
            let brightnessSlider = NSSlider()
            brightnessSlider.frame = NSRect(x: 40, y: currentY - 20, width: 160, height: 16)
            brightnessSlider.minValue = 1
            brightnessSlider.maxValue = 100
            brightnessSlider.doubleValue = brightness * 100
            brightnessSlider.target = self
            brightnessSlider.action = #selector(brightnessSliderChanged(_:))
            brightnessSlider.controlSize = .regular
            
            // Add mouse event handling for dragging state
            brightnessSlider.sendAction(on: [.leftMouseDown, .leftMouseUp, .leftMouseDragged])
            
            containerView.addSubview(brightnessSlider)
            self.brightnessSlider = brightnessSlider
            
            // Add sun.min icon on the left
            let sunMinImageView = NSImageView()
            sunMinImageView.frame = NSRect(x: 20, y: currentY - 20, width: 16, height: 16)
            sunMinImageView.image = NSImage(systemSymbolName: "sun.min", accessibilityDescription: "Minimum brightness")
            sunMinImageView.contentTintColor = NSColor.labelColor
            containerView.addSubview(sunMinImageView)
            
            // Add sun.max icon on the right
            let sunMaxImageView = NSImageView()
            sunMaxImageView.frame = NSRect(x: 204, y: currentY - 20, width: 16, height: 16)
            sunMaxImageView.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Maximum brightness")
            sunMaxImageView.contentTintColor = NSColor.labelColor
            containerView.addSubview(sunMaxImageView)
        }
        
        self.view = containerView
        
        // Get initial state
        if let currentState = DeviceStateManager.shared.getDeviceState(for: deviceUUID) {
            isOn = currentState.isOn
            brightness = currentState.brightness
            colorTemperature = currentState.colorTemperature
            currentHue = currentState.hue
            currentSaturation = currentState.saturation
            selectedColor = NSColor(hue: currentHue, saturation: currentSaturation, brightness: brightness, alpha: 1.0)
            updateUI()
        }
        
        // Request current HomeKit values
        requestCurrentHomeKitValues()
    }
    
    @objc private func brightnessSliderChanged(_ sender: NSSlider) {
        // Activate user intent to prevent HomeKit callbacks from overriding
        activateUserIntent()
        
        let newBrightness = sender.doubleValue / 100.0
        self.brightness = newBrightness
        
        // Check if this is a mouse event to track dragging state
        if let event = NSApplication.shared.currentEvent {
            switch event.type {
            case .leftMouseDown:
                isDraggingBrightness = true
                startPeriodicUpdates()
            case .leftMouseUp:
                isDraggingBrightness = false
                stopPeriodicUpdates()
                // Send final value immediately
                setBrightness(newBrightness)
                return
            case .leftMouseDragged:
                // Continue dragging
                break
            default:
                break
            }
        }
        
        // If dragging, schedule for periodic update; otherwise send immediately
        if isDraggingBrightness {
            hasChangedSinceLastUpdate = true
            lastSentBrightness = newBrightness
        } else {
            setBrightness(newBrightness)
        }
    }
    
    @objc private func temperatureSliderChanged(_ sender: NSSlider) {
        // Activate user intent to prevent HomeKit callbacks from overriding
        activateUserIntent()
        
        let newTemperature = sender.doubleValue
        self.colorTemperature = newTemperature
        
        // Check if this is a mouse event to track dragging state
        if let event = NSApplication.shared.currentEvent {
            switch event.type {
            case .leftMouseDown:
                isDraggingTemperature = true
                startPeriodicUpdates()
            case .leftMouseUp:
                isDraggingTemperature = false
                stopPeriodicUpdates()
                // Send final value immediately
                setColorTemperature(newTemperature)
                return
            case .leftMouseDragged:
                // Continue dragging
                break
            default:
                break
            }
        }
        
        // If dragging, schedule for periodic update; otherwise send immediately
        if isDraggingTemperature {
            hasChangedSinceLastUpdate = true
            lastSentTemperature = newTemperature
        } else {
            setColorTemperature(newTemperature)
        }
    }
    
    @objc private func toggleLabelClicked(_ sender: NSClickGestureRecognizer) {
        togglePower()
    }
    
    private func scheduleHomeKitUpdate() {
        // Convert NSColor to HSV values
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        // Convert to sRGB color space for better color conversion
        let sRGBColor = selectedColor.usingColorSpace(NSColorSpace.sRGB) ?? selectedColor
        sRGBColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Use the slider brightness (this is what we want to control)
        let brightnessValue = self.brightness
        
        // Check if values have actually changed (with larger tolerance to reduce snapping)
        let tolerance: CGFloat = 0.005 // Increased tolerance for smoother operation
        let hueChanged = abs(hue - lastSentHue) > tolerance
        let saturationChanged = abs(saturation - lastSentSaturation) > tolerance
        let brightnessChanged = abs(brightnessValue - lastSentBrightness) > tolerance
        
        let hasChanged = hueChanged || saturationChanged || brightnessChanged
        
        HMLog.menuDebug("scheduleHomeKitUpdate - isDragging: \(isDragging), hasChanged: \(hasChanged)")
        
        if hasChanged {
            hasChangedSinceLastUpdate = true
            // Store the latest values
            lastSentHue = hue
            lastSentSaturation = saturation
            lastSentBrightness = brightnessValue
            
            // If not dragging, send immediately for responsive control
            if !isDragging {
                HMLog.menuDebug("Sending color immediately (not dragging)")
                sendColorToHomeKit()
                hasChangedSinceLastUpdate = false
            } else {
                HMLog.menuDebug("Storing for periodic update (dragging)")
            }
        }
    }
    
    private func startPeriodicUpdates() {
        // Only start timer if it's not already running
        if updateTimer == nil {
            updateTimer = Timer(timeInterval: updateInterval, repeats: true) { [weak self] _ in
                self?.sendPeriodicUpdate()
            }
            // Add to main run loop explicitly
            RunLoop.main.add(updateTimer!, forMode: .common)
        }
    }
    
    private func stopPeriodicUpdates() {
        // Only stop if no other dragging is active
        if !isDragging && !isDraggingBrightness && !isDraggingTemperature {
            if updateTimer != nil {
                updateTimer?.invalidate()
                updateTimer = nil
            }
        }
    }
    
    private func sendPeriodicUpdate() {
        // Only send if we're still dragging and values have changed
        if (isDragging || isDraggingBrightness || isDraggingTemperature) && hasChangedSinceLastUpdate {
            // Send color wheel updates if dragging
            if isDragging {
                sendColorToHomeKit()
            }
            
            // Send brightness updates if dragging brightness
            if isDraggingBrightness && lastSentBrightness != -1 {
                setBrightness(lastSentBrightness)
            }
            
            // Send temperature updates if dragging temperature
            if isDraggingTemperature && lastSentTemperature != -1 {
                setColorTemperature(lastSentTemperature)
            }
            
            hasChangedSinceLastUpdate = false
        }
    }
    
    private func sendColorToHomeKit() {
        // Use the stored values (which are updated immediately during dragging)
        let hue = lastSentHue
        let saturation = lastSentSaturation
        let brightnessValue = lastSentBrightness
        
        HMLog.menuDebug("sendColorToHomeKit - Sending hue: \(hue), saturation: \(saturation), brightness: \(brightnessValue)")
        
        // Always send color commands first, regardless of light state
        sendHueValue(hue, hueUUID: hueUUID)
        sendSaturationValue(saturation, saturationUUID: saturationUUID)
        sendBrightnessValue(brightnessValue, brightnessUUID: brightnessUUID)
        
        // If light is off, turn it on after sending color
        if !isOn, let onOffUUID = onOffUUID {
            HMLog.menuDebug("Light is off, turning it on after sending color")
            mac2ios?.setCharacteristic(of: onOffUUID, object: true)
            
            // Update local state immediately
            isOn = true
            
            // Update centralized state manager
            DeviceStateManager.shared.updateDeviceState(
                deviceUUID: deviceUUID,
                characteristicUUID: onOffUUID,
                value: true,
                valueType: .on
            )
        }
    }
    
    private func setBrightness(_ brightness: CGFloat) {
        guard let brightnessUUID = brightnessUUID else { return }
        
        let brightnessToSend = HomeKitRanges.clamp(brightness * 100.0, to: HomeKitRanges.brightness)
        mac2ios?.setCharacteristic(of: brightnessUUID, object: brightnessToSend)
        
        self.brightness = brightness
        DeviceStateManager.shared.updateDeviceState(
            deviceUUID: deviceUUID,
            characteristicUUID: brightnessUUID,
            value: brightnessToSend,
            valueType: .brightness
        )
    }
    
    private func setColorTemperature(_ temperature: CGFloat) {
        guard let colorTemperatureUUID = colorTemperatureUUID else { return }
        
        let temperatureToSend = HomeKitRanges.clamp(temperature, to: HomeKitRanges.temperature)
        mac2ios?.setCharacteristic(of: colorTemperatureUUID, object: temperatureToSend)
        
        self.colorTemperature = temperature
        DeviceStateManager.shared.updateDeviceState(
            deviceUUID: deviceUUID,
            characteristicUUID: colorTemperatureUUID,
            value: temperatureToSend,
            valueType: .colorTemperature
        )
    }
    
    private func sendHueValue(_ hue: CGFloat, hueUUID: UUID?) {
        guard let hueUUID = hueUUID else { 
            HMLog.menuDebug("No hue UUID available")
            return 
        }
        let hueValue = hue * 360.0 // Convert to degrees
        let clampedHue = HomeKitRanges.clamp(hueValue, to: HomeKitRanges.hueDegrees)
        HMLog.menuDebug("Sending hue value \(clampedHue) to UUID \(hueUUID)")
        mac2ios?.setCharacteristic(of: hueUUID, object: clampedHue)
    }
    
    private func sendSaturationValue(_ saturation: CGFloat, saturationUUID: UUID?) {
        guard let saturationUUID = saturationUUID else { 
            HMLog.menuDebug("No saturation UUID available")
            return 
        }
        let saturationValue = saturation * 100.0 // Convert to percentage
        let clampedSaturation = HomeKitRanges.clamp(saturationValue, to: HomeKitRanges.saturation)
        HMLog.menuDebug("Sending saturation value \(clampedSaturation) to UUID \(saturationUUID)")
        mac2ios?.setCharacteristic(of: saturationUUID, object: clampedSaturation)
    }
    
    private func sendBrightnessValue(_ brightness: CGFloat, brightnessUUID: UUID?) {
        guard let brightnessUUID = brightnessUUID else { 
            HMLog.menuDebug("No brightness UUID available")
            return 
        }
        let brightnessToSend = brightness * 100.0
        let clampedBrightness = HomeKitRanges.clamp(brightnessToSend, to: HomeKitRanges.brightness)
        HMLog.menuDebug("Sending brightness value \(clampedBrightness) to UUID \(brightnessUUID)")
        mac2ios?.setCharacteristic(of: brightnessUUID, object: clampedBrightness)
    }
    
    private func togglePower() {
        guard let onOffUUID = onOffUUID else { return }
        
        let newState = !isOn
        mac2ios?.setCharacteristic(of: onOffUUID, object: newState)
        
        isOn = newState
        DeviceStateManager.shared.updateDeviceState(
            deviceUUID: deviceUUID,
            characteristicUUID: onOffUUID,
            value: newState,
            valueType: .on
        )
        
        updateToggleButtonState()
    }
    
    private func updateToggleButtonState() {
        guard let toggleLabel = toggleButton else { return }
        
        if isOn {
            toggleLabel.stringValue = "Turn Off"
            toggleLabel.textColor = NSColor.controlAccentColor
        } else {
            toggleLabel.stringValue = "Turn On"
            toggleLabel.textColor = NSColor.labelColor
        }
    }
    
    private func updateUI() {
        updateToggleButtonState()
        
        if let tempSlider = temperatureSlider {
            tempSlider.doubleValue = colorTemperature
        }
        
        if let brightnessSlider = brightnessSlider {
            brightnessSlider.doubleValue = brightness * 100
        }
        
        // Update color wheel if available
        if let colorWheel = colorWheel {
            selectedColor = NSColor(hue: currentHue, saturation: currentSaturation, brightness: brightness, alpha: 1.0)
            colorWheel.setColor(selectedColor, brightness: brightness)
        }
    }
    
    private func requestCurrentHomeKitValues() {
        if let hueUUID = hueUUID {
            mac2ios?.readCharacteristic(of: hueUUID)
        }
        if let saturationUUID = saturationUUID {
            mac2ios?.readCharacteristic(of: saturationUUID)
        }
        if let colorTemperatureUUID = colorTemperatureUUID {
            mac2ios?.readCharacteristic(of: colorTemperatureUUID)
        }
        if let brightnessUUID = brightnessUUID {
            mac2ios?.readCharacteristic(of: brightnessUUID)
        }
        if let onOffUUID = onOffUUID {
            mac2ios?.readCharacteristic(of: onOffUUID)
        }
    }
    
    private func findCharacteristic(by type: CharacteristicType, in characteristics: [CharacteristicInfoProtocol]) -> UUID? {
        return SharedUtilities.findCharacteristic(by: type, in: characteristics)
    }
    
    // MARK: - MenuItemFromUUID Implementation
    func bind(with uniqueIdentifier: UUID) -> Bool {
        return colorTemperatureUUID == uniqueIdentifier || brightnessUUID == uniqueIdentifier || onOffUUID == uniqueIdentifier || hueUUID == uniqueIdentifier || saturationUUID == uniqueIdentifier
    }
    
    func UUIDs() -> [UUID] {
        var uuids: [UUID] = []
        if let colorTemperatureUUID = colorTemperatureUUID { uuids.append(colorTemperatureUUID) }
        if let brightnessUUID = brightnessUUID { uuids.append(brightnessUUID) }
        if let onOffUUID = onOffUUID { uuids.append(onOffUUID) }
        if let hueUUID = hueUUID { uuids.append(hueUUID) }
        if let saturationUUID = saturationUUID { uuids.append(saturationUUID) }
        return uuids
    }
    
    // MARK: - StateObserver Implementation
    public func deviceStateDidChange(deviceUUID: UUID, state: DeviceState) {
        HMLog.menuDebug("deviceStateDidChange called for unified item, userIntentActive: \(userIntentActive)")
        
        // If user intent is active, don't update UI from centralized state changes
        // This prevents the "bounce back" effect when user is dragging the sliders
        if userIntentActive {
            HMLog.menuDebug("Skipping UI update in deviceStateDidChange due to active user intent for unified item")
            return
        }
        
        isOn = state.isOn
        brightness = state.brightness
        colorTemperature = state.colorTemperature
        currentHue = state.hue
        currentSaturation = state.saturation
        updateUI()
    }
}

// MARK: - Simple Toggle Menu Item (for basic on/off bulbs)
class SimpleToggleMenuItem: NSMenuItem, MenuItemFromUUID, ErrorMenuItem, StateObserver {
    deinit {
        // Ensure we unregister from centralized state updates to avoid leaks
        DeviceStateManager.shared.removeObserver(for: deviceUUID, observer: self)
    }
    
    // Explicit cleanup to be called before menu teardown
    func cleanupOnRemoval() {
        DeviceStateManager.shared.removeObserver(for: deviceUUID, observer: self)
    }
    var reachable: Bool = true
    private var onOffUUID: UUID?
    private var mac2ios: mac2iOS?
    private var isOn: Bool = true
    var deviceUUID: UUID = UUID()
    
    // UI elements
    private var toggleButton: NSTextField?
    
    init(serviceInfo: ServiceInfoProtocol, mac2ios: mac2iOS?) {
        super.init(title: "", action: nil, keyEquivalent: "")
        self.mac2ios = mac2ios
        self.target = self
        
        // Find on/off characteristic
        onOffUUID = SharedUtilities.findCharacteristic(by: .on, in: serviceInfo.characteristics)
        
        setupSimpleToggleView()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupSimpleToggleView() {
        // Create a simple view for basic on/off bulbs
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 60))
        
        // Toggle button
        let toggleLabel = NSTextField()
        toggleLabel.frame = NSRect(x: 20, y: 20, width: 200, height: 20)
        toggleLabel.isEditable = false
        toggleLabel.isBordered = false
        toggleLabel.backgroundColor = NSColor.clear
        toggleLabel.font = NSFont.menuFont(ofSize: 14)
        toggleLabel.alignment = .center
        toggleLabel.isSelectable = false
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(toggleLabelClicked(_:)))
        toggleLabel.addGestureRecognizer(clickGesture)
        containerView.addSubview(toggleLabel)
        self.toggleButton = toggleLabel
        
        self.view = containerView
        
        // Get initial state
        if let currentState = DeviceStateManager.shared.getDeviceState(for: deviceUUID) {
            isOn = currentState.isOn
            updateToggleButtonState()
        }
        
        // Request current HomeKit values
        if let onOffUUID = onOffUUID {
            mac2ios?.readCharacteristic(of: onOffUUID)
        }
    }
    
    @objc private func toggleLabelClicked(_ sender: NSClickGestureRecognizer) {
        togglePower()
    }
    
    private func togglePower() {
        guard let onOffUUID = onOffUUID else { return }
        
        let newState = !isOn
        mac2ios?.setCharacteristic(of: onOffUUID, object: newState)
        
        isOn = newState
        DeviceStateManager.shared.updateDeviceState(
            deviceUUID: deviceUUID,
            characteristicUUID: onOffUUID,
            value: newState,
            valueType: .on
        )
        
        updateToggleButtonState()
    }
    
    private func updateToggleButtonState() {
        guard let toggleLabel = toggleButton else { return }
        
        if isOn {
            toggleLabel.stringValue = "Turn Off"
            toggleLabel.textColor = NSColor.controlAccentColor
        } else {
            toggleLabel.stringValue = "Turn On"
            toggleLabel.textColor = NSColor.labelColor
        }
    }
    
    // MARK: - MenuItemFromUUID Implementation
    func bind(with uniqueIdentifier: UUID) -> Bool {
        return onOffUUID == uniqueIdentifier
    }
    
    func UUIDs() -> [UUID] {
        return onOffUUID.map { [$0] } ?? []
    }
    
    // MARK: - StateObserver Implementation
    public func deviceStateDidChange(deviceUUID: UUID, state: DeviceState) {
        isOn = state.isOn
        updateToggleButtonState()
    }
}

// MARK: - Switch Menu Item
class SwitchMenuItem: ToggleMenuItem {
    override init(serviceInfo: ServiceInfoProtocol, mac2ios: mac2iOS?) {
        super.init(serviceInfo: serviceInfo, mac2ios: mac2ios)
        self.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: nil)
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Outlet Menu Item
class OutletMenuItem: ToggleMenuItem {
    override init(serviceInfo: ServiceInfoProtocol, mac2ios: mac2iOS?) {
        super.init(serviceInfo: serviceInfo, mac2ios: mac2ios)
        self.image = NSImage(systemSymbolName: "poweroutlet.type.b", accessibilityDescription: nil)
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

import Foundation
import AppKit
import os
import OSLog

@objc(MacOSController)
public class MacOSController: NSObject, @preconcurrency iOS2Mac, NSMenuDelegate {
    let mainMenu = NSMenu()
    public var iosListener: mac2iOS?
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    private var appearanceObserver: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    
    public required override init() {
        super.init()
        
        // Setup default settings if this is the first time
        SharedUtilities.setupDefaultSettingsIfNeeded()
        updateStatusItemIcon()



        
        self.statusItem.menu = mainMenu
        mainMenu.delegate = self
        // Block-based NotificationCenter observers with stored tokens
        notificationTokens.append(
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] note in
                self?.didChangeUserDefaults(notification: note)
            }
        )
        notificationTokens.append(
            NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] note in
                self?.settingsChanged(note)
            }
        )
        notificationTokens.append(
            NotificationCenter.default.addObserver(forName: .reloadFromHomeKit, object: nil, queue: .main) { [weak self] note in
                self?.reloadFromHomeKit(note)
            }
        )
        
        // Clean up any unwanted UIKit windows that Catalyst might create
        Task { @MainActor in
            self.cleanupUnwantedUIWindows()
        }
        
        
        // Also use KVO on NSApp.effectiveAppearance for more reliable detection
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, change in
            self?.handleAppearanceChange(change.newValue)
        }
        
    }
    
    deinit {
        // Remove block-based tokens
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        appearanceObserver?.invalidate()
    }
    
    // MARK: - NSMenuDelegate
    
    public func menuWillOpen(_ menu: NSMenu) {
        if menu == mainMenu {
            let items = NSMenu.getSubItems(menu: menu)
                .compactMap { $0 as? MenuItemFromUUID }
                .flatMap { $0.UUIDs() }
            
            for uniqueIdentifider in items {
                iosListener?.readCharacteristic(of: uniqueIdentifider)
            }
        }
    }
    
    // MARK: - Reload menu items
    
    @MainActor
    public func reloadMenuExtra() {
        // Proactively cleanup observers/timers from existing menu items before teardown
        let existingItems = NSMenu.getSubItems(menu: mainMenu)
        for item in existingItems {
            // Call cleanupOnRemoval if the item provides it
            if let cleanupItem = item as? ToggleMenuItem {
                cleanupItem.cleanupOnRemoval()
            } else if let cleanupItem = item as? UnifiedAdaptiveMenuItem {
                cleanupItem.cleanupOnRemoval()
            } else if let cleanupItem = item as? SimpleToggleMenuItem {
                cleanupItem.cleanupOnRemoval()
            } else if let cleanupItem = item as? AdaptiveLightbulbMenuItem {
                cleanupItem.cleanupOnRemoval()
            }
        }
        
        mainMenu.removeAllItems()
        reloadHomeKitMenuItems()
        reloadEachRooms()
        reloadOtherItems()
        
        // Menu items are reloaded above; nothing else to do here.
    }
    
    @MainActor
    func reloadHomeKitMenuItems() {
        // Reload and test items removed for cleaner interface
        mainMenu.addItem(NSMenuItem.separator())
    }
    
    // Duplicate legacy implementation of reloadEachRooms removed. A newer deduplicated version exists below.
    
    @MainActor
    func reloadSceneItems() {
        guard let actionSets = self.iosListener?.actionSets else {
            return
        }
        
        // Get hidden scene IDs from settings
        let hiddenSceneIDs = Set(UserDefaults.standard.array(forKey: SharedUtilities.SettingsKeys.hiddenScenes) as? [String] ?? [])
        
        // Filter out hidden scenes
        let visibleActionSets = actionSets.filter { !hiddenSceneIDs.contains($0.uniqueIdentifier.uuidString) }
        
        
        if !visibleActionSets.isEmpty {
            // Add a separator before scenes
            mainMenu.addItem(NSMenuItem.separator())
            
            // Add scenes header
            let scenesHeaderItem = NSMenuItem()
            scenesHeaderItem.title = "Scenes"
            scenesHeaderItem.isEnabled = false
            mainMenu.addItem(scenesHeaderItem)
            
            // Add each visible scene
            for actionSet in visibleActionSets {
                let sceneItem = NSMenuItem()
                sceneItem.title = actionSet.name
                sceneItem.action = #selector(activateScene(_:))
                sceneItem.target = self
                sceneItem.representedObject = actionSet.uniqueIdentifier.uuidString
                
                // Set custom icon if available
                let sceneUUID = actionSet.uniqueIdentifier.uuidString
                if let customIcon = getSceneIcon(for: sceneUUID) {
                    sceneItem.image = NSImage(systemSymbolName: customIcon, accessibilityDescription: nil)
                }
                
                mainMenu.addItem(sceneItem)
            }
        }
        
    }
    
    @objc private func activateScene(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let uuid = UUID(uuidString: uuidString) else {
            HMLog.error(.menu, "Invalid scene UUID")
            return
        }
        
        iosListener?.executeActionSet(uniqueIdentifier: uuid)
    }
    
    // MARK: - All Home / Room Controls
    
    @objc private func allHomeOn(_ sender: NSMenuItem) {
        setAllHomeState(true)
    }
    
    @objc private func allHomeOff(_ sender: NSMenuItem) {
        setAllHomeState(false)
    }
    
    @MainActor
    private func addRoomAllControl(room: RoomInfoProtocol, accessories: [AccessoryInfoProtocol]) {
        // Create "Toggle All" menu item with submenu
        let toggleAllItem = NSMenuItem(title: "Toggle All", action: nil, keyEquivalent: "")
        toggleAllItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        
        // Create submenu with On/Off options
        let submenu = NSMenu()
        
        let onItem = NSMenuItem(title: "On", action: #selector(roomAllOn(_:)), keyEquivalent: "")
        onItem.target = self
        onItem.representedObject = room.uniqueIdentifier.uuidString
        
        let offItem = NSMenuItem(title: "Off", action: #selector(roomAllOff(_:)), keyEquivalent: "")
        offItem.target = self
        offItem.representedObject = room.uniqueIdentifier.uuidString
        
        submenu.addItem(onItem)
        submenu.addItem(offItem)
        
        toggleAllItem.submenu = submenu
        mainMenu.addItem(toggleAllItem)
    }
    
    @objc private func roomAllOn(_ sender: NSMenuItem) {
        guard let roomUUID = sender.representedObject as? String else { return }
        setRoomAllState(roomUUID: roomUUID, state: true)
    }
    
    @objc private func roomAllOff(_ sender: NSMenuItem) {
        guard let roomUUID = sender.representedObject as? String else { return }
        setRoomAllState(roomUUID: roomUUID, state: false)
    }
    
    private func setAllHomeState(_ state: Bool) {
        guard let accessories = iosListener?.accessories else { return }
        
        var characteristicsToSet: [UUID] = []
        var deviceUUIDs: [UUID] = []
        
        for accessory in accessories {
            for service in accessory.services {
                if isServiceSupported(service) && !isDeviceHidden(service.uniqueIdentifier.uuidString) {
                    if let onOffChar = SharedUtilities.findCharacteristic(by: .on, in: service.characteristics) {
                        characteristicsToSet.append(onOffChar)
                        deviceUUIDs.append(service.uniqueIdentifier)
                    }
                }
            }
        }
        
        // Update centralized state manager immediately for responsive UI
        for (index, characteristicUUID) in characteristicsToSet.enumerated() {
            if index < deviceUUIDs.count {
                DeviceStateManager.shared.updateDeviceState(
                    deviceUUID: deviceUUIDs[index],
                    characteristicUUID: characteristicUUID,
                    value: state,
                    valueType: .on
                )
            }
        }
        
        // Send commands to HomeKit
        for characteristicUUID in characteristicsToSet {
            iosListener?.setCharacteristic(of: characteristicUUID, object: state)
        }
        
        HMLog.info(.homekit, "Set all home devices to \(state ? "ON" : "OFF")")
    }
    
    private func setRoomAllState(roomUUID: String, state: Bool) {
        guard let accessories = iosListener?.accessories else { return }
        
        var characteristicsToSet: [UUID] = []
        var deviceUUIDs: [UUID] = []
        
        for accessory in accessories {
            guard accessory.room?.uniqueIdentifier.uuidString == roomUUID else { continue }
            
            for service in accessory.services {
                if isServiceSupported(service) && !isDeviceHidden(service.uniqueIdentifier.uuidString) {
                    if let onOffChar = SharedUtilities.findCharacteristic(by: .on, in: service.characteristics) {
                        characteristicsToSet.append(onOffChar)
                        deviceUUIDs.append(service.uniqueIdentifier)
                    }
                }
            }
        }
        
        // Update centralized state manager immediately for responsive UI
        for (index, characteristicUUID) in characteristicsToSet.enumerated() {
            if index < deviceUUIDs.count {
                DeviceStateManager.shared.updateDeviceState(
                    deviceUUID: deviceUUIDs[index],
                    characteristicUUID: characteristicUUID,
                    value: state,
                    valueType: .on
                )
            }
        }
        
        // Send commands to HomeKit
        for characteristicUUID in characteristicsToSet {
            iosListener?.setCharacteristic(of: characteristicUUID, object: state)
        }
        
        HMLog.info(.homekit, "Set all devices in room \(roomUUID) to \(state ? "ON" : "OFF")")
    }
    
    @MainActor
    func reloadOtherItems() {
        // Add scenes if enabled
        if getShowScenesInMenuSetting() {
            reloadSceneItems()
        }
        
        // Status indicator removed for cleaner interface
        
        mainMenu.addItem(NSMenuItem.separator())
        
        let prefItem = NSMenuItem()
        prefItem.title = "Settings…"
        prefItem.action = #selector(MacOSController.preferences(sender:))
        prefItem.target = self
        mainMenu.addItem(prefItem)
        
        mainMenu.addItem(NSMenuItem.separator())
        
        let menuItem = NSMenuItem()
        menuItem.title = "Quit"
        menuItem.action = #selector(MacOSController.quit(sender:))
        menuItem.target = self
        mainMenu.addItem(menuItem)
    }
    
    private func getStatusText() -> String {
        let isConnected = iosListener != nil
        
        if isConnected {
            // Get status from iOS app through the listener
            let homeCount = iosListener?.homes.count ?? 0
            let accessoryCount = iosListener?.accessories.count ?? 0
            
            if homeCount > 0 {
                return "🟢 Connected • \(homeCount) home(s) • \(accessoryCount) device(s)"
            } else {
                return "🟢 Connected • No homes found"
            }
        } else {
            return "🔴 Disconnected"
        }
    }
    
    // MARK: - Actions
    
    private var settingsWindow: SettingsWindow?
    
    @IBAction func preferences(sender: Any?) {
        
        // Create or show settings window
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(iosListener: iosListener)
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    

    
    @IBAction func quit(sender: NSButton) {
        NSApplication.shared.terminate(self)
    }
    
    @IBAction func didChangeUserDefaults(notification: Notification) {
        reloadMenuExtra()
    }
    
    @objc private func effectiveAppearanceChanged(_ notification: Notification) {
        HMLog.uiDebug("Effective appearance changed notification received, updating icon...")
        updateStatusItemIcon()
    }
    
    private func handleAppearanceChange(_ appearance: NSAppearance?) {
        HMLog.uiDebug("KVO appearance change detected: \(appearance?.name.rawValue ?? "unknown")")
        updateStatusItemIcon()
    }
    
    private func updateStatusItemIcon() {
        guard let button = self.statusItem.button else { 
            HMLog.uiDebug("No status item button found")
            return 
        }
        
        let symbolName = "homekit"
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        
        HMLog.uiDebug("Updating icon - Current appearance: \(appearance?.rawValue ?? "unknown")")
        HMLog.uiDebug("NSApp.effectiveAppearance: \(NSApp.effectiveAppearance)")

        // Use multicolor only in dark mode
        let baseConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let config: NSImage.SymbolConfiguration

        if appearance == .darkAqua {
            config = baseConfig.applying(.preferringMulticolor())
            HMLog.uiDebug("Using multicolor config for dark mode")
        } else {
            config = baseConfig // no multicolor in light mode
            HMLog.uiDebug("Using standard config for light mode")
        }

        // Create image with desired config
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)

        if let image = image {
            guard let finalImage = image.copy() as? NSImage else {
                button.image = image
                return
            }
            
            if appearance == .aqua {
                // Light mode: use template mode for proper black rendering
                finalImage.isTemplate = true
                HMLog.uiDebug("Set isTemplate = true for light mode")
            } else {
                // Dark mode: keep as is for multicolor
                finalImage.isTemplate = false
                HMLog.uiDebug("Set isTemplate = false for dark mode")
            }

            button.image = finalImage
            HMLog.uiDebug("Updated button image with template: \(finalImage.isTemplate)")
        } else {
            button.image = NSImage(systemSymbolName: "house", accessibilityDescription: nil)
        }
    }
    
    @objc func settingsChanged(_ notification: Notification) {
        Task { @MainActor in
            reloadMenuExtra()
        }
    }
    
    private var isReloading = false
    
    @objc private func reloadFromHomeKit(_ notification: Notification) {
        // Prevent multiple simultaneous reloads
        guard !isReloading else {
            HMLog.info(.menu, "Reload already in progress, skipping...")
            return
        }
        
        isReloading = true
        HMLog.info(.homekit, "Reloading from HomeKit...")
        
        Task { @MainActor in
            defer { isReloading = false }
            
            // Request fresh data from HomeKit
            iosListener?.fetchFromHomeKitAndReloadMenuExtra()
            
            // Refresh the settings window if it's open
            if let settingsWindow = settingsWindow, settingsWindow.isVisible {
                settingsWindow.refreshDeviceAndSceneLists()
            }
            
            HMLog.info(.homekit, "HomeKit reload completed")
        }
    }
    
    // MARK: - Settings Helper Methods
    
    private func getGroupByRoomSetting() -> Bool {
        return SharedUtilities.getGroupByRoomSetting()
    }
    
    private func getShowRoomNamesSetting() -> Bool {
        return SharedUtilities.getShowRoomNamesSetting()
    }
    
    private func getShowAllHomeControlSetting() -> Bool {
        return SharedUtilities.getShowAllHomeControlSetting()
    }
    
    private func getShowRoomAllControlsSetting() -> Bool {
        return SharedUtilities.getShowRoomAllControlsSetting()
    }
    
    // MARK: - Home Selection
    
    @MainActor
    private func addHomeSelectionToSubmenu(_ submenu: NSMenu) {
        guard let homes = iosListener?.homes, homes.count > 1 else { return }
        
        // Add home selection header
        let headerItem = NSMenuItem(title: "Select Home:", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        submenu.addItem(headerItem)
        
        // Add each home as a selectable option
        for home in homes {
            let homeItem = NSMenuItem(title: home.name, action: #selector(switchHome(_:)), keyEquivalent: "")
            homeItem.target = self
            homeItem.representedObject = home.uniqueIdentifier
            
            // Show checkmark for current home
            if home.uniqueIdentifier == iosListener?.homeUniqueIdentifier {
                homeItem.state = .on
            }
            
            submenu.addItem(homeItem)
        }
    }
    
    @objc private func switchHome(_ sender: NSMenuItem) {
        guard let homeUUID = sender.representedObject as? UUID else {
            HMLog.error(.menu, "Invalid home UUID in switchHome")
            return
        }
        
        HMLog.menuDebug("Switching to home with UUID: \(homeUUID)")
        
        // Update the selected home
        iosListener?.homeUniqueIdentifier = homeUUID
        
        // Post notification that home has changed
        NotificationCenter.default.post(
            name: .homeChanged,
            object: nil,
            userInfo: ["homeUUID": homeUUID.uuidString]
        )
        
        // Refresh the menu with the new home's devices
        iosListener?.fetchFromHomeKitAndReloadMenuExtra()
    }
    
    @MainActor
    private func addAllHomeControl(accessories: [AccessoryInfoProtocol]) {
        // Create "All Home" menu item with submenu
        let allHomeItem = NSMenuItem(title: "Home", action: nil, keyEquivalent: "")
        allHomeItem.image = NSImage(systemSymbolName: "house", accessibilityDescription: nil)
        
        // Create submenu with On/Off options
        let submenu = NSMenu()
        
        // Add toggle current home label
        let toggleLabel = NSMenuItem(title: "Toggle Current Home:", action: nil, keyEquivalent: "")
        toggleLabel.isEnabled = false
        submenu.addItem(toggleLabel)
        
        let onItem = NSMenuItem(title: "On", action: #selector(allHomeOn(_:)), keyEquivalent: "")
        onItem.target = self
        
        let offItem = NSMenuItem(title: "Off", action: #selector(allHomeOff(_:)), keyEquivalent: "")
        offItem.target = self
        
        submenu.addItem(onItem)
        submenu.addItem(offItem)
        
        // Add home selection at the bottom if there are multiple homes
        if let homes = iosListener?.homes, homes.count > 1 {
            submenu.addItem(NSMenuItem.separator())
            addHomeSelectionToSubmenu(submenu)
        }
        
        allHomeItem.submenu = submenu
        mainMenu.addItem(allHomeItem)
        
        // Add separator after All Home control
        mainMenu.addItem(NSMenuItem.separator())
    }
    
    @MainActor
    func reloadEachRooms() {
        guard let accessories = self.iosListener?.accessories else {
            HMLog.menuDebug("No accessories available from iOS listener")
            return
        }
        guard let rooms = self.iosListener?.rooms else {
            HMLog.menuDebug("No rooms available from iOS listener")
            return
        }

        // Add All Home control if enabled
        if getShowAllHomeControlSetting() {
            addAllHomeControl(accessories: accessories)
        }

        // Revert to room-grouped rendering and place sensors at the bottom of each room section.
        // Classification is still service-based, but rendering is per room for both devices and sensors.

        // Helper to build menu items for a set of services in an accessory
        func buildMenuItems(from accessories: [AccessoryInfoProtocol]) -> [NSMenuItem] {
            var items: [NSMenuItem] = []
            for accessory in accessories {
                for serviceInfo in accessory.services {
                    if isServiceSupported(serviceInfo) && !isDeviceHidden(serviceInfo.uniqueIdentifier.uuidString) {
                        let created = NSMenuItem.HomeMenus(serviceInfo: serviceInfo, mac2ios: iosListener).compactMap { $0 }
                        items.append(contentsOf: created)
                    }
                }
            }
            return items
        }

        let groupByRoom = getGroupByRoomSetting()
        let showRoomNames = getShowRoomNamesSetting()

        // Define helpers to classify services on a service type basis
        func isDeviceService(_ service: ServiceInfoProtocol) -> Bool {
            HMLog.menuDebug("isDeviceService: checking service \(service.name)")
            
            // First check if the service is already identified as a device type
            if let si = service as? ServiceInfo {
                HMLog.menuDebug("isDeviceService: successfully cast to ServiceInfo, type: \(si.type.rawValue)")
                switch si.type {
                case .lightbulb, .switch, .outlet:
                    HMLog.menuDebug("isDeviceService: \(service.name) - identified as device by type")
                    return true
                case .unknown:
                    // Fall through to characteristic-based inference
                    HMLog.menuDebug("isDeviceService: \(service.name) - unknown type, will infer from characteristics")
                default:
                    HMLog.menuDebug("isDeviceService: \(service.name) - not a device type")
                    return false
                }
            } else {
                HMLog.menuDebug("isDeviceService: failed to cast \(service.name) to ServiceInfo, will infer from characteristics")
            }
            
            // Always try to infer the type from characteristics since type info is lost during data transfer
            HMLog.menuDebug("isDeviceService: \(service.name) - attempting inference from characteristics")
            let inferredType = SharedUtilities.inferServiceType(from: service)
            HMLog.menuDebug("isDeviceService: \(service.name) inferred type: \(inferredType.rawValue)")
            
            switch inferredType {
            case .lightbulb, .switch, .outlet:
                HMLog.menuDebug("isDeviceService: \(service.name) - identified as device by inference")
                // Also update the service type for future use if possible
                if let si = service as? ServiceInfo {
                    si.setType(inferredType)
                    HMLog.menuDebug("isDeviceService: \(service.name) - updated type to \(inferredType.rawValue)")
                }
                return true
            default:
                HMLog.menuDebug("isDeviceService: \(service.name) - not a device type by inference")
                return false
            }
        }
        func isSensorService(_ service: ServiceInfoProtocol) -> Bool {
            HMLog.menuDebug("isSensorService: checking service \(service.name)")
            
            // First check if the service is already identified as a sensor type
            if let si = service as? ServiceInfo {
                HMLog.menuDebug("isSensorService: successfully cast to ServiceInfo, type: \(si.type.rawValue)")
                switch si.type {
                case .temperatureSensor, .humiditySensor, .lightSensor, .airQualitySensor:
                    HMLog.menuDebug("isSensorService: \(service.name) - identified as sensor by type")
                    return true
                case .unknown:
                    // Fall through to characteristic-based inference
                    HMLog.menuDebug("isSensorService: \(service.name) - unknown type, will infer from characteristics")
                default:
                    HMLog.menuDebug("isSensorService: \(service.name) - not a sensor type")
                    return false
                }
            } else {
                HMLog.menuDebug("isSensorService: failed to cast \(service.name) to ServiceInfo, will infer from characteristics")
            }
            
            // Always try to infer the type from characteristics since type info is lost during data transfer
            HMLog.menuDebug("isSensorService: \(service.name) - attempting inference from characteristics")
            let inferredType = SharedUtilities.inferServiceType(from: service)
            HMLog.menuDebug("isSensorService: \(service.name) inferred type: \(inferredType.rawValue)")
            
            switch inferredType {
            case .temperatureSensor, .humiditySensor, .lightSensor, .airQualitySensor:
                HMLog.menuDebug("isSensorService: \(service.name) - identified as sensor by inference")
                // Also update the service type for future use if possible
                if let si = service as? ServiceInfo {
                    si.setType(inferredType)
                    HMLog.menuDebug("isSensorService: \(service.name) - updated type to \(inferredType.rawValue)")
                }
                return true
            default:
                HMLog.menuDebug("isSensorService: \(service.name) - not a sensor type by inference")
                return false
            }
        }

        // Room-grouped rendering: devices first, then sensors at bottom of each room
        if groupByRoom {
            for room in rooms {
                var buffer: [NSMenuItem] = []

                // Select accessories in this room
                let roomAccessories = accessories.filter { $0.room?.uniqueIdentifier == room.uniqueIdentifier }

                // Split services into device vs sensor per accessory
                var deviceItems: [NSMenuItem] = []
                var sensorItems: [NSMenuItem] = []

                for accessory in roomAccessories {
                    // Collect device services
                    let deviceServices = accessory.services.filter { isServiceSupported($0) && isDeviceService($0) && !isDeviceHidden($0.uniqueIdentifier.uuidString) }
                    for svc in deviceServices {
                        let created = NSMenuItem.HomeMenus(serviceInfo: svc, mac2ios: iosListener).compactMap { $0 }
                        deviceItems.append(contentsOf: created)
                        
                        // Request current values for newly created menu items
                        for item in created {
                            if let uuidItem = item as? MenuItemFromUUID {
                                for uuid in uuidItem.UUIDs() {
                                    HMLog.menuDebug("Requesting initial value for characteristic: \(uuid)")
                                    iosListener?.readCharacteristic(of: uuid)
                                }
                            }
                        }
                    }

                    // Collect sensor services
                    HMLog.menuDebug("Room \(room.name): Processing \(accessory.services.count) services for accessory \(accessory.name)")
                    for svc in accessory.services {
                        HMLog.menuDebug("Room \(room.name): Service \(svc.name) - isServiceSupported: \(isServiceSupported(svc)), isSensorService: \(isSensorService(svc)), isHidden: \(isDeviceHidden(svc.uniqueIdentifier.uuidString))")
                    }
                    let sensorServices = accessory.services.filter { isServiceSupported($0) && isSensorService($0) && !isDeviceHidden($0.uniqueIdentifier.uuidString) }
                    HMLog.menuDebug("Room \(room.name): Found \(sensorServices.count) sensor services for accessory \(accessory.name)")
                    for svc in sensorServices {
                        HMLog.menuDebug("Processing sensor service: \(svc.name) (UUID: \(svc.uniqueIdentifier))")
                        // Try specialized factory first
                        var created = NSMenuItem.HomeMenus(serviceInfo: svc, mac2ios: iosListener).compactMap { $0 }
                        HMLog.menuDebug("Factory created \(created.count) menu items for sensor \(svc.name)")

                        // If factory returns nothing (common for sensor types), create SensorMenuItem explicitly
                        if created.isEmpty, let sInfo = svc as? ServiceInfo {
                            HMLog.menuDebug("Creating SensorMenuItem explicitly for \(svc.name)")
                            created = [SensorMenuItem(serviceInfo: sInfo, mac2ios: iosListener)]
                        }

                        // As a final fallback, render a basic NSMenuItem with service name to avoid dropping sensors
                        if created.isEmpty {
                            HMLog.menuDebug("Creating fallback menu item for sensor \(svc.name)")
                            let fallback = NSMenuItem(title: svc.name, action: nil, keyEquivalent: "")
                            created = [fallback]
                        }

                        sensorItems.append(contentsOf: created)
                        
                        // Request current values for newly created sensor menu items
                        for item in created {
                            if let uuidItem = item as? MenuItemFromUUID {
                                for uuid in uuidItem.UUIDs() {
                                    HMLog.menuDebug("Requesting initial value for sensor characteristic: \(uuid)")
                                    iosListener?.readCharacteristic(of: uuid)
                                }
                            }
                        }
                    }
                }

                // If there are no devices but there are sensors, we still want to show the room header.
                let hasAnyContent = (!deviceItems.isEmpty || !sensorItems.isEmpty)

                if showRoomNames && hasAnyContent {
                    let roomNameItem = NSMenuItem()
                    roomNameItem.title = room.name
                    roomNameItem.isEnabled = false
                    buffer.append(roomNameItem)
                }

                // Append devices first
                buffer.append(contentsOf: deviceItems)

                // Optional room-level controls after devices
                if !deviceItems.isEmpty, getShowRoomAllControlsSetting() {
                    addRoomAllControl(room: room, accessories: roomAccessories)
                }

                // Then sensors at the bottom of the room device list
                if !sensorItems.isEmpty {
                    HMLog.menuDebug("Adding \(sensorItems.count) sensor items to room \(room.name)")
                    sensorItems.forEach { buffer.append($0) }
                }

                // Flush this room if it has any content at all
                if hasAnyContent {
                    buffer.forEach { mainMenu.addItem($0) }
                    mainMenu.addItem(NSMenuItem.separator())
                }
            }
        } else {
            // Flat rendering without grouping: show all devices first, then all sensors
            var deviceItems: [NSMenuItem] = []
            var sensorItems: [NSMenuItem] = []

            for accessory in accessories {
                for svc in accessory.services {
                    guard isServiceSupported(svc), !isDeviceHidden(svc.uniqueIdentifier.uuidString) else { continue }
                    if isDeviceService(svc) {
                        let created = NSMenuItem.HomeMenus(serviceInfo: svc, mac2ios: iosListener).compactMap { $0 }
                        deviceItems.append(contentsOf: created)
                        
                        // Request current values for newly created device menu items in flat mode
                        for item in created {
                            if let uuidItem = item as? MenuItemFromUUID {
                                for uuid in uuidItem.UUIDs() {
                                    HMLog.menuDebug("Requesting initial value for device characteristic in flat mode: \(uuid)")
                                    iosListener?.readCharacteristic(of: uuid)
                                }
                            }
                        }
                    } else if isSensorService(svc) {
                        HMLog.menuDebug("Processing sensor service in flat mode: \(svc.name) (UUID: \(svc.uniqueIdentifier))")
                        var created = NSMenuItem.HomeMenus(serviceInfo: svc, mac2ios: iosListener).compactMap { $0 }
                        HMLog.menuDebug("Factory created \(created.count) menu items for sensor \(svc.name) in flat mode")
                        if created.isEmpty, let sInfo = svc as? ServiceInfo {
                            HMLog.menuDebug("Creating SensorMenuItem explicitly for \(svc.name) in flat mode")
                            created = [SensorMenuItem(serviceInfo: sInfo, mac2ios: iosListener)]
                        }
                        if created.isEmpty {
                            HMLog.menuDebug("Creating fallback menu item for sensor \(svc.name) in flat mode")
                            let fallback = NSMenuItem(title: svc.name, action: nil, keyEquivalent: "")
                            created = [fallback]
                        }
                        sensorItems.append(contentsOf: created)
                        
                        // Request current values for newly created sensor menu items in flat mode
                        for item in created {
                            if let uuidItem = item as? MenuItemFromUUID {
                                for uuid in uuidItem.UUIDs() {
                                    HMLog.menuDebug("Requesting initial value for sensor characteristic in flat mode: \(uuid)")
                                    iosListener?.readCharacteristic(of: uuid)
                                }
                            }
                        }
                    }
                }
            }

            if !deviceItems.isEmpty {
                deviceItems.forEach { mainMenu.addItem($0) }
            }
            if !sensorItems.isEmpty {
                HMLog.menuDebug("Adding \(sensorItems.count) sensor items in flat mode")
                sensorItems.forEach { mainMenu.addItem($0) }
            }
            if !deviceItems.isEmpty || !sensorItems.isEmpty {
                mainMenu.addItem(NSMenuItem.separator())
            }
        }
    }
    
    private func getShowScenesInMenuSetting() -> Bool {
        return SharedUtilities.getShowScenesInMenuSetting()
    }
    
    private func getShowAllScenesSetting() -> Bool {
        // Deprecated: using ShowScenesInMenu as "all scenes" toggle; keep for backward compatibility if referenced elsewhere.
        return SharedUtilities.getShowScenesInMenuSetting()
    }
    
    private func getHiddenDeviceIDs() -> Set<String> {
        if let hiddenDevicesArray = UserDefaults.standard.array(forKey: SharedUtilities.SettingsKeys.hiddenDevices) as? [String] {
            return Set(hiddenDevicesArray)
        }
        return Set()
    }
    
    private func isDeviceHidden(_ deviceID: String) -> Bool {
        return SharedUtilities.isDeviceHidden(deviceID)
    }
    
    private func getSceneIcon(for sceneUUID: String) -> String? {
        if let sceneIconsDict = UserDefaults.standard.dictionary(forKey: SharedUtilities.SettingsKeys.sceneIcons) as? [String: String] {
            return sceneIconsDict[sceneUUID]
        }
        return nil
    }
    
    private func isServiceSupported(_ service: ServiceInfoProtocol) -> Bool {
        return SharedUtilities.isServiceSupported(service)
    }
    

    
    // MARK: - Menu Item Updates
    
    /// Update menu items related to a specific characteristic UUID when its value changes
    /// This method is called when HomeKit characteristic values are updated
    @MainActor
    public func updateMenuItemsRelated(to characteristicUUID: UUID, value: Any) {
        HMLog.menuDebug("updateMenuItemsRelated called for UUID: \(characteristicUUID), value: \(value)")
        
        // Get all menu items that can be updated
        let allItems = NSMenu.getSubItems(menu: mainMenu)
        
        for item in allItems {
            // Check if this item is bound to the characteristic UUID
            if let uuidItem = item as? MenuItemFromUUID {
                if uuidItem.bind(with: characteristicUUID) {
                    // Update sensor menu items specifically
                    if let sensorItem = item as? SensorMenuItem {
                        if sensorItem.isPrimaryBound(to: characteristicUUID) {
                            // Convert value to Double for sensor updates
                            if let doubleValue = value as? Double {
                                sensorItem.update(value: doubleValue)
                            } else if let intValue = value as? Int {
                                sensorItem.update(value: Double(intValue))
                            }
                        } else {
                            // Update air quality submenu values
                            sensorItem.updateAirQualityValue(for: characteristicUUID, value: value)
                        }
                    } else {
                        // For lamp menu items, update the DeviceStateManager so observers get notified
                        // Determine the characteristic type and update DeviceStateManager
                        if let toggleItem = item as? ToggleMenuItem {
                            // For on/off characteristic
                            if let boolValue = value as? Bool {
                                DeviceStateManager.shared.updateDeviceState(
                                    deviceUUID: toggleItem.deviceUUID,
                                    characteristicUUID: characteristicUUID,
                                    value: boolValue,
                                    valueType: .on
                                )
                            }
                        } else if let adaptiveItem = item as? AdaptiveLightbulbMenuItem {
                            // For adaptive lightbulb characteristics, use the stored characteristic type mapping
                            if let doubleValue = value as? Double {
                                // Get the characteristic type from the stored mapping
                                if let characteristicType = adaptiveItem.getCharacteristicType(for: characteristicUUID) {
                                    DeviceStateManager.shared.updateDeviceState(
                                        deviceUUID: adaptiveItem.deviceUUID,
                                        characteristicUUID: characteristicUUID,
                                        value: doubleValue,
                                        valueType: characteristicType
                                    )
                                }
                            } else if let boolValue = value as? Bool {
                                // For on/off characteristic
                                DeviceStateManager.shared.updateDeviceState(
                                    deviceUUID: adaptiveItem.deviceUUID,
                                    characteristicUUID: characteristicUUID,
                                    value: boolValue,
                                    valueType: .on
                                )
                            }
                        } else if let unifiedItem = item as? UnifiedAdaptiveMenuItem {
                            // For unified adaptive menu items
                            if let doubleValue = value as? Double {
                                // Get the characteristic type from the stored mapping
                                if let characteristicType = unifiedItem.getCharacteristicType(for: characteristicUUID) {
                                    DeviceStateManager.shared.updateDeviceState(
                                        deviceUUID: unifiedItem.deviceUUID,
                                        characteristicUUID: characteristicUUID,
                                        value: doubleValue,
                                        valueType: characteristicType
                                    )
                                }
                            } else if let boolValue = value as? Bool {
                                // For on/off characteristic
                                DeviceStateManager.shared.updateDeviceState(
                                    deviceUUID: unifiedItem.deviceUUID,
                                    characteristicUUID: characteristicUUID,
                                    value: boolValue,
                                    valueType: .on
                                )
                            }
                        } else if let simpleItem = item as? SimpleToggleMenuItem {
                            // For simple toggle menu items
                            if let boolValue = value as? Bool {
                                DeviceStateManager.shared.updateDeviceState(
                                    deviceUUID: simpleItem.deviceUUID,
                                    characteristicUUID: characteristicUUID,
                                    value: boolValue,
                                    valueType: .on
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Connection Management
    
    private func checkConnection() {
        if iosListener == nil {
            HMLog.info(.app, "iOS listener is nil - menu may not be functional")
        } else {
        }
    }
    
    public func ensureConnection() {
        checkConnection()
        // Try to reload the menu to ensure it's functional
        Task { @MainActor in
            reloadMenuExtra()
        }
    }
    
    // MARK: - Window Management
    
    @MainActor
    private func cleanupUnwantedUIWindows() {
        
        NSApplication.shared.windows.forEach { window in
            let name = "\(type(of: window))"
            
            if name == "UINSWindow" {
                window.close()
                
                // Get the UI windows and close them through iOS listener
                let uiWindows = window.value(forKeyPath: "uiWindows") as? [Any] ?? []
                if !uiWindows.isEmpty {
                    iosListener?.close(windows: uiWindows)
                }
            }
        }
        
        // Schedule periodic cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.periodicWindowCleanup()
        }
    }
    
    @MainActor
    private func periodicWindowCleanup() {
        // Perform periodic cleanup every 5 seconds
        NSApplication.shared.windows.forEach { window in
            let name = "\(type(of: window))"
            if name == "UINSWindow" {
                window.close()
            }
        }
        
        // Schedule next cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.periodicWindowCleanup()
        }
    }
}

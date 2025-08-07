import Foundation
import AppKit

class SettingsWindow: NSWindow, NSToolbarDelegate {
    
    // MARK: - Properties
    private var tabView: NSTabView?
    // Custom segmented control (capsule) to highlight the active tab in a native way
    private var tabSegmentedControl: NSSegmentedControl?
    private enum ToolbarItemID: String {
        case menu = "settings.menu"
        case scenes = "settings.scenes"
        case devices = "settings.devices"
    }
    
    private var iosListener: mac2iOS?
    private var scenesListContainerView: NSView?
    private var devicesListContainerView: NSView?
    private var hiddenDeviceIDs: Set<String> = Set()
    private var hiddenSceneIDs: Set<String> = Set()
    private var sceneButtonUUIDs: [Int: String] = [:]  // Maps button tags to scene UUIDs
    private var sceneIcons: [String: String] = [:]  // Maps scene UUIDs to icon names
    
    // Settings Keys - Now using shared utilities
    private struct SettingsKeys {
        static let groupByRoom = SharedUtilities.SettingsKeys.groupByRoom
        static let showRoomNames = SharedUtilities.SettingsKeys.showRoomNames
        static let hiddenDevices = SharedUtilities.SettingsKeys.hiddenDevices
        static let showScenesInMenu = SharedUtilities.SettingsKeys.showScenesInMenu
        static let hiddenScenes = SharedUtilities.SettingsKeys.hiddenScenes
        static let sceneIcons = SharedUtilities.SettingsKeys.sceneIcons
        static let showAllHomeControl = SharedUtilities.SettingsKeys.showAllHomeControl
        static let showRoomAllControls = SharedUtilities.SettingsKeys.showRoomAllControls
    }
    
    // Layout Constants
    private let standardPadding: CGFloat = 20.0
    private let elementSpacing: CGFloat = 10.0
    private let sectionSpacing: CGFloat = 25.0
    private let checkboxIndent: CGFloat = 20.0
    private let sceneRowHeight: CGFloat = 60.0  // Increased height for icon picker
    private let sceneRowSpacing: CGFloat = 8.0
    private let contentWidth: CGFloat = 700.0
    
    // Available scene icons (SF Symbols)
    private let availableSceneIcons = [
        ("Play", "play.circle"),
        ("Theater", "theatermasks"),
        ("House", "house"),
        ("Moon", "moon"),
        ("Sun", "sun.max"),
        ("Music", "music.note"),
        ("Dining", "fork.knife"),
        ("TV", "tv"),
        ("Lightbulb", "lightbulb"),
        ("Bed", "bed.double"),
        ("Car", "car"),
        ("Temperature", "thermometer"),
        ("Lock", "lock"),
        ("Unlock", "lock.open"),
        ("Star", "star"),
        ("Heart", "heart"),
        ("Target", "target"),
        ("Flame", "flame"),
        ("Drop", "drop"),
        ("Leaf", "leaf"),
        ("Party", "party.popper"),
        ("Power", "power"),
        ("Timer", "timer"),
        ("Bell", "bell"),
        ("Shield", "shield"),
        ("Gear", "gear"),
        ("Camera", "camera"),
        ("Book", "book"),
        ("Gamecontroller", "gamecontroller"),
        ("Speaker", "speaker.wave.2")
    ]
    
    // MARK: - Initialization
    
    init(iosListener: mac2iOS?) {
        self.iosListener = iosListener
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Setup default settings if this is the first time
        SharedUtilities.setupDefaultSettingsIfNeeded()
        
        setupWindow()
        setupContent()
        loadSettings()
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        // Load hidden devices
        if let hiddenDevicesArray = UserDefaults.standard.array(forKey: SettingsKeys.hiddenDevices) as? [String] {
            hiddenDeviceIDs = Set(hiddenDevicesArray)
        }
        
        // Load hidden scenes
        if let hiddenScenesArray = UserDefaults.standard.array(forKey: SettingsKeys.hiddenScenes) as? [String] {
            hiddenSceneIDs = Set(hiddenScenesArray)
        }
        
        // Load scene icons
        if let sceneIconsDict = UserDefaults.standard.dictionary(forKey: SettingsKeys.sceneIcons) as? [String: String] {
            sceneIcons = sceneIconsDict
        }
    }
    
    private func getCurrentHomeName() -> String {
        guard let currentHomeUUID = iosListener?.homeUniqueIdentifier,
              let homes = iosListener?.homes,
              let currentHome = homes.first(where: { $0.uniqueIdentifier == currentHomeUUID }) else {
            return "Unknown Home"
        }
        return currentHome.name
    }
    
    private func filterDevicesForCurrentHome(_ devices: [AccessoryInfoProtocol]) -> [AccessoryInfoProtocol] {
        guard let currentHomeUUID = iosListener?.homeUniqueIdentifier else {
            return devices
        }
        
        return devices.filter { accessory in
            guard let accessoryHome = accessory.home else { return false }
            return accessoryHome.uniqueIdentifier == currentHomeUUID
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(Array(hiddenDeviceIDs), forKey: SettingsKeys.hiddenDevices)
        UserDefaults.standard.set(Array(hiddenSceneIDs), forKey: SettingsKeys.hiddenScenes)
        UserDefaults.standard.set(sceneIcons, forKey: SettingsKeys.sceneIcons)
    }
    
    // MARK: - Public Settings Accessors
    
    var groupByRoom: Bool {
        return SharedUtilities.getGroupByRoomSetting()
    }
    
    var showRoomNames: Bool {
        return SharedUtilities.getShowRoomNamesSetting()
    }
    
    var showScenesInMenu: Bool {
        return SharedUtilities.getShowScenesInMenuSetting()
    }
    
    var showAllHomeControl: Bool {
        return SharedUtilities.getShowAllHomeControlSetting()
    }
    
    var showRoomAllControls: Bool {
        return SharedUtilities.getShowRoomAllControlsSetting()
    }
    
    func isDeviceHidden(_ deviceID: String) -> Bool {
        return SharedUtilities.isDeviceHidden(deviceID)
    }
    
    func isSceneHidden(_ sceneID: String) -> Bool {
        return hiddenSceneIDs.contains(sceneID)
    }
    
    func getSceneIcon(_ sceneID: String) -> String? {
        return sceneIcons[sceneID]
    }
    
    // MARK: - Window Setup
    
    private func setupWindow() {
        title = "HomeMenuBar Settings"
        isReleasedWhenClosed = false
        center()
        titleVisibility = .hidden
        // Provide reasonable minimum/maximum sizes so the small “Menu” tab looks right
        minSize = NSSize(width: 520, height: 360)
        maxSize = NSSize(width: 1200, height: 900)
        if #available(macOS 11.0, *) {
            toolbarStyle = .preference
            let tb = NSToolbar(identifier: "SettingsToolbar")
            tb.showsBaselineSeparator = true // native bottom separator
            tb.delegate = self as NSToolbarDelegate
            tb.displayMode = .iconAndLabel
            tb.allowsUserCustomization = false
            tb.sizeMode = .default
            self.toolbar = tb
        }
        
        // Add observer for when window becomes active to refresh home information
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(homeDidChange),
            name: .homeChanged,
            object: nil
        )
        
        // Add observer for home changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(homeDidChange),
            name: .homeChanged,
            object: nil
        )
    }
    
    @objc private func windowDidBecomeActive() {
        // Refresh content when window becomes active to show current home information
        self.refreshContent()
    }
    
    @objc private func homeDidChange(_ notification: Notification) {
        // Refresh content when home changes
        HMLog.menuDebug("SettingsWindow: Home changed, refreshing content")
        DispatchQueue.main.async { [weak self] in
            self?.refreshContent()
        }
    }
    
    // MARK: - Content Setup
    
    private func setupContent() {
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .noTabsNoBorder
        self.tabView = tabView
        
        // Merge Home (Menu) + Devices into a single "Home" tab
        let homeTab = NSTabViewItem(identifier: ToolbarItemID.menu.rawValue)
        homeTab.label = "Home"
        homeTab.view = createHomeTabContent()
        
        let scenesTab = NSTabViewItem(identifier: ToolbarItemID.scenes.rawValue)
        scenesTab.label = "Scenes"
        scenesTab.view = createScenesTabContent()
        
        // Order: Home, Scenes
        tabView.addTabViewItem(homeTab)
        tabView.addTabViewItem(scenesTab)
        
        contentView = tabView
        
        if let contentView = contentView {
            NSLayoutConstraint.activate([
                tabView.topAnchor.constraint(equalTo: contentView.topAnchor),
                tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }
    
    // MARK: - Toolbar (NSToolbarDelegate)
    @available(macOS 11.0, *)
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("SettingsToolbar.SegmentedTabs"),
            .flexibleSpace
        ]
    }
    
    @available(macOS 11.0, *)
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Place capsule control aligned leading like native Preferences panes
        return [
            NSToolbarItem.Identifier("SettingsToolbar.SegmentedTabs"),
            .flexibleSpace
        ]
    }
    
    @available(macOS 11.0, *)
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier.rawValue == "SettingsToolbar.SegmentedTabs" else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        
        // Build a compact, capsule-style segmented control (more native)
        let seg = NSSegmentedControl(labels: ["Home", "Scenes"], trackingMode: .selectOne, target: self, action: #selector(segmentedChanged(_:)))
        seg.segmentStyle = .capsule
        seg.controlSize = .regular
        seg.translatesAutoresizingMaskIntoConstraints = false
        seg.selectedSegment = 0
        // Content hugging/compression for natural sizing
        seg.setContentHuggingPriority(.required, for: .horizontal)
        seg.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Make it a bit wider than intrinsic, but not too large
        for i in 0..<seg.segmentCount {
            seg.setWidth(100, forSegment: i)
        }
        self.tabSegmentedControl = seg
        // Wrap in a container view so we can add some leading padding to match native layouts
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(seg)
        NSLayoutConstraint.activate([
            seg.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            seg.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            seg.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            seg.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        item.view = container
        return item
    }
    
    @objc private func selectMenuTab() { selectTab(with: ToolbarItemID.menu.rawValue) }
    @objc private func selectScenesTab() { selectTab(with: ToolbarItemID.scenes.rawValue) }
    
    @objc private func segmentedChanged(_ sender: NSSegmentedControl) {
        // Map segment to identifiers in order: Menu (0), Devices (1), Scenes (2)
        let identifier: String
        switch sender.selectedSegment {
        case 0: identifier = ToolbarItemID.menu.rawValue // Home
        case 1: identifier = ToolbarItemID.scenes.rawValue
        default: identifier = ToolbarItemID.menu.rawValue
        }
        selectTab(with: identifier)
    }
    
    private func selectTab(with identifier: String) {
        guard let tabView = self.tabView else { return }
        let idx = tabView.indexOfTabViewItem(withIdentifier: identifier)
        if idx != NSNotFound {
            // Ensure the window is key and on top so traffic lights are active and toolbar can highlight
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            tabView.selectTabViewItem(at: idx)
            // Update custom segmented control selection for a clear, persistent highlight
            if let seg = self.tabSegmentedControl {
                switch identifier {
                case ToolbarItemID.menu.rawValue: seg.selectedSegment = 0
                case ToolbarItemID.scenes.rawValue: seg.selectedSegment = 1
                default: break
                }
            }
        }
    }

    // MARK: - Home Tab Content (merged Menu + Devices)
    
    private func createHomeTabContent() -> NSView {
        // Create a container view for the tab
        let containerView = NSView()
        // Use autoresizing instead of Auto Layout for the container
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]
        
        // Match native window background
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.windowBackgroundColor
        // Make the tab feel compact by limiting the document view height
        scrollView.contentView.postsBoundsChangedNotifications = true
        
        // Add scroll view to container and make it fill the container
        containerView.addSubview(scrollView)
        scrollView.frame = containerView.bounds
        scrollView.autoresizingMask = [.width, .height]
        
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        // Menu Organization Section (from Menu tab)
        let organizationLabel = createSectionHeader(title: "Menu Organization")
        let groupByRoomCheckbox = createCheckbox(
            title: "Group devices by room",
            state: SharedUtilities.getGroupByRoomSetting() ? .on : .off,
            target: self,
            action: #selector(self.menuSettingChanged)
        )
        groupByRoomCheckbox.tag = 1 // Tag to identify which setting
        
        let showRoomNamesCheckbox = createCheckbox(
            title: "Show room names",
            state: SharedUtilities.getShowRoomNamesSetting() ? .on : .off,
            target: self,
            action: #selector(menuSettingChanged)
        )
        showRoomNamesCheckbox.tag = 2 // Tag to identify which setting
        
        let showAllHomeCheckbox = createCheckbox(
            title: "Show All Home control",
            state: SharedUtilities.getShowAllHomeControlSetting() ? .on : .off,
            target: self,
            action: #selector(menuSettingChanged)
        )
        showAllHomeCheckbox.tag = 3 // Tag to identify which setting
        
        let showRoomAllCheckbox = createCheckbox(
            title: "Show room-level All controls",
            state: SharedUtilities.getShowRoomAllControlsSetting() ? .on : .off,
            target: self,
            action: #selector(menuSettingChanged)
        )
        showRoomAllCheckbox.tag = 4 // Tag to identify which setting
        
        // Home status + reload (from Menu tab)
        let currentHomeName = getCurrentHomeName()
        let homeInfoLabel = NSTextField(labelWithString: "Current Home: \(currentHomeName)")
        homeInfoLabel.font = NSFont.systemFont(ofSize: 12)
        homeInfoLabel.textColor = NSColor.secondaryLabelColor
        homeInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let reloadButton = createButton(title: "Reload from HomeKit", target: self, action: #selector(self.reloadFromHomeKit))
        reloadButton.controlSize = .small
        reloadButton.font = NSFont.systemFont(ofSize: 11)
        
        let homeHeaderStack = NSStackView(views: [homeInfoLabel, reloadButton])
        homeHeaderStack.orientation = .horizontal
        homeHeaderStack.alignment = .centerY
        homeHeaderStack.spacing = 10
        homeHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Devices list (from Devices tab)
        let devicesHeader = createSectionHeader(title: "Devices")
        let devicesInfo = NSTextField(labelWithString: "Show or hide devices from the menu")
        devicesInfo.font = NSFont.systemFont(ofSize: 12)
        devicesInfo.textColor = NSColor.secondaryLabelColor
        devicesInfo.translatesAutoresizingMaskIntoConstraints = false
        
        devicesListContainerView = NSView()
        devicesListContainerView?.translatesAutoresizingMaskIntoConstraints = false
        
        guard let devicesListContainer = devicesListContainerView else {
            HMLog.error(.ui, "Devices list container view is nil")
            return containerView
        }
        
        let devicesStack = NSStackView(views: [
            devicesHeader,
            devicesInfo,
            devicesListContainer
        ])
        devicesStack.orientation = .vertical
        devicesStack.alignment = .leading
        devicesStack.spacing = elementSpacing
        devicesStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Combined stack for entire "Home" tab
        let homeStack = NSStackView(views: [
            organizationLabel,
            groupByRoomCheckbox,
            showRoomNamesCheckbox,
            showAllHomeCheckbox,
            showRoomAllCheckbox,
            homeHeaderStack,
            devicesStack
        ])
        homeStack.orientation = .vertical
        homeStack.alignment = .leading
        homeStack.spacing = elementSpacing
        homeStack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        homeStack.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(homeStack)
        populateDevicesList()
        
        NSLayoutConstraint.activate([
            homeStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: standardPadding),
            homeStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: standardPadding),
            homeStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -standardPadding),
            homeStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -standardPadding),
            devicesListContainer.leadingAnchor.constraint(equalTo: homeStack.leadingAnchor),
            devicesListContainer.trailingAnchor.constraint(equalTo: homeStack.trailingAnchor),
            
            // Add checkbox indentation
            groupByRoomCheckbox.leadingAnchor.constraint(equalTo: homeStack.leadingAnchor, constant: checkboxIndent - standardPadding),
            showRoomNamesCheckbox.leadingAnchor.constraint(equalTo: homeStack.leadingAnchor, constant: checkboxIndent - standardPadding),
            showAllHomeCheckbox.leadingAnchor.constraint(equalTo: homeStack.leadingAnchor, constant: checkboxIndent - standardPadding),
            showRoomAllCheckbox.leadingAnchor.constraint(equalTo: homeStack.leadingAnchor, constant: checkboxIndent - standardPadding)
        ])
        
        scrollView.documentView = contentView
    
    // Pin contentView to the clip view so Auto Layout can size it
    let clip = scrollView.contentView
    let widthConstraint = contentView.widthAnchor.constraint(equalTo: clip.widthAnchor)
    widthConstraint.priority = NSLayoutConstraint.Priority(999) // High but not required
    
    let heightConstraint = contentView.heightAnchor.constraint(greaterThanOrEqualTo: clip.heightAnchor)
    heightConstraint.priority = NSLayoutConstraint.Priority(250) // Low priority to allow content to grow
    
    NSLayoutConstraint.activate([
        contentView.topAnchor.constraint(equalTo: clip.topAnchor),
        contentView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
        contentView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
        contentView.bottomAnchor.constraint(greaterThanOrEqualTo: clip.bottomAnchor),
        widthConstraint,
        heightConstraint
    ])
    
    return containerView
    }
    
    // Removed separate Devices tab; devices are shown in the merged Home tab.
    
    private func populateDevicesList() {
        guard let containerView = devicesListContainerView else {
            HMLog.error(.menu, "Devices list container view is nil")
            return
        }
        
        // Ensure settings are loaded before creating UI
        loadSettings()
        
        // Clear any existing subviews
        containerView.subviews.forEach { $0.removeFromSuperview() }
        
        let homeKitDevices = iosListener?.accessories ?? []
        
        // Filter devices for the current home
        let filteredDevices = filterDevicesForCurrentHome(homeKitDevices)
        
        // Create a list of individual services (like the menu bar does)
        // Devices tab should only show lightbulbs/lamps, not sensors.
        var individualServices: [(accessory: AccessoryInfoProtocol, service: ServiceInfoProtocol)] = []
        
        for device in filteredDevices {
            for service in device.services {
                if isServiceSupported(service) && SharedUtilities.isServiceLightbulb(service) {
                    individualServices.append((accessory: device, service: service))
                }
            }
        }
        
        // Filter out hidden services from supported services
        let visibleServices = individualServices.filter { !hiddenDeviceIDs.contains($0.service.uniqueIdentifier.uuidString) }
        let hiddenServices = individualServices.filter { hiddenDeviceIDs.contains($0.service.uniqueIdentifier.uuidString) }
        
        
        if visibleServices.isEmpty && hiddenServices.isEmpty {
            let noDevicesLabel = NSTextField(labelWithString: "No supported lightbulbs found\n(Only lightbulbs and lamps are supported)")
            noDevicesLabel.font = NSFont.systemFont(ofSize: 14)
            noDevicesLabel.textColor = NSColor.labelColor
            noDevicesLabel.alignment = .center
            noDevicesLabel.translatesAutoresizingMaskIntoConstraints = false
            noDevicesLabel.maximumNumberOfLines = 0
            containerView.addSubview(noDevicesLabel)
            
            NSLayoutConstraint.activate([
                noDevicesLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                noDevicesLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                noDevicesLabel.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: standardPadding),
                noDevicesLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -standardPadding)
            ])
        } else {
            var previousView: NSView?
            
            // First show visible services
            if !visibleServices.isEmpty {
                let visibleSectionLabel = createSectionLabel(title: "Visible Devices (\(visibleServices.count))")
                containerView.addSubview(visibleSectionLabel)
                
                NSLayoutConstraint.activate([
                    visibleSectionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    visibleSectionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    visibleSectionLabel.heightAnchor.constraint(equalToConstant: 30)
                ])
                
                if previousView == nil {
                    visibleSectionLabel.topAnchor.constraint(equalTo: containerView.topAnchor).isActive = true
                } else {
                    visibleSectionLabel.topAnchor.constraint(equalTo: previousView!.bottomAnchor, constant: sceneRowSpacing).isActive = true
                }
                previousView = visibleSectionLabel
                
                for (index, serviceData) in visibleServices.enumerated() {
                    let deviceRowView = createServiceRowView(accessory: serviceData.accessory, service: serviceData.service, index: index, isHidden: false)
                    containerView.addSubview(deviceRowView)
                    
                    NSLayoutConstraint.activate([
                        deviceRowView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                        deviceRowView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                        deviceRowView.heightAnchor.constraint(equalToConstant: sceneRowHeight)
                    ])
                    
                    deviceRowView.topAnchor.constraint(equalTo: previousView!.bottomAnchor, constant: sceneRowSpacing).isActive = true
                    previousView = deviceRowView
                }
            }
            
            // Then show hidden services if any
            if !hiddenServices.isEmpty {
                let hiddenSectionLabel = createSectionLabel(title: "Hidden Devices (\(hiddenServices.count))")
                containerView.addSubview(hiddenSectionLabel)
                
                NSLayoutConstraint.activate([
                    hiddenSectionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    hiddenSectionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    hiddenSectionLabel.heightAnchor.constraint(equalToConstant: 30)
                ])
                
                if previousView == nil {
                    hiddenSectionLabel.topAnchor.constraint(equalTo: containerView.topAnchor).isActive = true
                } else {
                    hiddenSectionLabel.topAnchor.constraint(equalTo: previousView!.bottomAnchor, constant: sectionSpacing).isActive = true
                }
                previousView = hiddenSectionLabel
                
                for (index, serviceData) in hiddenServices.enumerated() {
                    let deviceRowView = createServiceRowView(accessory: serviceData.accessory, service: serviceData.service, index: index + visibleServices.count, isHidden: true)
                    containerView.addSubview(deviceRowView)
                    
                    NSLayoutConstraint.activate([
                        deviceRowView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                        deviceRowView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                        deviceRowView.heightAnchor.constraint(equalToConstant: sceneRowHeight)
                    ])
                    
                    deviceRowView.topAnchor.constraint(equalTo: previousView!.bottomAnchor, constant: sceneRowSpacing).isActive = true
                    previousView = deviceRowView
                }
            }
            
            if let lastView = previousView {
                lastView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor).isActive = true
            }
        }
    }
    
    private func createSectionLabel(title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isBordered = false
        label.isEditable = false
        label.backgroundColor = NSColor.clear
        label.drawsBackground = false
        return label
    }
    
    // MARK: - Device Filtering Helper
    
    private func isServiceSupported(_ service: ServiceInfoProtocol) -> Bool {
        // Only treat lightbulbs as supported for the Devices tab; sensors are excluded from here.
        return SharedUtilities.isServiceSupported(service) && SharedUtilities.isServiceLightbulb(service)
    }
    
    // MARK: - Device Row View
    
    private func createDeviceRowView(device: AccessoryInfoProtocol, index: Int, isHidden: Bool) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.wantsLayer = true
        rowView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        rowView.layer?.cornerRadius = 6
        rowView.layer?.borderWidth = 0.5
        rowView.layer?.borderColor = NSColor.separatorColor.cgColor
        
        let deviceLabel = NSTextField(labelWithString: device.name)
        deviceLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        deviceLabel.textColor = NSColor.labelColor
        deviceLabel.translatesAutoresizingMaskIntoConstraints = false
        deviceLabel.lineBreakMode = NSLineBreakMode.byTruncatingTail
        deviceLabel.isBordered = false
        deviceLabel.isEditable = false
        deviceLabel.backgroundColor = NSColor.clear
        deviceLabel.drawsBackground = false
        
        // Create device type label
        let deviceType = getDeviceTypeDescription(for: device)
        let typeLabel = NSTextField(labelWithString: deviceType)
        typeLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        typeLabel.textColor = NSColor.systemBlue
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.lineBreakMode = NSLineBreakMode.byTruncatingTail
        typeLabel.isBordered = false
        typeLabel.isEditable = false
        typeLabel.backgroundColor = NSColor.clear
        typeLabel.drawsBackground = false
        
        let roomLabel = NSTextField(labelWithString: device.room?.name ?? "No Room")
        roomLabel.font = NSFont.systemFont(ofSize: 12)
        roomLabel.textColor = NSColor.secondaryLabelColor
        roomLabel.translatesAutoresizingMaskIntoConstraints = false
        roomLabel.lineBreakMode = NSLineBreakMode.byTruncatingTail
        roomLabel.isBordered = false
        roomLabel.isEditable = false
        roomLabel.backgroundColor = NSColor.clear
        roomLabel.drawsBackground = false
        
        let hideButton = createButton(
            title: isHidden ? "Show in Menu" : "Hide from Menu", 
            target: self, 
            action: #selector(deviceButtonClicked(_:))
        )
        hideButton.tag = index
        hideButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        hideButton.bezelStyle = NSButton.BezelStyle.rounded
        hideButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Style the row differently if hidden
        if isHidden {
            deviceLabel.textColor = NSColor.secondaryLabelColor
            typeLabel.textColor = NSColor.tertiaryLabelColor
            roomLabel.textColor = NSColor.tertiaryLabelColor
        }
        
        // Create a horizontal stack for device name and type
        let nameTypeStack = NSStackView(views: [deviceLabel, typeLabel])
        nameTypeStack.orientation = NSUserInterfaceLayoutOrientation.horizontal
        nameTypeStack.alignment = NSLayoutConstraint.Attribute.centerY
        nameTypeStack.spacing = 8
        nameTypeStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Create a vertical stack for name+type and room
        let labelStack = NSStackView(views: [nameTypeStack, roomLabel])
        labelStack.orientation = NSUserInterfaceLayoutOrientation.vertical
        labelStack.alignment = NSLayoutConstraint.Attribute.leading
        labelStack.spacing = 2
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        
        rowView.addSubview(labelStack)
        rowView.addSubview(hideButton)
        
        NSLayoutConstraint.activate([
            labelStack.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: standardPadding),
            labelStack.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: hideButton.leadingAnchor, constant: -elementSpacing),
            
            hideButton.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            hideButton.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -standardPadding),
            hideButton.widthAnchor.constraint(equalToConstant: 120)
        ])
        
        return rowView
    }
    
    private func createServiceRowView(accessory: AccessoryInfoProtocol, service: ServiceInfoProtocol, index: Int, isHidden: Bool) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.wantsLayer = true
        rowView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        rowView.layer?.cornerRadius = 6
        rowView.layer?.borderWidth = 0.5
        rowView.layer?.borderColor = NSColor.separatorColor.cgColor
        
        // Create a more descriptive name that includes both accessory and service info
        let serviceName = service.name.isEmpty ? accessory.name : service.name
        let displayName = accessory.name == serviceName ? accessory.name : "\(accessory.name) - \(serviceName)"
        
        let deviceLabel = NSTextField(labelWithString: displayName)
        deviceLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        deviceLabel.textColor = NSColor.labelColor
        deviceLabel.translatesAutoresizingMaskIntoConstraints = false
        deviceLabel.lineBreakMode = NSLineBreakMode.byTruncatingTail
        deviceLabel.isBordered = false
        deviceLabel.isEditable = false
        deviceLabel.backgroundColor = NSColor.clear
        deviceLabel.drawsBackground = false
        
        // Create device type label
        let deviceType = getDeviceTypeDescription(for: accessory)
        let typeLabel = NSTextField(labelWithString: deviceType)
        typeLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        typeLabel.textColor = NSColor.systemBlue
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.lineBreakMode = NSLineBreakMode.byTruncatingTail
        typeLabel.isBordered = false
        typeLabel.isEditable = false
        typeLabel.backgroundColor = NSColor.clear
        typeLabel.drawsBackground = false
        
        let roomLabel = NSTextField(labelWithString: accessory.room?.name ?? "No Room")
        roomLabel.font = NSFont.systemFont(ofSize: 12)
        roomLabel.textColor = NSColor.secondaryLabelColor
        roomLabel.translatesAutoresizingMaskIntoConstraints = false
        roomLabel.lineBreakMode = NSLineBreakMode.byTruncatingTail
        roomLabel.isBordered = false
        roomLabel.isEditable = false
        roomLabel.backgroundColor = NSColor.clear
        roomLabel.drawsBackground = false
        
        // Create hide/show button
        let buttonTitle = isHidden ? "Show" : "Hide"
        let hideButton = NSButton(title: buttonTitle, target: self, action: #selector(deviceButtonClicked(_:)))
        hideButton.bezelStyle = NSButton.BezelStyle.rounded
        hideButton.controlSize = .small
        hideButton.font = NSFont.systemFont(ofSize: 11)
        hideButton.translatesAutoresizingMaskIntoConstraints = false
        hideButton.tag = index
        
        // Create a vertical stack for the labels
        let labelStack = NSStackView(views: [deviceLabel, typeLabel, roomLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Style the row differently if hidden
        if isHidden {
            deviceLabel.textColor = NSColor.secondaryLabelColor
            typeLabel.textColor = NSColor.tertiaryLabelColor
            roomLabel.textColor = NSColor.tertiaryLabelColor
        }
        
        rowView.addSubview(labelStack)
        rowView.addSubview(hideButton)
        
        NSLayoutConstraint.activate([
            labelStack.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: standardPadding),
            labelStack.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: hideButton.leadingAnchor, constant: -elementSpacing),
            
            hideButton.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            hideButton.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -standardPadding),
            hideButton.widthAnchor.constraint(equalToConstant: 120)
        ])
        
        return rowView
    }
    
    private func getDeviceTypeDescription(for device: AccessoryInfoProtocol) -> String {
        // Devices tab shows only bulbs; keep label consistent.
        for service in device.services {
            if SharedUtilities.isServiceLightbulb(service) {
                return "💡 Lightbulb"
            }
        }
        return "💡 Light Device"
    }
    
    // MARK: - Scenes Tab Content
    
    private func createScenesTabContent() -> NSView {
        // Create a container view for the tab
        let containerView = NSView()
        // Use autoresizing instead of Auto Layout for the container
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]
        
        // Match native window background
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.windowBackgroundColor
        
        // Add scroll view to container and make it fill the container
        containerView.addSubview(scrollView)
        scrollView.frame = containerView.bounds
        scrollView.autoresizingMask = [.width, .height]
        
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        // Scene Display Section
        let displayLabel = createSectionHeader(title: "Scene Menu")
        let showScenesInMenuCheckbox = createCheckbox(
            title: "Show scenes in menu",
            state: SharedUtilities.getShowScenesInMenuSetting() ? .on : .off,
            target: self,
            action: #selector(sceneDisplaySettingChanged)
        )
        showScenesInMenuCheckbox.tag = 1 // Tag to identify this setting
        
        // Scene Management Section
        let sceneManagementLabel = createSectionHeader(title: "Scene Management")
        
        // Add home information for scenes
        let sceneHomeInfoLabel = NSTextField(labelWithString: "Current Home: \(getCurrentHomeName())")
        sceneHomeInfoLabel.font = NSFont.systemFont(ofSize: 12)
        sceneHomeInfoLabel.textColor = NSColor.secondaryLabelColor
        sceneHomeInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let sceneInfoLabel = NSTextField(labelWithString: "Click scenes to remove them from the menu:")
        sceneInfoLabel.font = NSFont.systemFont(ofSize: 13)
        sceneInfoLabel.textColor = NSColor.secondaryLabelColor
        sceneInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        scenesListContainerView = NSView()
        scenesListContainerView?.translatesAutoresizingMaskIntoConstraints = false
        
        // Set a minimum height to prevent layout shifting
        if let container = scenesListContainerView {
            // Set both minimum and maximum height constraints to provide more stability
            let minHeightConstraint = container.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
            minHeightConstraint.priority = NSLayoutConstraint.Priority(750) // High priority but not required
            minHeightConstraint.isActive = true
        }
        
        guard let scenesListContainer = scenesListContainerView else {
            HMLog.error(.ui, "Scenes list container view is nil")
            return containerView
        }
        
        // 1) Put all views into a main vertical NSStackView
        let scenesStack = NSStackView(views: [
            displayLabel,
            showScenesInMenuCheckbox,
            sceneManagementLabel,
            sceneHomeInfoLabel,
            sceneInfoLabel,
            scenesListContainer
        ])
        scenesStack.orientation = .vertical
        scenesStack.alignment = .leading
        scenesStack.translatesAutoresizingMaskIntoConstraints = false
        
        // 2) Give it a uniform spacing
        scenesStack.spacing = elementSpacing
        
        // 3) Add extra gap after each section
        scenesStack.setCustomSpacing(sectionSpacing, after: showScenesInMenuCheckbox)
        
        // 4) Embed the stack in your contentView
        contentView.addSubview(scenesStack)
        
        // Populate scenes list
        populateScenesList()
        
        // Layout constraints with better stability
        NSLayoutConstraint.activate([
            scenesStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: standardPadding),
            scenesStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: standardPadding),
            scenesStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -standardPadding),
            scenesStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -standardPadding),
            // Add checkbox indentation
            showScenesInMenuCheckbox.leadingAnchor.constraint(equalTo: scenesStack.leadingAnchor, constant: checkboxIndent - standardPadding),
            // Make sure scenes list container fills remaining space with stable constraints
            scenesListContainer.leadingAnchor.constraint(equalTo: scenesStack.leadingAnchor),
            scenesListContainer.trailingAnchor.constraint(equalTo: scenesStack.trailingAnchor)
        ])
    
    scrollView.documentView = contentView
    
    // Pin contentView to the clip view so Auto Layout can size it
    let clip = scrollView.contentView
    let widthConstraint = contentView.widthAnchor.constraint(equalTo: clip.widthAnchor)
    widthConstraint.priority = NSLayoutConstraint.Priority(999) // High but not required
    
    let heightConstraint = contentView.heightAnchor.constraint(greaterThanOrEqualTo: clip.heightAnchor)
    heightConstraint.priority = NSLayoutConstraint.Priority(250) // Low priority to allow content to grow
    
    NSLayoutConstraint.activate([
        contentView.topAnchor.constraint(equalTo: clip.topAnchor),
        contentView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
        contentView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
        contentView.bottomAnchor.constraint(greaterThanOrEqualTo: clip.bottomAnchor),
        widthConstraint,
        heightConstraint
    ])
    
    return containerView
    }
    
    private func populateScenesList() {
        guard let containerView = scenesListContainerView else {
            HMLog.error(.menu, "Scenes list container view is nil")
            return
        }
        
        // Ensure settings are loaded before creating UI
        loadSettings()
        
        // Clear any existing subviews 
        containerView.subviews.forEach { subview in
            subview.removeFromSuperview()
        }
        
        // Clear the scene button UUIDs mapping
        sceneButtonUUIDs.removeAll()
        
        let homeKitScenes = iosListener?.actionSets ?? []
        
        // Ensure default icons are assigned to scenes that don't have one yet
        SharedUtilities.ensureDefaultSceneIcons(for: homeKitScenes)
        
        // Reload sceneIcons after potential changes
        if let sceneIconsDict = UserDefaults.standard.dictionary(forKey: SettingsKeys.sceneIcons) as? [String: String] {
            sceneIcons = sceneIconsDict
        }
        
        // Filter out hidden scenes
        let visibleScenes = homeKitScenes.filter { !hiddenSceneIDs.contains($0.uniqueIdentifier.uuidString) }
        let hiddenScenes = homeKitScenes.filter { hiddenSceneIDs.contains($0.uniqueIdentifier.uuidString) }
        
        
        if visibleScenes.isEmpty && hiddenScenes.isEmpty {
            let noScenesLabel = NSTextField(labelWithString: "No user-defined scenes found in HomeKit\n(Create scenes in the Home app)")
            noScenesLabel.font = NSFont.systemFont(ofSize: 14)
            noScenesLabel.textColor = NSColor.labelColor
            noScenesLabel.alignment = .center
            noScenesLabel.translatesAutoresizingMaskIntoConstraints = false
            noScenesLabel.maximumNumberOfLines = 0
            containerView.addSubview(noScenesLabel)
            
            NSLayoutConstraint.activate([
                noScenesLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                noScenesLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                noScenesLabel.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: standardPadding),
                noScenesLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -standardPadding)
            ])
        } else {
            var previousView: NSView?
            var buttonTagCounter = 0
            
            // First show visible scenes
            if !visibleScenes.isEmpty {
                let visibleSectionLabel = createSectionLabel(title: "Visible Scenes (\(visibleScenes.count))")
                containerView.addSubview(visibleSectionLabel)
                
                NSLayoutConstraint.activate([
                    visibleSectionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    visibleSectionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    visibleSectionLabel.heightAnchor.constraint(equalToConstant: 30)
                ])
                
                if previousView == nil {
                    visibleSectionLabel.topAnchor.constraint(equalTo: containerView.topAnchor).isActive = true
                } else {
                    visibleSectionLabel.topAnchor.constraint(equalTo: previousView!.bottomAnchor, constant: sceneRowSpacing).isActive = true
                }
                previousView = visibleSectionLabel
                
                for scene in visibleScenes {
                    // Store the scene UUID mapping for the icon picker
                    sceneButtonUUIDs[buttonTagCounter] = scene.uniqueIdentifier.uuidString
                    
                    let sceneRowView = createSceneRowView(scene: scene, buttonTag: buttonTagCounter, isHidden: false)
                    buttonTagCounter += 1
                    containerView.addSubview(sceneRowView)
                    
                    NSLayoutConstraint.activate([
                        sceneRowView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                        sceneRowView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                        sceneRowView.heightAnchor.constraint(equalToConstant: sceneRowHeight)
                    ])
                    
                    sceneRowView.topAnchor.constraint(equalTo: previousView!.bottomAnchor, constant: sceneRowSpacing).isActive = true
                    previousView = sceneRowView
                }
            }
            
            // Then show hidden scenes if any
            if !hiddenScenes.isEmpty {
                let hiddenSectionLabel = createSectionLabel(title: "Hidden Scenes (\(hiddenScenes.count))")
                containerView.addSubview(hiddenSectionLabel)
                
                NSLayoutConstraint.activate([
                    hiddenSectionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    hiddenSectionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    hiddenSectionLabel.heightAnchor.constraint(equalToConstant: 30)
                ])
                
                if previousView == nil {
                    hiddenSectionLabel.topAnchor.constraint(equalTo: containerView.topAnchor).isActive = true
                } else {
                    hiddenSectionLabel.topAnchor.constraint(equalTo: previousView!.bottomAnchor, constant: sectionSpacing).isActive = true
                }
                previousView = hiddenSectionLabel
                
                for scene in hiddenScenes {
                    // Store the scene UUID mapping for the icon picker
                    sceneButtonUUIDs[buttonTagCounter] = scene.uniqueIdentifier.uuidString
                    
                    let sceneRowView = createSceneRowView(scene: scene, buttonTag: buttonTagCounter, isHidden: true)
                    buttonTagCounter += 1
                    containerView.addSubview(sceneRowView)
                    
                    NSLayoutConstraint.activate([
                        sceneRowView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                        sceneRowView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                        sceneRowView.heightAnchor.constraint(equalToConstant: sceneRowHeight)
                    ])
                    
                    sceneRowView.topAnchor.constraint(equalTo: previousView!.bottomAnchor, constant: sceneRowSpacing).isActive = true
                    previousView = sceneRowView
                }
            }
            
            if let lastView = previousView {
                let bottomConstraint = lastView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor)
                bottomConstraint.priority = NSLayoutConstraint.Priority(500) // Medium priority to avoid conflicts
                bottomConstraint.isActive = true
            }
        }
    }
    
    // MARK: - Scene Row View
    
    private func createSceneRowView(scene: ActionSetInfoProtocol, buttonTag: Int, isHidden: Bool) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.wantsLayer = true
        rowView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        rowView.layer?.cornerRadius = 6
        rowView.layer?.borderWidth = 0.5
        rowView.layer?.borderColor = NSColor.separatorColor.cgColor
        
        let sceneLabel = NSTextField(labelWithString: scene.name)
        sceneLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        sceneLabel.textColor = NSColor.labelColor
        sceneLabel.translatesAutoresizingMaskIntoConstraints = false
        sceneLabel.lineBreakMode = .byTruncatingTail
        sceneLabel.isBordered = false
        sceneLabel.isEditable = false
        sceneLabel.backgroundColor = NSColor.clear
        sceneLabel.drawsBackground = false
        
        let sceneTypeLabel = NSTextField(labelWithString: "Scene")
        sceneTypeLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        sceneTypeLabel.textColor = NSColor.systemPurple
        sceneTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        sceneTypeLabel.lineBreakMode = NSLineBreakMode.byTruncatingTail
        sceneTypeLabel.isBordered = false
        sceneTypeLabel.isEditable = false
        sceneTypeLabel.backgroundColor = NSColor.clear
        sceneTypeLabel.drawsBackground = false
        
        // Create icon picker dropdown
        let iconPicker = createIconPickerButton(for: scene, buttonTag: buttonTag)
        
        // Create hide/show button
        let buttonTitle = isHidden ? "Show" : "Hide"
        let hideButton = NSButton(title: buttonTitle, target: self, action: #selector(sceneButtonClicked(_:)))
        hideButton.bezelStyle = NSButton.BezelStyle.rounded
        hideButton.controlSize = .small
        hideButton.font = NSFont.systemFont(ofSize: 11)
        hideButton.translatesAutoresizingMaskIntoConstraints = false
        hideButton.tag = buttonTag
        
        // Create a vertical stack for the labels
        let labelStack = NSStackView(views: [sceneLabel, sceneTypeLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Style the row differently if hidden
        if isHidden {
            HMLog.menuDebug("Styling scene '\(scene.name)' as hidden")
            sceneLabel.textColor = NSColor.secondaryLabelColor
            sceneTypeLabel.textColor = NSColor.tertiaryLabelColor
            iconPicker.isEnabled = false
        } else {
            HMLog.menuDebug("Styling scene '\(scene.name)' as visible")
            iconPicker.isEnabled = true
        }
        
        rowView.addSubview(labelStack)
        rowView.addSubview(iconPicker)
        rowView.addSubview(hideButton)
        
        NSLayoutConstraint.activate([
            labelStack.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: standardPadding),
            labelStack.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: iconPicker.leadingAnchor, constant: -elementSpacing),
            
            iconPicker.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            iconPicker.trailingAnchor.constraint(equalTo: hideButton.leadingAnchor, constant: -elementSpacing),
            
            hideButton.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            hideButton.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -standardPadding),
            hideButton.widthAnchor.constraint(equalToConstant: 80)
        ])
        
        return rowView
    }
    
    // MARK: - Icon Picker
    
    private func createIconPickerButton(for scene: ActionSetInfoProtocol, buttonTag: Int) -> NSPopUpButton {
        let sceneUUID = scene.uniqueIdentifier.uuidString
        let currentIcon = sceneIcons[sceneUUID] ?? "play.circle"  // Default icon
        
        
        let dropdown = NSPopUpButton()
        dropdown.tag = buttonTag
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.target = self
        dropdown.action = #selector(iconDropdownChanged(_:))
        
        // Add all available icons to the dropdown
        for (displayName, symbolName) in availableSceneIcons {
            let menuItem = NSMenuItem()
            menuItem.title = displayName
            
            // Add the icon to the menu item
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: displayName) {
                image.size = NSSize(width: 16, height: 16)
                menuItem.image = image
            }
            
            dropdown.menu?.addItem(menuItem)
        }
        
        // Select the current icon if one is set - this must happen after all items are added
        if let currentIndex = availableSceneIcons.firstIndex(where: { $0.1 == currentIcon }) {
            dropdown.selectItem(at: currentIndex)
        } else {
            // Fallback: select the default "Theater" option
            dropdown.selectItem(at: 0)
        }
        
        // Set a wider width for the dropdown to accommodate longer names
        NSLayoutConstraint.activate([
            dropdown.widthAnchor.constraint(equalToConstant: 140)
        ])
        
        return dropdown
    }
    
    @objc private func iconDropdownChanged(_ sender: NSPopUpButton) {
        let buttonTag = sender.tag
        
        guard let sceneUUID = sceneButtonUUIDs[buttonTag] else {
            HMLog.error(.menu, "Could not find scene UUID for button tag: \(buttonTag)")
            return
        }
        
        let selectedIndex = sender.indexOfSelectedItem
        if selectedIndex >= 0 && selectedIndex < availableSceneIcons.count {
            let selectedIcon = availableSceneIcons[selectedIndex]
            sceneIcons[sceneUUID] = selectedIcon.1  // Store the symbol name
            saveSettings()
            
            
            // Notify the main app to update the menu
            notifyMenuUpdate()
        } else {
            HMLog.error(.menu, "Invalid selection index: \(selectedIndex)")
        }
    }
    
    // MARK: - Actions (Scene Management)
    
    @objc private func sceneButtonClicked(_ sender: NSButton) {
        let sceneIndex = sender.tag
        let homeKitScenes = iosListener?.actionSets ?? []
        
        // Get visible and hidden scenes
        let visibleScenes = homeKitScenes.filter { !hiddenSceneIDs.contains($0.uniqueIdentifier.uuidString) }
        let hiddenScenes = homeKitScenes.filter { hiddenSceneIDs.contains($0.uniqueIdentifier.uuidString) }
        
        if sceneIndex < visibleScenes.count {
            // This is a visible scene - hide it
            let scene = visibleScenes[sceneIndex]
            HMLog.menuDebug("Hiding scene '\(scene.name)' with UUID: \(scene.uniqueIdentifier.uuidString)")
            hiddenSceneIDs.insert(scene.uniqueIdentifier.uuidString)
            saveSettings()
            

        } else {
            // This is a hidden scene - show it
            let hiddenSceneIndex = sceneIndex - visibleScenes.count
            guard hiddenSceneIndex >= 0 && hiddenSceneIndex < hiddenScenes.count else {
                HMLog.error(.menu, "Hidden scene index out of bounds: \(hiddenSceneIndex) (hidden scenes: \(hiddenScenes.count), visible scenes: \(visibleScenes.count), button tag: \(sceneIndex))")
                return
            }
            
            let scene = hiddenScenes[hiddenSceneIndex]
            hiddenSceneIDs.remove(scene.uniqueIdentifier.uuidString)
            saveSettings()
            

        }
        
        // Refresh the scenes list to show updated state
        populateScenesList()
        
        // Notify the main app to update the menu
        notifyMenuUpdate()
    }
    
    // MARK: - Actions (Settings Changes)
    

    
    @objc private func deviceButtonClicked(_ sender: NSButton) {
        let serviceIndex = sender.tag
        let homeKitDevices = iosListener?.accessories ?? []
        
        // Create a list of individual services (same as in populateDevicesList)
        var individualServices: [(accessory: AccessoryInfoProtocol, service: ServiceInfoProtocol)] = []
        
        for device in homeKitDevices {
            for service in device.services {
                if isServiceSupported(service) {
                    individualServices.append((accessory: device, service: service))
                }
            }
        }
        
        // Filter out hidden services from supported services
        let visibleServices = individualServices.filter { !hiddenDeviceIDs.contains($0.service.uniqueIdentifier.uuidString) }
        let hiddenServices = individualServices.filter { hiddenDeviceIDs.contains($0.service.uniqueIdentifier.uuidString) }
        
        if serviceIndex < visibleServices.count {
            // This is a visible service - hide it
            let serviceData = visibleServices[serviceIndex]
            hiddenDeviceIDs.insert(serviceData.service.uniqueIdentifier.uuidString)
            saveSettings()
        } else {
            // This is a hidden service - show it
            let hiddenServiceIndex = serviceIndex - visibleServices.count
            guard hiddenServiceIndex >= 0 && hiddenServiceIndex < hiddenServices.count else {
                HMLog.error(.menu, "Hidden service index out of bounds: \(hiddenServiceIndex) (hidden services: \(hiddenServices.count), visible services: \(visibleServices.count), button tag: \(serviceIndex))")
                return
            }
            
            let serviceData = hiddenServices[hiddenServiceIndex]
            hiddenDeviceIDs.remove(serviceData.service.uniqueIdentifier.uuidString)
            saveSettings()
        }
        
        // Refresh the devices list to show updated state
        populateDevicesList()
        
        // Notify the main app to update the menu
        notifyMenuUpdate()
    }
    
    @objc private func menuSettingChanged(_ sender: NSButton) {
        let isChecked = sender.state == .on
        
        switch sender.tag {
        case 1: // Group by room
            UserDefaults.standard.set(isChecked, forKey: SettingsKeys.groupByRoom)
        case 2: // Show room names
            UserDefaults.standard.set(isChecked, forKey: SettingsKeys.showRoomNames)
        case 3: // Show All Home control
            UserDefaults.standard.set(isChecked, forKey: SettingsKeys.showAllHomeControl)
        case 4: // Show room-level All controls
            UserDefaults.standard.set(isChecked, forKey: SettingsKeys.showRoomAllControls)
        default:
            break
        }
        
        
        // Notify the main app to update the menu
        notifyMenuUpdate()
    }
    
    private func notifyMenuUpdate() {
        // Post a notification that settings have changed so the main app can update the menu
        NotificationCenter.default.post(
            name: .settingsChanged,
            object: nil,
            userInfo: [
                "groupByRoom": groupByRoom,
                "showRoomNames": showRoomNames,
                "showScenesInMenu": showScenesInMenu,
                "showAllHomeControl": showAllHomeControl,
                "showRoomAllControls": showRoomAllControls,
                "hiddenDevices": Array(hiddenDeviceIDs),
                "hiddenScenes": Array(hiddenSceneIDs),
                "sceneIcons": sceneIcons
            ]
        )
    }
    
    @objc private func sceneDisplaySettingChanged(_ sender: NSButton) {
        let isChecked = sender.state == .on
        
        // Only handle the "Show scenes in menu" setting now
        UserDefaults.standard.set(isChecked, forKey: SettingsKeys.showScenesInMenu)
        
        
        // Notify the main app to update the menu
        notifyMenuUpdate()
    }
    
    @objc private func reloadFromHomeKit() {
        HMLog.menuDebug("SettingsWindow: Reloading from HomeKit...")
        iosListener?.fetchFromHomeKitAndReloadMenuExtra()
        
        // Refresh the settings window content to show updated home information
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshContent()
        }
    }
    
    private func refreshContent() {
        // Refresh both device and scene lists to show current home information
        populateDevicesList()
        populateScenesList()
    }
    
    func refreshDeviceAndSceneLists() {
        // Refresh both the devices and scenes lists in the settings window
        DispatchQueue.main.async { [weak self] in
            self?.populateDevicesList()
            self?.populateScenesList()
        }
    }
    
    // MARK: - UI Element Factory Methods
    
    private func createSectionHeader(title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = NSColor.labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func createCheckbox(title: String, state: NSControl.StateValue, target: Any?, action: Selector?) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: target, action: action)
        checkbox.state = state
        checkbox.font = NSFont.systemFont(ofSize: 13)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        return checkbox
    }
    
    private func createButton(title: String, target: Any?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

//
//  SettingsManager.swift
//  HomeMenuBar
//
//  Created by Luca Pedrocchi on 02.08.2025.
//

import Foundation

/// Simplified SettingsManager for iOS/Catalyst app
/// Only manages settings that are actually used by the HomeKit functionality
class SettingsManager {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Settings Keys
    private enum Keys {
        static let lastHomeUUID = "LastHomeUUID"
    }
    
    // MARK: - Properties
    /// Stores the UUID of the last selected home for app restoration
    var lastHomeUUID: String? {
        get { defaults.string(forKey: Keys.lastHomeUUID) }
        set { defaults.set(newValue, forKey: Keys.lastHomeUUID) }
    }
    
    // MARK: - Initialization
    private init() {
        // No default values needed - lastHomeUUID is optional
    }
} 
//
//  AppDelegate.swift
//  HomeMenuBar
//
//  Created by Luca Pedrocchi on 02.08.2025.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    // No window property - completely background-only app
    var baseManager: BaseManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Setup default settings if this is the first time
        SharedUtilities.setupDefaultSettingsIfNeeded()
        
        baseManager = BaseManager()
        // No window creation - the app stays in the background
        
        return true
    }

    // MARK: UISceneSession Lifecycle
    // Adopt scene lifecycle but create completely hidden windows

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        // Explicitly prevent any storyboard loading
        config.storyboard = nil
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // BaseManager handles its own connection monitoring
    }
    
    // MARK: - Application Lifecycle
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Clean up resources
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Called when the application enters the background.
        // BaseManager handles connection monitoring automatically
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state.
        // Ensure the menu bar is functional
        baseManager?.checkAndMaintainConnection()
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Called when the application has become active
        // Ensure the menu bar is functional
        baseManager?.checkAndMaintainConnection()
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Called when the application is about to resign active
        // BaseManager handles connection monitoring automatically
    }
    
    // MARK: - Termination Prevention
    
    // For Mac Catalyst, we rely on the Info.plist settings to prevent termination
    // LSBackgroundOnly, LSUIElement, NSSupportsAutomaticTermination, and NSSupportsSuddenTermination
    // are configured to keep the app running in the background
    

}


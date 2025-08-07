//
//  SceneDelegate.swift
//  HomeMenuBar
//
//  Created by Luca Pedrocchi on 02.08.2025.
//

import UIKit

/// Minimal SceneDelegate for background-only Catalyst app
/// Creates a hidden window to satisfy Catalyst requirements
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // Create a minimal hidden window to satisfy Catalyst requirements
        let window = UIWindow(windowScene: windowScene)
        
        // Create a minimal view controller
        let minimalVC = UIViewController()
        minimalVC.view.backgroundColor = .clear
        window.rootViewController = minimalVC
        
        // Hide the window completely
        window.isHidden = true
        window.alpha = 0.0
        window.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        
        // Set window restrictions to prevent showing
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 1, height: 1)
        windowScene.sizeRestrictions?.maximumSize = CGSize(width: 1, height: 1)
        
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Clean up resources
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Keep window hidden
        window?.isHidden = true
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Keep window hidden
        window?.isHidden = true
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Keep window hidden
        window?.isHidden = true
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Keep window hidden
        window?.isHidden = true
    }
}
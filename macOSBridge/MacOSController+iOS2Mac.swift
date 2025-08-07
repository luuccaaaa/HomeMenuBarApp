import Foundation
import AppKit
import os

extension MacOSController {
    
    public func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func centeringWindows() {
        for window in NSApp.windows {
            window.center()
        }
    }
    
    public func setReachablityOfMenuItemRelated(to uniqueIdentifier: UUID, using isReachable: Bool) {
        let items = NSMenu.getSubItems(menu: mainMenu)
        
        let candidates = items.compactMap({ item in
            item as? MenuItemFromUUID
        }).filter ({ item in
            item.bind(with: uniqueIdentifier)
        })
        
        for item in candidates {
            switch (item) {
            case let item as ToggleMenuItem:
                item.reachable = isReachable
            case let item as SensorMenuItem:
                item.reachable = isReachable
            default:
                do {}
            }
        }
    }
    
    
    public func openNoHomeError() {
        let alert = NSAlert()
        alert.messageText = "HomeKit error"
        alert.informativeText = "App can not find any Homes of HomeKit. Please confirm your HomeKit devices on Home.app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }
    
    public func openHomeKitAuthenticationError() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Failed to access HomeKit because of your privacy settings."
        alert.informativeText = "Allow app to access HomeKit in System Settings."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open System Settings")
        
        let ret = alert.runModal()
        switch ret {
        case .alertSecondButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_HomeKit") {
                NSWorkspace.shared.open(url)
            }
            return true
        default:
            return false
        }
    }
    
    public func showLaunchView() {
        // Show launch view if needed
    }
}

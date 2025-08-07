import Foundation
import HomeKit

extension BaseManager {
    
    /// Recreate the home manager to force a fresh HomeKit session.
    func rebootHomeManager() {
        homeManager?.delegate = nil
        homeManager = HMHomeManager()
        homeManager?.delegate = self
    }

    /// Read a characteristic value and forward the result to the macOS plug‑in.
    func readCharacteristic(of uniqueIdentifier: UUID) {
        guard let characteristic = homeManager?.getCharacteristic(from: self.homeUniqueIdentifier, with: uniqueIdentifier) else { return }
        Task {
            do {
                try await characteristic.readValue()
                
                // After reading, notify the macOS controller with the updated value
                if let value = characteristic.value {
                    await MainActor.run {
                        self.macOSController?.updateMenuItemsRelated(to: uniqueIdentifier, value: value)
                    }
                }
            } catch {
                await MainActor.run {
                    self.macOSController?.setReachablityOfMenuItemRelated(to: uniqueIdentifier, using: false)
                }
            }
        }
    }

    /// Write a new value to the given characteristic and update the menu item.
    func setCharacteristic(of uniqueIdentifier: UUID, object: Any) {
        HMLog.menuDebug("HomeMenuBar: setCharacteristic called for UUID: \(uniqueIdentifier), value: \(object)")
        
        guard let characteristic = homeManager?.getCharacteristic(from: self.homeUniqueIdentifier, with: uniqueIdentifier) else {
            HMLog.error(.homekit, "Characteristic not found for UUID: \(uniqueIdentifier)")
            return
        }

        HMLog.menuDebug("HomeMenuBar: Found characteristic: \(characteristic.characteristicType)")

        Task.detached(priority: .userInitiated) {
            do {
                HMLog.menuDebug("HomeMenuBar: Writing value \(object) to characteristic \(characteristic.characteristicType) (UUID: \(uniqueIdentifier))")
                try await characteristic.writeValue(object)
                HMLog.menuDebug("HomeMenuBar: Successfully wrote value \(object) to characteristic \(characteristic.characteristicType) (UUID: \(uniqueIdentifier))")
                // Disabled callback - we don't want HomeKit callbacks interfering with the color wheel
            } catch {
                HMLog.error(.homekit, "Failed to write value \(object) to characteristic \(characteristic.characteristicType) (UUID: \(uniqueIdentifier)): \(error.localizedDescription)")
                await MainActor.run {
                    self.macOSController?.setReachablityOfMenuItemRelated(to: uniqueIdentifier, using: false)
                }
            }
        }
    }

    /// Execute the scene identified by the provided UUID.
    func executeActionSet(uniqueIdentifier: UUID) {
        guard let home = homeManager?.usedHome(with: homeUniqueIdentifier),
              let actionSet = home.actionSets.first(where: { $0.uniqueIdentifier == uniqueIdentifier }) else { return }

        Task {
            do {
                try await home.executeActionSet(actionSet)
            } catch {
                HMLog.error(.homekit, "Failed to execute action set: \(error.localizedDescription)")
            }
        }
    }

    /// Placeholder to allow the plug‑in to request window closures.
    func close(windows: [Any]) {
        // Currently unused on iOS.
    }

    /// Bring the iOS app window to the foreground and ensure the bridge connection stays alive.
    func bringToFront() {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                if window.isHidden {
                    window.isHidden = false
                }
                window.makeKeyAndVisible()
            }
        }
        macOSController?.ensureConnection()
    }
}
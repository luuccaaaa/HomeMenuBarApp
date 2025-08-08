import Foundation
import HomeKit

extension BaseManager {
    
    // MARK: HMHomeManagerDelegate
    
    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        // React to authorization changes and refresh the menu when allowed.
        if status.contains(.restricted) {
            _ = macOSController?.openHomeKitAuthenticationError()
        } else if status.contains(.authorized) {
            DispatchQueue.main.async {
                self.fetchFromHomeKitAndReloadMenuExtra()
            }
        }
        macOSController?.reloadMenuExtra()
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        // Home structure updated; mark readiness and refresh
        self.initialHomeListReceived = true
        self.homeFetchRetryCount = 0
        DispatchQueue.main.async { self.fetchFromHomeKitAndReloadMenuExtra() }
    }

    // MARK: HMAccessoryDelegate

    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        updateDeviceState(from: characteristic, in: service)
    }
}

private extension BaseManager {
    func updateDeviceState(from characteristic: HMCharacteristic, in service: HMService) {
        let characteristicType = CharacteristicType(key: characteristic.characteristicType)
        
        guard let value = characteristic.value, characteristicType.isSupported else {
            return
        }

        // Use the service UUID as the device identifier, since UI items are keyed by service UUID
        let deviceUUID = service.uniqueIdentifier

        HMLog.menuDebug("HomeKit: Received update for \(characteristicType.stringValue) on device \(deviceUUID) - value: \(value)")

        DeviceStateManager.shared.updateDeviceState(
            deviceUUID: deviceUUID,
            characteristicUUID: characteristic.uniqueIdentifier,
            value: value,
            valueType: characteristicType
        )
        
        // Also notify the macOS controller to update menu items directly
        DispatchQueue.main.async {
            self.macOSController?.updateMenuItemsRelated(to: characteristic.uniqueIdentifier, value: value)
        }
    }
}

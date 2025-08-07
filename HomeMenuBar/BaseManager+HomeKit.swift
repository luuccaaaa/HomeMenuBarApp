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
        // Home structure changed; update the menu representation.
        DispatchQueue.main.async {
            self.fetchFromHomeKitAndReloadMenuExtra()
        }
    }

    // MARK: HMAccessoryDelegate

    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        updateDeviceState(from: characteristic, in: accessory)
    }
}

private extension BaseManager {
    func updateDeviceState(from characteristic: HMCharacteristic, in accessory: HMAccessory) {
        let characteristicType = CharacteristicType(key: characteristic.characteristicType)
        
        guard let value = characteristic.value, characteristicType.isSupported else {
            return
        }

        let deviceUUID = accessory.uniqueIdentifier

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

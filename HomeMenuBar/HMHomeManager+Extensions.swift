import Foundation
import HomeKit

extension HMHomeManager {
    
    func usedHome(with uniqueIdentifier: UUID?) -> HMHome? {
        if let uuid = uniqueIdentifier {
            return homes.first { $0.uniqueIdentifier == uuid }
        }
        return homes.first
    }
    
    func getCharacteristic(from homeUUID: UUID?, with characteristicUUID: UUID) -> HMCharacteristic? {
        guard let home = usedHome(with: homeUUID) else { return nil }
        
        for accessory in home.accessories {
            for service in accessory.services {
                for characteristic in service.characteristics {
                    if characteristic.uniqueIdentifier == characteristicUUID {
                        return characteristic
                    }
                }
            }
        }
        return nil
    }
} 
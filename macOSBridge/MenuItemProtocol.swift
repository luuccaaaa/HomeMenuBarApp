import Foundation
import Cocoa

protocol MenuItemFromUUID {
    func bind(with uniqueIdentifier: UUID) -> Bool
    func UUIDs() -> [UUID]
}

protocol ErrorMenuItem {
    var reachable: Bool { get set }
}

protocol MenuItemOrder  {
    var orderPriority: Int { get }
} 
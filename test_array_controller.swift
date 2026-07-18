import Foundation
import CoreData
import Cocoa

let model = NSManagedObjectModel()
let entity = NSEntityDescription()
entity.name = "Group"
let artistEntity = NSEntityDescription()
artistEntity.name = "Artist"
model.entities = [entity, artistEntity]

let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
context.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

// To mock KVC for itemId
class MockGroup: NSObject {
    @objc var itemId: String? = nil
    @objc var entity: NSEntityDescription
    init(entity: NSEntityDescription) { self.entity = entity }
}
class MockArtist: NSObject {
    @objc var itemId: String? = "123"
    @objc var entity: NSEntityDescription
    init(entity: NSEntityDescription) { self.entity = entity }
}

let mockGroup = MockGroup(entity: entity)
let mockArtist = MockArtist(entity: artistEntity)

let controller = NSArrayController(content: [mockGroup, mockArtist])
let predicate = NSPredicate(format: "(itemId != nil || entity == %@)", entity)

controller.filterPredicate = predicate
let arranged = controller.arrangedObjects as! [NSObject]
print("Arranged count:", arranged.count)

let predicateName = NSPredicate(format: "(itemId != nil || entity.name == 'Group')")
controller.filterPredicate = predicateName
let arrangedName = controller.arrangedObjects as! [NSObject]
print("Arranged count by name:", arrangedName.count)

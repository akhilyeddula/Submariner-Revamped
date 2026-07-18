import Foundation
import CoreData

let model = NSManagedObjectModel()
let entity = NSEntityDescription()
entity.name = "Group"
let artistEntity = NSEntityDescription()
artistEntity.name = "Artist"
model.entities = [entity, artistEntity]

let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
context.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

let group = NSManagedObject(entity: entity, insertInto: context)
let artist = NSManagedObject(entity: artistEntity, insertInto: context)

let predicate = NSPredicate(format: "entity == %@", entity)
print("Evaluating group:", predicate.evaluate(with: group))
print("Evaluating artist:", predicate.evaluate(with: artist))

let predicateName = NSPredicate(format: "entity.name == 'Group'")
print("Evaluating group by name:", predicateName.evaluate(with: group))
print("Evaluating artist by name:", predicateName.evaluate(with: artist))

import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor MemoryDisclosureFile:ProviderDisclosurePersistence{
  var disk=ProviderDisclosureDisk(),fail=false
  func load()async throws->ProviderDisclosureDisk{disk}
  func save(_ value:ProviderDisclosureDisk,revision:UInt64)async throws{if fail{throw RemoteError.unavailable};disk=value}
  func failWrites(){fail=true}
}
private actor DisclosureReader:OpenCodeSharingReading{
  let destination:OpenCodeSharingDestination
  init(_ destination:OpenCodeSharingDestination){self.destination=destination}
  func sharingDestination(target:OpenCodeTarget)async throws->OpenCodeSharingDestination{destination}
}
@Suite @MainActor struct ProviderDisclosureTests{
  private func destination(_ id:ConnectionID=ConnectionID(),digest:UInt8=1)throws->OpenCodeSharingDestination{
    let object:[String:Any]=["connectionID":["rawValue":id.rawValue.uuidString],"origin":"https://synthetic.example",
      "model":["providerID":"Provider","id":"model"],"configurationDigest":Data(repeating:digest,count:32).base64EncodedString()]
    return try JSONDecoder().decode(OpenCodeSharingDestination.self,from:JSONSerialization.data(withJSONObject:object))
  }
  @Test func firstSharingRequiresDeliberateUnknownDestinationReviewAndPersistsTheExactContext()async throws{
    let destination=try destination(),file=MemoryDisclosureFile(),store=ProviderDisclosureStore(persistence:file)
    let target=OpenCodeTarget(connectionID:destination.connectionID,projectID:"project",sessionID:"ses_owned",directory:"/project")
    let reader=DisclosureReader(destination),classes=OpenCodeSharedData.conversationContext
    try await store.restore();store.activate(target)
    #expect(!(await store.authorize(target:target,reader:reader,classes:classes)))
    let review=try #require(store.review)
    #expect(!(await store.approve(review,using:reader,acknowledgesUnknownDestination:false)))
    #expect(await store.approve(review,using:reader,acknowledgesUnknownDestination:true))
    #expect(await store.authorize(target:target,reader:reader,classes:classes))
    let reopened=ProviderDisclosureStore(persistence:file);try await reopened.restore();reopened.activate(target)
    #expect(await reopened.authorize(target:target,reader:reader,classes:classes))
    #expect(!(await reopened.authorize(target:target,reader:reader,classes:classes.union([.photos]))))
    #expect(reopened.review?.classes.contains(.photos)==true)
    try await reopened.clearConsents()
    let cleared=ProviderDisclosureStore(persistence:file);try await cleared.restore();cleared.activate(target)
    #expect(!(await cleared.authorize(target:target,reader:reader,classes:classes)))
  }
  @Test func changedConfigurationAndFailedPersistenceCannotEnableSharing()async throws{
    let destination=try destination(),file=MemoryDisclosureFile(),store=ProviderDisclosureStore(persistence:file)
    let target=OpenCodeTarget(connectionID:destination.connectionID,projectID:"project",sessionID:"ses_owned",directory:"/project")
    let reader=DisclosureReader(destination),changed=DisclosureReader(try self.destination(destination.connectionID,digest:2))
    try await store.restore();store.activate(target)
    _ = await store.authorize(target:target,reader:reader,classes:OpenCodeSharedData.conversationContext)
    let old=try #require(store.review)
    #expect(!(await store.approve(old,using:changed,acknowledgesUnknownDestination:true)))
    let current=try #require(store.review);#expect(current.id != old.id)
    await file.failWrites()
    #expect(!(await store.approve(current,using:changed,acknowledgesUnknownDestination:true)))
    #expect(!(await store.authorize(target:target,reader:changed,classes:OpenCodeSharedData.conversationContext)))
    store.activate(nil)
    #expect(!(await store.approve(current,using:changed,acknowledgesUnknownDestination:true)))
  }
}

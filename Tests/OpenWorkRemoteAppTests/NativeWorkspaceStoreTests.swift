import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor NativeWorkspaceService:OpenCodeWorkspaceServing {
  var instructions="Review only"
  var noRepo=false
  var slow=false
  var statuses=0
  func changeSkill(){instructions="Changed instructions"}
  func nonRepository(){noRepo=true}
  func slowChanges(){slow=true}
  func count()->Int{statuses}
  private func decode<T:Decodable>(_ type:T.Type,_ value:Any)throws->T{try JSONDecoder().decode(type,from:JSONSerialization.data(withJSONObject:value))}
  func workspaceInfo(location:OpenCodeLocation)async throws->OpenCodeWorkspaceInfo{
    let value:[String:Any]=noRepo ? ["branch":[:]]:["provider":"git","branch":["current":"main"]]
    return try decode(OpenCodeWorkspaceInfo.self,value)
  }
  func workspaceChanges(location:OpenCodeLocation)async throws->[OpenCodeChange]{
    statuses+=1;if slow{try? await Task.sleep(for:.milliseconds(80))}
    return try decode([OpenCodeChange].self,[["file":"notes.txt","additions":1,"deletions":0,"status":"modified"]])
  }
  func workspaceDiff(location:OpenCodeLocation)async throws->[OpenCodeWorkingDiff]{[]}
  func skills(location:OpenCodeLocation)async throws->[OpenCodeSkill]{
    try decode([OpenCodeSkill].self,[["id":"skill_owned","name":"Review","path":"/skills/review/SKILL.md","content":instructions]])
  }
}
@Suite @MainActor struct NativeWorkspaceStoreTests {
  private func target(_ id:String="ses_owned")->OpenCodeTarget{OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:id,directory:"/project")}
  @Test func skillPreviewSelectionAndChangedVersionRequireReviewBeforeSend()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let journal=NativeConversationJournal(persistence:try NativeConversationFile(directory:root));try await journal.restore()
    let service=NativeWorkspaceService(),store=NativeWorkspaceStore(journal:journal),target=target()
    let context=store.activate(target:target,client:service)
    await store.loadSkills(context)
    let skill=try #require(store.skills.first)
    #expect(journal.skills(for:target).isEmpty)
    try await store.choose(skill,selected:true,context:context)
    #expect(journal.skills(for:target).first?.id==skill.id)
    let restored=NativeConversationJournal(persistence:try NativeConversationFile(directory:root));try await restored.restore()
    #expect(restored.skills(for:target)==journal.skills(for:target))
    #expect(await store.validatedSkills(context)==[skill.id])
    await service.changeSkill()
    #expect(await store.validatedSkills(context)==nil)
    #expect(journal.skills(for:target).first?.fingerprint==skill.fingerprint)
    #expect(journal.pending(for:target)==nil)
    let current=try #require(store.skills.first);try await store.choose(current,selected:true,context:context)
    #expect(await store.validatedSkills(context)==[skill.id])
    let pending=try await journal.prepare(target:target,skills:[skill.id])
    await #expect(throws:(any Error).self){try await store.choose(current,selected:false,context:context)}
    try await journal.confirm(pending)
    #expect(journal.skills(for:target).isEmpty)
  }
  @Test func nonRepositoryAndLateChangeReadNeverCreateGitOrReplaceAnotherChat()async throws{
    let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let journal=NativeConversationJournal(persistence:try NativeConversationFile(directory:root));try await journal.restore()
    let service=NativeWorkspaceService(),store=NativeWorkspaceStore(journal:journal)
    let context=store.activate(target:target(),client:service)
    await service.nonRepository();await store.loadChanges(context)
    #expect(store.info != nil && store.info?.provider==nil);#expect(await service.count()==0)
    let slow=NativeWorkspaceService();await slow.slowChanges()
    let old=store.activate(target:target(),client:slow),read=Task{await store.loadChanges(old)}
    try await Task.sleep(for:.milliseconds(10))
    let current=store.activate(target:target("ses_other"),client:slow)
    await read.value
    #expect(store.context==current && store.changes.isEmpty && !store.changesLoading)
  }
}

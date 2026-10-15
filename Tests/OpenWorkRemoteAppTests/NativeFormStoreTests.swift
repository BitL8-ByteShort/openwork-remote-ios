import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

actor NativeFormMemory:NativeFormPersistence {
  var value=NativeFormDisk()
  func load() async throws -> NativeFormDisk{value}
  func save(_ value:NativeFormDisk,revision:UInt64) async throws{self.value=value}
}
actor NativeFormService:OpenCodeFormServing {
  var settled=false
  var uncertain=false
  var writes=0
  var required=false
  var hidden=false
  func forms(target:OpenCodeTarget) async throws -> [OpenCodeForm]{[try await form(target:target,id:"frm_owned")]}
  func form(target:OpenCodeTarget,id:String) async throws -> OpenCodeForm{
    let hiddenSuffix=hidden ? #","hidden":true,"default":"synthetic-default""# : ""
    let state=settled ? #"{"status":"answered","answer":{"choice":"a"}}"# : #"{"status":"pending"}"#
    return try JSONDecoder().decode(OpenCodeForm.self,from:Data((#"{"id":"frm_owned","sessionID":"ses_owned","title":"Choose","fields":[{"key":"choice","type":"string","required":\#(required),"options":[{"value":"a","label":"A"}]\#(hiddenSuffix)}],"state":\#(state)}"#).utf8))
  }
  func replyForm(target:OpenCodeTarget,form:OpenCodeForm,answer:[String:OpenCodeFormValue]) async throws -> OpenCodeFormResolution{writes+=1;if uncertain{throw RemoteError.outcomeUnknown};settled=true;return .confirmed}
  func cancelForm(target:OpenCodeTarget,form:OpenCodeForm) async throws -> OpenCodeFormResolution{writes+=1;settled=true;return .confirmed}
  func loseReply(){uncertain=true}
  func finishOnDesktop(){settled=true}
  func changeDefinition(){required=true}
  func hideDefault(){hidden=true}
  func writeCount()->Int{writes}
}
@Suite @MainActor struct NativeFormStoreTests {
  @Test func clearingUnsentAnswersKeepsUnconfirmedReplyEvidence()async throws{
    let memory=NativeFormMemory(),service=NativeFormService(),store=NativeFormStore(persistence:memory)
    try await store.restore();let context=store.activate(target:target(),client:service)
    await store.open(id:"frm_owned",context:context);store.setAnswer(.string("a"),for:"choice");try await store.flush()
    try await store.clearUnsentDrafts()
    #expect(store.answers.isEmpty)
    #expect(try await memory.load().records.isEmpty)
    store.setAnswer(.string("a"),for:"choice");await service.loseReply()
    #expect(!(await store.submit(context:context)))
    try await store.clearUnsentDrafts()
    #expect(store.hasUncertainOperation && store.answers["choice"] == .string("a"))
    #expect(try await memory.load().records.count==1)
    #expect(await service.writeCount()==1)
  }
  func target()->OpenCodeTarget{OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")}
  @Test func unsupportedHiddenDefaultsAreNeverCopiedIntoSavedAnswerDrafts() async throws {
    let memory=NativeFormMemory(),service=NativeFormService(),store=NativeFormStore(persistence:memory)
    try await store.restore();await service.hideDefault()
    let context=store.activate(target:target(),client:service);await store.open(id:"frm_owned",context:context)
    #expect(store.form?.supported==false);#expect(store.answers.isEmpty)
    try await store.flush();#expect(try await memory.load().records.isEmpty)
  }
  @Test func closingAndRelaunchPreserveDraftWithoutSubmitting() async throws {
    let memory=NativeFormMemory(),service=NativeFormService(),target=target()
    let a=NativeFormStore(persistence:memory);try await a.restore();let ca=a.activate(target:target,client:service)
    await a.open(id:"frm_owned",context:ca);a.setAnswer(.string("a"),for:"choice");try await a.flush();a.close()
    let b=NativeFormStore(persistence:memory);try await b.restore();let cb=b.activate(target:target,client:service)
    await b.open(id:"frm_owned",context:cb)
    #expect(b.answers["choice"] == .string("a"));#expect(await service.writeCount()==0)
    await service.changeDefinition();await b.open(id:"frm_owned",context:cb)
    #expect(b.answers.isEmpty)
  }
  @Test func uncertainSubmissionSurvivesRelaunchAndOnlyChecksStatus() async throws {
    let memory=NativeFormMemory(),service=NativeFormService(),target=target()
    let a=NativeFormStore(persistence:memory);try await a.restore();let ca=a.activate(target:target,client:service)
    await a.open(id:"frm_owned",context:ca);a.setAnswer(.string("a"),for:"choice");await service.loseReply()
    #expect(await a.submit(context:ca)==false);#expect(a.hasUncertainOperation)
    let b=NativeFormStore(persistence:memory);try await b.restore();let cb=b.activate(target:target,client:service)
    await b.open(id:"frm_owned",context:cb)
    #expect(b.hasUncertainOperation);#expect(await b.submit(context:cb)==false)
    #expect(await service.writeCount()==1)
    await service.finishOnDesktop();await b.checkStatus(context:cb)
    #expect(!b.hasUncertainOperation);#expect(b.form?.isPending==false)
    #expect(await service.writeCount()==1)
  }
}

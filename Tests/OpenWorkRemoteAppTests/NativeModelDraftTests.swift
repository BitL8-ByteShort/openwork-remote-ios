import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

@Suite @MainActor struct NativeModelDraftTests {
  func model(_ provider:String="provider",id:String="model",variants:[String]=["high"])->OpenCodeModel {
    try! JSONDecoder().decode(OpenCodeModel.self,from:JSONSerialization.data(withJSONObject:["providerID":provider,"id":id,"modelID":id,"name":id,"enabled":true,"status":"active","variants":variants.map{["id":$0]},"capabilities":["tools":true,"input":["text"],"output":["text"]]]))
  }
  func session(_ model:OpenCodeModelRef?=nil)->OpenCodeSession {
    var value:[String:Any]=["id":"ses_owned","projectID":"project","location":["directory":"/project"],"time":["created":1,"updated":2]]
    if let model{value["model"]=try! JSONSerialization.jsonObject(with:JSONEncoder().encode(model))}
    return try! JSONDecoder().decode(OpenCodeSession.self,from:JSONSerialization.data(withJSONObject:value))
  }
  @Test func missingDesktopSelectionNeverFallsBackToTheFirstCatalogEntry() throws {
    let removed=try OpenCodeModelRef(providerID:"old",id:"removed",variant:"custom")
    let snapshot=NativeControlSnapshot(session:session(removed),models:[model()],agents:[],serverDefault:model(),requests:[],saved:[])
    let draft=NativeModelDraft(snapshot:snapshot)
    #expect(draft.current==removed)
    #expect(draft.selectedKey==nil)
    #expect(draft.selection(in:snapshot.models)==nil)
  }
  @Test func nativeVariantIsRetainedAndOnlyAClearModelChoiceResetsIt() throws {
    let current=try OpenCodeModelRef(providerID:"provider",id:"model",variant:"high")
    let models=[model(),model("other",id:"model",variants:["fast"])]
    let snapshot=NativeControlSnapshot(session:session(current),models:models,agents:[],serverDefault:nil,requests:[],saved:[])
    var draft=NativeModelDraft(snapshot:snapshot)
    #expect(draft.variant=="high");#expect(draft.selection(in:models)==current)
    draft.choose(models[1]);#expect(draft.variant.isEmpty)
    #expect(draft.selection(in:models)?.providerID=="other")
  }
}

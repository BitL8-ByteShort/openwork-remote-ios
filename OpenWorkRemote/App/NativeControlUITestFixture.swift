#if DEBUG
import SwiftUI
import OpenWorkRemoteCore

/// Isolated UI fixture: no pairing, credentials, host or network access.
private actor NativeControlUITestService:OpenCodeControlServing {
  var selected=try! OpenCodeModelRef(providerID:"Provider A",id:"shared",variant:"high")
  var agent="build"
  var rules=[try! OpenCodePermissionRule(action:"read",resource:"*.env",effect:.deny)]
  let slow:Bool
  init(slow:Bool){self.slow=slow}
  private func decode<T:Decodable>(_ value:Any,as type:T.Type)throws->T{try JSONDecoder().decode(type,from:JSONSerialization.data(withJSONObject:value))}
  func session(id:String) async throws -> OpenCodeSession {
    if slow{try await Task.sleep(for:.seconds(30))}
    return try decode(["id":id,"projectID":"project","location":["directory":"/synthetic"],"time":["created":1,"updated":2],"model":JSONSerialization.jsonObject(with:JSONEncoder().encode(selected)),"agent":agent,"permissions":JSONSerialization.jsonObject(with:JSONEncoder().encode(rules))],as:OpenCodeSession.self)
  }
  func models(location:OpenCodeLocation) async throws -> [OpenCodeModel]{
    try ["Provider A","Provider B"].map{provider in try decode(["providerID":provider,"id":"shared","modelID":"shared","name":"Model "+provider.suffix(1),"enabled":true,"status":"active","variants":[["id":"high"],["id":"fast"]],"capabilities":["tools":true,"input":["text","image"],"output":["text"]]],as:OpenCodeModel.self)}
  }
  func agents(location:OpenCodeLocation) async throws -> [OpenCodeAgent]{
    try ["build","plan"].map{try decode(["id":$0,"name":$0.capitalized,"mode":"primary","hidden":false,"permissions":[]],as:OpenCodeAgent.self)}
  }
  func defaultModel(location:OpenCodeLocation) async throws -> OpenCodeModel?{try await models(location:location).first}
  func setModel(target:OpenCodeTarget,model:OpenCodeModelRef,expectedModel:OpenCodeModelRef?) async throws -> OpenCodeSession{guard selected==expectedModel else{throw RemoteError.conflict};selected=model;return try await session(id:target.sessionID)}
  func setAgent(target:OpenCodeTarget,agentID:String,expectedAgent:String?) async throws -> OpenCodeSession{guard agent==expectedAgent else{throw RemoteError.conflict};agent=agentID;return try await session(id:target.sessionID)}
  func setSessionRules(target:OpenCodeTarget,rules:[OpenCodePermissionRule],expectedRules:[OpenCodePermissionRule]?) async throws -> OpenCodeSession{guard self.rules==expectedRules else{throw RemoteError.conflict};self.rules=rules;return try await session(id:target.sessionID)}
  func pendingPermissions(target:OpenCodeTarget) async throws -> [OpenCodePermissionRequest]{[]}
  func replyPermission(target:OpenCodeTarget,request:OpenCodePermissionRequest,decision:OpenCodePermissionDecision) async throws -> OpenCodePermissionResolution{.alreadyResolved}
  func savedPermissions(target:OpenCodeTarget) async throws -> [OpenCodeSavedPermission]{[]}
  func removeSavedPermission(target:OpenCodeTarget,id:String) async throws{throw RemoteError.notFound}
}
struct NativeControlUITestFixture:View {
  @State private var store=NativeControlStore()
  @State private var context:NativeControlContext?
  @State private var showing=true
  var body:some View {
    Text("Native settings dismissed").accessibilityIdentifier("native-settings-home")
      .task{
        if context==nil{context=store.activate(target:OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_synthetic",directory:"/synthetic"),client:NativeControlUITestService(slow:ProcessInfo.processInfo.arguments.contains("-slow-native-settings")))}
      }.sheet(isPresented:$showing){if let context{NativeModelSettingsView(store:store,context:context)}}
  }
}
#endif

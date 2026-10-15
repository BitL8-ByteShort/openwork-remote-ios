import Foundation
import Testing
@testable import OpenWorkRemoteCore

actor NativeControlsTransport:HTTPTransport {
  var requests:[URLRequest]=[]
  var model:[String:String]=["providerID":"provider","id":"old"]
  var rules:[[String:String]]=[["action":"read","resource":"*.env","effect":"deny"]]
  var pending=true
  let modelStatus:String
  init(modelStatus:String="active",rules:[[String:String]]?=nil){self.modelStatus=modelStatus;if let rules{self.rules=rules}}
  let catalog=#"{"location":{"directory":"/project"},"data":[{"id":"new","modelID":"provider-actual","providerID":"provider","name":"Native model","enabled":true,"status":"active","variants":[{"id":"high","headers":{"private":"discard"}}],"capabilities":{"tools":true,"input":["text","image"],"output":["text"]}}]}"#
  func data(for request:URLRequest) async throws -> (Data,Int) {
    requests.append(request);let path=request.url!.path
    if path=="/api/info"{return (Data(#"{"version":"2.0.29","urls":[],"paths":{"tmp":"/tmp"}}"#.utf8),200)}
    if path=="/api/model"{return (Data(catalog.replacingOccurrences(of:"\"status\":\"active\"",with:"\"status\":\"\(modelStatus)\"").utf8),200)}
    if path.hasSuffix("/model") && request.httpMethod=="POST" {
      let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
      model=body["model"] as! [String:String];return (Data(),204)
    }
    if path.hasSuffix("/permission/per_owned/reply") {pending=false;return (Data(),204)}
    if path.hasSuffix("/permission") {
      return (Data((pending ? #"{"data":[{"id":"per_owned","sessionID":"ses_owned","action":"read","resources":["test.txt"],"save":["test.txt"]}]}"# : #"{"data":[]}"#).utf8),200)
    }
    if request.httpMethod=="PATCH" {
      let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
      rules=body["permissions"] as! [[String:String]];return (Data(),204)
    }
    return (try JSONSerialization.data(withJSONObject:["data":["id":"ses_owned","projectID":"project","model":model,
      "permissions":rules,"location":["directory":"/project"],"time":["created":1,"updated":2]]]),200)
  }
  func allRequests()->[URLRequest]{requests}
  func settle(){pending=false}
}
@Suite struct OpenCodeControlTests {
  func setup(_ transport:NativeControlsTransport) throws -> (OpenCodeClient,OpenCodeTarget) {
    let connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    return (try OpenCodeClient(connection:connection,token:"synthetic-token",transport:transport),OpenCodeTarget(connectionID:connection.id,projectID:"project",sessionID:"ses_owned",directory:"/project"))
  }
  @Test func catalogUsesNativeReferenceVariantsAndModalities() async throws {
    let (client,_)=try setup(NativeControlsTransport())
    let models=try await client.models(location:OpenCodeLocation(directory:"/project"))
    #expect(models.first?.id=="new")
    #expect(models.first?.modelID=="provider-actual")
    #expect(models.first?.variants.map(\.id)==["high"])
    #expect(models.first?.capabilities.input==["text","image"])
  }
  @Test func modelSelectionReadbackUsesProviderIDAndIDWithoutInventingReasoning() async throws {
    let (client,target)=try setup(NativeControlsTransport())
    let chosen=try OpenCodeModelRef(providerID:"provider",id:"new",variant:"high")
    let actual=try await client.setModel(target:target,model:chosen,expectedModel:OpenCodeModelRef(providerID:"provider",id:"old"))
    #expect(actual.model==chosen)
  }
  @Test func staleDesktopSelectionOrUnsupportedVariantCannotOverwriteAnything() async throws {
    let transport=NativeControlsTransport(),(client,target)=try setup(transport)
    await #expect(throws:RemoteError.conflict){_ = try await client.setModel(target:target,model:OpenCodeModelRef(providerID:"provider",id:"new"),expectedModel:nil)}
    await #expect(throws:RemoteError.invalidResponse){_ = try await client.setModel(target:target,model:OpenCodeModelRef(providerID:"provider",id:"new",variant:"invented"),expectedModel:OpenCodeModelRef(providerID:"provider",id:"old"))}
    #expect(await transport.allRequests().contains{$0.httpMethod=="POST"}==false)
  }
  @Test func modelIdentityIsDistinctAcrossProvidersAndDelimiterCharacters() async throws {
    let fields:[(String,String)]=[("one","same"),("two","same"),("a/b","c"),("a","b/c"),("a\u{301}\u{323}","id"),("a\u{323}\u{301}","id")]
    let models=fields.map{provider,id in
      ["providerID":provider,"id":id,"modelID":id,"name":"Synthetic","enabled":true,"status":"active",
       "variants":[],"capabilities":["tools":true,"input":["text"],"output":["text"]]] as [String:Any]
    }
    let bytes=try JSONSerialization.data(withJSONObject:["location":["directory":"/project"],"data":models])
    let connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:connection,token:"synthetic-token",transport:NativeResponseTransport(String(decoding:bytes,as:UTF8.self)))
    let catalog=try await client.models(location:OpenCodeLocation(directory:"/project"))
    #expect(Set(catalog.map(\.selectionKey)).count==6)
  }
  @Test func anUnknownModelStatusCannotBeAssumedSupported() async throws {
    let transport=NativeControlsTransport(modelStatus:"future-status"),(client,target)=try setup(transport)
    await #expect(throws:RemoteError.invalidResponse){_ = try await client.setModel(target:target,model:OpenCodeModelRef(providerID:"provider",id:"new"),expectedModel:OpenCodeModelRef(providerID:"provider",id:"old"))}
    #expect(await transport.allRequests().contains{$0.httpMethod=="POST"}==false)
  }
}

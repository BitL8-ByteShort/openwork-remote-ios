import Foundation
import Testing
@testable import OpenWorkRemoteCore

actor NativeFileTransport:HTTPTransport {
  let pdf:Bool
  var selected="model"
  var requests:[URLRequest]=[]
  var lost=false
  var defaultVariant=false
  init(pdf:Bool){self.pdf=pdf}
  func data(for request:URLRequest) async throws -> (Data,Int){
    requests.append(request);let path=request.url!.path
    if path=="/api/info"{return(Data(#"{"version":"2.0.29","urls":[],"paths":{"tmp":"/native tmp"}}"#.utf8),200)}
    if path=="/api/model"{return(try JSONSerialization.data(withJSONObject:["location":["directory":"/project"],"data":[["providerID":"provider","id":"model","modelID":"model","name":"Model","enabled":true,"status":"active","variants":[],"capabilities":["tools":true,"input":pdf ? ["text","pdf"] : ["text"],"output":["text"]]]]]),200)}
    if path=="/api/experimental/fs/write"{
      if lost{throw URLError(.networkConnectionLost)}
      let destination=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first{$0.name=="path"}!.value!
      return(try JSONSerialization.data(withJSONObject:["location":["directory":"/project"],"data":["path":destination]]),200)
    }
    return(try JSONSerialization.data(withJSONObject:["data":["id":"ses_owned","projectID":"project","model":defaultVariant ? ["providerID":"provider","id":selected,"variant":"default"] : ["providerID":"provider","id":selected],"location":["directory":"/project"],"time":["created":1,"updated":2]]]),200)
  }
  func loseUpload(){lost=true}
  func useDefaultVariant(){defaultVariant=true}
  func changeModel(){selected="another"}
  func allRequests()->[URLRequest]{requests}
}
@Suite struct OpenCodeFileTests {
  let pdf=Data("%PDF-1.4\nSynthetic selected PDF\n%%EOF\n".utf8)
  func setup(_ transport:NativeFileTransport)throws->(OpenCodeClient,OpenCodeTarget){
    let c=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    return(try OpenCodeClient(connection:c,token:"synthetic",transport:transport),OpenCodeTarget(connectionID:c.id,projectID:"project",sessionID:"ses_owned",directory:"/project"))
  }
  @Test func nativeDefaultVariantAliasIsAConfirmedNoOpAndAValidEffectiveModel() async throws {
    let transport=NativeFileTransport(pdf:true),(client,target)=try setup(transport)
    await transport.useDefaultVariant()
    let before=try await client.session(id:target.sessionID)
    let requested=try OpenCodeModelRef(providerID:"provider",id:"model")
    let actual=try await client.setModel(target:target,model:requested,expectedModel:before.model)
    #expect(actual.model?.variant=="default")
    #expect(try await client.attachmentModel(target:target).id=="model")
  }
  @Test func supportedMediaStaysInlineAndItsSavedDescriptorContainsNoRawBytes() async throws {
    let transport=NativeFileTransport(pdf:true),(client,target)=try setup(transport)
    let model=try #require(try await client.models(location:OpenCodeLocation(directory:target.directory)).first)
    let file=try await client.prepareAttachment(bytes:pdf,name:"sample.pdf",mime:"application/pdf",target:target,model:model)
    #expect(file.placement == .inline)
    #expect(try file.inlineURI().hasPrefix("data:application/pdf;base64,"))
    let saved=try JSONEncoder().encode(file)
    #expect(!String(decoding:saved,as:UTF8.self).contains(pdf.base64EncodedString()))
    let restored=try JSONDecoder().decode(OpenCodePromptFile.self,from:saved)
    #expect(restored.sha256==file.sha256)
    #expect(throws:RemoteError.unavailable){try restored.inlineURI()}
    #expect(await transport.allRequests().contains{$0.httpMethod=="POST"}==false)
  }
  @Test func unsupportedMediaUsesOnlyFreshOwnedNativeTemporaryDestinations() async throws {
    let transport=NativeFileTransport(pdf:false),(client,target)=try setup(transport)
    let model=try #require(try await client.models(location:OpenCodeLocation(directory:target.directory)).first)
    let a=try await client.prepareAttachment(bytes:pdf,name:"../../a\\b.pdf",mime:"application/pdf",target:target,model:model)
    let b=try await client.prepareAttachment(bytes:pdf,name:"../../a\\b.pdf",mime:"application/pdf",target:target,model:model)
    #expect(a.placement == .staged);#expect(a.stagedPath != b.stagedPath)
    #expect(a.stagedPath?.hasPrefix("/native tmp/uploads/")==true)
    #expect(!a.name.contains("/") && !a.name.contains("\\"))
    let writes=await transport.allRequests().filter{$0.httpMethod=="POST"}
    #expect(writes.count==2);#expect(writes.allSatisfy{$0.url?.path=="/api/experimental/fs/write" && $0.httpBody==pdf})
  }
  @Test func lostUploadIsNotRetriedAndAChangedModelCannotReceiveAnOldInlineChoice() async throws {
    let transport=NativeFileTransport(pdf:false),(client,target)=try setup(transport)
    let model=try #require(try await client.models(location:OpenCodeLocation(directory:target.directory)).first)
    await transport.loseUpload()
    await #expect(throws:RemoteError.outcomeUnknown){_ = try await client.prepareAttachment(bytes:pdf,name:"sample.pdf",mime:"application/pdf",target:target,model:model)}
    #expect(await transport.allRequests().filter{$0.httpMethod=="POST"}.count==1)
    await transport.changeModel()
    await #expect(throws:RemoteError.conflict){_ = try await client.prepareAttachment(bytes:pdf,name:"sample.pdf",mime:"application/pdf",target:target,model:model)}
    #expect(await transport.allRequests().filter{$0.httpMethod=="POST"}.count==1)
  }
  @Test func malformedOrOversizedSelectedBytesNeverReachAnUpload() async throws {
    let transport=NativeFileTransport(pdf:false),(client,target)=try setup(transport)
    let model=try #require(try await client.models(location:OpenCodeLocation(directory:target.directory)).first)
    await #expect(throws:RemoteError.invalidResponse){_ = try await client.prepareAttachment(bytes:Data("not an image".utf8),name:"image.png",mime:"image/png",target:target,model:model)}
    await #expect(throws:RemoteError.oversized){_ = try await client.prepareAttachment(bytes:Data(repeating:0,count:20*1_048_576+1),name:"sample.pdf",mime:"application/pdf",target:target,model:model)}
    #expect(await transport.allRequests().contains{$0.httpMethod=="POST"}==false)
  }
}

import Foundation
import Testing
import CoreGraphics
@testable import OpenWorkRemoteCore

private struct NativeMaximumFileDiagnosticTransport:HTTPTransport {
  let base=SessionTransport(profile:.openCode)
  func data(for request:URLRequest) async throws -> (Data,Int){try await data(for:request,maximumBytes:8_388_608)}
  func data(for request:URLRequest,maximumBytes:Int) async throws -> (Data,Int){
    let value=try await base.data(for:request,maximumBytes:maximumBytes)
    let path=request.url!.path.hasPrefix("/auth/") ? "/auth/<redacted>" : request.url!.path
    print("Owned maximum wire: \(request.httpMethod ?? "GET") \(path) request bytes \(request.httpBody?.count ?? 0), HTTP \(value.1), response bytes \(value.0.count)")
    return value
  }
}
@Suite struct OpenCodeLiveFileTests {
  private struct Fixture:Decodable{let pairing:String;let projectID:String;let sessionID:String;let directory:String;let nonce:String}
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_FILES_FIXTURE"] != nil))
  func nativeInlineImageAndStagedPathAdmissionWithoutProviderExecution() async throws {
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_FILES_FIXTURE"])
    let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let payload=try OpenCodePairingPayload.parse(fixture.pairing),origin=try #require(payload.origins.first)
    let credential=try await OpenCodePairingClient().redeem(payload,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned native file qualification")
    let client=try OpenCodeClient(connection:connection,token:credential.token)
    let target=OpenCodeTarget(connectionID:connection.id,projectID:fixture.projectID,sessionID:fixture.sessionID,directory:fixture.directory)
    let models=try await client.models(location:OpenCodeLocation(directory:fixture.directory))
    let model=try #require(models.first{$0.selectable && $0.capabilities.input.contains("image")})
    let before=try await client.session(id:target.sessionID)
    _ = try await client.setModel(target:target,model:OpenCodeModelRef(providerID:model.providerID,id:model.id),expectedModel:before.model)
    print("Owned file qualification: model selection confirmed")
    let inline=try await client.prepareAttachment(bytes:Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPQCFjwHwAD1AIYT3hZ1AAAAABJRU5ErkJggg==")!,name:"inline.png",mime:"image/png",target:target,model:model)
    #expect(inline.placement == .inline)
    print("Owned file qualification: inline prepared")
    let first=try OpenCodePrompt(text:"PocketWork synthetic inline image admission",resume:false,files:[inline])
    #expect(try await client.send(target:target,input:first).matches(first,sessionID:target.sessionID))
    print("Owned file qualification: inline admitted")
    let staged=try await client.prepareAttachment(bytes:Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAB9EAAAABCAYAAABpP15DAAAAI0lEQVR4nO3DAQ0AAAgDIOMYx4hveovAxuylqqqqqqqqqmr6IMtWuJb8CXAAAAAASUVORK5CYII=")!,name:"PocketWork-qualification-"+fixture.nonce+".png",mime:"image/png",target:target,model:model)
    #expect(staged.placement == .staged)
    print("Owned file qualification: staged upload acknowledged")
    let second=try OpenCodePrompt(text:"PocketWork synthetic staged path admission",resume:false,files:[staged])
    #expect(try await client.send(target:target,input:second).matches(second,sessionID:target.sessionID))
    print("Owned file qualification: staged reference admitted")
    let inbox=try await client.inbox(target:target)
    #expect(inbox.first{$0.id==first.id}?.user?.matches(first,sessionID:target.sessionID)==true)
    #expect(inbox.first{$0.id==second.id}?.user?.matches(second,sessionID:target.sessionID)==true)
  }
  private func syntheticPDF(bytes:Int)throws->Data{
    var data=Data("%PDF-1.7\n".utf8),offsets=[0]
    let objects=["<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << >> >>","<< /Length 0 >>\nstream\n\nendstream"]
    for (index,object) in objects.enumerated(){offsets.append(data.count);data.append(Data("\(index+1) 0 obj\n\(object)\nendobj\n".utf8))}
    func tail(_ start:Int)->Data{
      let entries=offsets.dropFirst().map{String(format:"%010d 00000 n \n",$0)}.joined()
      return Data(("xref\n0 5\n0000000000 65535 f \n"+entries+"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n"+String(format:"%010d",start)+"\n%%EOF\n").utf8)
    }
    let count=bytes-data.count-tail(0).count
    guard count>2 else{throw RemoteError.invalidResponse}
    var padding=Data(repeating:32,count:count)
    for index in stride(from:0,to:count,by:1024){padding[index]=37;padding[min(index+1023,count-1)]=10}
    data.append(padding);data.append(tail(data.count))
    #expect(data.count==bytes)
    let provider=try #require(CGDataProvider(data:data as CFData))
    #expect(try #require(CGPDFDocument(provider)).numberOfPages==1)
    return data
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_MAX_FILES_FIXTURE"] != nil))
  func twoTwentyMiBPDFsAdmitAtTheFortyMiBMessageLimitWithoutExecution() async throws{
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_MAX_FILES_FIXTURE"])
    let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
    let payload=try OpenCodePairingPayload.parse(fixture.pairing),origin=try #require(payload.origins.first)
    let transport=NativeMaximumFileDiagnosticTransport()
    let credential=try await OpenCodePairingClient(transport:transport).redeem(payload,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned native maximum-file qualification")
    let client=try OpenCodeClient(connection:connection,token:credential.token,transport:transport)
    let target=OpenCodeTarget(connectionID:connection.id,projectID:fixture.projectID,sessionID:fixture.sessionID,directory:fixture.directory)
    let models=try await client.models(location:OpenCodeLocation(directory:fixture.directory))
    let model=try #require(models.first{$0.selectable && $0.capabilities.input.contains("pdf")})
    let before=try await client.session(id:target.sessionID)
    _=try await client.setModel(target:target,model:OpenCodeModelRef(providerID:model.providerID,id:model.id),expectedModel:before.model)
    print("Owned maximum-file qualification: model selection confirmed")
    let small=try await client.prepareAttachment(bytes:syntheticPDF(bytes:5*1_048_576),name:"Inline-five-MiB.pdf",mime:"application/pdf",target:target,model:model)
    #expect(small.placement == .inline)
    let inlinePrompt=try OpenCodePrompt(text:"Synthetic five MiB inline PDF admission only",resume:false,files:[small])
    #expect(try await client.send(target:target,input:inlinePrompt).matches(inlinePrompt,sessionID:target.sessionID))
    print("Owned maximum-file qualification: five MiB inline PDF admitted")
    let bytes=try syntheticPDF(bytes:20*1_048_576)
    let a=try await client.prepareAttachment(bytes:bytes,name:"PocketWork-qualification-"+fixture.nonce+"-Maximum-A.pdf",mime:"application/pdf",target:target,model:model)
    let b=try await client.prepareAttachment(bytes:bytes,name:"PocketWork-qualification-"+fixture.nonce+"-Maximum-B.pdf",mime:"application/pdf",target:target,model:model)
    #expect(a.placement == .staged);#expect(b.placement == .staged)
    print("Owned maximum-file qualification: two valid twenty MiB PDFs prepared")
    let prompt=try OpenCodePrompt(text:"Synthetic maximum-size PDF admission only",resume:false,files:[a,b])
    #expect(try await client.send(target:target,input:prompt).matches(prompt,sessionID:target.sessionID))
    print("Owned maximum-file qualification: forty MiB of staged files admitted with exact path metadata")
    let inbox=try await client.inbox(target:target)
    #expect(inbox.first{$0.id==prompt.id}?.user?.matches(prompt,sessionID:target.sessionID)==true)
    #expect(inbox.first{$0.id==inlinePrompt.id}?.user?.matches(inlinePrompt,sessionID:target.sessionID)==true)
    #expect(try await !client.activeSessions().contains(target.sessionID))
    print("Owned maximum-file qualification: durable inbox verified; execution disabled")
  }

}

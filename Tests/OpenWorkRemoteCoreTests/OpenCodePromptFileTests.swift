import Foundation
import Testing
@testable import OpenWorkRemoteCore

@Suite struct OpenCodePromptFileTests {
  let pdf=Data("%PDF-1.4\nSynthetic selected PDF\n%%EOF\n".utf8)
  func file(inline:Bool) async throws -> OpenCodePromptFile{
    let transport=NativeFileTransport(pdf:inline),(client,target)=try OpenCodeFileTests().setup(transport)
    let model=try #require(try await client.models(location:OpenCodeLocation(directory:target.directory)).first)
    return try await client.prepareAttachment(bytes:pdf,name:"sample.pdf",mime:"application/pdf",target:target,model:model)
  }
  @Test func fileOnlyPromptUsesInlineWireBytesButPersistsOnlyIdentity() async throws {
    let attachment=try await file(inline:true)
    let prompt=try OpenCodePrompt(text:"",files:[attachment])
    let body=try JSONSerialization.jsonObject(with:prompt.wireBody()) as! [String:Any]
    #expect((body["files"] as? [[String:String]])?.first?["uri"]=="data:application/pdf;base64,"+pdf.base64EncodedString())
    #expect(body["target"]==nil)
    let saved=try JSONEncoder().encode(prompt)
    #expect(!String(decoding:saved,as:UTF8.self).contains(pdf.base64EncodedString()))
    let recovered=try JSONDecoder().decode(OpenCodePrompt.self,from:saved)
    #expect(recovered==prompt)
    #expect(throws:RemoteError.unavailable){try recovered.wireBody()}
  }
  @Test func stagedFilesMatchOfficialPathTextAndPresentationMetadata() async throws {
    let attachment=try await file(inline:false),prompt=try OpenCodePrompt(text:"Read this",files:[attachment])
    let body=try JSONSerialization.jsonObject(with:prompt.wireBody()) as! [String:Any]
    #expect(body["text"] as? String=="Read this\nAttached file: `"+attachment.stagedPath!+"`")
    #expect(body["files"]==nil)
    let metadata=body["metadata"] as? [String:Any]
    #expect(metadata?["displayText"] as? String=="Read this")
    #expect((metadata?["attachments"] as? [[String:String]])?.first?["path"]==attachment.stagedPath)
  }
  @Test func materializedFileBytesAndIdentityMustMatchThePersistedIntent() async throws {
    let attachment=try await file(inline:true),prompt=try OpenCodePrompt(text:"Review",files:[attachment])
    func receipt(_ bytes:Data)throws->OpenCodePromptAdmission{
      try JSONDecoder().decode(OpenCodePromptAdmission.self,from:JSONSerialization.data(withJSONObject:["id":prompt.id,"sessionID":attachment.target.sessionID,"type":"user","payload":["text":"Review","files":[["data":bytes.base64EncodedString(),"mime":"application/pdf","name":"sample.pdf","source":["type":"inline"]]]]]))
    }
    #expect(try receipt(pdf).matches(prompt,sessionID:attachment.target.sessionID))
    #expect(try !receipt(Data("Different admitted file".utf8)).matches(prompt,sessionID:attachment.target.sessionID))
    #expect(try receipt(pdf).matches(OpenCodePrompt(id:prompt.id,text:"Review"),sessionID:attachment.target.sessionID)==false)
  }
  @Test func projectedHistoryReconcilesTheSameMaterializedAttachmentAndKeepsPresentationHonest() async throws {
    let attachment=try await file(inline:true),prompt=try OpenCodePrompt(text:"Review",files:[attachment])
    let body:[String:Any]=["id":prompt.id,"type":"user","text":"Review","files":[["data":pdf.base64EncodedString(),"mime":"application/pdf","name":"sample.pdf","source":["type":"inline"]]],"time":["created":1]]
    let message=try JSONDecoder().decode(OpenCodeMessage.self,from:JSONSerialization.data(withJSONObject:body))
    #expect(message.matches(prompt))
    let staged=try await file(inline:false),stagedPrompt=try OpenCodePrompt(text:"Review",files:[staged])
    var projected:[String:Any]=["id":stagedPrompt.id,"type":"user","text":stagedPrompt.wireText,"time":["created":1],
      "metadata":["displayText":"Review","comments":[],"attachments":[["name":staged.name,"mime":staged.mime,"path":staged.stagedPath!]]]]
    var decoded=try JSONDecoder().decode(OpenCodeMessage.self,from:JSONSerialization.data(withJSONObject:projected))
    #expect(decoded.matches(stagedPrompt))
    #expect(decoded.presentation(sessionID:staged.target.sessionID,active:false)?.blocks.first?.text=="Review")
    projected["metadata"]=["displayText":"Hide the original text","comments":[],"attachments":[["name":staged.name,"mime":staged.mime,"path":staged.stagedPath!]]]
    decoded=try JSONDecoder().decode(OpenCodeMessage.self,from:JSONSerialization.data(withJSONObject:projected))
    #expect(decoded.presentation(sessionID:staged.target.sessionID,active:false)?.blocks.first?.text==stagedPrompt.wireText)
  }
  @Test func aggregateLimitsAndAnotherChatAreRejectedBeforeSend() async throws {
    let attachment=try await file(inline:true)
    #expect(throws:RemoteError.oversized){try OpenCodePrompt(text:"Review",files:Array(repeating:attachment,count:5))}
    let c=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Other")
    let transport=NativeControlsTransport(),client=try OpenCodeClient(connection:c,token:"synthetic",transport:transport)
    let target=OpenCodeTarget(connectionID:c.id,projectID:"project",sessionID:"ses_owned",directory:"/project")
    let prompt=try OpenCodePrompt(text:"Review",files:[attachment])
    await #expect(throws:OpenCodePromptNotSubmitted(reason:.conflict)){_ = try await client.send(target:target,input:prompt)}
    #expect(await transport.allRequests().contains{$0.httpMethod=="POST"}==false)
  }
}

import Foundation
import Testing
@testable import OpenWorkRemoteCore

private actor NativeResultTransport:HTTPTransport {
  var changed=false
  var probeStatus=206
  var advertisedSize:Int?
  var raceAfterRead=false
  var read=false
  func changeAfterRead(){raceAfterRead=true}
  func probeStatus(_ value:Int){probeStatus=value}
  func advertiseSize(_ value:Int){advertisedSize=value}
  var maliciousList=false
  var requests:[URLRequest]=[]
  var bytes=Data("A synthetic result\n".utf8)
  func changeOnRead(){changed=true}
  func returnOutsideEntry(){maliciousList=true}
  func data(for request:URLRequest) async throws -> (Data,Int){
    requests.append(request)
    if request.url!.path=="/api/fs/list"{
      let path=maliciousList ? "../secret.txt":"result + 日本語.txt"
      return(try JSONSerialization.data(withJSONObject:["location":["directory":"/project"],"data":[["path":path,"type":"file"]]]),200)
    }
    return(Data(#"{"data":{"id":"ses_owned","projectID":"project","location":{"directory":"/project"},"time":{"created":1,"updated":2}}}"#.utf8),200)
  }
  func binary(for request:URLRequest,maximumBytes:Int) async throws -> BinaryHTTPResponse{
    requests.append(request)
    if request.value(forHTTPHeaderField:"Range")=="bytes=0-0"{
      return BinaryHTTPResponse(data:bytes.prefix(1),status:probeStatus,mime:"text/plain",contentRange:"bytes 0-0/\(advertisedSize ?? bytes.count)",entityTag:raceAfterRead && read ? "W/\"changed\"":"W/\"synthetic\"",length:1)
    }
    read=true
    return BinaryHTTPResponse(data:bytes,status:changed ? 200:206,mime:"text/plain",contentRange:"bytes 0-\(bytes.count-1)/\(bytes.count)",entityTag:changed ? "W/\"changed\"":"W/\"synthetic\"",length:bytes.count)
  }
  func called()->[URLRequest]{requests}
}
@Suite struct OpenCodeResultTests {
  private var target:OpenCodeTarget{OpenCodeTarget(connectionID:ConnectionID(),projectID:"project",sessionID:"ses_owned",directory:"/project")}
  @Test func structuredReferencesKeepUnicodeAndRejectOutsideOrAmbiguousPaths() throws{
    let t=target
    let file=try OpenCodeResultFile(toolURI:"file:///project/result%20%2B%20%E6%97%A5%E6%9C%AC%E8%AA%9E.txt",target:t)
    #expect(file.relativePath=="result + 日本語.txt")
    for uri in ["https://example.test/result.txt","data:text/plain;base64,YQ==","file://another-host/project/a.txt","file:///project2/a.txt","file:///project/../secret.txt","file:///project/%2e%2e/secret.txt","file:///project/a.txt?token=secret","file:///project/a.txt#x"]{
      #expect(throws:(any Error).self){try OpenCodeResultFile(toolURI:uri,target:t)}
    }
    let a=try OpenCodeResultFile(relativePath:"caf\u{e9}.txt",target:t)
    let b=try OpenCodeResultFile(relativePath:"cafe\u{301}.txt",target:t)
    #expect(a.id != b.id)
  }
  @Test func onlyStructuredToolOutputsBecomeResults() throws{
    let page=try JSONDecoder().decode(OpenCodeMessagePage.self,from:Data(#"{"data":[{"id":"msg_assistant","type":"assistant","time":{"created":1},"snapshot":{"files":["changed.md","../outside.md"]},"content":[{"type":"text","text":"Download file:///project/not-a-result.txt"},{"type":"tool","name":"generate","state":{"status":"completed","content":[{"type":"file","uri":"file:///project/result.txt","mime":"text/plain"},{"type":"file","uri":"https://example.test/outside.txt","mime":"text/plain"},{"type":"file","uri":123,"mime":"text/plain"}]}}]}],"cursor":{}}"#.utf8))
    let catalog=OpenCodeResultCatalog(messages:page.data,target:target)
    #expect(catalog.files.map(\.relativePath)==["result.txt","changed.md"])
    #expect(catalog.unsupportedReferences==3)
  }
  @Test func nativeRangeDownloadIsBoundToTargetAndValidator() async throws{
    let transport=NativeResultTransport(),t=target
    let connection=try OpenCodeConnection(id:t.connectionID,origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:connection,token:"synthetic",transport:transport)
    let ref=try OpenCodeResultFile(relativePath:"result + 日本語.txt",target:t)
    let info=try await client.probeResult(ref)
    let result=try await client.downloadResult(info)
    #expect(String(decoding:result.data,as:UTF8.self)=="A synthetic result\n")
    #expect(result.sha256.count==64)
    let requests=await transport.called()
    #expect(requests.allSatisfy{$0.httpMethod=="GET"})
    #expect(requests.filter{$0.value(forHTTPHeaderField:"Range") != nil}.count==4)
    #expect(requests.contains{$0.url!.absoluteString.contains("result%20%2B%20")})
    await transport.changeOnRead()
    await #expect(throws:RemoteError.conflict){try await client.downloadResult(info)}
  }
  @Test func directoryResultsCannotBroadenTheSelectedProject() async throws{
    let transport=NativeResultTransport(),t=target
    let c=try OpenCodeConnection(id:t.connectionID,origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:c,token:"synthetic",transport:transport)
    #expect(try await client.projectFiles(target:t,directory:nil).count==1)
    await transport.returnOutsideEntry()
    await #expect(throws:RemoteError.invalidResponse){try await client.projectFiles(target:t,directory:nil)}
    await #expect(throws:RemoteError.invalidResponse){try await client.projectFiles(target:t,directory:"../")}
  }
  @Test(arguments:[200,304,416]) func unexpectedProbeStatusesNeverBecomeAFile(status:Int) async throws{
    let transport=NativeResultTransport(),t=target
    let connection=try OpenCodeConnection(id:t.connectionID,origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:connection,token:"synthetic",transport:transport)
    await transport.probeStatus(status)
    await #expect(throws:(any Error).self){try await client.probeResult(OpenCodeResultFile(relativePath:"result.txt",target:t))}
  }
  @Test func oversizedFileAndPostReadVersionChangeAreRejected() async throws{
    let transport=NativeResultTransport(),t=target
    let connection=try OpenCodeConnection(id:t.connectionID,origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:connection,token:"synthetic",transport:transport)
    let file=try OpenCodeResultFile(relativePath:"result.txt",target:t)
    await transport.advertiseSize(20*1_048_576+1)
    await #expect(throws:RemoteError.oversized){try await client.probeResult(file)}
    await transport.advertiseSize("A synthetic result\n".utf8.count)
    let info=try await client.probeResult(file)
    await transport.changeAfterRead()
    await #expect(throws:RemoteError.conflict){try await client.downloadResult(info)}
  }

}

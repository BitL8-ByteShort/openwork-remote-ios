import Foundation
import Testing
import OpenWorkRemoteCore

private actor LiveNativeEventFlag {
  private var value=false
  func mark(){value=true}
  func observed()->Bool{value}
}
/// Private opt-in fixture contains only a fresh QR and owned synthetic resources.
@Suite struct OpenCodeLiveHistoryTests {
  private struct Fixture:Decodable {
    let pairing:String
    let projectID:String
    let sessionID:String
    let directory:String
    let messageIDs:[String]
  }
  @Test(.enabled(if:ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_HISTORY_FIXTURE"] != nil))
  func typedNativeHistoryLocationAdmissionAndEvents() async throws {
    let path=try #require(ProcessInfo.processInfo.environment["POCKETWORK_NATIVE_HISTORY_FIXTURE"])
    let bytes=try Data(contentsOf:URL(fileURLWithPath:path))
    #expect(bytes.count<100_000)
    let fixture=try JSONDecoder().decode(Fixture.self,from:bytes)
    let payload=try OpenCodePairingPayload.parse(fixture.pairing)
    let origin=try #require(payload.origins.first)
    let pairing=try await OpenCodePairingClient().redeem(payload,origin:origin)
    let connection=try OpenCodeConnection(origin:origin,displayName:"Owned native qualification")
    let client=try OpenCodeClient(connection:connection,token:pairing.token)
    let info=try await client.info()
    #expect(info.version=="2.0.29")
    let projects=try await client.projects()
    #expect(projects.contains{$0.id==fixture.projectID})
    let location=try await client.location(directory:fixture.directory)
    #expect(location.project.id==fixture.projectID)
    var cursor:String?,ids:[String]=[],compactions=0
    for _ in 0..<5 {
      let page=try await client.messages(sessionID:fixture.sessionID,cursor:cursor)
      ids+=page.data.map(\.id);compactions+=page.data.filter{$0.type=="compaction"}.count;cursor=page.cursor.next
      if cursor==nil{break}
    }
    #expect(ids==Array(fixture.messageIDs.reversed()))
    #expect(ids.count==205);#expect(Set(ids).count==205);#expect(compactions==1)
    let target=OpenCodeTarget(connectionID:connection.id,projectID:fixture.projectID,sessionID:fixture.sessionID,directory:fixture.directory)
    let source=try await client.events(),flag=LiveNativeEventFlag()
    let events=Task {
      do{
        for try await event in source where event.affects(target) {
          if event.type=="session.inbox.enqueued"{await flag.mark();break}
        }
      }catch{}
    }
    defer{events.cancel()}
    let prompt=try OpenCodePrompt(text:"Synthetic admission only. Do not execute.",resume:false)
    let admission=try await client.send(target:target,input:prompt)
    #expect(admission.matches(prompt,sessionID:fixture.sessionID))
    let queued=try await client.inbox(target:target)
    #expect(queued.contains{$0.user?.matches(prompt,sessionID:fixture.sessionID)==true})
    #expect(try await client.interrupt(target:target)==false)
    for _ in 0..<30 {if await flag.observed(){break};try await Task.sleep(for:.milliseconds(100))}
    #expect(await flag.observed())
    events.cancel();await events.value
  }
}

import Foundation
import Testing
@testable import OpenWorkRemoteCore

private actor NativeWorkspaceTransport:HTTPTransport {
  var wrongLocation=false
  var large=false
  var largeSkills=false
  var calls:[(String,String)]=[]
  func changeLocation(){wrongLocation=true}
  func hugeDiff(){large=true}
  func hugeSkillCatalog(){largeSkills=true}
  func methods()->[String]{calls.map(\.0)}
  func paths()->[String]{calls.map(\.1)}
  func data(for r:URLRequest)async throws->(Data,Int){
    let path=r.url!.path;calls.append((r.httpMethod ?? "",path))
    let directory=URLComponents(url:r.url!,resolvingAgainstBaseURL:false)!.queryItems!.first{$0.name=="location[directory]"}!.value!
    let payload:Any
    switch path{
    case "/api/vcs":payload=["provider":"git","branch":["current":"main"]]
    case "/api/vcs/status":payload=[["file":"../shared/日本語.txt","status":"modified","additions":1,"deletions":0]]
    case "/api/vcs/diff":
      #expect(URLComponents(url:r.url!,resolvingAgainstBaseURL:false)!.queryItems!.contains{$0.name=="mode" && $0.value=="working"})
      payload=[["file":"../shared/日本語.txt","status":"modified","additions":1,"deletions":0,"patch":large ? String(repeating:"x",count:1_048_577):"@@ -1 +1 @@\n-old\n+new"]]
    case "/api/skill":
      if largeSkills{payload=(0..<100).map{["id":"skill_"+String($0),"name":"Synthetic skill","path":"/skills/skill/SKILL.md","content":String(repeating:"x",count:90_000)]}}
      else{payload=[["id":"skill_owned","name":"Review","description":"Synthetic instructions","path":"/home/synthetic/.config/skills/review/SKILL.md","content":"Only review the supplied text."]]}
    default:throw RemoteError.invalidResponse
    }
    return(try JSONSerialization.data(withJSONObject:["location":["directory":wrongLocation ? "/different":directory],"data":payload]),200)
  }
}
@Suite struct OpenCodeWorkspaceTests {
  private func setup(_ t:NativeWorkspaceTransport)throws->OpenCodeClient{
    try OpenCodeClient(connection:OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer"),token:"synthetic",transport:t)
  }
  @Test func typedReadOnlyWorkspaceAndSkillsPreserveLocationAndNeverExecute()async throws{
    let t=NativeWorkspaceTransport(),client=try setup(t),location=OpenCodeLocation(directory:"/project C++ 日本語")
    #expect(try await client.workspaceInfo(location:location).provider=="git")
    #expect(try await client.workspaceChanges(location:location).first?.file=="../shared/日本語.txt")
    #expect(try await client.workspaceDiff(location:location).first?.patch.contains("+new")==true)
    let skills=try await client.skills(location:location)
    #expect(skills.first?.name=="Review" && skills.first?.content=="Only review the supplied text.")
    #expect(skills.first?.fingerprint.count==64)
    #expect(await t.methods()==["GET","GET","GET","GET"])
    #expect(await t.paths()==["/api/vcs","/api/vcs/status","/api/vcs/diff","/api/skill"])
  }
  @Test func skillCatalogUsesItsOwnBoundedBudgetBeyondOrdinaryEightMiB()async throws{
    let t=NativeWorkspaceTransport(),client=try setup(t)
    await t.hugeSkillCatalog()
    #expect(try await client.skills(location:OpenCodeLocation(directory:"/project")).count==100)
  }
  @Test func mismatchedLocationAndOversizedDiffFailClosed()async throws{
    let t=NativeWorkspaceTransport(),client=try setup(t),location=OpenCodeLocation(directory:"/project")
    await t.hugeDiff()
    await #expect(throws:RemoteError.oversized){try await client.workspaceDiff(location:location)}
    await t.changeLocation()
    await #expect(throws:RemoteError.conflict){try await client.skills(location:location)}
  }
}

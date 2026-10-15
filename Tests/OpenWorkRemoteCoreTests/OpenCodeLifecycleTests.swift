import Foundation
import Testing
@testable import OpenWorkRemoteCore

private actor NativeLifecycleTransport:HTTPTransport {
  var holdInfo=false,holdPatch=false
  var held:CheckedContinuation<Void,Never>?
  var waiters:[CheckedContinuation<Void,Never>]=[]
  var count=0,patches=0
  var title="Original"
  func hold(_ patch:Bool){holdPatch=patch;holdInfo = !patch}
  func waitForHold()async{if held != nil{return};await withCheckedContinuation{waiters.append($0)}}
  func release(){held?.resume();held=nil}
  func counts()->(Int,Int){(count,patches)}
  private func pause()async{await withCheckedContinuation{held=$0;waiters.forEach{$0.resume()};waiters=[]}}
  func data(for r:URLRequest)async throws->(Data,Int){
    count+=1
    if r.url!.path=="/api/info"{
      if holdInfo{await pause()}
      return(Data(#"{"version":"2.0.29","urls":[],"paths":{"tmp":"/tmp/native"}}"#.utf8),200)
    }
    if r.httpMethod=="PATCH"{patches+=1;if holdPatch{await pause()};title="Renamed";return(Data(),204)}
    let value:[String:Any]=["data":["id":"ses_owned","projectID":"project","title":title,"location":["directory":"/project"],"time":["created":1,"updated":2]]]
    return(try JSONSerialization.data(withJSONObject:value),200)
  }
}
private actor NativeRetirementEventTransport:HTTPTransport{
  var cancelled=false
  var hold=false
  var opening:CheckedContinuation<Void,Never>?
  var source:AsyncThrowingStream<SSEFrame,any Error>.Continuation?
  func holdOpening(){hold=true}
  func isOpening()->Bool{opening != nil}
  func releaseOpening(){opening?.resume();opening=nil}
  func cleanup(){source?.finish();source=nil}
  func data(for request:URLRequest)async throws->(Data,Int){throw RemoteError.unavailable}
  func events(for request:URLRequest)async throws->AsyncThrowingStream<SSEFrame,any Error>{
    if hold{await withCheckedContinuation{opening=$0}}
    return AsyncThrowingStream{continuation in source=continuation;continuation.onTermination={ [weak self] _ in Task{await self?.markCancelled()} }}
  }
  func markCancelled(){cancelled=true}
  func didCancel()->Bool{cancelled}
}
@Suite struct OpenCodeLifecycleTests {
  @Test(.timeLimit(.minutes(1))) func aStreamOpenedAfterRetirementIsDisposedEvenWithoutATypedConsumer()async throws{
    let t=NativeRetirementEventTransport(),connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:connection,token:"synthetic",transport:t)
    await t.holdOpening();let opening=Task{try await client.events()}
    while !(await t.isOpening()){await Task.yield()}
    client.retire();await t.releaseOpening();_ = try? await opening.value
    try await Task.sleep(for:.milliseconds(50))
    #expect(await t.didCancel())
    await t.cleanup()
  }
  private func setup(_ t:NativeLifecycleTransport)throws->(OpenCodeClient,OpenCodeTarget){
    let c=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    return(try OpenCodeClient(connection:c,token:"synthetic",transport:t),OpenCodeTarget(connectionID:c.id,projectID:"project",sessionID:"ses_owned",directory:"/project"))
  }
  @Test(.timeLimit(.minutes(1))) func retiringAlsoClosesAnAlreadyReturnedEventStream()async throws{
    let t=NativeRetirementEventTransport(),connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:connection,token:"synthetic",transport:t)
    let stream=try await client.events(),reading=Task{for try await _ in stream{}}
    client.retire();try await Task.sleep(for:.milliseconds(50))
    #expect(await t.didCancel())
    reading.cancel();_=try? await reading.value
  }
  @Test(.timeLimit(.minutes(1))) func retireDuringPreflightPreventsAnyLateWrite()async throws{
    let t=NativeLifecycleTransport(),(client,target)=try setup(t);await t.hold(false)
    let writing=Task{try await client.rename(target:target,title:"Renamed",expectedTitle:"Original")}
    await t.waitForHold();client.retire();await t.release()
    await #expect(throws:OpenCodeChatNotSubmitted(reason:.cancelled)){try await writing.value}
    #expect(await t.counts().1==0)
    let before=await t.counts().0
    await #expect(throws:(any Error).self){try await client.info()}
    #expect(await t.counts().0==before)
  }
  @Test(.timeLimit(.minutes(1))) func retireAfterDispatchKeepsAnUnconfirmedWriteUnknown()async throws{
    let t=NativeLifecycleTransport(),(client,target)=try setup(t);await t.hold(true)
    let writing=Task{try await client.rename(target:target,title:"Renamed",expectedTitle:"Original")}
    await t.waitForHold();client.retire();await t.release()
    await #expect(throws:RemoteError.outcomeUnknown){try await writing.value}
    #expect(await t.counts().1==1)
  }
}

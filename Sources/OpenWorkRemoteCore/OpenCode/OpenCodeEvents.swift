import Foundation

/// Native events are volatile hints. Authoritative reads repair gaps and overflow.
public struct OpenCodeEvent:Decodable,Sendable {
  public struct Fields:Decodable,Sendable {
    public let sessionID:String?
    public let assistantMessageID:String?
    public let ordinal:Int?
    public let delta:String?
    public let text:String?
  }
  public let id:String
  public let type:String
  public let location:OpenCodeLocation?
  public let data:Fields
  public static func decode(_ frame:SSEFrame) throws -> OpenCodeEvent {
    guard frame.data.utf8.count<=262_144 else{throw RemoteError.oversized}
    guard let bytes=frame.data.data(using:.utf8),let result=try? JSONDecoder().decode(Self.self,from:bytes),
      !result.id.isEmpty,result.id.utf8.count<=2_048,!result.type.isEmpty,result.type.utf8.count<=256,
      (result.data.sessionID?.utf8.count ?? 0)<=2_048,
      (result.data.assistantMessageID?.utf8.count ?? 0)<=2_048,
      result.data.ordinal.map({(0..<4_096).contains($0)}) ?? true else{throw RemoteError.invalidResponse}
    return result
  }
  public func affects(_ target:OpenCodeTarget)->Bool {
    data.sessionID==target.sessionID || type=="server.connected" || type=="location.shutdown"
  }
}
extension OpenCodeClient {
  public func events() async throws -> AsyncThrowingStream<OpenCodeEvent,any Error> {
    var request=try makeRequest(segments:["api","event"])
    request.setValue("text/event-stream",forHTTPHeaderField:"Accept")
    let source=try await transport.events(for:request)
    return AsyncThrowingStream(bufferingPolicy:.bufferingNewest(128)){ continuation in
      let task=Task {
        do {
          for try await frame in source {
            try Task.checkCancellation()
            let event=try OpenCodeEvent.decode(frame)
            if case .dropped=continuation.yield(event){throw RemoteError.oversized}
          }
          continuation.finish()
        } catch{continuation.finish(throwing:error)}
      }
      continuation.onTermination={_ in task.cancel()}
    }
  }
}

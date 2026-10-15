import Foundation

/// Only the transport gate can establish that an operation never reached the base transport.
struct OpenCodeRequestNotDispatched:Error,Sendable{}

/// Synchronous retirement fences requests even while another actor is awaiting preflight.
/// Cancellation callbacks run outside the lock and never contain request bodies or credentials.
final class OpenCodeRequestLifetime:@unchecked Sendable {
  private let lock=NSLock()
  private var active=true
  private var operations:[UUID:@Sendable()->Void]=[:]
  private var authenticationFailure:(@Sendable()->Void)?
  var isActive:Bool{lock.withLock{active}}
  func requireActive()throws{guard isActive else{throw OpenCodeRequestNotDispatched()}}
  func observeAuthenticationFailure(_ handler:@escaping @Sendable()->Void){lock.withLock{if active{authenticationFailure=handler}}}
  func register(_ cancel:@escaping @Sendable()->Void)throws->UUID{
    try lock.withLock{
      guard active else{throw OpenCodeRequestNotDispatched()}
      let id=UUID();operations[id]=cancel;return id
    }
  }
  func finish(_ id:UUID){_ = lock.withLock{operations.removeValue(forKey:id)}}
  func retire(authenticationRejected:Bool=false){
    let result:([@Sendable()->Void],(@Sendable()->Void)?)=lock.withLock{
      guard active else{return([],nil)}
      active=false;let cancels=Array(operations.values),handler=authenticationRejected ? authenticationFailure:nil
      operations.removeAll();authenticationFailure=nil;return(cancels,handler)
    }
    result.0.forEach{$0()};result.1?()
  }
}
private final class NativeCancellationSlot:@unchecked Sendable {
  private let lock=NSLock()
  private var cancelled=false
  private var handler:(@Sendable()->Void)?
  func install(_ handler:@escaping @Sendable()->Void){
    let cancel=lock.withLock{self.handler=handler;return cancelled}
    if cancel{handler()}
  }
  func cancel(){let action=lock.withLock{cancelled=true;return handler};action?()}
}
/// Every typed client request, including direct mutation and binary paths, shares this lifetime.
struct OpenCodeScopedTransport:HTTPTransport {
  let base:any HTTPTransport
  let lifetime:OpenCodeRequestLifetime
  private func perform<Value:Sendable>(_ operation:@escaping @Sendable()async throws->Value)async throws->Value{
    let slot=NativeCancellationSlot()
    let id=try lifetime.register{slot.cancel()}
    defer{lifetime.finish(id)}
    let task=Task{
      try lifetime.requireActive();try Task.checkCancellation()
      let value=try await operation()
      // A completed response from a retired connection cannot enter current state.
      guard lifetime.isActive else{throw CancellationError()}
      return value
    }
    slot.install{task.cancel()}
    return try await withTaskCancellationHandler{try await task.value}onCancel:{slot.cancel()}
  }
  func data(for request:URLRequest)async throws->(Data,Int){try await data(for:request,maximumBytes:8_388_608)}
  func data(for request:URLRequest,maximumBytes:Int)async throws->(Data,Int){
    let result=try await perform{try await base.data(for:request,maximumBytes:maximumBytes)}
    if result.1==401{lifetime.retire(authenticationRejected:true)}
    return result
  }
  func binary(for request:URLRequest,maximumBytes:Int)async throws->BinaryHTTPResponse{
    let result=try await perform{try await base.binary(for:request,maximumBytes:maximumBytes)}
    if result.status==401{lifetime.retire(authenticationRejected:true)}
    return result
  }
  func events(for request:URLRequest)async throws->AsyncThrowingStream<SSEFrame,any Error>{
    do{return try await perform{try await base.events(for:request)}}
    catch{if error as? RemoteError == .unauthorized{lifetime.retire(authenticationRejected:true)};throw error}
  }
}

import Foundation
import Testing
@testable import OpenWorkRemoteCore

private actor LargeNativeHistoryTransport:HTTPTransport {
  var queries:[[URLQueryItem]]=[]
  func data(for request:URLRequest) async throws -> (Data,Int){
    let query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems ?? []
    queries.append(query)
    if query.contains(URLQueryItem(name:"limit",value:"100")){throw RemoteError.oversized}
    return(Data(#"{"data":[{"id":"msg_large","type":"user","text":"One complete message","time":{"created":1}}],"cursor":{"next":"opaque-single-item"}}"#.utf8),200)
  }
  func limits()->[String]{queries.compactMap{$0.first(where:{$0.name=="limit"})?.value}}
}
@Suite struct OpenCodeTransferTests {
  @Test func largeInitialHistoryFallsBackToOneCompleteMessageWithoutTruncatingOrInventingACursor() async throws {
    let transport=LargeNativeHistoryTransport(),connection=try OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Computer")
    let client=try OpenCodeClient(connection:connection,token:"synthetic",transport:transport)
    let page=try await client.messages(sessionID:"ses_owned",cursor:nil)
    #expect(page.data.first?.text=="One complete message")
    #expect(page.cursor.next=="opaque-single-item")
    #expect(await transport.limits()==["100","1"])
  }
}

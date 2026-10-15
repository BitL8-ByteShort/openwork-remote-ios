import Foundation
import Testing
import OpenWorkRemoteCore
@testable import OpenWorkRemoteAppState

private actor NativeSearchReader:OpenCodeSessionSearching {
  func sessions(projectID:String,cursor:String?,search:String?)async throws->OpenCodeSessionPage{
    if search=="slow"{try? await Task.sleep(for:.milliseconds(80))}
    let id=cursor==nil ? "ses_first":"ses_older"
    let value:[String:Any]=["data":[["id":id,"projectID":projectID,"title":search ?? "","location":["directory":"/project"],"time":["created":1,"updated":2]]],"cursor":cursor==nil || search=="loop" ? ["next":"opaque"]:[:]]
    return try JSONDecoder().decode(OpenCodeSessionPage.self,from:JSONSerialization.data(withJSONObject:value))
  }
}
@Suite @MainActor struct OpenCodeSearchTests {
  @Test func repeatedCursorKeepsMatchesAndRequiresANewSearch()async{
    let store=NativeChatSearchStore()
    store.activate(NativeProjectKey(connectionID:ConnectionID(),projectID:"project"),reader:NativeSearchReader())
    await store.search("loop",debounce:false);await store.more()
    #expect(store.results.map(\.id)==["ses_first"])
    #expect(store.cursor==nil && !store.complete && store.notice != nil)
  }
  @Test func pagesOlderMatchesAndFencesLateQueryOrProject()async throws{
    let store=NativeChatSearchStore(),reader=NativeSearchReader()
    let scope=NativeProjectKey(connectionID:ConnectionID(),projectID:"project")
    store.activate(scope,reader:reader)
    await store.search("name",debounce:false)
    #expect(store.results.map(\.id)==["ses_first"] && store.cursor=="opaque")
    await store.more()
    #expect(store.results.map(\.id)==["ses_first","ses_older"] && store.complete)
    let late=Task{await store.search("slow",debounce:false)}
    await Task.yield()
    await store.search("fresh",debounce:false)
    await late.value
    #expect(store.query=="fresh" && store.results.first?.title=="fresh")
    let older=Task{await store.search("slow",debounce:false)}
    await Task.yield()
    store.activate(NativeProjectKey(connectionID:scope.connectionID,projectID:"elsewhere"),reader:reader)
    await older.value
    #expect(store.results.isEmpty && store.query.isEmpty)
  }
}

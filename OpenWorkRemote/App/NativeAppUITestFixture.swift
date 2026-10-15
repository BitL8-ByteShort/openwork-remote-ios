#if DEBUG
import SwiftUI
import OpenWorkRemoteCore

/// Exercises the shared production views through the typed native HTTP client.
/// Synthetic origin/credential; every response is in-process, no real network.
private actor NativeAppUITestTransport:HTTPTransport {
  var admitted:[String:Any]?
  let slow:Bool
  init(slow:Bool){self.slow=slow}
  private var record:[String:Any]{["id":"ses_owned","projectID":"project","title":"Native chat","location":["directory":"/project"],"time":["created":1,"updated":2],"model":["providerID":"Synthetic provider","id":"native-model"],"agent":"build","permissions":[]]}
  private var form:[String:Any]{["id":"frm_owned","sessionID":"ses_owned","title":"Which option do you prefer?","fields":[["key":"answer","type":"string","required":true]],"state":["status":"pending"]]}
  private var model:[String:Any]{["providerID":"Synthetic provider","id":"native-model","modelID":"native-model","name":"Native model","enabled":true,"status":"active","variants":[],"capabilities":["tools":true,"input":["text","image","pdf"],"output":["text"]]]}
  func data(for request:URLRequest) async throws -> (Data,Int){
    let path=request.url!.path,value:Any
    switch path{
    case "/api/info":value=["version":"2.0.29","urls":[],"paths":["tmp":"/tmp/native"]]
    case "/api/project":value=[["id":"project","name":"Native project","canonical":"/project","sandboxes":[],"time":["created":1,"updated":2,"active":2]]]
    case "/api/session":value=["data":[record],"cursor":[:]]
    case "/api/session/ses_owned":value=["data":record]
    case "/api/session/ses_owned/message":value=["data":[["id":"msg_owned","type":"user","text":"Native message","time":["created":1]]],"cursor":[:]]
    case "/api/session/ses_owned/prompt":
      let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
      let files=(body["files"] as? [[String:Any]] ?? []).map{file -> [String:Any] in
        let uri=file["uri"] as! String,parts=uri.split(separator:",",maxSplits:1)
        return ["name":file["name"]!,"mime":String(parts[0].dropFirst(5).split(separator:";")[0]),"data":String(parts[1]),"source":["type":"inline"]]
      }
      admitted=["id":body["id"]!,"sessionID":"ses_owned","type":"user","payload":["text":body["text"]!,"files":files]]
      value=["data":admitted!]
    case "/api/session/ses_owned/inbox":value=["data":admitted.map{[$0]} ?? []]
    case "/api/session/active":value=["data":[:]]
    case "/api/session/ses_owned/permission":value=["data":[["id":"per_owned","sessionID":"ses_owned","action":"read","resources":["notes.txt"]]]]
    case "/api/session/ses_owned/form":value=["data":[form]]
    case "/api/session/ses_owned/form/frm_owned":value=["data":form]
    case "/api/model":
      if slow{try await Task.sleep(for:.seconds(30))}
      value=["location":["directory":"/project"],"data":[model]]
    case "/api/model/default":value=["location":["directory":"/project"],"data":model]
    case "/api/agent":value=["location":["directory":"/project"],"data":[["id":"build","name":"Build","mode":"primary","hidden":false,"permissions":[]]]]
    case "/api/permission/saved":value=["data":[]]
    default:throw RemoteError.invalidResponse
    }
    return(try JSONSerialization.data(withJSONObject:value),200)
  }
  func events(for request:URLRequest) async throws -> AsyncThrowingStream<SSEFrame,any Error>{AsyncThrowingStream{_ in}}
}
struct NativeAppUITestFixture:View {
  @State private var model:AppModel
  init(){
    let directory=FileManager.default.temporaryDirectory.appending(path:"native-shell-ui-"+UUID().uuidString)
    let saved=StoredOpenCodeConnection(connection:try! OpenCodeConnection(origin:URL(string:"https://synthetic.example")!,displayName:"Synthetic computer"),token:"synthetic-token")
    let native=try! NativeAppCoordinator(directory:directory,connectionPersistence:OpenCodePersistence(load:{saved},save:{_ in},remove:{}),transport:NativeAppUITestTransport(slow:ProcessInfo.processInfo.arguments.contains("-slow-native-app-settings")))
    _model=State(initialValue:AppModel(native:native,legacyDraftStore:try! DraftStore(directory:directory),pairingPersistence:PairingPersistence(load:{nil},save:{_ in},remove:{})))
  }
  var body:some View{NavigationStack{ChatView()}.environment(model).tint(Theme.accent).task{await model.start()}}
}
#endif

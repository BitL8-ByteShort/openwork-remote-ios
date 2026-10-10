import Foundation
import Testing
@testable import OpenWorkRemoteCore

private let sampleQuestion = #"{"id":"frm_test","sessionId":"ses_test","revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","supported":true,"reason":null,"fields":[{"key":"layout","kind":"singleChoice","title":"Layout","prompt":"Which layout do you prefer?","custom":false,"options":[{"value":"simple","label":"Same label","description":"Few controls"},{"value":"detailed","label":"Same label","description":"More controls"}]},{"key":"name","kind":"text","title":"Project name","prompt":"What should it be called?","custom":true,"options":[]}]}"#
private actor QuestionsTransport: HTTPTransport {
  var bodies: [Data] = []
  var question = sampleQuestion
  func use(_ value: String) { question = value }
  func captured() -> [Data] { bodies }
  func data(for request: URLRequest) async throws -> (Data,Int) {
    if let body=request.httpBody {
      bodies.append(body)
      let value=try JSONDecoder().decode(QuestionSubmission.self,from:body)
      return (Data("{\"data\":{\"requestId\":\"\(value.requestId)\",\"resourceId\":\"frm_test\",\"state\":\"accepted\",\"observedAt\":\"now\"},\"cursor\":null}".utf8),200)
    }
    return (Data("{\"data\":[\(question)],\"cursor\":null}".utf8),200)
  }
}
@Suite struct QuestionsTests {
  private func question() throws -> QuestionRequest { try JSONDecoder().decode(QuestionRequest.self,from:Data(sampleQuestion.utf8)) }
  @Test func duplicateLabelsSendStableValues() async throws {
    let transport=QuestionsTransport(),client=try BridgeClient(origin:URL(string:"https://fixture.example.test")!,token:"synthetic",transport:transport)
    let q=try await client.questions("ws_test","ses_test")[0]
    #expect(q.fields[0].options.map(\.value)==["simple","detailed"])
    _=try await client.replyQuestion("ws_test","ses_test",question:q,answers:["layout":.string("detailed"),"name":.string("Fixture project")],requestId:UUID())
    let body=try #require(await transport.captured().first)
    let decoded=try JSONDecoder().decode(QuestionSubmission.self,from:body)
    #expect(decoded.answers?["layout"] == .string("detailed"))
  }
  @Test func labelsMissingFieldsAndWrongTypesNeverSubmit() async throws {
    let q=try question()
    for answers: QuestionAnswers in [["layout":.string("Same label"),"name":.string("Fixture")],["layout":.string("simple")],["layout":.multiple(["simple"]),"name":.string("Fixture")]] {
      #expect(throws:RemoteError.self){try q.validate(answers:answers)}
    }
    #expect(throws:RemoteError.oversized){try q.validate(answers:["layout":.string("simple"),"name":.string(String(repeating:"x",count:32769))])}
  }
  @Test func crossSessionResponseIsRejected() async throws {
    let transport=QuestionsTransport();await transport.use(sampleQuestion.replacingOccurrences(of:"ses_test",with:"ses_other"))
    let client=try BridgeClient(origin:URL(string:"https://fixture.example.test")!,transport:transport)
    await #expect(throws:RemoteError.invalidResponse){try await client.questions("ws_test","ses_test")}
  }
  @Test func unsupportedQuestionsStayVisibleButCannotReply() async throws {
    let transport=QuestionsTransport();await transport.use(#"{"id":"frm_test","sessionId":"ses_test","revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","supported":false,"reason":"Continue on your computer.","fields":[]}"#)
    let client=try BridgeClient(origin:URL(string:"https://fixture.example.test")!,transport:transport)
    let q=try await client.questions("ws_test","ses_test")[0]
    #expect(!q.supported)
    await #expect(throws:RemoteError.incompatible){try await client.replyQuestion("ws_test","ses_test",question:q,answers:[:],requestId:UUID())}
    #expect(await transport.captured().isEmpty)
  }
}

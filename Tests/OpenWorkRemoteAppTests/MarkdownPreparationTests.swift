import Foundation
import Testing
@testable import OpenWorkRemoteAppState

@Suite struct MarkdownPreparationTests{
  @Test func preservesCodeBytesAndPreparesInlineFormatting()async throws{
    let code="let folder = \"cafe\u{301}/日本語\"\n"
    let document=try await MarkdownPreparation.prepare("## Heading\n\nA **bold** reply.\n\n```swift\n"+code+"```")
    guard case .rich(let parts)=document.content else{Issue.record("Small reply should retain formatting");return}
    guard parts.count==2,case .prose(let paragraphs)=parts[0],case .code(let text,let language)=parts[1] else{Issue.record("Expected prose and code");return}
    guard case .heading(let heading)=paragraphs[0],case .text(let attributed)=paragraphs[1] else{Issue.record("Expected heading and paragraph");return}
    #expect(heading=="Heading");#expect(String(attributed.characters)=="A bold reply.")
    #expect(Array(text.utf8)==Array(code.utf8));#expect(language=="swift")
  }
  @Test func aLargeReplyUsesBoundedLiteralPagesWithoutLosingAnyBytes()async throws{
    let source=String(repeating:"👩🏽‍💻 cafe\u{301} 日本語\n",count:12_000)
    let document=try await MarkdownPreparation.prepare(source)
    guard case .plainPages(let pages)=document.content else{Issue.record("Large reply should use literal pages");return}
    #expect(pages.count>1)
    #expect(pages.allSatisfy{!$0.isEmpty && $0.unicodeScalars.count<=4_000})
    #expect(Array(pages.joined().utf8)==Array(source.utf8))
  }
  @Test func tooManyTinyBlocksCannotCreateAnUnboundedFormattedViewTree()async throws{
    let source=String(repeating:"**one**\n\n",count:1_000)
    let document=try await MarkdownPreparation.prepare(source)
    guard case .plainPages(let pages)=document.content else{Issue.record("Dense reply should use literal pages");return}
    #expect(pages.joined()==source)
  }
  @Test func aSingleOversizedTextOrCodeBlockAlsoUsesPages()async throws{
    for source in [String(repeating:"word ",count:2_000),"```swift\n"+String(repeating:"let example = 42\n",count:400)+"``` "]{
      let document=try await MarkdownPreparation.prepare(source)
      guard case .plainPages(let pages)=document.content else{Issue.record("One enormous Text also needs a layout bound");continue}
      #expect(Array(pages.joined().utf8)==Array(source.utf8))
    }
  }
  @Test func sourceIdentityDoesNotMergeCanonicallyEquivalentCodeBytes(){
    let composed=MarkdownSource(text:"```\ncafé\n```"),decomposed=MarkdownSource(text:"```\ncafe\u{301}\n```")
    #expect(composed.text==decomposed.text)
    #expect(composed != decomposed)
    #expect(composed==MarkdownSource(text:composed.text))
  }
  @Test func cancellationCannotPublishAPreparedReply()async{
    let task=Task{try await MarkdownPreparation.prepare(String(repeating:"**reply**\n\n",count:100_000))}
    task.cancel()
    do{_ = try await task.value;Issue.record("Cancelled work must not publish a document")}
    catch is CancellationError{}
    catch{Issue.record("Unexpected cancellation error: \(error)")}
  }
}

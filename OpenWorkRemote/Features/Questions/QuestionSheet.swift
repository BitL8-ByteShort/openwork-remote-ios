import OpenWorkRemoteCore
import SwiftUI

struct QuestionPresentation: Identifiable {
  let question: QuestionRequest
  let context: QuestionContext
  var id: String { question.id + question.revision + context.generation.uuidString + context.selection.uuidString }
}

struct QuestionBanner: View {
  let question: QuestionRequest
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: "questionmark.bubble")
        Text(question.supported ? "OpenWork has a question" : "Review a question on your computer")
          .font(.callout.weight(.semibold))
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
      }.foregroundStyle(Theme.ink).padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }.accessibilityIdentifier("question-banner")
  }
}

struct QuestionSheet: View {
  let presentation: QuestionPresentation
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var index = 0
  @State private var confirmDismiss = false
  private var question: QuestionRequest { presentation.question }
  private var store: QuestionStore { model.questions }
  private var matches: Bool { model.questionContext == presentation.context && store.context == presentation.context }
  private var current: Bool { matches && store.isCurrent(question) }
  private var editable: Bool { matches && model.connection == .ready && store.canEdit(question) }
  private var state: QuestionDraft.State? { matches ? store.draft(for: question)?.state : nil }
  private var answers: QuestionAnswers { matches ? store.answers(for: question) : [:] }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if !question.supported {
            Text("Continue on your computer").font(.title2.weight(.semibold))
            Text(question.reason ?? "Open this chat in OpenWork to answer this request.").foregroundStyle(Theme.muted)
          } else if let field = question.fields.indices.contains(index) ? question.fields[index] : nil {
            Text("Question \(index + 1) of \(question.fields.count)").font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
            QuestionFieldView(field: field, answer: answers[field.key], enabled: editable) {
              store.setAnswer($0, field: field.key, question: question)
            }
            status
            if index < question.fields.count - 1 {
              Button("Next question") { index += 1 }.buttonStyle(PrimaryButtonStyle())
                .disabled(!fieldAnswered(field)).accessibilityIdentifier("question-next")
            } else {
              Button("Send answers") {
                Task { await model.answerQuestion(question, context: presentation.context) }
              }.buttonStyle(PrimaryButtonStyle()).disabled(!editable || !store.canReply(question))
                .accessibilityIdentifier("question-send")
            }
            Button("Dismiss question", role: .destructive) { confirmDismiss = true }
              .frame(maxWidth: .infinity, minHeight: 44).disabled(!editable)
          }
          if matches, let notice = store.notice {
            Text(notice).font(.callout).foregroundStyle(Theme.muted).accessibilityIdentifier("question-notice")
          }
          if state == .sent || !current || !question.supported {
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
          }
        }.frame(maxWidth: 600, alignment: .leading).padding(24).frame(maxWidth: .infinity)
      }.background(Theme.background).navigationTitle("Answer OpenWork").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          if index > 0 { ToolbarItem(placement: .topBarTrailing) { Button("Previous") { index -= 1 } } }
        }.confirmationDialog("Dismiss this question in OpenWork?", isPresented: $confirmDismiss, titleVisibility: .visible) {
          Button("Dismiss question", role: .destructive) {
            Task { await model.answerQuestion(question, context: presentation.context, dismiss: true) }
          }
        } message: {
          Text("This cancels the pending question in this chat on your computer. Your local draft is kept.")
        }
    }
  }
  @ViewBuilder private var status: some View {
    if state == .sending {
      Label { Text("Sending answers") } icon: { ProgressView() }.font(.callout).foregroundStyle(Theme.muted)
    } else if !current && state != .sent && state != .uncertain {
      Text(matches ? "This question changed or is no longer pending. Close this sheet and review the latest request."
        : "This question belongs to a different connection or chat. Close this sheet to continue.")
        .font(.callout).foregroundStyle(Theme.muted)
    } else if model.connection != .ready && state != .sent {
      Text("Reconnect to send. Your answers are kept on this iPhone.").font(.callout).foregroundStyle(Theme.muted)
    }
  }
  private func fieldAnswered(_ field: QuestionField) -> Bool {
    switch answers[field.key] {
    case .string(let value): return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .multiple(let values): return !values.isEmpty
    case nil: return false
    }
  }
}

private struct QuestionFieldView: View {
  let field: QuestionField
  let answer: QuestionAnswer?
  let enabled: Bool
  let change: (QuestionAnswer) -> Void
  private var values: [String] {
    switch answer {
    case .string(let value): return [value]
    case .multiple(let values): return values
    case nil: return []
    }
  }
  private var custom: String { values.first { value in !field.options.contains(where: { $0.value == value }) } ?? "" }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(field.prompt.isEmpty ? field.title : field.prompt).font(.title.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
      Text("Your answer goes to this chat on your computer.").font(.callout).foregroundStyle(Theme.muted)
      if !field.options.isEmpty {
        Text(field.kind == .multipleChoice ? "Choose one or more." : "Choose one.").foregroundStyle(Theme.muted)
        ForEach(field.options) { option in
          Button {
            if field.kind == .multipleChoice {
              var selected = values
              if let i = selected.firstIndex(of: option.value) { selected.remove(at: i) } else { selected.append(option.value) }
              change(.multiple(selected))
            } else { change(.string(option.value)) }
          } label: {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 4) {
                Text(option.label).font(.body.weight(.medium))
                if !option.description.isEmpty { Text(option.description).font(.callout).foregroundStyle(Theme.muted) }
              }
              Spacer()
              if values.contains(option.value) { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.foregroundStyle(values.contains(option.value) ? Theme.accent : Theme.ink)
              .padding(16).frame(maxWidth: .infinity, alignment: .leading)
              .background(values.contains(option.value) ? Theme.accent.opacity(0.06) : Theme.raised,
                in: RoundedRectangle(cornerRadius: 18))
              .overlay(RoundedRectangle(cornerRadius: 18).stroke(values.contains(option.value) ? Theme.accent : Theme.line))
          }.disabled(!enabled).accessibilityIdentifier("question-option-" + option.value)
            .accessibilityAddTraits(values.contains(option.value) ? .isSelected : [])
        }
      }
      if field.custom {
        TextField(field.options.isEmpty ? "Your answer" : "Other answer", text: Binding(get: { custom }, set: { value in
          if field.kind == .multipleChoice {
            let selected = values.filter { v in field.options.contains(where: { $0.value == v }) }
            change(.multiple(selected + (value.isEmpty ? [] : [value])))
          } else { change(.string(value)) }
        })).padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
          .disabled(!enabled).accessibilityIdentifier("question-text-" + field.key)
      }
    }
  }
}

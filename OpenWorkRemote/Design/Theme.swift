import SwiftUI

enum Theme {
  // Reviewed Penpot spacing and card radius tokens.
  static let rowGap: CGFloat = 16
  static let radius: CGFloat = 20
  static let background = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark ? UIColor(hex: 0x15181E) : UIColor(hex: 0xFAF9F6)
    })
  static let surface = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark ? UIColor(hex: 0x232730) : UIColor(hex: 0xF0EFEB)
    })
  static let raised = Color(
    uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x2C313B) : .white })
  static let ink = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF3F4F7) : UIColor(hex: 0x20242B)
    })
  static let muted = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark ? UIColor(hex: 0xADB4C0) : UIColor(hex: 0x626872)
    })
  static let accent = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark ? UIColor(hex: 0xAABBFF) : UIColor(hex: 0x3559DF)
    })
  static let onAccent = Color(
    uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x172246) : .white })
  static let line = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark ? UIColor(hex: 0x3B414D) : UIColor(hex: 0xDDDFE3)
    })
  static let diffAdded = Color(uiColor:UIColor {$0.userInterfaceStyle == .dark ? UIColor(hex:0x183D2D) : UIColor(hex:0xECF8F1)})
  static let diffRemoved = Color(uiColor:UIColor {$0.userInterfaceStyle == .dark ? UIColor(hex:0x48262B) : UIColor(hex:0xFEF0F0)})
  static let mark = Color(red: 0.21, green: 0.35, blue: 0.87)
}
extension UIColor {
  fileprivate convenience init(hex: Int) {
    self.init(
      red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
      blue: CGFloat(hex & 255) / 255, alpha: 1)
  }
}
struct BrandMark: View {
  var size: CGFloat = 38
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.3).fill(Theme.mark)
      Path { p in
        let lo = size * 0.29
        let hi = size * 0.71
        let x = size * 0.13
        p.move(to: CGPoint(x: lo + x, y: lo))
        p.addLine(to: CGPoint(x: lo, y: lo))
        p.addLine(to: CGPoint(x: lo, y: hi))
        p.addLine(to: CGPoint(x: lo + x, y: hi))
        p.move(to: CGPoint(x: hi - x, y: lo))
        p.addLine(to: CGPoint(x: hi, y: lo))
        p.addLine(to: CGPoint(x: hi, y: hi))
        p.addLine(to: CGPoint(x: hi - x, y: hi))
        p.move(to: CGPoint(x: size * 0.41, y: size * 0.5))
        p.addLine(to: CGPoint(x: size * 0.59, y: size * 0.5))
        p.move(to: CGPoint(x: size * 0.54, y: size * 0.45))
        p.addLine(to: CGPoint(x: size * 0.59, y: size * 0.5))
        p.addLine(to: CGPoint(x: size * 0.54, y: size * 0.55))
      }.stroke(
        .white,
        style: StrokeStyle(lineWidth: max(1.5, size * 0.046), lineCap: .round, lineJoin: .round))
    }.frame(width: size, height: size).accessibilityHidden(true)
  }
}
struct PrimaryButtonStyle: ButtonStyle {
  var fill: Color = Theme.accent
  var ink: Color = Theme.onAccent
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.headline).frame(maxWidth: .infinity).frame(minHeight: 54)
      .foregroundStyle(ink).background(
        fill, in: RoundedRectangle(cornerRadius: 18)
      ).opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
  }
}
struct SetupIllustration: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 32).fill(Theme.surface)
      ZStack(alignment: .bottomTrailing) {
        VStack(spacing: 12) {
          HStack {
            Circle().frame(width: 5)
            Circle().frame(width: 5)
            Spacer()
          }.foregroundStyle(Theme.line).padding(10).background(
            Theme.background, in: RoundedRectangle(cornerRadius: 7))
          HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 7).fill(Theme.surface).frame(width: 44)
            VStack(alignment: .leading, spacing: 9) {
              RoundedRectangle(cornerRadius: 2).fill(Theme.line).frame(height: 6)
              RoundedRectangle(cornerRadius: 2).fill(Theme.line).frame(width: 92, height: 6)
              RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.12)).frame(height: 32)
              RoundedRectangle(cornerRadius: 2).fill(Theme.line).frame(height: 6)
              Spacer()
            }
          }
        }.padding(12).frame(width: 226, height: 150).background(
          Theme.raised, in: RoundedRectangle(cornerRadius: 16)
        ).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
        VStack(spacing: 14) {
          Capsule().fill(Theme.ink).frame(width: 30, height: 6)
          Spacer()
          RoundedRectangle(cornerRadius: 8).fill(Theme.surface).frame(height: 40)
          RoundedRectangle(cornerRadius: 2).fill(Theme.line).frame(height: 4)
          RoundedRectangle(cornerRadius: 2).fill(Theme.line).frame(height: 4)
          Spacer()
          HStack {
            Spacer()
            Circle().fill(Theme.accent).frame(width: 9)
          }
        }.padding(13).frame(width: 88, height: 154).background(
          Theme.background, in: RoundedRectangle(cornerRadius: 21)
        ).overlay(RoundedRectangle(cornerRadius: 21).stroke(Theme.ink, lineWidth: 7)).offset(
          x: 32, y: 48)
        Image(systemName: "link").font(.title2).foregroundStyle(Theme.accent).padding(13)
          .background(Theme.background, in: Circle()).offset(x: -58, y: 24)
      }
    }.frame(height: 264).accessibilityHidden(true)
  }
}

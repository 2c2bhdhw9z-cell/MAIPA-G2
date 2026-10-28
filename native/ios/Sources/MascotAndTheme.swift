import SwiftUI
import AgentCore

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (139, 92, 246)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}

public struct AccentColorOption: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let hex: String

    public static let options: [AccentColorOption] = [
        AccentColorOption(id: "kiro-purple", name: "Kiro Purple", hex: "#8B5CF6"),
        AccentColorOption(id: "arena-amber", name: "Arena Warm Gold", hex: "#F59E0B"),
        AccentColorOption(id: "ocean-blue", name: "Ocean Blue", hex: "#3B82F6"),
        AccentColorOption(id: "emerald", name: "Emerald", hex: "#10B981"),
        AccentColorOption(id: "crimson-rose", name: "Rose", hex: "#F43F5E")
    ]
}

/// MAIPA-G's friendly ghost/companion mascot inspired by Kiro's mascot,
/// with a gentle floating effect that respects the user's Settings switch.
public struct MAIPAGMascotView: View {
    public let accentColor: Color
    public let animateFloat: Bool
    @State private var floatingOffset: CGFloat = 0

    public init(accentColor: Color, animateFloat: Bool) {
        self.accentColor = accentColor
        self.animateFloat = animateFloat
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.16))
                .frame(width: 58, height: 58)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 42)

                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                }
                .offset(y: -3)
            }
            .offset(y: animateFloat ? floatingOffset : 0)
        }
        .onAppear {
            guard animateFloat else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                floatingOffset = -4
            }
        }
        .onChange(of: animateFloat) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    floatingOffset = -4
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    floatingOffset = 0
                }
            }
        }
    }
}

import SwiftUI

struct WakeChallengeView: View {
    let sessionID: String
    var allowsDirectStop = false
    let onCompleted: () -> Void

    @State private var step = 0
    @State private var challenge = WakeChallenge.make(for: 0)
    @State private var feedback: Feedback?
    @State private var isAnswering = false

    private let totalSteps = 3

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RobineTheme.night950, RobineTheme.night900, RobineTheme.moon.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                header
                Spacer(minLength: 8)
                challengeCard
                if allowsDirectStop {
                    Button("Arrêt direct", action: onCompleted)
                        .buttonStyle(RobineSecondaryButtonStyle())
                }
                Spacer(minLength: 8)
                Text("L’alarme continue jusqu’à la résolution des trois défis.")
                    .font(.caption)
                    .foregroundStyle(RobineTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(RobineTheme.moon)
                .symbolEffect(.pulse)

            Text("Bonjour")
                .font(.largeTitle.bold())

            Text("Résolvez trois défis pour confirmer que vous êtes bien réveillé.")
                .font(.subheadline)
                .foregroundStyle(RobineTheme.muted)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index < step ? RobineTheme.mint : index == step ? RobineTheme.moon : Color.white.opacity(0.14))
                        .frame(height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Défi \(min(step + 1, totalSteps)) sur \(totalSteps)")
        }
    }

    private var challengeCard: some View {
        VStack(spacing: 22) {
            Label(challenge.kind.title, systemImage: challenge.kind.icon)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(RobineTheme.rose)

            Text(challenge.prompt)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)

            Text(challenge.instruction)
                .font(.subheadline)
                .foregroundStyle(RobineTheme.muted)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(challenge.options, id: \.self) { option in
                    Button {
                        answer(option)
                    } label: {
                        Text("\(option)")
                            .font(.title2.bold())
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .buttonStyle(WakeAnswerButtonStyle())
                    .disabled(isAnswering)
                }
            }

            if let feedback {
                Label(feedback.text, systemImage: feedback.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(feedback.color)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(RobineTheme.moon.opacity(0.25))
        }
    }

    private func answer(_ value: Int) {
        guard !isAnswering else { return }
        isAnswering = true

        if value == challenge.answer {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { feedback = .correct }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                if step + 1 == totalSteps {
                    onCompleted()
                } else {
                    step += 1
                    challenge = WakeChallenge.make(for: step)
                    feedback = nil
                    isAnswering = false
                }
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation { feedback = .incorrect }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                challenge = WakeChallenge.make(for: step)
                feedback = nil
                isAnswering = false
            }
        }
    }
}

private struct WakeAnswerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RobineTheme.text)
            .background(
                configuration.isPressed ? RobineTheme.moon.opacity(0.35) : Color.white.opacity(0.09),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.white.opacity(0.1))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct WakeChallenge {
    enum Kind {
        case arithmetic
        case sequence
        case attention

        var title: String {
            switch self {
            case .arithmetic: "Calcul"
            case .sequence: "Suite logique"
            case .attention: "Attention"
            }
        }

        var icon: String {
            switch self {
            case .arithmetic: "plus.forwardslash.minus"
            case .sequence: "ellipsis"
            case .attention: "eye.fill"
            }
        }
    }

    let kind: Kind
    let prompt: String
    let instruction: String
    let options: [Int]
    let answer: Int

    static func make(for step: Int) -> WakeChallenge {
        switch step % 3 {
        case 0: arithmetic()
        case 1: sequence()
        default: attention()
        }
    }

    private static func arithmetic() -> WakeChallenge {
        let left = Int.random(in: 14...38)
        let right = Int.random(in: 6...24)
        let subtract = Bool.random()
        let answer = subtract ? left - right : left + right
        let symbol = subtract ? "−" : "+"

        return WakeChallenge(
            kind: .arithmetic,
            prompt: "\(left) \(symbol) \(right) = ?",
            instruction: "Choisissez le résultat",
            options: choices(around: answer),
            answer: answer
        )
    }

    private static func sequence() -> WakeChallenge {
        let start = Int.random(in: 2...12)
        let increment = Int.random(in: 2...7)
        let values = (0..<4).map { start + $0 * increment }
        let answer = start + 4 * increment

        return WakeChallenge(
            kind: .sequence,
            prompt: values.map(String.init).joined(separator: "  ·  ") + "  ·  ?",
            instruction: "Quel nombre vient ensuite ?",
            options: choices(around: answer),
            answer: answer
        )
    }

    private static func attention() -> WakeChallenge {
        let target = Int.random(in: 3...8)
        let count = Int.random(in: 2...4)
        var digits = Array(repeating: target, count: count)

        while digits.count < 7 {
            let digit = Int.random(in: 1...9)
            if digit != target { digits.append(digit) }
        }
        digits.shuffle()

        return WakeChallenge(
            kind: .attention,
            prompt: digits.map(String.init).joined(separator: "  "),
            instruction: "Combien de fois voyez-vous le chiffre \(target) ?",
            options: [1, 2, 3, 4].shuffled(),
            answer: count
        )
    }

    private static func choices(around answer: Int) -> [Int] {
        var values: Set<Int> = [answer]
        let offsets = [-8, -6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6, 8].shuffled()

        for offset in offsets where values.count < 4 {
            values.insert(answer + offset)
        }

        return Array(values).shuffled()
    }
}

private enum Feedback {
    case correct
    case incorrect

    var text: String { self == .correct ? "Bien joué" : "Presque — nouveau défi" }
    var icon: String { self == .correct ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill" }
    var color: Color { self == .correct ? RobineTheme.mint : RobineTheme.rose }
}

import AppKit
import SwiftUI

// Visual rewards: what plays when something gets done.

/// Haptic tick (Force Touch trackpads) and a soft pop when something gets done.
@MainActor
enum Reward {
    private static let pop: NSSound? = {
        let sound = NSSound(named: "Pop")
        sound?.volume = 0.25
        return sound
    }()

    static func play() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        pop?.stop()
        pop?.play()
    }
}

/// A ring and sparks that fly out once each time `trigger` turns true. Put it in an overlay.
struct Burst: View {
    let trigger: Bool
    var color: Color = .accentColor
    /// Diameter of the thing it bursts from.
    var size: CGFloat = 16

    @State private var progress: CGFloat = 1

    private static let sparks = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.5)
                .frame(width: size, height: size)
                .scaleEffect(1 + progress * 0.9)
            ForEach(0..<Self.sparks, id: \.self) { index in
                let angle = Angle.degrees(Double(index) / Double(Self.sparks) * 360)
                let distance = size * (0.55 + progress * 0.65)
                Circle()
                    .fill(color)
                    .frame(width: max(2, size / 6), height: max(2, size / 6))
                    .offset(x: cos(angle.radians) * distance, y: sin(angle.radians) * distance)
                    .scaleEffect(1 - progress * 0.6)
            }
        }
        .opacity(1 - progress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, fired in
            guard fired else { return }
            progress = 0
            withAnimation(.easeOut(duration: 0.55)) { progress = 1 }
        }
    }
}

/// Circular progress, 0…1, that fills with a spring.
struct ProgressRing: View {
    let progress: Double
    var color: Color = .accentColor
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Theme.Motion.celebrate, value: progress)
        .accessibilityElement()
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// Today's tasks as a ring: `done` of `total`. Turns into a celebration when everything is done.
struct DayProgressCard: View {
    let done: Int
    let total: Int

    private var isComplete: Bool { total > 0 && done >= total }

    private var message: String {
        switch (done, total - done) {
        case (_, ...0): "All clear for today"
        case (0, _): "Let’s get the first one done"
        case (_, 1): "One more to go"
        default: "\(total - done) more to go"
        }
    }

    var body: some View {
        Card {
            CardRow {
                ZStack {
                    ProgressRing(progress: total == 0 ? 0 : Double(done) / Double(total),
                                 color: isComplete ? Theme.Palette.success : .accentColor)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.Palette.success)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 34, height: 34)
                .overlay { Burst(trigger: isComplete, color: Theme.Palette.success, size: 34) }
                .padding(.vertical, Theme.Space.xs)

                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(message)
                        .font(Theme.Font.sectionTitle)
                        .contentTransition(.interpolate)
                    Text("\(done) of \(total) done today")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(done)))
                }
                Spacer()
            }
        }
        .animation(Theme.Motion.celebrate, value: done)
        .animation(Theme.Motion.celebrate, value: isComplete)
        .accessibilityElement(children: .combine)
    }
}

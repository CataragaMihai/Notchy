import SwiftUI

/// The Claude Code mascot as pixel art, after the block-character figure Claude Code prints at
/// startup: a wide orange body with two eyes, little arms and four legs. Each cell is twice as
/// tall as it is wide, like the quarter blocks in a terminal.
struct ClaudeMascot: View {
    var rows: [String] = Frames.standing
    var pixel: CGFloat = 1.5
    private var height: CGFloat { pixel * 2 }
    static let color = Color(red: 0.85, green: 0.47, blue: 0.34)

    enum Frames {
        static let standing = [
            "...############...",
            "...##.######.##...",
            ".################.",
            "...############...",
            "....#.#....#.#....",
        ]
        static let blinking = [
            "...############...",
            "...############...",
            ".################.",
            "...############...",
            "....#.#....#.#....",
        ]
        static let lookingLeft = [
            "...############...",
            "...#.######.###...",
            ".################.",
            "...############...",
            "....#.#....#.#....",
        ]
        static let lookingRight = [
            "...############...",
            "...###.######.#...",
            ".################.",
            "...############...",
            "....#.#....#.#....",
        ]
        /// Left arm up.
        static let waving = [
            "...############...",
            ".#.##.######.##...",
            "...##############.",
            "...############...",
            "....#.#....#.#....",
        ]
        /// Arms up, legs shifted: the other half of a step.
        static let stepping = [
            "...############...",
            ".#.##.######.##.#.",
            "...############...",
            "...############...",
            "...#.#....#.#.....",
        ]
    }

    var body: some View {
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, cell) in row.enumerated() where cell == "#" {
                    let rect = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * height, width: pixel, height: height)
                    context.fill(Path(rect), with: .color(Self.color))
                }
            }
        }
        .frame(width: CGFloat(Frames.standing[0].count) * pixel, height: CGFloat(Frames.standing.count) * height)
        .accessibilityLabel("Claude Code")
    }
}

/// The mascot acting out what Claude Code is doing: asleep with no session, blinking when idle,
/// stepping and bobbing while it works, hopping when it needs you. Redraws only a few times a
/// second, and only in Claude Code mode.
struct AnimatedMascot: View {
    let activity: ClaudeTerminal.Activity

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let (rows, lift) = pose(at: t)
            ClaudeMascot(rows: rows)
                .offset(y: -lift)
                .opacity(activity == .off ? 0.4 : 1)
        }
    }

    private var interval: TimeInterval {
        switch activity {
        case .off: 60
        case .idle: 0.12
        case .working, .attention: 0.09
        }
    }

    private func pose(at t: TimeInterval) -> ([String], CGFloat) {
        switch activity {
        case .off:
            return (ClaudeMascot.Frames.blinking, 0)
        case .idle:
            return idlePose(at: t)
        case .working:
            // Vibing: alternate steps, bobbing up on every other one.
            let step = Int(t / 0.18) % 2 == 0
            return (step ? ClaudeMascot.Frames.standing : ClaudeMascot.Frames.stepping, step ? 0 : 1.5)
        case .attention:
            // A quick hop with arms up, then a pause.
            let phase = t.truncatingRemainder(dividingBy: 0.9)
            return phase < 0.27 ? (ClaudeMascot.Frames.stepping, 3) : (ClaudeMascot.Frames.standing, 0)
        }
    }
}

extension AnimatedMascot {
    /// Waiting, it picks a little act every three seconds, at random but the same for the
    /// whole slot: standing and blinking, looking around, waving, hopping, a short dance.
    private enum IdleAct: CaseIterable {
        case blink, lookLeft, lookRight, lookAround, wave, hop, dance, stand
    }

    private static let slot: TimeInterval = 3

    private func idlePose(at t: TimeInterval) -> ([String], CGFloat) {
        let index = Int(t / Self.slot)
        let local = t - Double(index) * Self.slot
        let act = IdleAct.allCases[Self.pick(index, IdleAct.allCases.count)]
        let frames = ClaudeMascot.Frames.self
        let blinkAtEnd = local > Self.slot - 0.15
        switch act {
        case .stand:
            return (frames.standing, 0)
        case .blink:
            return (blinkAtEnd || (local > 1.2 && local < 1.35) ? frames.blinking : frames.standing, 0)
        case .lookLeft:
            return (local < 2.2 ? frames.lookingLeft : frames.standing, 0)
        case .lookRight:
            return (local < 2.2 ? frames.lookingRight : frames.standing, 0)
        case .lookAround:
            return (local < 1 ? frames.lookingLeft : local < 2 ? frames.lookingRight : frames.standing, 0)
        case .wave:
            let up = local < 1.6 && Int(local / 0.25) % 2 == 0
            return (up ? frames.waving : frames.standing, 0)
        case .hop:
            let lift: CGFloat = local > 0.4 && local < 0.65 ? 3 : 0
            return (lift > 0 ? frames.stepping : frames.standing, lift)
        case .dance:
            guard local < 1.8 else { return (frames.standing, 0) }
            let step = Int(local / 0.2) % 2 == 0
            return (step ? frames.stepping : frames.standing, step ? 1.5 : 0)
        }
    }

    /// A stable pseudo-random choice for a slot, so a redraw mid-act keeps the same act.
    static func pick(_ slot: Int, _ count: Int) -> Int {
        Int(UInt64(truncatingIfNeeded: slot) &* 2_654_435_761 % UInt64(count))
    }
}

/// The right side of the notch in Claude Code mode: what the session is doing.
struct ClaudeStatus: View {
    let activity: ClaudeTerminal.Activity

    var body: some View {
        switch activity {
        case .off:
            label("asleep", color: .white.opacity(0.45))
        case .idle:
            // A different word every six seconds while it waits.
            TimelineView(.periodic(from: .now, by: 6)) { context in
                let slot = Int(context.date.timeIntervalSinceReferenceDate / 6)
                label(Self.idleWords[AnimatedMascot.pick(slot, Self.idleWords.count)], color: .white.opacity(0.8))
            }
        case let .working(since, verb):
            TimelineView(.periodic(from: since, by: 1)) { context in
                label("\(verb) \(Int(context.date.timeIntervalSince(since)))s", color: ClaudeMascot.color)
            }
        case .attention:
            label("needs you", color: ClaudeMascot.color)
        }
    }

    private static let idleWords = ["ready", "chilling", "vibing", "all ears", "on standby", "here", "hanging out"]

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

/// "Drop here", in the notch and over the terminal while a file is dragged over them.
struct DropHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 18, weight: .semibold))
            Text("Drop to add to Claude Code")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(ClaudeMascot.color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(ClaudeMascot.color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}

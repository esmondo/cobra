import CobraCore
import SwiftUI

/// The floating pill that appears next to the caret while Cobra is listening.
/// It is the only part of the app most people will look at, so it carries the
/// brand: matte surface, venom accent, faint scanlines.
struct RecordingHUD: View {
    @ObservedObject var engine: DictationEngine

    var body: some View {
        HStack(spacing: 10) {
            StatusIndicator(state: engine.state)

            if engine.state == .recording {
                LevelMeter(levels: engine.levels)
                LiveTranscript(text: engine.partialText, placeholder: label)
            } else {
                Text(label)
                    .font(Theme.Typeface.label)
                    .foregroundStyle(Theme.Palette.text)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Theme.Metrics.hudPadding)
        .frame(height: Theme.Metrics.hudHeight)
        .background {
            Capsule()
                .fill(Theme.Palette.surface)
                .overlay { Scanlines().clipShape(Capsule()) }
                .overlay { Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1) }
        }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .padding(14)  // Room for the shadow inside the panel's own bounds.
        .animation(.easeOut(duration: 0.15), value: engine.state)
        .onTapGesture { engine.openSettingsForMissingPermission() }
    }

    private var label: String {
        switch engine.state {
        case .preparing(.downloading(let fraction)):
            return "Fetching model \(Int(fraction * 100))%"
        case .preparing:
            return "Warming up"
        case .recording:
            return engine.isHandsFree ? "Hands-free" : "Listening"
        case .transcribing:
            return "Thinking"
        case .needsPermission:
            return "Click to grant permission"
        case .failed:
            return "Something broke"
        case .idle:
            return "Ready"
        }
    }
}

/// A venom dot that breathes while recording and spins while transcribing.
private struct StatusIndicator: View {
    let state: DictationEngine.State
    @State private var animating = false

    var body: some View {
        Group {
            switch state {
            case .recording:
                Circle()
                    .fill(Theme.Palette.venom)
                    .frame(width: 8, height: 8)
                    .shadow(color: Theme.Palette.venom.opacity(0.8), radius: 5)
                    .scaleEffect(animating ? 1.0 : 0.65)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animating)
                    .onAppear { animating = true }

            case .failed, .needsPermission:
                Circle().fill(Theme.Palette.danger).frame(width: 8, height: 8)

            default:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(Theme.Palette.venom)
            }
        }
        .frame(width: 12)
    }
}

/// Words as they are recognised, ahead of the user releasing the key.
///
/// The width is fixed rather than fitted to the text: the panel is sized when
/// the HUD appears, and a pill that grew with every word would need to resize
/// mid-utterance and jitter under the caret. Older words scroll off the front,
/// so the most recent speech stays visible.
private struct LiveTranscript: View {
    let text: String
    let placeholder: String

    var body: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(Theme.Typeface.label)
            .foregroundStyle(text.isEmpty ? Theme.Palette.textDim : Theme.Palette.text)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(width: 240, alignment: .leading)
            .animation(nil, value: text)  // Text should appear, not slide.
    }
}

/// Bar meter fed by recent input levels.
private struct LevelMeter: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.Palette.venom.opacity(0.9))
                    .frame(width: 2, height: height(for: level))
            }
        }
        .frame(height: 16)
        .animation(.linear(duration: 0.05), value: levels)
    }

    private func height(for level: Float) -> CGFloat {
        // Raw amplitude barely moves for normal speech; the square root spreads
        // quiet input across the meter so it reads as responsive.
        let scaled = CGFloat(sqrt(max(0, min(1, level))))
        return 2 + scaled * 14
    }
}

/// Faint horizontal lines over the pill — the "scanline" half of the identity.
private struct Scanlines: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let line = Path(CGRect(x: 0, y: 0, width: size.width, height: 0.5))
                for y in stride(from: 0.0, to: size.height, by: 3.0) {
                    context.fill(line.offsetBy(dx: 0, dy: y), with: .color(.white.opacity(0.025)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
    }
}

//
//  SplashScreenView.swift
//  TimeBlocks
//
//  Animated launch splash: floating jenga-style blocks in category colors,
//  a big yellow pencil, and the TimeBlocks title in bubble letters.
//  Rendered entirely with SwiftUI vector shapes — no image assets.
//

import SwiftUI

// MARK: - Brand colors

extension Color {
    static let tbBlue = Color(red: 0.18, green: 0.49, blue: 0.82)       // primary blue
    static let tbDeepBlue = Color(red: 0.08, green: 0.20, blue: 0.40)   // background depth
    static let tbOrange = Color(red: 1.00, green: 0.55, blue: 0.26)     // primary accent
    static let tbYellow = Color(red: 1.00, green: 0.80, blue: 0.20)     // free time / pencil
    static let tbPurple = Color(red: 0.32, green: 0.20, blue: 0.55)     // sleep
    static let tbGreen = Color(red: 0.30, green: 0.69, blue: 0.31)      // sports
}

// MARK: - Floating (bobbing) effect

private struct Floating: ViewModifier {
    var amplitude: CGFloat
    var duration: Double
    var delay: Double
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -amplitude : amplitude)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}

private extension View {
    /// Gently bobs the view up and down forever, as if weightless.
    func floating(amplitude: CGFloat = 7, duration: Double = 2.2, delay: Double = 0) -> some View {
        modifier(Floating(amplitude: amplitude, duration: duration, delay: delay))
    }
}

// MARK: - Jenga-style block

/// A toy block with a simple 3D extrusion: colored front face with an emoji,
/// a lighter top face, and a darker right-side face.
struct JengaBlockView: View {
    let color: Color
    let emoji: String
    var width: CGFloat = 92
    var height: CGFloat = 52
    var depth: CGFloat = 13

    private var topFace: Path {
        Path { p in
            p.move(to: CGPoint(x: 7, y: depth))
            p.addLine(to: CGPoint(x: 7 + depth, y: 0))
            p.addLine(to: CGPoint(x: width + depth - 7, y: 0))
            p.addLine(to: CGPoint(x: width - 7, y: depth))
            p.closeSubpath()
        }
    }

    private var sideFace: Path {
        Path { p in
            p.move(to: CGPoint(x: width, y: depth + 7))
            p.addLine(to: CGPoint(x: width + depth, y: 7))
            p.addLine(to: CGPoint(x: width + depth, y: height + depth - 12))
            p.addLine(to: CGPoint(x: width, y: height + depth - 7))
            p.closeSubpath()
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Top face: base color lightened
            topFace.fill(color)
            topFace.fill(Color.white.opacity(0.35))
            // Side face: base color darkened
            sideFace.fill(color)
            sideFace.fill(Color.black.opacity(0.30))
            // Front face with emoji
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .frame(width: width, height: height)
                .overlay(Text(emoji).font(.system(size: height * 0.58)))
                .offset(y: depth)
        }
        .frame(width: width + depth, height: height + depth, alignment: .topLeading)
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 8)
    }
}

// MARK: - Pencil

/// A right-pointing triangle used for the pencil's wood and graphite tips.
private struct PencilTip: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// A big yellow pencil built from shapes: eraser, ferrule, body, wood tip, graphite.
struct PencilView: View {
    var length: CGFloat = 250
    var thickness: CGFloat = 38

    var body: some View {
        HStack(spacing: 0) {
            // Eraser
            UnevenRoundedRectangle(
                topLeadingRadius: thickness / 2,
                bottomLeadingRadius: thickness / 2
            )
            .fill(Color(red: 0.95, green: 0.55, blue: 0.62))
            .frame(width: thickness * 0.75)

            // Metal ferrule
            Rectangle()
                .fill(Color(white: 0.78))
                .overlay(
                    HStack(spacing: 3) {
                        Rectangle().fill(Color(white: 0.6)).frame(width: 2)
                        Rectangle().fill(Color(white: 0.6)).frame(width: 2)
                    }
                )
                .frame(width: thickness * 0.35)

            // Yellow body with top highlight / bottom shade facets
            Rectangle()
                .fill(Color.tbYellow)
                .overlay(
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(0.30))
                        Rectangle().fill(Color.clear)
                        Rectangle().fill(Color.black.opacity(0.12))
                    }
                )

            // Wood tip with graphite point
            ZStack(alignment: .trailing) {
                PencilTip()
                    .fill(Color(red: 0.91, green: 0.76, blue: 0.55))
                PencilTip()
                    .fill(Color(white: 0.25))
                    .frame(width: thickness * 0.5, height: thickness * 0.36)
            }
            .frame(width: thickness * 1.4)
        }
        .frame(width: length, height: thickness)
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 8)
    }
}

// MARK: - Logo

/// Floating cluster of category blocks crossed by the big yellow pencil.
struct TimeBlocksLogoView: View {
    var body: some View {
        ZStack {
            JengaBlockView(color: .tbPurple, emoji: "🌙")
                .rotationEffect(.degrees(-10))
                .offset(x: -66, y: -78)
                .floating(amplitude: 8, duration: 2.4)
            JengaBlockView(color: .tbOrange, emoji: "📚")
                .rotationEffect(.degrees(8))
                .offset(x: 64, y: -48)
                .floating(amplitude: 6, duration: 2.0, delay: 0.3)
            JengaBlockView(color: .tbGreen, emoji: "🏃")
                .rotationEffect(.degrees(-7))
                .offset(x: -60, y: 56)
                .floating(amplitude: 7, duration: 2.6, delay: 0.6)
            JengaBlockView(color: .tbBlue, emoji: "⏰")
                .rotationEffect(.degrees(12))
                .offset(x: 68, y: 74)
                .floating(amplitude: 9, duration: 2.2, delay: 0.15)
            PencilView()
                .rotationEffect(.degrees(-32))
                .floating(amplitude: 5, duration: 2.8, delay: 0.45)
        }
        .frame(width: 310, height: 280)
    }
}

// MARK: - Bubble title

/// "TimeBlocks" in chunky rounded letters, alternating orange/yellow,
/// each slightly tilted and popping in one-by-one with a spring.
struct BubbleTitleView: View {
    let text: String
    @State private var shown = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(index.isMultiple(of: 2) ? Color.tbOrange : Color.tbYellow)
                    .shadow(color: .tbDeepBlue.opacity(0.7), radius: 0, x: 0, y: 4)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -5 : 5))
                    .offset(y: index.isMultiple(of: 2) ? -2 : 2)
                    .scaleEffect(shown ? 1 : 0.01)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.55).delay(0.3 + Double(index) * 0.06),
                        value: shown
                    )
            }
        }
        .onAppear { shown = true }
    }
}

// MARK: - Splash screen

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            // Blue gradient backdrop with soft warm glows
            LinearGradient(colors: [.tbBlue, .tbDeepBlue], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle()
                .fill(Color.tbOrange.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 60)
                .offset(x: 140, y: -260)
            Circle()
                .fill(Color.tbYellow.opacity(0.12))
                .frame(width: 380, height: 380)
                .blur(radius: 70)
                .offset(x: -150, y: 300)

            VStack(spacing: 52) {
                TimeBlocksLogoView()
                BubbleTitleView(text: "TimeBlocks")
            }
        }
    }
}

// MARK: - Root view with splash overlay

/// Shows the splash over the real root view for a few seconds, then fades it
/// out. The app loads underneath, so the splash masks startup rather than
/// adding to it.
struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ContentView()
            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.6)) {
                showSplash = false
            }
        }
    }
}

#Preview("Splash") {
    SplashScreenView()
}

#Preview("Logo only") {
    ZStack {
        Color.tbBlue.ignoresSafeArea()
        TimeBlocksLogoView()
    }
}

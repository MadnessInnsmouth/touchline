//
//  PitchReplayView.swift
//  Touchline
//
//  Created for Touchline - iOS Football Manager Game.
//  Two-dimensional position-cam match replay. Renders 22 interpolated player dots
//  and the ball on a top-down pitch, driven by a minute ticker, and announces major
//  events for VoiceOver. Animation only; match outcome is decided by MatchEngine.
//

import SwiftUI
import Accessibility

// MARK: - Pitch Replay View

public struct PitchReplayView: View {
    public let fixture: Fixture
    public let homeClub: Club
    public let awayClub: Club
    public let minute: Int
    
    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, canvasSize in
                drawPitch(in: &context, size: canvasSize)
                drawPlayers(in: &context, size: canvasSize)
                drawBall(in: &context, size: canvasSize)
            }
            .frame(width: size.width, height: size.height)
            .background(Color.pitchGrassDark)
        }
        .aspectRatio(68.0 / 105.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.25), lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Match pitch replay, minute \(minute). Visual pitch only; use the live commentary list below for each match event.")
    }
    
    // MARK: - Pitch Drawing
    
    private func drawPitch(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        
        // Mowing stripes
        let stripeCount = 8
        for i in 0..<stripeCount {
            let rect = CGRect(
                x: 0,
                y: h * CGFloat(i) / CGFloat(stripeCount),
                width: w,
                height: h / CGFloat(stripeCount)
            )
            let color = i % 2 == 0 ? Color.pitchGrassLight : Color.pitchGrassDark
            context.fill(Path(rect), with: .color(color))
        }
        
        // Outer boundary
        let lineColor = Color.white.opacity(0.7)
        let lineWidth = max(1.5, w * 0.005)
        let inset = w * 0.03
        let field = CGRect(x: inset, y: inset, width: w - inset * 2, height: h - inset * 2)
        context.stroke(Path(field), with: .color(lineColor), lineWidth: lineWidth)
        
        // Halfway line
        var halfway = Path()
        halfway.move(to: CGPoint(x: field.minX, y: field.midY))
        halfway.addLine(to: CGPoint(x: field.maxX, y: field.midY))
        context.stroke(halfway, with: .color(lineColor), lineWidth: lineWidth)
        
        // Centre circle
        let circleRadius = field.width * 0.13
        context.stroke(
            Path(ellipseIn: CGRect(
                x: field.midX - circleRadius,
                y: field.midY - circleRadius,
                width: circleRadius * 2,
                height: circleRadius * 2
            )),
            with: .color(lineColor),
            lineWidth: lineWidth
        )
        
        // Penalty boxes (top & bottom)
        let boxW = field.width * 0.55
        let boxH = field.height * 0.14
        let topBox = CGRect(x: field.midX - boxW / 2, y: field.minY, width: boxW, height: boxH)
        let bottomBox = CGRect(x: field.midX - boxW / 2, y: field.maxY - boxH, width: boxW, height: boxH)
        context.stroke(Path(topBox), with: .color(lineColor), lineWidth: lineWidth)
        context.stroke(Path(bottomBox), with: .color(lineColor), lineWidth: lineWidth)
        
        // Goal boxes
        let goalW = field.width * 0.28
        let goalH = boxH * 0.42
        let topGoal = CGRect(x: field.midX - goalW / 2, y: field.minY, width: goalW, height: goalH)
        let bottomGoal = CGRect(x: field.midX - goalW / 2, y: field.maxY - goalH, width: goalW, height: goalH)
        context.stroke(Path(topGoal), with: .color(lineColor), lineWidth: lineWidth)
        context.stroke(Path(bottomGoal), with: .color(lineColor), lineWidth: lineWidth)
    }
    
    // MARK: - Player Positioning
    
    /// Returns a normalised (0...1) attacking position for a player index at the given minute.
    /// The shape drifts toward the attacking goal and wobbles deterministically over time.
    private func position(for index: Int, isHome: Bool, minute: Int) -> CGPoint
    {
        // Formation slot layout (x: 0..1 across width, y: 0..1 up the pitch from own goal).
        let homeSlots: [CGPoint] = [
            CGPoint(x: 0.50, y: 0.06), // GK
            CGPoint(x: 0.14, y: 0.24), CGPoint(x: 0.38, y: 0.22), CGPoint(x: 0.62, y: 0.22), CGPoint(x: 0.86, y: 0.24),
            CGPoint(x: 0.16, y: 0.44), CGPoint(x: 0.38, y: 0.46), CGPoint(x: 0.62, y: 0.46), CGPoint(x: 0.84, y: 0.44),
            CGPoint(x: 0.40, y: 0.68), CGPoint(x: 0.60, y: 0.68)
        ]
        let slot = homeSlots[min(index, homeSlots.count - 1)]
        
        // Time-based deterministic wobble so the picture breathes as minutes pass.
        let phase = Double(minute) * 0.35 + Double(index) * 1.7
        let wobbleX = sin(phase) * 0.045
        let wobbleY = cos(phase * 0.8) * 0.035
        
        // A gentle push toward the opponent goal grows through the match.
        let push = min(0.12, Double(minute) / 90.0 * 0.12) * (slot.y > 0.3 ? 1 : 0)
        
        var nx = slot.x + wobbleX
        var ny = slot.y + wobbleY + push
        
        // Flip vertically for the away team (attacking the other way).
        if !isHome {
            ny = 1.0 - ny
            nx = 1.0 - nx
        }
        
        nx = min(0.98, max(0.02, nx))
        ny = min(0.98, max(0.02, ny))
        return CGPoint(x: nx, y: ny)
    }
    
    private func drawPlayers(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let radius = max(4, w * 0.018)
        let homeColor = Color(hex: homeClub.primaryColor)
        let awayColor = Color(hex: awayClub.primaryColor)
        
        for index in 0..<11 {
            let homePos = position(for: index, isHome: true, minute: minute)
            let homeCenter = CGPoint(x: homePos.x * w, y: homePos.y * h)
            let homeRect = CGRect(
                x: homeCenter.x - radius,
                y: homeCenter.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: homeRect), with: .color(homeColor))
            context.stroke(Path(ellipseIn: homeRect), with: .color(.white.opacity(0.85)), lineWidth: 1.2)
            
            let awayPos = position(for: index, isHome: false, minute: minute)
            let awayCenter = CGPoint(x: awayPos.x * w, y: awayPos.y * h)
            let awayRect = CGRect(
                x: awayCenter.x - radius,
                y: awayCenter.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: awayRect), with: .color(awayColor))
            context.stroke(Path(ellipseIn: awayRect), with: .color(.black.opacity(0.6)), lineWidth: 1.2)
        }
    }
    
    private func drawBall(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let radius = max(2.5, w * 0.010)
        
        // The ball roams around the middle third, moving deterministically with the clock.
        let phase = Double(minute) * 0.9
        let bx = 0.5 + sin(phase) * 0.28
        let by = 0.5 + cos(phase * 1.3) * 0.33
        let center = CGPoint(x: bx * w, y: by * h)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        
        context.fill(Path(ellipseIn: rect), with: .color(.white))
        context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.7)), lineWidth: 1)
    }
}

// MARK: - Live Match Screen

/// The match played live, a minute at a time. The manager can stop it
/// whenever he likes ("Changes") to make substitutions or change tactics;
/// it stops by itself at half-time and when one of his players is hurt.
public struct LiveMatchView: View {
    @Environment(GameState.self) private var gameState

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    @State private var minute = 0
    @State private var isPlaying = false
    @State private var didSimulate = false
    @State private var ticker: Timer?
    @State private var goalFlash: MatchEvent?
    @State private var pane: Pane = .commentary
    /// Set once Skip / Continue is pressed, so the match is finished once.
    @State private var finishing = false
    /// Why the match is stopped for the manager (half-time, an injury, or
    /// his own call); nil while it is running.
    @State private var touchline: String?
    @State private var editingLineup = false
    @State private var editingTactics = false

    // The animated pitch view is gone: the match is followed in the
    // commentary, with the stats and line-ups alongside.
    enum Pane: String, CaseIterable { case commentary = "Commentary", stats = "Stats", lineups = "Lineups" }

    private var fixture: Fixture? { gameState.activeMatchFixture }
    private var session: LiveMatchSession? {
        guard let s = gameState.liveMatch, s.fixtureId == fixture?.id else { return nil }
        return s
    }
    /// The full result once the match is over; the match so far while it is on.
    private var result: MatchResult? {
        if let played = fixture?.result { return played }
        return session?.soFar
    }
    /// Still being played (not yet at the final whistle).
    private var inProgress: Bool {
        guard let fixture, !fixture.isPlayed, let session else { return false }
        return !session.isFinished
    }
    private var manages: Bool { gameState.gameMode == .manageClub }

    /// The last minute of the match. While it is being played that is the
    /// end of stoppage time (or extra time) as it stands.
    private var finalMinute: Int {
        if inProgress, let session { return session.paused.maxMinute }
        return max(90, result?.events.map { $0.minute }.max() ?? 90)
    }

    public var body: some View {
        VStack(spacing: 14) {
            if let fixture = fixture,
               let home = gameState.club(withId: fixture.homeClubId),
               let away = gameState.club(withId: fixture.awayClubId) {

                scoreboard(home: home, away: away)

                GFTabs(selection: $pane, compact: true)
                    .padding(.horizontal)

                Group {
                    switch pane {
                    case .commentary:
                        commentaryCards(home: home, away: away)
                    case .stats:
                        liveStats(home: home, away: away)
                    case .lineups:
                        lineups(home: home, away: away)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay {
                    if let goal = goalFlash {
                        goalBanner(goal, club: goal.isHomeTeam ? home : away)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                // At half-time (or any stop) the tabs stay usable, so the
                // manager can read the stats; the stop's options sit with the
                // match controls at the bottom instead of a panel on top.

                controls(fixture: fixture)
            } else {
                ContentUnavailableView("No Active Match", systemImage: "sportscourt")
            }
        }
        .padding(.vertical)
        .stadiumBackground()
        .navigationTitle(gameState.gameMode == .createClub ? "Watching" : "Live Match")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prepare)
        .onDisappear {
            stopTicker()
            CrowdAtmosphere.shared.stopMatch()
        }
        .sheet(isPresented: $editingLineup) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(substitutionRules, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if gameState.gameMode != .createClub {
                            KeepLineupBar(allowRevert: false)
                        }
                        LineupEditorView()
                    }
                    .padding()
                }
                .stadiumBackground()
                .navigationTitle("Changes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editingLineup = false } } }
            }
        }
        .sheet(isPresented: $editingTactics) {
            NavigationStack {
                TacticsView()
                    .stadiumBackground()
                    .navigationTitle("Tactics")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editingTactics = false } } }
            }
        }
    }

    private var substitutionRules: String {
        let subs = gameState.liveSubsRemaining
        let windows = gameState.liveWindowsRemaining
        let atBreak = (session?.paused.minute ?? 0) == 46
        var text = "\(subs) substitution\(subs == 1 ? "" : "s") left"
        text += atBreak ? " (half-time changes don't use a window). " : ", \(windows) window\(windows == 1 ? "" : "s") to make them in. "
        text += "Swap a bench player with a starter to bring him on, or swap two starters to change positions. Players taken off cannot return."
        return text
    }

    /// The manager's stop: the score, why play stopped, and the chance to
    /// change things.
    private func touchlinePanel(reason: String, home: Club, away: Club) -> some View {
        VStack(spacing: 14) {
            Text(reason == "HALF-TIME" ? "HALF-TIME" : "TOUCHLINE").font(.gfDisplay(22))
            Text("\(home.name) \(currentHomeGoals) - \(currentAwayGoals) \(away.name)")
                .font(.gfDisplay(20))
                .multilineTextAlignment(.center)
            if reason != "HALF-TIME" && reason != "TOUCHLINE" {
                Label(reason, systemImage: "cross.case.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            if manages {
                Text("Substitutions left: \(gameState.liveSubsRemaining)  ·  Windows left: \(gameState.liveWindowsRemaining)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Lineup") { editingLineup = true }
                        .buttonStyle(.gfOutline)
                        .accessibilityHint("Make substitutions and change positions")
                    Button("Tactics") { editingTactics = true }
                        .buttonStyle(.gfOutline)
                        .accessibilityHint("Change formation, mentality, pressing and more")
                }
            }
            Button(minute == 45 && reason == "HALF-TIME" ? "Start Second Half" : "Resume") { resumePlay() }
                .buttonStyle(.gfPrimary)
                .padding(.horizontal, 20)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.gfNight.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.5), lineWidth: 1.5))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func stopForManager(_ reason: String) {
        stopTicker()
        withAnimation { touchline = reason }
        let spoken = reason == "HALF-TIME" ? "Half-time. \(scoreText)." : reason
        AccessibilityNotification.Announcement("\(spoken) You can make substitutions and change tactics.").post()
    }

    private func resumePlay() {
        withAnimation { touchline = nil }
        startTicker()
    }

    // MARK: - Subviews

    private var clockText: String {
        if minute >= finalMinute && !inProgress { return "FT" }
        if touchline == "HALF-TIME" { return "HT" }
        let stoppage = session?.paused.secondHalfStoppage ?? 0
        if minute > 90 && minute <= 90 + stoppage { return "90+\(minute - 90)'" }
        return "\(minute)'"
    }

    private func scoreboard(home: Club, away: Club) -> some View {
        VStack(spacing: 8) {
            Text(fixture.flatMap { f in f.cupRound.map { "\(f.competition) • \($0)" } } ?? fixture?.competition ?? "Match")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            HStack {
                VStack(spacing: 4) {
                    CrestView(club: home, size: 34)
                    Text(home.name.uppercased()).font(.gfLabel(14)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 2) {
                    Text(scoreText)
                        .font(.gfDisplay(32))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: scoreText)
                    Text(clockText)
                        .font(.caption.weight(.heavy).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.25), in: Capsule())
                }
                VStack(spacing: 4) {
                    CrestView(club: away, size: 34)
                    Text(away.name.uppercased()).font(.gfLabel(14)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.white)
            if let attendance = result?.attendance, attendance > 0 {
                Text("\(home.stadium) (\(attendance.formatted()) fans)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            ProgressView(value: Double(min(minute, finalMinute)), total: Double(max(1, finalMinute)))
                .tint(Color.gfMint)
        }
        .padding(.horizontal, 14)
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(home.name) \(currentHomeGoals), \(away.name) \(currentAwayGoals), minute \(minute)")
    }

    private func goalBanner(_ goal: MatchEvent, club: Club) -> some View {
        let scorer = goal.playerId.flatMap { gameState.player(withId: $0)?.player.fullName }
        let assist = goal.assistPlayerId.flatMap { gameState.player(withId: $0)?.player.fullName }
        return VStack(spacing: 6) {
            Text("GOAL!")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                CrestView(club: club, size: 22)
                Text(scorer ?? club.name).font(.headline).foregroundStyle(.white)
            }
            if let assist {
                Text("Assist: \(assist)").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .background(Color(hex: club.primaryColor).opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 12)
    }

    private var visibleEvents: [MatchEvent] {
        (result?.events ?? []).filter { $0.minute <= minute }
    }

    private func timelineFeed(home: Club, away: Club) -> some View {
        List {
            let visible = visibleEvents
            if visible.isEmpty {
                Text(minute == 0 ? "Kick-off imminent..." : "No key events yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visible.reversed()) { ev in
                    let isGoal = ev.type == .goal || ev.type == .penalty || ev.type == .ownGoal
                    let club = ev.isHomeTeam ? home : away
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: club.primaryColor))
                            .frame(width: 4)
                        Text("\(ev.minute)'")
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .frame(width: 30, alignment: .leading)
                        Image(systemName: ev.type.icon).accessibilityHidden(true)
                            .foregroundStyle(isGoal ? Color.winGreen : ev.type == .redCard || ev.type == .secondYellow ? .red : ev.type == .yellowCard ? .yellow : ev.type == .injury ? .orange : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.shortText)
                                .font(.subheadline.weight(isGoal ? .bold : .regular))
                            if isGoal || ev.type == .chanceMissed || ev.type == .woodwork || ev.type == .injury || ev.type == .substitution {
                                Text(ev.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .listRowBackground(isGoal ? Color.winGreen.opacity(0.1) : Color.clear)
                    .accessibleMatchEvent(ev)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// What a stop offers: why play stopped, changes, and carrying on.
    @ViewBuilder
    private var stopStrip: some View {
        if let reason = touchline {
            VStack(spacing: 8) {
                if reason != "HALF-TIME" && reason != "TOUCHLINE" {
                    Label(reason, systemImage: "cross.case.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                if manages {
                    Text("\(reason == "HALF-TIME" ? "Half-time · " : "")Substitutions left: \(gameState.liveSubsRemaining) · Windows left: \(gameState.liveWindowsRemaining)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Button("Lineup") { editingLineup = true }
                            .buttonStyle(.gfOutline)
                            .accessibilityHint("Make substitutions and change positions")
                        Button("Tactics") { editingTactics = true }
                            .buttonStyle(.gfOutline)
                            .accessibilityHint("Change formation, mentality, pressing and more")
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func controls(fixture: Fixture) -> some View {
        VStack(spacing: 10) {
        stopStrip
        if !inProgress && minute >= finalMinute {
            // The final whistle has gone: one button, Continue.
            Button {
                finish(fixture: fixture)
            } label: {
                Text("Continue").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.gfPrimary)
            .disabled(finishing)
            .padding(.horizontal, 24)
        } else {
        HStack(spacing: 10) {
            Menu {
                ForEach(MatchSettings.Speed.allCases) { speed in
                    Button(speed.displayName) {
                        gameState.matchSettings.speed = speed
                        if isPlaying { startTicker() }
                    }
                }
            } label: {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.gfNavy.opacity(0.7)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.75), lineWidth: 1.5))
            }
            .accessibilityLabel("Replay speed, \(gameState.matchSettings.speed.displayName)")

            if manages && inProgress {
                Button {
                    stopForManager("TOUCHLINE")
                } label: {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.title3.weight(.bold))
                }
                .buttonStyle(.gfOutline)
                .disabled(touchline != nil)
                .accessibilityLabel("Changes: stop the match to make substitutions or change tactics")
            }

            if let reason = touchline {
                Button(minute == 45 && reason == "HALF-TIME" ? "Start Second Half" : "Resume") { resumePlay() }
                    .buttonStyle(.gfPrimary)
            } else {
                Button {
                    isPlaying ? stopTicker() : startTicker()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                }
                .buttonStyle(.gfPrimary)
                .disabled(minute >= finalMinute && !inProgress)
                .accessibilityLabel(isPlaying ? "Pause match" : "Play match")
            }

            Button {
                finish(fixture: fixture)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3.weight(.bold))
            }
            .buttonStyle(.gfOutline)
            .disabled(finishing)
            .accessibilityLabel("Skip to full time")
        }
        .padding(.horizontal, 24)
        }
        }
    }

    /// Every event so far as a card: goals in the scorer's club colours,
    /// cards and chances in white, the home side's minute on the right.
    private func commentaryCards(home: Club, away: Club) -> some View {
        let visible = visibleEvents
        return ScrollView {
            LazyVStack(spacing: 8) {
                if visible.isEmpty {
                    Text(minute == 0 ? "Kick-off imminent..." : "No key events yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                }
                ForEach(visible.reversed()) { ev in
                    let isGoal = ev.type == .goal || ev.type == .penalty || ev.type == .ownGoal
                    let club = ev.isHomeTeam ? home : away
                    let fill = isGoal ? Color(hex: club.primaryColor) : Color.white
                    let text = isGoal ? Color.readable(on: club.primaryColor) : Color.black
                    let marker = VStack(spacing: 2) {
                        Image(systemName: ev.type.icon).accessibilityHidden(true).font(.caption)
                        Text("\(ev.minute)'").font(.caption2.weight(.heavy).monospacedDigit())
                    }
                    .foregroundStyle(Color.gfNight)
                    .frame(width: 38)
                    .frame(maxHeight: .infinity)
                    .background(Color.white)
                    HStack(spacing: 0) {
                        if !ev.isHomeTeam { marker }
                        VStack(alignment: ev.isHomeTeam ? .leading : .trailing, spacing: 3) {
                            if isGoal {
                                let scorer = ev.playerId.flatMap { gameState.player(withId: $0)?.player.displayName }
                                Text("\((scorer ?? club.name).uppercased())!").font(.gfDisplay(18))
                            }
                            Text(ev.detailText)
                                .font(.subheadline)
                                .multilineTextAlignment(ev.isHomeTeam ? .leading : .trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(text)
                        .frame(maxWidth: .infinity, alignment: ev.isHomeTeam ? .leading : .trailing)
                        .padding(12)
                        if ev.isHomeTeam { marker }
                    }
                    .background(fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibleMatchEvent(ev)
                }
            }
            .padding(.horizontal)
        }
    }

    /// Match stats so far. While the match is live they are exact; for a
    /// finished match being replayed they are scaled to the minute reached,
    /// so the replay does not give away what is still to come.
    private func liveStats(home: Club, away: Club) -> some View {
        let share = inProgress ? 1.0 : (finalMinute > 0 ? Double(minute) / Double(finalMinute) : 1)
        func scaled(_ v: Int) -> Int { Int((Double(v) * share).rounded()) }
        let goals = (result?.goalEvents ?? []).filter { $0.minute <= minute }
        let h = result?.homeStats, a = result?.awayStats
        let homeColor = Color(hex: home.primaryColor)
        let awayColor = Color(hex: away.primaryColor == home.primaryColor ? away.secondaryColor : away.primaryColor)
        return ScrollView {
            VStack(spacing: 14) {
                if let h, let a {
                    DualStatBar(title: "Possession %", home: h.possession, away: a.possession,
                                homeText: "\(Int(h.possession.rounded()))", awayText: "\(Int(a.possession.rounded()))",
                                homeColor: homeColor, awayColor: awayColor)
                    DualStatBar(title: "xG", home: h.xG * share, away: a.xG * share,
                                homeText: String(format: "%.2f", h.xG * share), awayText: String(format: "%.2f", a.xG * share),
                                homeColor: homeColor, awayColor: awayColor)
                    let hg = goals.filter { $0.isHomeTeam }.count, ag = goals.count - goals.filter { $0.isHomeTeam }.count
                    let hOn = max(hg, scaled(h.shotsOnTarget)), aOn = max(ag, scaled(a.shotsOnTarget))
                    DualStatBar(title: "Shots on target", home: Double(hOn), away: Double(aOn),
                                homeText: "\(hOn)", awayText: "\(aOn)", homeColor: homeColor, awayColor: awayColor)
                    DualStatBar(title: "Shots", home: Double(max(hOn, scaled(h.shots))), away: Double(max(aOn, scaled(a.shots))),
                                homeText: "\(max(hOn, scaled(h.shots)))", awayText: "\(max(aOn, scaled(a.shots)))",
                                homeColor: homeColor, awayColor: awayColor)
                    DualStatBar(title: "Corners", home: Double(scaled(h.corners)), away: Double(scaled(a.corners)),
                                homeText: "\(scaled(h.corners))", awayText: "\(scaled(a.corners))", homeColor: homeColor, awayColor: awayColor)
                    DualStatBar(title: "Fouls", home: Double(scaled(h.fouls)), away: Double(scaled(a.fouls)),
                                homeText: "\(scaled(h.fouls))", awayText: "\(scaled(a.fouls))", homeColor: homeColor, awayColor: awayColor)
                    DualStatBar(title: "Offsides", home: Double(scaled(h.offsides)), away: Double(scaled(a.offsides)),
                                homeText: "\(scaled(h.offsides))", awayText: "\(scaled(a.offsides))", homeColor: homeColor, awayColor: awayColor)
                    let cards = visibleEvents
                    let hy = cards.filter { $0.isHomeTeam && $0.type == .yellowCard }.count
                    let ay = cards.filter { !$0.isHomeTeam && $0.type == .yellowCard }.count
                    DualStatBar(title: "Yellow cards", home: Double(hy), away: Double(ay),
                                homeText: "\(hy)", awayText: "\(ay)", homeColor: homeColor, awayColor: awayColor)
                }
            }
            .gfCard()
            .padding(.horizontal)
        }
    }

    /// Who is on the pitch now. While the match is live, each player shows
    /// how much he has left in his legs, and any knock he is carrying.
    private func onPitch(_ club: Club, isHome: Bool) -> [Player] {
        guard let session, !session.isFinished else { return club.startingXIPlayers }
        let ids = isHome ? session.paused.homeOnPitch : session.paused.awayOnPitch
        let source = isHome ? session.home : session.away
        return ids.compactMap { id in source.players.first { $0.id == id } ?? club.players.first { $0.id == id } }
    }

    private func lineups(home: Club, away: Club) -> some View {
        let done = !inProgress && minute >= finalMinute
        let fatigue = session?.paused.fatigue ?? [:]
        let hurt = session?.paused.hurtIds ?? []
        let off = session?.paused.sentOffIds ?? []
        func column(_ club: Club, isHome: Bool, alignment: HorizontalAlignment) -> some View {
            VStack(alignment: alignment, spacing: 6) {
                Text(club.tactics.formation.rawValue).font(.gfLabel(14)).foregroundStyle(.secondary)
                ForEach(onPitch(club, isHome: isHome)) { player in
                    HStack(spacing: 6) {
                        if alignment == .trailing { Spacer(minLength: 0) }
                        Text(player.primaryPosition.abbreviation)
                            .font(.gfLabel(11))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(player.primaryPosition.category.accentColor))
                        Text(player.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .strikethrough(off.contains(player.id))
                        if hurt.contains(player.id) {
                            Image(systemName: "cross.case.fill").accessibilityHidden(true).font(.caption2).foregroundStyle(.orange)
                                .accessibilityLabel("hurt")
                        }
                        if inProgress, let tired = fatigue[player.id] {
                            // Condition: what is left in his legs.
                            let left = max(0, 1 - tired / 45)
                            Capsule().fill(Color.white.opacity(0.2))
                                .frame(width: 26, height: 5)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(left > 0.55 ? Color.gfMint : left > 0.3 ? Color.yellow : Color.red)
                                        .frame(width: 26 * left, height: 5)
                                }
                                .accessibilityLabel("condition \(Int(left * 100)) percent")
                        }
                        if done, let rating = result?.playerRatings[player.id] {
                            Text(String(format: "%.1f", rating))
                                .font(.caption2.weight(.heavy).monospacedDigit())
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(rating >= 7 ? Color.gfMint : Color.white.opacity(0.85)))
                                .foregroundStyle(Color.gfNight)
                        }
                        if alignment == .leading { Spacer(minLength: 0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        }
        return ScrollView {
            HStack(alignment: .top, spacing: 12) {
                column(home, isHome: true, alignment: .leading)
                column(away, isHome: false, alignment: .trailing)
            }
            .gfCard()
            .padding(.horizontal)
        }
    }

    // MARK: - Logic

    private var currentHomeGoals: Int {
        (result?.goalEvents ?? []).filter { $0.minute <= minute && $0.isHomeTeam }.count
    }

    private var currentAwayGoals: Int {
        (result?.goalEvents ?? []).filter { $0.minute <= minute && !$0.isHomeTeam }.count
    }

    private var scoreText: String {
        if !inProgress, minute >= finalMinute, let result { return result.scoreText }
        return "\(currentHomeGoals) - \(currentAwayGoals)"
    }

    private func prepare() {
        // Never replay a finished match: if the active fixture has already
        // been played and we are not mid-replay, pick today's match instead.
        if !didSimulate, let current = fixture, current.isPlayed {
            if !gameState.selectTodaysUserFixture() {
                gameState.currentScreen = .dashboard
                return
            }
        }
        guard let fixture = fixture else { return }
        if !didSimulate {
            if !fixture.isPlayed {
                gameState.applyTeamTalkIfNeeded()
                // Kick off; the match is then played a minute at a time.
                if !gameState.beginLiveMatch(fixtureId: fixture.id) {
                    gameState.simulateFixture(id: fixture.id)
                }
            }
            didSimulate = true
        }
        // Coming back to a match in progress carries on from where it was.
        minute = session.map { $0.isFinished ? 0 : $0.paused.minutePlayed } ?? 0
        if let home = gameState.club(withId: fixture.homeClubId) {
            CrowdAtmosphere.shared.startMatch(capacity: home.stadiumCapacity)
        }
        // A screen-reader user follows the match in the Commentary tab.
        if voiceOverOn { pane = .commentary }
        startTicker()
    }

    private func startTicker() {
        guard inProgress || minute < finalMinute else { return }
        isPlaying = true
        ticker?.invalidate()
        // With VoiceOver on, give each minute time to be read out.
        let interval = voiceOverOn ? max(2.5, gameState.matchSettings.speed.tickInterval) : gameState.matchSettings.speed.tickInterval
        ticker = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        isPlaying = false
    }

    /// One minute of the match: played by the engine if the match is live,
    /// then shown.
    private func tick() {
        guard let fixture else { stopTicker(); return }
        let previous = minute
        if inProgress {
            let target = minute + 1
            let stillPlaying = gameState.advanceLiveMatch(through: target)
            minute = target
            if !stillPlaying {
                // Final whistle: write the result like any other match.
                gameState.simulateFixture(id: fixture.id)
            }
            reveal(from: previous)
            if stillPlaying, let session {
                if let reason = session.paused.stopReason {
                    Haptics.matchEvent(.injury)
                    stopForManager(reason)
                    return
                }
                if minute == 45 && manages && gameState.matchSettings.stopAtHalfTime {
                    stopForManager("HALF-TIME")
                    return
                }
            }
        } else {
            minute = min(finalMinute, minute + 1)
            reveal(from: previous)
        }
        if !inProgress && minute >= finalMinute {
            stopTicker()
            Haptics.matchEvent(.fullTime)
            CrowdAtmosphere.shared.fullTime()
            AccessibilityNotification.Announcement("Full time. \(scoreText).").post()
        }
    }

    /// Crowd, haptics and announcements for what happened since `previous`.
    private func reveal(from previous: Int) {
        let events = result?.events ?? []
        // The crowd and haptics react to every incident, not just major ones.
        for ev in events where ev.minute > previous && ev.minute <= minute {
            CrowdAtmosphere.shared.react(to: ev)
            if ev.type == .goal || ev.type == .penalty || ev.type == .ownGoal {
                let userId = gameState.userClubId
                Haptics.goal(forUser: ev.type == .ownGoal ? ev.clubId != userId : ev.clubId == userId)
            } else {
                Haptics.matchEvent(ev.type)
            }
        }
        if inProgress, let capacity = fixture.flatMap({ gameState.club(withId: $0.homeClubId)?.stadiumCapacity }) {
            CrowdAtmosphere.shared.ensureRunning(capacity: capacity)
        }
        CrowdAtmosphere.shared.tickMinute(homeLeading: currentHomeGoals > currentAwayGoals)

        // VoiceOver follows the match: everything that happened this minute is
        // read out as one announcement, in order, so none of it talks over the
        // rest. The Commentary tab holds the same lines to scroll back through.
        let happened = events.filter { $0.minute > previous && $0.minute <= minute && $0.type != .commentary }
        if voiceOverOn, !happened.isEmpty {
            let lines = happened.map { "\($0.minute) minutes. \($0.detailText)" }
            AccessibilityNotification.Announcement(lines.joined(separator: " ")).post()
        }

        // Announce major events as their minute arrives.
        let newEvents = events.filter { $0.minute > previous && $0.minute <= minute && $0.type.isMajorEvent }
        for ev in newEvents {
            if ev.type == .goal || ev.type == .penalty || ev.type == .ownGoal {
                SoundManager.shared.play(.goal, enabled: gameState.soundEnabled)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { goalFlash = ev }
                let shown = ev.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    if goalFlash?.id == shown { withAnimation(.easeOut) { goalFlash = nil } }
                }
            }
        }
    }

    /// Finishes the match once. Simulating the rest can take a moment, and a
    /// second tap in that time used to finish the match (and the matchweek)
    /// twice, jumping straight to the player of the match or crashing.
    private func finish(fixture: Fixture) {
        guard !finishing else { return }
        finishing = true
        stopTicker()
        touchline = nil
        // Let the button show as pressed first; the work follows on the next pass.
        DispatchQueue.main.async {
            guard gameState.season.fixtures.contains(where: { $0.id == fixture.id }) else { return }
            gameState.simulateFixture(id: fixture.id)
            minute = finalMinute
            gameState.finishMatchweekAfterUserMatch()
            gameState.currentScreen = .postMatch
        }
    }
}

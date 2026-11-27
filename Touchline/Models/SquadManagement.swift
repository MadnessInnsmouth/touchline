//
//  SquadManagement.swift
//  Touchline
//
//  The manager's squad decisions outside the transfer window negotiations:
//  marking players as available, untouchable or listed, and terminating
//  contracts by mutual consent.
//

import Foundation

extension GameState {

    /// Sets the user's stance on selling one of their players.
    public func setTransferStatus(playerId: UUID, to status: TransferStatus) {
        guard let clubIdx = clubs.firstIndex(where: { $0.isUserClub }),
              let pIdx = clubs[clubIdx].players.firstIndex(where: { $0.id == playerId }),
              !clubs[clubIdx].players[pIdx].isOnLoan else { return }
        clubs[clubIdx].players[pIdx].transferStatus = status == .available ? nil : status
    }

    /// The pay-off for terminating a contract by mutual consent: half of the
    /// wages left on the deal, as players usually settle for less than the
    /// full amount to secure a free transfer.
    public func releaseCost(for player: Player) -> Int {
        guard let contract = player.contract else { return 0 }
        return max(0, contract.wage * 52 * max(1, contract.yearsRemaining) / 2)
    }

    /// Terminates a player's contract and releases him as a free agent.
    /// Returns a message describing what happened.
    @discardableResult
    public func releasePlayer(playerId: UUID) -> String {
        guard let clubIdx = clubs.firstIndex(where: { $0.isUserClub }),
              let player = clubs[clubIdx].player(withId: playerId) else {
            return "That player is not at your club."
        }
        if let loan = player.loan {
            return "\(player.fullName) is on loan from \(loan.parentClubName). Send him back instead."
        }
        guard clubs[clubIdx].players.count > 16 else {
            return "You need at least 16 senior players. Sign a replacement first."
        }
        let cost = releaseCost(for: player)
        guard clubs[clubIdx].finances.balance >= cost else {
            return "The club cannot afford the \(Player.formatCurrency(cost)) settlement."
        }
        guard var released = clubs[clubIdx].removePlayer(withId: playerId) else {
            return "The release could not be completed."
        }
        clubs[clubIdx].finances.balance -= cost
        seasonLedger?.wages += cost
        released.contract = nil
        released.transferStatus = nil
        freeAgents.append(released)
        pendingTransferOffers.removeAll { $0.playerId == playerId && $0.isIncoming }
        clubs[clubIdx].ensureTacticalIntegrity()
        clubs[clubIdx].finances.currentWageBill = clubs[clubIdx].totalWeeklyWageBill
        addNews(
            headline: "\(player.fullName) Released",
            body: "\(player.fullName)'s contract has been terminated by mutual consent. The settlement cost \(Player.formatCurrency(cost)), and his \(Player.formatCurrency(player.wage))/w wage is off the books.",
            category: .transfer,
            sender: "Club Secretary"
        )
        return "\(player.fullName) has been released."
    }
}

// MARK: - Lineup editing

/// Where a player sits in the user's matchday squad.
public enum LineupSlot: Equatable {
    case starter(Int)   // index into the starting XI (formation slot)
    case bench(Int)     // index into the substitutes
    case reserve
}

extension GameState {

    private var userClubIndex: Int? { clubs.firstIndex(where: { $0.isUserClub }) }

    public func lineupSlot(of playerId: UUID) -> LineupSlot? {
        guard let idx = userClubIndex, clubs[idx].player(withId: playerId) != nil else { return nil }
        let tactics = clubs[idx].tactics
        if let i = tactics.startingXI.firstIndex(of: playerId) { return .starter(i) }
        if let i = tactics.substitutes.firstIndex(of: playerId) { return .bench(i) }
        return .reserve
    }

    /// Swaps two players anywhere in the matchday squad: two starters swap
    /// positions (left back for right back), a starter and a substitute or
    /// reserve swap places, a substitute and a reserve swap places.
    /// Returns a message explaining why the swap was refused, or nil.
    @discardableResult
    public func swapLineup(_ a: UUID, _ b: UUID) -> String? {
        guard a != b, let idx = userClubIndex,
              let slotA = lineupSlot(of: a), let slotB = lineupSlot(of: b),
              let playerA = clubs[idx].player(withId: a),
              let playerB = clubs[idx].player(withId: b) else { return "Those players cannot be swapped." }
        // Anyone moving into the XI or onto the bench must be available.
        func entering(_ player: Player, into slot: LineupSlot) -> String? {
            if case .reserve = slot { return nil }
            if player.isInjured { return "\(player.fullName) is injured." }
            if player.isSuspended { return "\(player.fullName) is suspended." }
            return nil
        }
        if let reason = entering(playerA, into: slotB) ?? entering(playerB, into: slotA) { return reason }

        // During a live match: the bench is fixed, players taken off cannot
        // return, and substitutions are limited.
        if let session = liveMatch, session.config.userClubId == clubs[idx].id, !session.isFinished {
            let gone = session.paused.unavailableIds
            for (player, slot) in [(playerA, slotB), (playerB, slotA)] {
                guard case .starter = slot else { continue }
                if gone.contains(player.id) && !clubs[idx].tactics.startingXI.contains(player.id) {
                    return "\(player.fullName) has already gone off and cannot come back on."
                }
            }
            if case .reserve = slotA { return "\(playerA.fullName) is not in the matchday squad." }
            if case .reserve = slotB { return "\(playerB.fullName) is not in the matchday squad." }
            if case .bench = slotA, case .bench = slotB { return nil }
            // Bringing someone on from the bench: is a change left?
            let comingOn: Bool
            switch (slotA, slotB) {
            case (.bench, .starter), (.starter, .bench): comingOn = true
            default: comingOn = false
            }
            if comingOn {
                let isHome = session.home.id == clubs[idx].id
                let pitchAtStop = Set(isHome ? session.paused.homeOnPitch : session.paused.awayOnPitch)
                let newOnes = clubs[idx].tactics.startingXI.filter { !pitchAtStop.contains($0) }.count
                if newOnes >= liveSubsRemaining {
                    return liveSubsRemaining == 0
                        ? "No substitutions left\(liveWindowsRemaining == 0 ? " (all three windows used)" : "")."
                        : "That would be more substitutions than you have left."
                }
            }
            var tactics = clubs[idx].tactics
            switch slotA {
            case .starter(let i): tactics.startingXI[i] = b
            case .bench(let i): tactics.substitutes[i] = b
            case .reserve: break
            }
            switch slotB {
            case .starter(let i): tactics.startingXI[i] = a
            case .bench(let i): tactics.substitutes[i] = a
            case .reserve: break
            }
            clubs[idx].tactics = tactics
            return nil
        }

        var tactics = clubs[idx].tactics
        func put(_ id: UUID, into slot: LineupSlot) {
            switch slot {
            case .starter(let i): tactics.startingXI[i] = id
            case .bench(let i): tactics.substitutes[i] = id
            case .reserve: break
            }
        }
        if case .reserve = slotA, case .reserve = slotB { return nil }
        put(a, into: slotB)
        put(b, into: slotA)
        clubs[idx].tactics = tactics
        clubs[idx].ensureTacticalIntegrity()
        return nil
    }

    /// Adds a reserve to a free place on the bench (up to seven).
    @discardableResult
    public func addToBench(_ playerId: UUID) -> String? {
        guard let idx = userClubIndex, let player = clubs[idx].player(withId: playerId) else { return nil }
        guard case .reserve = lineupSlot(of: playerId) else { return nil }
        if liveMatch != nil { return "The matchday squad is fixed once the match has kicked off." }
        guard clubs[idx].tactics.substitutes.count < 7 else { return "The bench is full. Swap him with a substitute instead." }
        guard player.isAvailable else { return "\(player.fullName) is not available." }
        clubs[idx].tactics.substitutes.append(playerId)
        return nil
    }

    /// Takes a substitute off the bench.
    public func removeFromBench(_ playerId: UUID) {
        guard let idx = userClubIndex, liveMatch == nil else { return }
        clubs[idx].tactics.substitutes.removeAll { $0 == playerId }
    }

    /// Picks the strongest available side for the current formation.
    public func autoPickUserLineup() {
        guard let idx = userClubIndex, liveMatch == nil else { return }
        clubs[idx].autoPickStartingXI()
    }

    func setAutomaticMatchdaySelection(_ enabled: Bool) {
        matchSettings.autoSelectMatchdayLineup = enabled
        try? SaveManager.shared.autoSave(gameState: self)
    }

    // MARK: Match-only lineups

    /// Whether the current lineup is a one-off for the next match.
    public var hasMatchOnlyLineup: Bool { matchOnlyLineupBackup != nil }

    /// Remembers the usual lineup before changes made for the next match.
    /// Called when the manager opens the match-day lineup and at kick-off.
    /// Everything changed after this (on match day or during the match) is
    /// for that match only and is undone afterwards, unless he taps
    /// "Keep as my lineup". An existing snapshot is never replaced, so the
    /// usual lineup is the one from before match day.
    public func beginMatchOnlyLineup() {
        guard let idx = userClubIndex, matchOnlyLineupBackup == nil else { return }
        matchOnlyLineupBackup = clubs[idx].tactics
    }

    /// Whether the lineup for the next match differs from the usual one.
    public var matchLineupDiffersFromUsual: Bool {
        guard let backup = matchOnlyLineupBackup, let club = userClub else { return false }
        return backup != club.tactics
    }

    /// Restores the usual lineup (after the match, or if the manager cancels).
    public func restoreUsualLineup() {
        guard let backup = matchOnlyLineupBackup, let idx = userClubIndex else {
            matchOnlyLineupBackup = nil
            return
        }
        clubs[idx].tactics = backup
        clubs[idx].ensureTacticalIntegrity()
        matchOnlyLineupBackup = nil
    }

    /// Makes the current lineup the usual one. Later changes for this match
    /// are still undone afterwards, back to this lineup.
    public func keepMatchLineup() {
        guard let idx = userClubIndex, matchOnlyLineupBackup != nil else { return }
        matchOnlyLineupBackup = clubs[idx].tactics
    }
}

// MARK: - Scouting

extension GameState {
    /// What the club knows about a player's ceiling. Your own players are
    /// known exactly; for others the range narrows with your best scout
    /// (seven points either way with no scout, one with a five-star scout).
    /// The range always contains the true potential and stays the same
    /// between looks.
    public func potentialEstimate(for player: Player) -> ClosedRange<Int> {
        if userClub?.player(withId: player.id) != nil { return player.potential...player.potential }
        let quality = userClub?.bestScout?.quality ?? 0
        let width = max(1, 7 - quality)
        let seed = Int(truncatingIfNeeded: player.id.uuidString.hashValueStable)
        let below = abs(seed) % (width * 2 + 1)
        let low = max(player.overall, player.potential - below)
        let high = min(99, player.potential + (width * 2 - below))
        return low...max(low, high)
    }
}

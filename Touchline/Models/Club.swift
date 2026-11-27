//
//  Club.swift
//  Touchline
//
//  Created for Touchline - iOS Football Manager Game.
//  Club model encompassing squad personnel, tactical instructions, club finances,
//  staff management, facility upgrades, and historical season results.
//

import Foundation

// MARK: - Club Model

public struct Club: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var shortName: String          // Standard 3-letter abbreviation (e.g., "ARS", "MUN")
    public var stadium: String
    public var stadiumCapacity: Int
    public var city: String
    public var primaryColor: String        // Hex code (e.g., "#EF0107")
    public var secondaryColor: String      // Hex code (e.g., "#FFFFFF")
    public var leagueTier: LeagueTier
    public var reputation: Int             // Scale 1 - 100
    public var isUserClub: Bool
    
    public var players: [Player]
    public var manager: String

    // Youth Academy Prospects (aged 15-18, develop before promotion to the senior squad)
    public var academyProspects: [Player]
    
    // Financial Standing
    public var finances: ClubFinances
    
    // Coaching & Scouting Staff
    public var staff: [StaffMember]
    
    // Club Infrastructure Levels (1 - 5)
    public var trainingFacilityLevel: Int
    public var youthAcademyLevel: Int
    public var medicalFacilityLevel: Int
    
    // Strategic & In-Match Setup
    public var tactics: Tactics
    
    // Completed Match Logs
    public var seasonResults: [MatchResult]
    
    // MARK: - Initializer
    
    public init(
        id: UUID = UUID(),
        name: String,
        shortName: String,
        stadium: String,
        stadiumCapacity: Int,
        city: String,
        primaryColor: String,
        secondaryColor: String,
        leagueTier: LeagueTier,
        reputation: Int,
        isUserClub: Bool = false,
        players: [Player] = [],
        manager: String = "Manager",
        academyProspects: [Player] = [],
        finances: ClubFinances? = nil,
        staff: [StaffMember] = [],
        trainingFacilityLevel: Int = 2,
        youthAcademyLevel: Int = 2,
        medicalFacilityLevel: Int = 2,
        tactics: Tactics? = nil,
        seasonResults: [MatchResult] = []
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.stadium = stadium
        self.stadiumCapacity = stadiumCapacity
        self.city = city
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.leagueTier = leagueTier
        self.reputation = reputation
        self.isUserClub = isUserClub
        self.players = players
        self.manager = manager
        self.academyProspects = academyProspects
        
        let initialFinances = finances ?? ClubFinances.defaultFor(
            tier: leagueTier,
            reputation: reputation,
            capacity: stadiumCapacity
        )
        self.finances = initialFinances
        
        self.staff = staff.isEmpty ? StaffMember.defaultStaffFor(tier: leagueTier) : staff
        self.trainingFacilityLevel = trainingFacilityLevel
        self.youthAcademyLevel = youthAcademyLevel
        self.medicalFacilityLevel = medicalFacilityLevel
        self.tactics = tactics ?? Tactics.defaultTactics
        self.seasonResults = seasonResults
        
        // Synchronize initial wage bill & pick lineup if players are provided
        self.finances.currentWageBill = self.totalWeeklyWageBill
        if !players.isEmpty && self.tactics.startingXI.isEmpty {
            self.autoPickStartingXI()
        }
    }
    
    // MARK: - Squad Query Helpers
    
    /// Players currently assigned to the starting XI in order.
    public var startingXIPlayers: [Player] {
        return tactics.startingXI.compactMap { id in
            players.first { $0.id == id }
        }
    }
    
    /// Players assigned to the bench.
    public var substitutePlayers: [Player] {
        return tactics.substitutes.compactMap { id in
            players.first { $0.id == id }
        }
    }
    
    /// Players unassigned to starting XI or substitutes.
    public var reservePlayers: [Player] {
        let matchdayIds = Set(tactics.startingXI + tactics.substitutes)
        return players.filter { !matchdayIds.contains($0.id) }
    }
    
    /// Available players without injuries or active suspensions.
    public var availablePlayers: [Player] {
        return players.filter { $0.isAvailable }
    }
    
    public var injuredPlayers: [Player] {
        return players.filter { $0.isInjured }
    }
    
    public var suspendedPlayers: [Player] {
        return players.filter { $0.isSuspended }
    }
    
    public var squadSize: Int {
        return players.count
    }
    
    /// Total weekly wage obligation (all players + coaching staff).
    public var totalWeeklyWageBill: Int {
        return totalPlayerWageBill + totalStaffWageBill
    }
    
    public var totalPlayerWageBill: Int {
        return players.reduce(0) { $0 + $1.payrollWage }
    }
    
    public var totalStaffWageBill: Int {
        return staff.reduce(0) { $0 + $1.wage }
    }
    
    /// Mean overall rating across the entire registered squad.
    public var squadAverageOverall: Double {
        guard !players.isEmpty else { return 50.0 }
        let total = players.reduce(0) { $0 + $1.overall }
        return Double(total) / Double(players.count)
    }
    
    /// Mean overall rating of the starting 11 players.
    public var startingXIAverageOverall: Double {
        let xi = startingXIPlayers
        guard !xi.isEmpty else { return squadAverageOverall }
        let total = xi.reduce(0) { $0 + $1.overall }
        return Double(total) / Double(xi.count)
    }
    
    // MARK: - Player Access & Mutation
    
    public func player(withId id: UUID) -> Player? {
        return players.first { $0.id == id }
    }
    
    public mutating func updatePlayer(_ updated: Player) {
        if let idx = players.firstIndex(where: { $0.id == updated.id }) {
            players[idx] = updated
            finances.currentWageBill = totalWeeklyWageBill
        }
    }
    
    /// Clubs budget around the wages they already pay. A starting wage budget
    /// below the existing bill left a club unable to sign anyone (78 of 688
    /// clubs, including all of League Two). Budgets now leave about 35%
    /// headroom above the bill, so there is real room to sign and renew.
    public mutating func ensureWageHeadroom() {
        finances.currentWageBill = totalWeeklyWageBill
        let minimum = Int(Double(totalWeeklyWageBill) * 1.35)
        if finances.wageBudget < minimum {
            finances.wageBudget = minimum
        }
    }

    public mutating func addPlayer(_ newPlayer: Player) {
        if !players.contains(where: { $0.id == newPlayer.id }) {
            players.append(newPlayer)
            finances.currentWageBill = totalWeeklyWageBill
        }
    }
    
    // MARK: - Youth Academy

    public mutating func addProspect(_ prospect: Player) {
        if !academyProspects.contains(where: { $0.id == prospect.id }) {
            academyProspects.append(prospect)
        }
    }

    @discardableResult
    public mutating func promoteProspect(withId id: UUID) -> Player? {
        guard let idx = academyProspects.firstIndex(where: { $0.id == id }) else { return nil }
        let promoted = academyProspects.remove(at: idx)
        addPlayer(promoted)
        return promoted
    }

    @discardableResult
    public mutating func releaseProspect(withId id: UUID) -> Player? {
        guard let idx = academyProspects.firstIndex(where: { $0.id == id }) else { return nil }
        return academyProspects.remove(at: idx)
    }

    // MARK: - Staff & Facilities Management

    /// Best scout on the books, if any.
    public var bestScout: StaffMember? {
        staff.filter { $0.role == .scout }.max { $0.quality < $1.quality }
    }

    /// Cost to hire a scout of the given quality (1-5 stars).
    public static func scoutHiringFee(quality: Int) -> Int {
        return 250_000 + max(0, quality - 1) * 350_000
    }

    /// Cost to upgrade the youth academy one level.
    public var academyUpgradeCost: Int {
        return 1_500_000 * youthAcademyLevel
    }

    /// Cost to upgrade the training ground one level.
    public var trainingUpgradeCost: Int {
        return 2_000_000 * trainingFacilityLevel
    }

    public var medicalUpgradeCost: Int {
        return 1_250_000 * medicalFacilityLevel
    }

    public var stadiumExpansionCost: Int {
        return max(2_500_000, stadiumCapacity * 700)
    }

    /// Owner-only appointment. The fee represents search, signing and contract
    /// costs; ongoing wages are rolled into the club wage bill.
    @discardableResult
    public mutating func hireStaff(role: StaffRole, quality: Int) -> StaffMember? {
        let stars = max(1, min(5, quality))
        let fee = 180_000 + (stars * stars * 140_000)
        guard finances.balance >= fee else { return nil }
        finances.balance -= fee
        let staffer = StaffMember(
            name: Self.randomStaffName(role: role),
            role: role,
            quality: stars,
            wage: 500 + stars * 850
        )
        staff.append(staffer)
        finances.currentWageBill = totalWeeklyWageBill
        return staffer
    }

    /// Hires a new scout, paying from the treasury. Returns the new staff member
    /// (or nil if the club cannot afford it).
    @discardableResult
    public mutating func hireScout(quality: Int) -> StaffMember? {
        let fee = Club.scoutHiringFee(quality: quality)
        guard finances.transferBudget >= fee else { return nil }
        finances.transferBudget -= fee
        let scout = StaffMember(
            name: Club.randomScoutName(),
            role: .scout,
            quality: max(1, min(5, quality)),
            wage: 1_500 + quality * 900
        )
        staff.append(scout)
        finances.currentWageBill = totalWeeklyWageBill
        return scout
    }

    /// Releases a member of staff, returning whether they were found.
    @discardableResult
    public mutating func releaseStaff(withId id: UUID) -> Bool {
        guard let idx = staff.firstIndex(where: { $0.id == id }) else { return false }
        staff.remove(at: idx)
        finances.currentWageBill = totalWeeklyWageBill
        return true
    }

    /// Upgrades the youth academy a level if affordable.
    @discardableResult
    public mutating func upgradeYouthAcademy() -> Bool {
        guard youthAcademyLevel < 5, finances.transferBudget >= academyUpgradeCost else { return false }
        finances.transferBudget -= academyUpgradeCost
        youthAcademyLevel += 1
        return true
    }

    /// Upgrades the training ground a level if affordable.
    @discardableResult
    public mutating func upgradeTrainingGround() -> Bool {
        guard trainingFacilityLevel < 5, finances.transferBudget >= trainingUpgradeCost else { return false }
        finances.transferBudget -= trainingUpgradeCost
        trainingFacilityLevel += 1
        return true
    }

    @discardableResult
    public mutating func upgradeMedicalFacilities() -> Bool {
        guard medicalFacilityLevel < 5, finances.balance >= medicalUpgradeCost else { return false }
        finances.balance -= medicalUpgradeCost
        medicalFacilityLevel += 1
        return true
    }

    @discardableResult
    public mutating func expandStadium() -> Bool {
        guard finances.balance >= stadiumExpansionCost else { return false }
        finances.balance -= stadiumExpansionCost
        let previous = max(1, stadiumCapacity)
        stadiumCapacity += max(1_500, Int(Double(stadiumCapacity) * 0.15))
        finances.stadiumCapacity = stadiumCapacity
        // More seats sell proportionally more tickets and hospitality.
        finances.matchdayIncome = Int(Double(finances.matchdayIncome) * Double(stadiumCapacity) / Double(previous))
        return true
    }

    private static func randomScoutName() -> String {
        let first = ["Alan", "Brian", "Colin", "Derek", "Graham", "Ian", "Keith", "Malcolm", "Nigel", "Roy"]
        let last = ["Carr", "Doyle", "Ellis", "Hughes", "Kerr", "Lynch", "Nolan", "Pearce", "Quinn", "Ward"]
        return "\(first.randomElement() ?? "Alan") \(last.randomElement() ?? "Carr")"
    }

    static func randomStaffName(role: StaffRole, country: LeagueCountry? = nil) -> String {
        // Mostly local names, with the odd hire from abroad.
        let pools = [NamePools.england, NamePools.spain, NamePools.italy, NamePools.germany,
                     NamePools.france, NamePools.portugal, NamePools.netherlands, NamePools.scotland]
        let pool: NamePool
        if let country, Double.random(in: 0..<1) < 0.75 {
            pool = NamePools.pool(for: country)
        } else {
            pool = pools.randomElement() ?? NamePools.england
        }
        let name = pool.randomName()
        return "\(name.first) \(name.last)"
    }

    /// Older saves gave every club the same five real-world staff. Gives them
    /// fresh names and a spread of ability.
    public mutating func replaceLegacyStaff() {
        let legacy: Set<String> = ["John Terry", "Michael Carrick", "Steve Walsh", "Gary Lewin", "Neil Bath"]
        guard staff.contains(where: { legacy.contains($0.name) }) else { return }
        for idx in staff.indices where legacy.contains(staff[idx].name) {
            staff[idx].name = Club.randomStaffName(role: staff[idx].role, country: leagueTier.country)
            staff[idx].quality = max(1, min(5, staff[idx].quality + Int.random(in: -1...1)))
        }
    }

    // MARK: Staff market

    /// Number of people a club can employ in a role.
    public static func staffLimit(_ role: StaffRole) -> Int {
        switch role {
        case .coach, .scout: return 3
        default: return 1
        }
    }

    /// People available for a role this month. The list is stable for four
    /// weeks and pitched at the club's level: a fourth-tier side rarely
    /// attracts a five-star coach.
    public func staffCandidates(role: StaffRole, seasonYear: String, week: Int) -> [StaffCandidate] {
        let seedText = "\(id.uuidString)-\(role.rawValue)-\(seasonYear)-\(week / 4)"
        var rng = SeededGenerator(seed: UInt64(seedText.hashValueStable))
        let level = leagueTier.level
        let range: ClosedRange<Int>
        switch level {
        case 1: range = 2...5
        case 2: range = 2...4
        case 3: range = 1...4
        default: range = 1...3
        }
        let baseWage: Int
        switch level {
        case 1: baseWage = 4_000
        case 2: baseWage = 1_800
        case 3: baseWage = 900
        case 4: baseWage = 500
        default: baseWage = 300
        }
        let specialties = StaffCandidate.specialties(for: role)
        let pool = NamePools.pool(for: leagueTier.country)
        let abroad = [NamePools.spain, NamePools.italy, NamePools.germany, NamePools.france, NamePools.portugal, NamePools.netherlands]
        var result: [StaffCandidate] = []
        for index in 0..<5 {
            let names = (rng.next() % 4 == 0) ? abroad[Int(rng.next() % UInt64(abroad.count))] : pool
            let first = names.firstNames[Int(rng.next() % UInt64(names.firstNames.count))]
            let last = names.lastNames[Int(rng.next() % UInt64(names.lastNames.count))]
            var stars = range.lowerBound + Int(rng.next() % UInt64(range.count))
            // A rare stand-out who wants to step up.
            if rng.next() % 12 == 0 { stars = min(5, range.upperBound + 1) }
            let spread = 0.85 + Double(rng.next() % 30) / 100.0
            let wage = Int(Double(baseWage) * (0.5 + Double(stars) * 0.35) * spread)
            let age = 29 + Int(rng.next() % 35)
            let specialty = specialties[Int(rng.next() % UInt64(specialties.count))]
            result.append(StaffCandidate(
                id: "\(seedText)-\(index)",
                name: "\(first) \(last)",
                role: role,
                quality: stars,
                wage: max(150, wage / 10 * 10),
                fee: max(2_000, wage * 20 / 1_000 * 1_000),
                age: age,
                specialty: specialty
            ))
        }
        return result.sorted { $0.quality > $1.quality }
    }

    /// Hires a candidate. In a one-person role they replace whoever holds
    /// it. Returns a message for the UI.
    public mutating func hire(_ candidate: StaffCandidate) -> String {
        if staff.contains(where: { $0.name == candidate.name && $0.role == candidate.role }) {
            return "\(candidate.name) already works here."
        }
        let current = staff.filter { $0.role == candidate.role }
        let limit = Club.staffLimit(candidate.role)
        if limit > 1 && current.count >= limit {
            return "You already employ \(limit) people in this role. Release one first."
        }
        guard finances.balance >= candidate.fee else {
            return "The club cannot afford the \(Player.formatCurrency(candidate.fee)) fee."
        }
        finances.balance -= candidate.fee
        var replaced: String? = nil
        if limit == 1, let outgoing = current.first {
            staff.removeAll { $0.id == outgoing.id }
            replaced = outgoing.name
        }
        staff.append(StaffMember(name: candidate.name, role: candidate.role, quality: candidate.quality, wage: candidate.wage))
        finances.currentWageBill = totalWeeklyWageBill
        if let replaced {
            return "\(candidate.name) replaces \(replaced) as \(candidate.role.displayName)."
        }
        return "\(candidate.name) joins as \(candidate.role.displayName)."
    }

    @discardableResult
    public mutating func removePlayer(withId id: UUID) -> Player? {
        guard let idx = players.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = players.remove(at: idx)
        
        tactics.startingXI.removeAll { $0 == id }
        tactics.substitutes.removeAll { $0 == id }
        if tactics.captain == id { tactics.captain = nil }
        if tactics.cornerTaker == id { tactics.cornerTaker = nil }
        if tactics.freeKickTaker == id { tactics.freeKickTaker = nil }
        if tactics.penaltyTaker == id { tactics.penaltyTaker = nil }
        
        finances.currentWageBill = totalWeeklyWageBill
        return removed
    }
    
    // MARK: - Lineup & Tactical Intelligence
    
    /// Automatically selects the optimal 11 starters and bench players matching the current formation preset.
    public mutating func autoPickStartingXI() {
        var selectedStarters: [UUID] = []
        // Work from strongest to weakest so an exact positional match always
        // selects the best available player for that role.  The old behaviour
        // selected the first player in the data file, which made an auto-picked
        // side depend on import order rather than football ability.
        var pool = availablePlayers.sorted { lhs, rhs in
            if lhs.overall != rhs.overall { return lhs.overall > rhs.overall }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        
        let requiredPositions = tactics.formation.defaultPositions

        // 1. Match players to positions across the whole eleven at once: the
        // best (player, position) pairing first, then the next best among
        // the rest, and so on. Filling the positions one by one in order
        // used to put a centre-back at left-back (he was the best player
        // left for that slot) and leave the real left-back out. A player is
        // rated in a position by the match engine, so playing out of
        // position costs what it costs on the pitch; tired legs cost too.
        func value(_ p: Player, _ slot: Position) -> Double {
            if slot == .GK {
                return p.primaryPosition == .GK ? Double(p.overall) + 100
                    : (p.positions.contains(.GK) ? Double(p.overall) + 50 : -1000)
            }
            if p.primaryPosition == .GK { return -1000 }
            // Fitness and form count as well as ability: a player short of
            // match fitness or out of form loses out to a fresh, in-form one
            // of similar quality.
            let tired = max(0, 90 - p.matchFitness) / 2.5
            let recent = p.form.isEmpty ? 6.6 : p.form.reduce(0, +) / Double(p.form.count)
            let formBonus = max(-3, min(3, (recent - 6.6) * 3))
            return MatchEngine.rating(of: p, in: slot) - tired + formBonus
        }
        // Every pairing is rated once (this runs for every club every week).
        let scores: [[Double]] = pool.map { p in requiredPositions.map { value(p, $0) } }
        var slots = [UUID?](repeating: nil, count: requiredPositions.count)
        var openSlots = Set(requiredPositions.indices)
        var usedPlayers = Set<Int>()
        while !openSlots.isEmpty && usedPlayers.count < pool.count {
            var best: (slot: Int, player: Int, score: Double)?
            for i in pool.indices where !usedPlayers.contains(i) {
                for s in requiredPositions.indices where openSlots.contains(s) && (best == nil || scores[i][s] > best!.score) {
                    best = (s, i, scores[i][s])
                }
            }
            guard let pick = best else { break }
            slots[pick.slot] = pool[pick.player].id
            openSlots.remove(pick.slot)
            usedPlayers.insert(pick.player)
        }
        pool = pool.indices.filter { !usedPlayers.contains($0) }.map { pool[$0] }
        selectedStarters = slots.compactMap { $0 }
        tactics.startingXI = selectedStarters
        
        // 2. Select up to 7 substitute options (1 backup GK + defenders, midfielders, forwards)
        var subs: [UUID] = []
        
        // Backup GK
        if let backupGkIdx = pool.firstIndex(where: { $0.primaryPosition == .GK }) {
            subs.append(pool.remove(at: backupGkIdx).id)
        }
        
        // Sort remaining by overall rating
        pool.sort { $0.overall > $1.overall }
        while subs.count < 7 && !pool.isEmpty {
            subs.append(pool.removeFirst().id)
        }
        
        tactics.substitutes = subs
        
        // 3. Assign set piece takers & captain if unset
        let starters = startingXIPlayers
        if tactics.captain == nil || !selectedStarters.contains(tactics.captain!) {
            tactics.captain = starters.max(by: { $0.attributes.leadership < $1.attributes.leadership })?.id
        }
        if tactics.penaltyTaker == nil || !selectedStarters.contains(tactics.penaltyTaker!) {
            tactics.penaltyTaker = starters.max(by: { $0.attributes.penalties < $1.attributes.penalties })?.id
        }
        if tactics.freeKickTaker == nil || !selectedStarters.contains(tactics.freeKickTaker!) {
            tactics.freeKickTaker = starters.max(by: { $0.attributes.freeKicks < $1.attributes.freeKicks })?.id
        }
        if tactics.cornerTaker == nil || !selectedStarters.contains(tactics.cornerTaker!) {
            tactics.cornerTaker = starters.max(by: { $0.attributes.crossing < $1.attributes.crossing })?.id
        }
    }
    
    /// AI squad rotation: a starter short of match fitness is rested for a
    /// fresh squad player in the same area of the pitch who is not much worse.
    /// Keeps congested schedules (league, cup and Europe) from wearing the
    /// same eleven down, as a real manager would.
    /// How an AI manager prepares for a match: the best available side
    /// (so new signings, loanees and players back from injury get picked),
    /// then tired starters are rested.
    /// Every club needs two goalkeepers. Missing ones are added at roughly
    /// the squad's level (an emergency signing from the free market).
    @discardableResult
    public mutating func ensureGoalkeepers(minimum: Int = 2) -> Int {
        let keepers = players.filter { $0.primaryPosition == .GK }.count
        guard keepers < minimum else { return 0 }
        let ratings = players.map(\.overall).sorted(by: >).prefix(18)
        let level = ratings.isEmpty ? 55 : ratings.reduce(0, +) / ratings.count
        let added = DataLoader.generateProceduralSquad(targetCount: minimum - keepers, tier: leagueTier,
                                                       quality: max(40, level - 4))
        players.append(contentsOf: added)
        finances.currentWageBill = totalWeeklyWageBill
        return added.count
    }

    public mutating func prepareAIMatchday() {
        ensureGoalkeepers()
        autoPickStartingXI()
        rotateTiredStarters()
    }

    public mutating func rotateTiredStarters() {
        ensureTacticalIntegrity()
        let starters = Set(tactics.startingXI)
        for (slot, starterId) in tactics.startingXI.enumerated() {
            guard let starter = players.first(where: { $0.id == starterId }),
                  starter.matchFitness < 72 else { continue }
            let replacement = players
                .filter {
                    !starters.contains($0.id) && $0.isAvailable && $0.matchFitness >= 85
                        && $0.primaryPosition.category == starter.primaryPosition.category
                        && $0.overall >= starter.overall - 6
                }
                .max { $0.overall < $1.overall }
            guard let fresh = replacement else { continue }
            tactics.startingXI[slot] = fresh.id
            tactics.substitutes.removeAll { $0 == fresh.id }
            if !tactics.substitutes.contains(starterId) && tactics.substitutes.count < 7 {
                tactics.substitutes.append(starterId)
            }
        }
    }

    /// Validates and repairs startingXI and bench arrays, removing nonexistent, injured,
    /// or suspended players and replenishing from the available reserves.
    /// Fills gaps in the eleven with the best available player for each
    /// gap's position, bench first (he was named as cover), then reserves.
    private mutating func fillVacantSlots(_ slots: inout [UUID?]) {
        let positions = tactics.formation.defaultPositions
        for i in slots.indices where slots[i] == nil {
            let position = i < positions.count ? positions[i] : .CM
            let taken = Set(slots.compactMap { $0 })
            let pool = players.filter { $0.isAvailable && !taken.contains($0.id) }
            guard !pool.isEmpty else { continue }
            func score(_ p: Player) -> Double {
                var s = MatchEngine.rating(of: p, in: position)
                if position == .GK && p.primaryPosition != .GK { s -= 40 }
                if position != .GK && p.primaryPosition == .GK { s -= 40 }
                return s
            }
            let bench = pool.filter { tactics.substitutes.contains($0.id) }
            let benchBest = bench.max { score($0) < score($1) }
            let anyBest = pool.max { score($0) < score($1) }
            // Prefer the named cover unless someone else is clearly better.
            let pick: Player?
            if let b = benchBest, let a = anyBest, score(a) - score(b) <= 3 { pick = b } else { pick = anyBest }
            if let pick {
                slots[i] = pick.id
                tactics.substitutes.removeAll { $0 == pick.id }
            }
        }
    }

    /// After a change of formation, keeps the same eleven and moves each
    /// player to the new position that suits him best (no one is dropped).
    public mutating func fitLineupToFormation(repair: Bool = true) {
        let positions = tactics.formation.defaultPositions
        var remaining = startingXIPlayers
        guard remaining.count == 11 else {
            if repair { ensureTacticalIntegrity() }
            return
        }
        var slots = [UUID?](repeating: nil, count: positions.count)
        // Fill the most specialised positions first (keeper, then the rest by
        // how few players can play them).
        let order = positions.indices.sorted { a, b in
            if positions[a] == .GK { return true }
            if positions[b] == .GK { return false }
            let fa = remaining.filter { $0.positions.contains(positions[a]) }.count
            let fb = remaining.filter { $0.positions.contains(positions[b]) }.count
            return fa < fb
        }
        for i in order {
            guard let best = remaining.indices.max(by: {
                MatchEngine.rating(of: remaining[$0], in: positions[i]) < MatchEngine.rating(of: remaining[$1], in: positions[i])
            }) else { break }
            slots[i] = remaining.remove(at: best).id
        }
        tactics.startingXI = slots.compactMap { $0 }
        if repair { ensureTacticalIntegrity() }
    }

    public mutating func ensureTacticalIntegrity() {
        let playerIds = Set(players.map { $0.id })
        let unavailableIds = Set(players.filter { !$0.isAvailable }.map { $0.id })

        // Starters keep their places: a missing or unavailable starter leaves
        // a gap in his position (rather than everyone after him shuffling
        // into the wrong positions), and only that gap is filled.
        var seenStarters = Set<UUID>()
        var slots: [UUID?] = tactics.startingXI.prefix(11).map { id in
            guard playerIds.contains(id), !unavailableIds.contains(id), seenStarters.insert(id).inserted else { return nil }
            return id
        }
        tactics.substitutes.removeAll { !playerIds.contains($0) || unavailableIds.contains($0) }
        var seenSubs = seenStarters
        tactics.substitutes = tactics.substitutes.filter { seenSubs.insert($0).inserted }
        if tactics.substitutes.count > 7 {
            tactics.substitutes = Array(tactics.substitutes.prefix(7))
        }

        if slots.compactMap({ $0 }).count < 6 {
            // Nothing much left of the side (a new club, or an old save): pick afresh.
            autoPickStartingXI()
            return
        }
        while slots.count < 11 { slots.append(nil) }
        if slots.contains(where: { $0 == nil }) {
            fillVacantSlots(&slots)
        }
        tactics.startingXI = slots.compactMap { $0 }
        if tactics.startingXI.count < 11 {
            autoPickStartingXI()
            return
        }

        // Repair captain and set-piece duties that point at players who are no
        // longer in the starting XI (sold, injured, suspended, or benched).
        let xiIds = Set(tactics.startingXI)
        let starters = players.filter { xiIds.contains($0.id) }
        func bestStarter(_ attribute: (Player) -> Int) -> UUID? {
            starters.max { attribute($0) < attribute($1) }?.id
        }
        if let captain = tactics.captain, xiIds.contains(captain) {
            // Keep the current captain.
        } else {
            tactics.captain = bestStarter { $0.attributes.leadership }
        }
        if let taker = tactics.penaltyTaker, xiIds.contains(taker) {
            // Keep the current penalty taker.
        } else {
            tactics.penaltyTaker = bestStarter { $0.attributes.penalties }
        }
        if let taker = tactics.freeKickTaker, xiIds.contains(taker) {
            // Keep the current free-kick taker.
        } else {
            tactics.freeKickTaker = bestStarter { $0.attributes.freeKicks }
        }
        if let taker = tactics.cornerTaker, xiIds.contains(taker) {
            // Keep the current corner taker.
        } else {
            tactics.cornerTaker = bestStarter { $0.attributes.crossing }
        }
        
        // Top up the bench from available reserves without disturbing the starting XI.
        let availableReserves = players.filter {
            $0.isAvailable && !xiIds.contains($0.id) && !tactics.substitutes.contains($0.id)
        }
        let needed = max(0, 7 - tactics.substitutes.count)
        if needed > 0 {
            let additions = availableReserves
                .sorted { $0.overall > $1.overall }
                .prefix(needed)
                .map { $0.id }
            tactics.substitutes.append(contentsOf: additions)
        }
    }

    // MARK: - Codable (tolerant of saves predating the youth academy)

    private enum CodingKeys: String, CodingKey {
        case id, name, shortName, stadium, stadiumCapacity, city
        case primaryColor, secondaryColor, leagueTier, reputation, isUserClub
        case players, manager, academyProspects, finances, staff
        case trainingFacilityLevel, youthAcademyLevel, medicalFacilityLevel
        case tactics, seasonResults
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shortName = try c.decode(String.self, forKey: .shortName)
        stadium = try c.decode(String.self, forKey: .stadium)
        stadiumCapacity = try c.decode(Int.self, forKey: .stadiumCapacity)
        city = try c.decode(String.self, forKey: .city)
        primaryColor = try c.decode(String.self, forKey: .primaryColor)
        secondaryColor = try c.decode(String.self, forKey: .secondaryColor)
        leagueTier = try c.decode(LeagueTier.self, forKey: .leagueTier)
        reputation = try c.decode(Int.self, forKey: .reputation)
        isUserClub = try c.decode(Bool.self, forKey: .isUserClub)
        players = try c.decode([Player].self, forKey: .players)
        manager = try c.decode(String.self, forKey: .manager)
        academyProspects = try c.decodeIfPresent([Player].self, forKey: .academyProspects) ?? []
        finances = try c.decode(ClubFinances.self, forKey: .finances)
        staff = try c.decode([StaffMember].self, forKey: .staff)
        trainingFacilityLevel = try c.decode(Int.self, forKey: .trainingFacilityLevel)
        youthAcademyLevel = try c.decode(Int.self, forKey: .youthAcademyLevel)
        medicalFacilityLevel = try c.decode(Int.self, forKey: .medicalFacilityLevel)
        tactics = try c.decode(Tactics.self, forKey: .tactics)
        seasonResults = try c.decode([MatchResult].self, forKey: .seasonResults)

        // Repair stale derived values from older saves: the gate model and wage
        // headroom must reflect the club's real stadium and current squad.
        finances.stadiumCapacity = stadiumCapacity
        finances.currentWageBill = totalWeeklyWageBill
        // Older saves get the larger wage budgets too.
        ensureWageHeadroom()
    }
}

// MARK: - Club Finances

public struct ClubFinances: Codable, Hashable {
    public var transferBudget: Int
    public var wageBudget: Int          // Max allowed weekly wage
    public var currentWageBill: Int      // Actual current weekly wage
    public var balance: Int              // Total bank balance
    public var tvIncome: Int             // Annualized TV broadcast rights
    public var matchdayIncome: Int       // Estimated average gate receipts per home match
    public var sponsorshipIncome: Int    // Annualized sponsorship agreements
    public var merchandiseIncome: Int    // Annualized merchandise sales

    // MARK: Ticket / gate detail
    /// Average ticket price in pounds (scales with club stature).
    public var averageTicketPrice: Int
    /// Typical home attendance as a fraction of capacity (0.4-1.0).
    public var averageAttendancePct: Double
    /// Stadium capacity used to model gate receipts.
    public var stadiumCapacity: Int

    public init(
        transferBudget: Int,
        wageBudget: Int,
        currentWageBill: Int,
        balance: Int,
        tvIncome: Int,
        matchdayIncome: Int,
        sponsorshipIncome: Int,
        merchandiseIncome: Int,
        averageTicketPrice: Int = 30,
        averageAttendancePct: Double = 0.8,
        stadiumCapacity: Int = 20_000
    ) {
        self.transferBudget = transferBudget
        self.wageBudget = wageBudget
        self.currentWageBill = currentWageBill
        self.balance = balance
        self.tvIncome = tvIncome
        self.matchdayIncome = matchdayIncome
        self.sponsorshipIncome = sponsorshipIncome
        self.merchandiseIncome = merchandiseIncome
        self.averageTicketPrice = averageTicketPrice
        self.averageAttendancePct = averageAttendancePct
        self.stadiumCapacity = stadiumCapacity
    }

    public var weeklyWageSurplus: Int {
        return wageBudget - currentWageBill
    }

    public var isHealthy: Bool {
        return balance >= 0
    }

    public var weeklySponsorshipShare: Int {
        return sponsorshipIncome / 52
    }

    public var weeklyTvShare: Int {
        return tvIncome / 52
    }

    public var weeklyMerchandiseShare: Int {
        return merchandiseIncome / 52
    }

    /// Expected attendance for a home fixture, influenced by the club's pull
    /// (attendance %) and the calibre of the opposition.
    public func expectedAttendance(opponentReputation: Int) -> Int {
        // A marquee opponent draws a fuller house; a minnow leaves empty seats.
        let glamour = Double(opponentReputation) / 80.0
        let pct = min(1.0, max(0.35, averageAttendancePct * (0.88 + glamour * 0.24)))
        return Int(Double(stadiumCapacity) * pct)
    }

    /// Gate receipts for a single home match (tickets + matchday hospitality).
    /// `matchdayIncome` is the club's calibrated average per home game, so the
    /// gate swings around it with the size of the crowd the visitors draw.
    /// (Pricing every seat from capacity used to pay clubs two to four times
    /// their real matchday income, and balances ballooned season after season.)
    public func matchdayRevenue(opponentReputation: Int) -> Int {
        let typical = Double(max(1, expectedAttendance(opponentReputation: 60)))
        let crowd = Double(expectedAttendance(opponentReputation: opponentReputation))
        return Int(Double(matchdayIncome) * crowd / typical)
    }

    /// Processes weekly financial ledger: payroll debits and steady
    /// sponsorship/TV/merchandise credits, plus a specific home-game gate.
    public mutating func processWeeklyCashFlow(
        isHomeMatchThisWeek: Bool = false,
        gateReceipts: Int = 0
    ) {
        var weeklyIncome = weeklySponsorshipShare + weeklyTvShare + weeklyMerchandiseShare
        if isHomeMatchThisWeek {
            weeklyIncome += (gateReceipts > 0 ? gateReceipts : matchdayIncome)
        }
        let weeklyExpense = currentWageBill + weeklyOperatingCosts
        balance += (weeklyIncome - weeklyExpense)
    }

    /// Non-wage running costs: staff, stadium operations, travel, academy,
    /// administration. Roughly a third of turnover, as at real clubs; without
    /// it every club banked huge profits and balances inflated without limit.
    public var weeklyOperatingCosts: Int {
        let annualTurnover = tvIncome + sponsorshipIncome + merchandiseIncome + matchdayIncome * 19
        return Int(Double(annualTurnover) * 0.33 / 52.0)
    }

    /// Treasury top-up between seasons: boards reinvest a share of the balance
    /// into a fresh transfer kitty sized by club stature.
    /// New-season transfer kitty: a quarter of central and commercial income
    /// or 30% of cash in hand, whichever is larger, but never more than the
    /// club actually has. (This used to top the bank balance up for free
    /// every summer, inflating the economy and bailing out indebted clubs.)
    public mutating func rolloverForNewSeason(reputation: Int) {
        let fromIncome = Int(Double(tvIncome + sponsorshipIncome) * 0.25)
        let fromCash = max(0, balance) * 3 / 10
        let kitty = max(transferBudget, fromIncome, fromCash)
        transferBudget = max(0, min(kitty, max(0, balance)))
    }

    // MARK: - Realistic baseline from club stature
    //
    // The shipped dataset has no financial metadata, so we derive believable
    // money from a club's reputation (which itself is currently flat, so tier
    // and stadium capacity carry most of the signal). Values are tuned to feel
    // like the modern European game.

    /// Rough annual turnover bucket for a club of this stature.
    public static func annualTurnover(reputation: Int, tier: LeagueTier, capacity: Int) -> Int {
        let countryFactor: Double = {
            switch tier.country {
            case .england, .spain, .italy, .germany: return 1.0
            case .france: return 0.75
            case .portugal, .netherlands, .turkey, .scotland, .belgium: return 0.5
            default: return 0.35
            }
        }()
        let levelScale: Double = {
            switch tier.level {
            case 1: return 1.0
            case 2: return 0.2
            case 3: return 0.06
            default: return 0.02
            }
        }()
        // Reputation nudges the top-flight elite up; capacity adds matchday muscle.
        let repFactor = max(0.35, min(1.9, Double(reputation) / 70.0))
        let capacityFactor = max(0.5, min(1.6, Double(capacity) / 40_000.0))
        let base = 150_000_000.0 * countryFactor * levelScale * repFactor * capacityFactor
        return max(400_000, Int(base))
    }

    public static func baseTransferBudget(reputation: Int, tier: LeagueTier, capacity: Int) -> Int {
        let turnover = annualTurnover(reputation: reputation, tier: tier, capacity: capacity)
        // Boards typically release roughly a quarter of turnover for transfers.
        return max(150_000, Int(Double(turnover) * 0.25))
    }

    public static func defaultFor(tier: LeagueTier, reputation: Int = 70, capacity: Int = 25_000) -> ClubFinances {
        let turnover = annualTurnover(reputation: reputation, tier: tier, capacity: capacity)

        // Split turnover into plausible revenue lines.
        let tv = Int(Double(turnover) * 0.42)
        let commercial = Int(Double(turnover) * 0.28)
        let merchandise = Int(Double(turnover) * 0.10)
        // Matchday is modelled per-game below; approximate annual here for display.
        let matchdayAnnual = Int(Double(turnover) * 0.20)

        // Ticket pricing and attendance scale with stature.
        let rep = max(20, min(95, reputation))
        // Top-flight prices run from about £20 to £60; below that, roughly £15
        // to £35, in line with real ticketing.
        let ticketPrice = tier.level == 1
            ? max(20, Int(20.0 + Double(rep - 20) * 0.55))
            : max(12, Int(12.0 + Double(rep - 20) * 0.4))
        let attendancePct = min(0.98, 0.55 + Double(rep - 20) / 120.0)
        let gamesPerSeason = 19
        let perGameMatchday = max(120_000, matchdayAnnual / gamesPerSeason)

        // Wage budget is roughly 55% of turnover; transfer budget a third of it.
        let wageBudgetAnnual = Int(Double(turnover) * 0.70)
        let wageBudget = max(6_000, wageBudgetAnnual / 52)
        let currentWageBill = Int(Double(wageBudget) * 0.72)
        let transferBudget = baseTransferBudget(reputation: reputation, tier: tier, capacity: capacity)
        let balance = Int(Double(turnover) * 0.5)

        return ClubFinances(
            transferBudget: transferBudget,
            wageBudget: wageBudget,
            currentWageBill: currentWageBill,
            balance: balance,
            tvIncome: tv,
            matchdayIncome: perGameMatchday,
            sponsorshipIncome: commercial,
            merchandiseIncome: merchandise,
            averageTicketPrice: ticketPrice,
            averageAttendancePct: attendancePct,
            stadiumCapacity: capacity
        )
    }

    /// Tolerant decode so saves from earlier versions (no ticket fields) still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transferBudget = try c.decode(Int.self, forKey: .transferBudget)
        wageBudget = try c.decode(Int.self, forKey: .wageBudget)
        currentWageBill = try c.decode(Int.self, forKey: .currentWageBill)
        balance = try c.decode(Int.self, forKey: .balance)
        tvIncome = try c.decode(Int.self, forKey: .tvIncome)
        matchdayIncome = try c.decode(Int.self, forKey: .matchdayIncome)
        sponsorshipIncome = try c.decode(Int.self, forKey: .sponsorshipIncome)
        merchandiseIncome = try c.decode(Int.self, forKey: .merchandiseIncome)
        averageTicketPrice = try c.decodeIfPresent(Int.self, forKey: .averageTicketPrice) ?? 30
        averageAttendancePct = try c.decodeIfPresent(Double.self, forKey: .averageAttendancePct) ?? 0.8
        stadiumCapacity = try c.decodeIfPresent(Int.self, forKey: .stadiumCapacity) ?? 20_000
    }
}

// MARK: - Staff Member

/// Someone the club could appoint to its backroom staff.
public struct StaffCandidate: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let role: StaffRole
    public let quality: Int
    public let wage: Int
    public let fee: Int
    public let age: Int
    public let specialty: String

    static func specialties(for role: StaffRole) -> [String] {
        switch role {
        case .assistantManager: return ["Tactician", "Man-manager", "Motivator", "Opposition analyst", "Disciplinarian", "Former club captain"]
        case .coach: return ["Attacking coach", "Defensive coach", "Set-piece specialist", "Goalkeeping coach", "Fitness coach", "Technical coach"]
        case .scout: return ["Domestic leagues", "South America", "Youth talent", "Data analyst", "Lower leagues", "Europe-wide network"]
        case .physio: return ["Injury prevention", "Rehabilitation", "Sports scientist", "Nutritionist", "Recovery specialist"]
        case .youthCoach: return ["Academy builder", "Talent spotter", "Coach educator", "Local schools network", "Pathway planner"]
        }
    }
}

public struct StaffMember: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var role: StaffRole
    public var quality: Int     // 1 to 5 Stars
    public var wage: Int        // Weekly wage in GBP
    
    public init(
        id: UUID = UUID(),
        name: String,
        role: StaffRole,
        quality: Int,
        wage: Int
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.quality = max(1, min(5, quality))
        self.wage = wage
    }
    
    public static func defaultStaffFor(tier: LeagueTier) -> [StaffMember] {
        let baseQuality: Int
        let baseWage: Int
        
        switch tier.level {
        case 1: baseQuality = 4; baseWage = 7_000
        case 2: baseQuality = 3; baseWage = 3_000
        case 3: baseQuality = 2; baseWage = 1_200
        default: baseQuality = 2; baseWage = 600
        }
        
        // Every club gets its own people, of varying ability.
        func member(_ role: StaffRole, _ wageOffset: Int) -> StaffMember {
            let quality = max(1, min(5, baseQuality + Int.random(in: -1...1)))
            let wage = max(200, baseWage - wageOffset + (quality - baseQuality) * baseWage / 5)
            return StaffMember(name: Club.randomStaffName(role: role, country: tier.country), role: role,
                               quality: quality, wage: wage)
        }
        return [
            member(.assistantManager, 0),
            member(.coach, 100),
            member(.scout, 200),
            member(.physio, 150),
            member(.youthCoach, 200)
        ]
    }
}

// MARK: - Tactics

public struct Tactics: Codable, Hashable {
    public var formation: FormationPreset
    public var mentality: Mentality
    public var pressing: PressingIntensity
    public var tempo: Tempo
    public var width: Width
    public var passingStyle: PassingStyle
    
    public var startingXI: [UUID]     // Array of 11 Player IDs
    public var substitutes: [UUID]    // Array of up to 7 Player IDs
    
    // Set Piece Taker Assignments
    public var cornerTaker: UUID?
    public var freeKickTaker: UUID?
    public var penaltyTaker: UUID?
    public var captain: UUID?
    
    public init(
        formation: FormationPreset = .f442,
        mentality: Mentality = .balanced,
        pressing: PressingIntensity = .medium,
        tempo: Tempo = .normal,
        width: Width = .normal,
        passingStyle: PassingStyle = .mixed,
        startingXI: [UUID] = [],
        substitutes: [UUID] = [],
        cornerTaker: UUID? = nil,
        freeKickTaker: UUID? = nil,
        penaltyTaker: UUID? = nil,
        captain: UUID? = nil
    ) {
        self.formation = formation
        self.mentality = mentality
        self.pressing = pressing
        self.tempo = tempo
        self.width = width
        self.passingStyle = passingStyle
        self.startingXI = startingXI
        self.substitutes = substitutes
        self.cornerTaker = cornerTaker
        self.freeKickTaker = freeKickTaker
        self.penaltyTaker = penaltyTaker
        self.captain = captain
    }
    
    public static var defaultTactics: Tactics {
        return Tactics(
            formation: .f442,
            mentality: .balanced,
            pressing: .medium,
            tempo: .normal,
            width: .normal,
            passingStyle: .mixed
        )
    }
}

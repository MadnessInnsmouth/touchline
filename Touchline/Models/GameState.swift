//
//  GameState.swift
//  Touchline
//
//  Created for Touchline - iOS Football Manager Game.
//  Root @Observable state container managing world simulation, calendar advancement,
//  match simulation, AI club activities, news feed, and UI navigation.
//

import Foundation
import Observation

// MARK: - News Item Model

public struct NewsItem: Codable, Identifiable, Hashable {
    public let id: UUID
    public var headline: String
    public var body: String
    public var date: String
    public var category: NewsCategory
    /// Who the correspondence is from (e.g. "The Board", "Agent", "Club Secretary").
    public var sender: String
    /// Whether the manager has opened this message.
    public var isRead: Bool
    /// When set, this message is an actionable transfer negotiation and links to
    /// the referenced offer so the inbox can present Accept / Reject / Counter.
    public var transferOfferId: UUID?

    /// Sender for stories about the wider football world (other clubs'
    /// trophies, promotions, awards). They appear in News, not the inbox.
    public static let newsDesk = "News Desk"
    private static let newsOnlySenders: Set<String> = ["Transfer Desk", newsDesk, "Football News", "World Football Awards"]

    /// Whether this belongs in the manager's inbox. Stories about the rest of
    /// the football world (big-money moves between other clubs, who won
    /// which league or cup, promotions, awards) are news only.
    public var isInboxMessage: Bool {
        if Self.newsOnlySenders.contains(sender) { return false }
        // Older saves filed world stories under the default sender.
        if sender == "Club News Desk" && [.award, .promotion, .relegation].contains(category) { return false }
        return true
    }

    public init(
        id: UUID = UUID(),
        headline: String,
        body: String,
        date: String,
        category: NewsCategory,
        sender: String = "Club News Desk",
        isRead: Bool = false,
        transferOfferId: UUID? = nil
    ) {
        self.id = id
        self.headline = headline
        self.body = body
        self.date = date
        self.category = category
        self.sender = sender
        self.isRead = isRead
        self.transferOfferId = transferOfferId
    }

    private enum CodingKeys: String, CodingKey {
        case id, headline, body, date, category, sender, isRead, transferOfferId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        headline = try c.decode(String.self, forKey: .headline)
        body = try c.decode(String.self, forKey: .body)
        date = try c.decode(String.self, forKey: .date)
        category = try c.decode(NewsCategory.self, forKey: .category)
        sender = try c.decodeIfPresent(String.self, forKey: .sender) ?? "Club News Desk"
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        transferOfferId = try c.decodeIfPresent(UUID.self, forKey: .transferOfferId)
    }
}

// MARK: - Contract Renewal

/// Outcome of a contract-renewal offer. `demandedWage` is populated when the
/// player turns the offer down, so the UI can show what it would take to agree.
public struct ContractRenewalResult: Equatable {
    public let accepted: Bool
    public let demandedWage: Int?
    public let message: String

    public init(accepted: Bool, demandedWage: Int? = nil, message: String) {
        self.accepted = accepted
        self.demandedWage = demandedWage
        self.message = message
    }
}

// MARK: - Game State Class

@Observable
public final class GameState: Codable {
    
    // Core Game Setup
    public var gameMode: GameMode
    public var clubs: [Club]
    public var leagues: [League]
    public var season: Season
    public var userClubId: UUID?
    
    // Global Market & History
    public var freeAgents: [Player]
    public var transferHistory: [TransferRecord]
    public var pendingTransferOffers: [TransferOffer]
    public var news: [NewsItem]
    
    // Navigation & Live Match Context
    public var currentScreen: AppScreen
    public var isMatchInProgress: Bool
    public var activeMatchFixtureId: UUID?
    public var negotiationTargetPlayerId: UUID?
    
    // Preferences
    public var soundEnabled: Bool
    /// In-match user preferences (speed, half-time stop, auto-substitution rules).
    public var matchSettings: MatchSettings
    
    // Managerial Career
    public var manager: ManagerProfile
    public var jobOffers: [JobOffer]
    // Ownership Career. This remains independent of the manager profile so an
    // owner never becomes the person selecting the XI.
    public var owner: OwnerProfile
    /// Ensures a manager can run only one dedicated training session per week.
    public var lastTrainingWeek: Int?
    /// Board expectations and job security for the manager career.
    public var jobSecurity: JobSecurity
    /// This week's team talk, applied once before/during matchday preparation.
    public var teamTalk: TeamTalkStyle?
    public var teamTalkAppliedWeek: Int?
    
    // European club competitions (Champions League, Europa League, Conference League)
    public var europeanCompetitions: [EuropeanCompetitionState]
    /// European matchweek pointer; advances alongside the domestic calendar.
    public var europeanMatchweek: Int

    // International management (national teams + tournaments)
    public var nationalTeams: [NationalTeam]
    public var internationalTournaments: [InternationalTournament.State]
    /// The national team the user is currently managing, if any.
    public var managedNationalTeamId: String?

    /// True once the user has actually launched a career (founded or taken over
    /// a club). A freshly bootstrapped world is not a career, so it is never
    /// written over the autosave and the menu never offers to "continue" it.
    public var hasStartedCareer: Bool

    /// This season's national knockout cups, one per country.
    public var domesticCups: [DomesticCupState]

    /// Real derbies and rivalries between clubs.
    public var rivalries: [Rivalry]

    /// Clubs that earned European places last season, keyed by competition
    /// raw value. Consumed when the next season's competitions are drawn.
    public var europeanQualifiers: [String: [UUID]]

    /// The user's most recent completed season, shown until the next begins.
    public var lastSeasonReview: SeasonReview?
    /// Champions, awards and Hall of Fame across the career.
    public var history: WorldHistory
    /// Players the manager is tracking in the transfer market.
    public var shortlist: [UUID]
    /// The usual lineup, kept while a one-off lineup is used for the next match.
    public var matchOnlyLineupBackup: Tactics?
    /// A live match stopped at half-time. Not saved: leaving mid-match restarts it.
    public var liveMatch: LiveMatchSession?
    public var pendingWinBonusRequest: Bool
    public var winBonusAskedSeason: String
    public var winBonusPercent: Int
    public var pendingRecordMoment: ClubRecordMoment?
    public var clubRecords: ClubRecords
    public var dismissedTips: [String]
    public var achievements: [String: String]
    public var pendingOwnerDecision: OwnerDecision?
    public var answeredPressFixtureIds: [UUID]

    /// Season-to-date income and spending at the user's club.
    public var seasonLedger: FinanceLedger?
    /// Points deducted this season (administration), by club.
    public var pointsDeductions: [UUID: Int]
    /// A signing the owner's manager wants funded.
    public var pendingManagerRequest: ManagerRequest?
    /// A consortium's offer to buy the owner's club.
    public var pendingTakeover: TakeoverOffer?
    /// Sponsors waiting for the owner's answer.
    public var pendingSponsorOffers: [SponsorOffer] = []
    /// Weeks before the sponsorship agency can be briefed again.
    public var sponsorAgencyCooldown: Int = 0
    /// The owner has sold the club and is choosing which club to buy next.
    public var awaitingClubPurchase: Bool = false
    /// Transfer fees still to be paid: later installments and conditional
    /// add-ons, settled as their dates come round.
    public var transferInstallments: [TransferInstallment] = []
    /// Awards nights still to come (the Ballon d'Or, the Team of the Year).
    public var pendingCeremonies: [AwardCeremony] = []
    /// An awards night just held, waiting to be shown on screen.
    public var ceremonyToShow: AwardCeremony? = nil
    /// The end-of-season review is on screen (from Start New Season).
    public var showingSeasonReview = false
    /// The eleven, formation and approach the user picked for his nation.
    public var nationalTactics: Tactics? = nil
    /// Where the manager was before opening a player's profile screen.
    var screenBeforeProfile: AppScreen? = nil
    /// Titles and promotions already decided this season (so each is
    /// announced once).
    public var clinchedHonours: [String] = []
    /// A trophy or promotion for the user's club, waiting to be celebrated.
    public var celebrationToShow: Celebration? = nil
    /// The season's accounts at the last monthly finance report, so the
    /// next report can show the month's movements.
    public var lastFinanceSnapshot: FinanceLedger? = nil
    /// The last international match the user managed.
    public var lastInternationalReport: InternationalReport? = nil
    /// Rounds of contract-renewal talks with each of the user's players this
    /// session. A player tires of haggling after a few.
    var renewalRounds: [UUID: Int] = [:]
    /// Each player's latest counter in renewal talks this session.
    var renewalCounters: [UUID: Int] = [:]
    
    // MARK: - Initializer
    
    public init(
        gameMode: GameMode = .createClub,
        clubs: [Club] = [],
        leagues: [League] = [],
        season: Season = Season(),
        userClubId: UUID? = nil,
        freeAgents: [Player] = [],
        transferHistory: [TransferRecord] = [],
        pendingTransferOffers: [TransferOffer] = [],
        news: [NewsItem] = [],
        currentScreen: AppScreen = .mainMenu,
        isMatchInProgress: Bool = false,
        activeMatchFixtureId: UUID? = nil,
        negotiationTargetPlayerId: UUID? = nil,
        soundEnabled: Bool = true,
        matchSettings: MatchSettings = MatchSettings(),
        manager: ManagerProfile = ManagerProfile(),
        jobOffers: [JobOffer] = [],
        owner: OwnerProfile = OwnerProfile(),
        lastTrainingWeek: Int? = nil,
        jobSecurity: JobSecurity = JobSecurity(),
        teamTalk: TeamTalkStyle? = nil,
        teamTalkAppliedWeek: Int? = nil,
        europeanCompetitions: [EuropeanCompetitionState] = [],
        europeanMatchweek: Int = 0,
        nationalTeams: [NationalTeam] = [],
        internationalTournaments: [InternationalTournament.State] = [],
        managedNationalTeamId: String? = nil,
        hasStartedCareer: Bool = false,
        domesticCups: [DomesticCupState] = [],
        rivalries: [Rivalry] = [],
        europeanQualifiers: [String: [UUID]] = [:],
        lastSeasonReview: SeasonReview? = nil,
        history: WorldHistory = WorldHistory(),
        shortlist: [UUID] = [],
        matchOnlyLineupBackup: Tactics? = nil,
        pendingWinBonusRequest: Bool = false,
        winBonusAskedSeason: String = "",
        winBonusPercent: Int = 0,
        pendingRecordMoment: ClubRecordMoment? = nil,
        clubRecords: ClubRecords = ClubRecords(),
        dismissedTips: [String] = [],
        achievements: [String: String] = [:],
        pendingOwnerDecision: OwnerDecision? = nil,
        answeredPressFixtureIds: [UUID] = [],
        seasonLedger: FinanceLedger? = nil,
        pointsDeductions: [UUID: Int] = [:],
        pendingManagerRequest: ManagerRequest? = nil,
        pendingTakeover: TakeoverOffer? = nil
    ) {
        self.gameMode = gameMode
        self.clubs = clubs
        self.leagues = leagues
        self.season = season
        self.userClubId = userClubId
        self.freeAgents = freeAgents
        self.transferHistory = transferHistory
        self.pendingTransferOffers = pendingTransferOffers
        self.news = news
        self.currentScreen = currentScreen
        self.isMatchInProgress = isMatchInProgress
        self.activeMatchFixtureId = activeMatchFixtureId
        self.negotiationTargetPlayerId = negotiationTargetPlayerId
        self.soundEnabled = soundEnabled
        self.matchSettings = matchSettings
        self.manager = manager
        self.jobOffers = jobOffers
        self.owner = owner
        self.lastTrainingWeek = lastTrainingWeek
        self.jobSecurity = jobSecurity
        self.teamTalk = teamTalk
        self.teamTalkAppliedWeek = teamTalkAppliedWeek
        self.europeanCompetitions = europeanCompetitions
        self.europeanMatchweek = europeanMatchweek
        self.nationalTeams = nationalTeams
        self.internationalTournaments = internationalTournaments
        self.managedNationalTeamId = managedNationalTeamId
        self.hasStartedCareer = hasStartedCareer
        self.domesticCups = domesticCups
        self.rivalries = rivalries
        self.europeanQualifiers = europeanQualifiers
        self.lastSeasonReview = lastSeasonReview
        self.history = history
        self.shortlist = shortlist
        self.matchOnlyLineupBackup = matchOnlyLineupBackup
        self.pendingWinBonusRequest = pendingWinBonusRequest
        self.winBonusAskedSeason = winBonusAskedSeason
        self.winBonusPercent = winBonusPercent
        self.pendingRecordMoment = pendingRecordMoment
        self.clubRecords = clubRecords
        self.dismissedTips = dismissedTips
        self.achievements = achievements
        self.pendingOwnerDecision = pendingOwnerDecision
        self.answeredPressFixtureIds = answeredPressFixtureIds
        self.seasonLedger = seasonLedger
        self.pointsDeductions = pointsDeductions
        self.pendingManagerRequest = pendingManagerRequest
        self.pendingTakeover = pendingTakeover
    }

    // MARK: - World Bootstrap & Career Lifecycle

    /// Builds a brand-new world from the bundled data: every league, a fresh
    /// fixture list, European and international competitions, free agents and
    /// youth academies. No career is attached yet.
    public static func makeFreshWorld() -> GameState {
        let (clubs, leagues) = DataLoader.loadAllData()

        var allFixtures: [Fixture] = []
        for league in leagues {
            allFixtures.append(contentsOf: FixtureGenerator.generateLeagueSeason(
                clubIds: league.clubIds,
                competitionName: league.name,
                startDateString: "2026-08-08",
                rounds: league.tier.seasonRounds(clubCount: league.clubIds.count)
            ))
        }

        let initialSeason = Season(
            year: "2026-27",
            currentWeek: 1,
            currentPhase: .preseason,
            fixtures: allFixtures,
            currentDate: "2026-08-01"
        )

        let state = GameState(
            gameMode: .createClub,
            clubs: clubs,
            leagues: leagues,
            season: initialSeason,
            currentScreen: .mainMenu,
            europeanCompetitions: EuropeanCompetitionBuilder.build(from: clubs),
            nationalTeams: DataLoader.loadNationalTeams()
        )
        state.seedFreeAgents()
        state.seedAcademies()
        state.seedInternationalTournaments()
        state.seedDomesticCups()
        // Start every club at a realistic wage-to-turnover ratio.
        // Facilities by stature: the elite have the best training grounds,
        // academies and medical departments.
        for idx in state.clubs.indices {
            let rep = state.clubs[idx].reputation
            let base = max(1, min(5, (rep - 30) / 14 + 1))
            // AI academies top out at level 3 and training grounds at 4: each
            // academy level raises every prospect's ceiling, and level-5
            // academies at all the big clubs flooded the world with stars.
            // The user can still build to level 5 for an edge.
            // A level set in a datapack (anything but the default 2) is kept.
            if state.clubs[idx].trainingFacilityLevel == 2 {
                state.clubs[idx].trainingFacilityLevel = max(1, min(4, base + Int.random(in: -1...0)))
            }
            if state.clubs[idx].youthAcademyLevel == 2 {
                state.clubs[idx].youthAcademyLevel = max(1, min(3, base + Int.random(in: -1...0)))
            }
            if state.clubs[idx].medicalFacilityLevel == 2 {
                state.clubs[idx].medicalFacilityLevel = max(1, min(5, base + Int.random(in: -1...0)))
            }
        }
        for idx in state.clubs.indices {
            state.applyWageInflation(clubIdx: idx, maximumRise: 3.0, targetShare: 0.55)
            state.clubs[idx].ensureWageHeadroom()
        }
        state.rivalries = DataLoader.loadRivalries(for: clubs)
        state.payEuropeanParticipationFees()
        return state
    }

    /// Replaces every piece of world and career state with `other`'s, in place.
    /// The SwiftUI environment holds this exact instance, so loading a save or
    /// starting a new career must mutate it rather than swap in a new object.
    /// User preferences (sound, match settings) are kept from this instance.
    public func replaceContents(with other: GameState, keepPreferences: Bool = true) {
        gameMode = other.gameMode
        clubs = other.clubs
        leagues = other.leagues
        season = other.season
        userClubId = other.userClubId
        freeAgents = other.freeAgents
        transferHistory = other.transferHistory
        pendingTransferOffers = other.pendingTransferOffers
        news = other.news
        currentScreen = other.currentScreen
        isMatchInProgress = other.isMatchInProgress
        activeMatchFixtureId = other.activeMatchFixtureId
        negotiationTargetPlayerId = other.negotiationTargetPlayerId
        if !keepPreferences {
            soundEnabled = other.soundEnabled
            matchSettings = other.matchSettings
        }
        manager = other.manager
        jobOffers = other.jobOffers
        owner = other.owner
        lastTrainingWeek = other.lastTrainingWeek
        jobSecurity = other.jobSecurity
        teamTalk = other.teamTalk
        teamTalkAppliedWeek = other.teamTalkAppliedWeek
        europeanCompetitions = other.europeanCompetitions
        europeanMatchweek = other.europeanMatchweek
        nationalTeams = other.nationalTeams
        internationalTournaments = other.internationalTournaments
        managedNationalTeamId = other.managedNationalTeamId
        hasStartedCareer = other.hasStartedCareer
        domesticCups = other.domesticCups
        rivalries = other.rivalries
        europeanQualifiers = other.europeanQualifiers
        lastSeasonReview = other.lastSeasonReview
        history = other.history
        shortlist = other.shortlist
        matchOnlyLineupBackup = other.matchOnlyLineupBackup
        pendingWinBonusRequest = other.pendingWinBonusRequest
        winBonusAskedSeason = other.winBonusAskedSeason
        winBonusPercent = other.winBonusPercent
        pendingRecordMoment = other.pendingRecordMoment
        clubRecords = other.clubRecords
        dismissedTips = other.dismissedTips
        achievements = other.achievements
        pendingOwnerDecision = other.pendingOwnerDecision
        answeredPressFixtureIds = other.answeredPressFixtureIds
        seasonLedger = other.seasonLedger
        pointsDeductions = other.pointsDeductions
        pendingManagerRequest = other.pendingManagerRequest
        pendingTakeover = other.pendingTakeover
        pendingSponsorOffers = other.pendingSponsorOffers
        sponsorAgencyCooldown = other.sponsorAgencyCooldown
        awaitingClubPurchase = other.awaitingClubPurchase
        transferInstallments = other.transferInstallments
        pendingCeremonies = other.pendingCeremonies
        ceremonyToShow = other.ceremonyToShow
        showingSeasonReview = false
        nationalTactics = other.nationalTactics
        clinchedHonours = other.clinchedHonours
        celebrationToShow = other.celebrationToShow
        lastFinanceSnapshot = other.lastFinanceSnapshot
        lastInternationalReport = other.lastInternationalReport
        renewalRounds = [:]
    }

    /// An independent copy of the whole state. Every stored property is a value
    /// type, so this is cheap (copy-on-write) and the copy can be encoded on a
    /// background queue while the live state keeps changing on the main thread.
    public func makeSnapshot() -> GameState {
        let snapshot = GameState(
            gameMode: gameMode,
            clubs: clubs,
            leagues: leagues,
            season: season,
            userClubId: userClubId,
            freeAgents: freeAgents,
            transferHistory: transferHistory,
            pendingTransferOffers: pendingTransferOffers,
            news: news,
            currentScreen: currentScreen,
            isMatchInProgress: isMatchInProgress,
            activeMatchFixtureId: activeMatchFixtureId,
            negotiationTargetPlayerId: negotiationTargetPlayerId,
            soundEnabled: soundEnabled,
            matchSettings: matchSettings,
            manager: manager,
            jobOffers: jobOffers,
            owner: owner,
            lastTrainingWeek: lastTrainingWeek,
            jobSecurity: jobSecurity,
            teamTalk: teamTalk,
            teamTalkAppliedWeek: teamTalkAppliedWeek,
            europeanCompetitions: europeanCompetitions,
            europeanMatchweek: europeanMatchweek,
            nationalTeams: nationalTeams,
            internationalTournaments: internationalTournaments,
            managedNationalTeamId: managedNationalTeamId,
            hasStartedCareer: hasStartedCareer,
            domesticCups: domesticCups,
            rivalries: rivalries,
            europeanQualifiers: europeanQualifiers,
            lastSeasonReview: lastSeasonReview,
            history: history,
            shortlist: shortlist,
            matchOnlyLineupBackup: matchOnlyLineupBackup,
            pendingWinBonusRequest: pendingWinBonusRequest,
            winBonusAskedSeason: winBonusAskedSeason,
            winBonusPercent: winBonusPercent,
            pendingRecordMoment: pendingRecordMoment,
            clubRecords: clubRecords,
            dismissedTips: dismissedTips,
            achievements: achievements,
            pendingOwnerDecision: pendingOwnerDecision,
            answeredPressFixtureIds: answeredPressFixtureIds,
            seasonLedger: seasonLedger,
            pointsDeductions: pointsDeductions,
            pendingManagerRequest: pendingManagerRequest,
            pendingTakeover: pendingTakeover
        )
        snapshot.pendingSponsorOffers = pendingSponsorOffers
        snapshot.sponsorAgencyCooldown = sponsorAgencyCooldown
        snapshot.awaitingClubPurchase = awaitingClubPurchase
        snapshot.transferInstallments = transferInstallments
        snapshot.pendingCeremonies = pendingCeremonies
        snapshot.ceremonyToShow = ceremonyToShow
        snapshot.nationalTactics = nationalTactics
        snapshot.clinchedHonours = clinchedHonours
        snapshot.celebrationToShow = celebrationToShow
        snapshot.lastFinanceSnapshot = lastFinanceSnapshot
        snapshot.lastInternationalReport = lastInternationalReport
        return snapshot
    }

    /// Discards the current career and world, leaving a fresh world ready for a
    /// new career in `mode`. The autosave on disk is untouched until the new
    /// career is actually launched.
    public func resetForNewCareer(mode: GameMode) {
        replaceContents(with: GameState.makeFreshWorld())
        gameMode = mode
    }

    /// Shrinks results saved by older builds, which kept full commentary for
    /// every match in the world. Only the user's own matches stay detailed.
    public func compactArchivedResults() {
        let uid = userClubId
        for idx in season.fixtures.indices {
            guard let result = season.fixtures[idx].result, !result.isCompacted else { continue }
            if let uid, season.fixtures[idx].involves(clubId: uid) { continue }
            season.fixtures[idx].result = result.compactedForArchive()
        }
        for cIdx in clubs.indices where !clubs[cIdx].isUserClub {
            if clubs[cIdx].seasonResults.count > 6
                || clubs[cIdx].seasonResults.contains(where: { !$0.isCompacted || $0.homeStats != .empty }) {
                clubs[cIdx].seasonResults = clubs[cIdx].seasonResults.suffix(6).map { $0.compactedForArchive() }
            }
        }
    }

    /// Loads a saved career into this instance. Lands on the dashboard (or the
    /// job market for an unemployed manager) rather than mid-match.
    public func loadCareer(from loaded: GameState) {
        replaceContents(with: loaded)
        compactArchivedResults()
        seedRivalriesIfNeeded()
        isMatchInProgress = false
        negotiationTargetPlayerId = nil
        if userClub != nil {
            currentScreen = .dashboard
        } else if gameMode == .manageClub {
            currentScreen = .jobOffers
        } else {
            currentScreen = .mainMenu
        }
    }

    // MARK: - Computed Properties
    
    public var userClub: Club? {
        guard let id = userClubId else { return nil }
        return clubs.first { $0.id == id }
    }
    
    /// True when the user has a manager profile but no club (started unemployed
    /// or between jobs).
    public var isUnemployed: Bool {
        return userClub == nil
    }
    
    /// The division the user's club is contesting this season. After the
    /// final matchweek, promotion/relegation has already moved the club to
    /// next season's tier, so prefer the league its fixtures belong to;
    /// otherwise the end-of-season table would be a division it never played in.
    public var currentLeague: League? {
        guard let club = userClub else { return nil }
        if let competition = season.fixtures.first(where: { $0.involves(clubId: club.id) })?.competition,
           let league = leagues.first(where: { $0.name == competition }) {
            return league
        }
        return leagues.first { $0.tier == club.leagueTier }
    }
    
    public var activeMatchFixture: Fixture? {
        guard let id = activeMatchFixtureId else { return nil }
        return season.fixtures.first { $0.id == id }
    }
    
    public var nextUserFixture: Fixture? {
        guard let userClubId = userClubId else { return nil }
        return season.upcomingFixtures(forClub: userClubId).first
    }
    
    public var recentUserResults: [MatchResult] {
        guard let userClub = userClub else { return [] }
        return userClub.seasonResults.suffix(5).reversed()
    }
    
    public var currentLeagueStandings: [LeagueStanding] {
        guard let league = currentLeague else { return [] }
        return standings(for: league)
    }
    
    public func standings(for league: League) -> [LeagueStanding] {
        var table: [UUID: LeagueStanding] = [:]

        // Build the table from this division's own fixtures. Using the league's
        // current club list broke the final table once promotions and
        // relegations had been applied: arriving clubs dragged in their results
        // from the division they had just left, and departing clubs vanished.
        let leagueFixtures = season.fixtures.filter { $0.competition == league.name }
        for f in leagueFixtures {
            if table[f.homeClubId] == nil { table[f.homeClubId] = LeagueStanding(clubId: f.homeClubId) }
            if table[f.awayClubId] == nil { table[f.awayClubId] = LeagueStanding(clubId: f.awayClubId) }
        }
        if table.isEmpty {
            for clubId in league.clubIds {
                table[clubId] = LeagueStanding(clubId: clubId)
            }
        }
        
        for f in leagueFixtures where f.isPlayed {
            guard let res = f.result else { continue }
            table[f.homeClubId]?.recordResult(goalsFor: res.homeGoals, goalsAgainst: res.awayGoals)
            table[f.awayClubId]?.recordResult(goalsFor: res.awayGoals, goalsAgainst: res.homeGoals)
        }
        // Administration and similar sanctions.
        for (clubId, deduction) in pointsDeductions where table[clubId] != nil {
            table[clubId]?.points -= deduction
        }
        
        return table.values.sorted(by: LeagueStanding.standardSort)
    }
    
    public func club(withId id: UUID) -> Club? {
        return clubs.first { $0.id == id }
    }
    
    public func player(withId id: UUID) -> (player: Player, club: Club?)? {
        for club in clubs {
            if let p = club.player(withId: id) {
                return (p, club)
            }
        }
        if let freeP = freeAgents.first(where: { $0.id == id }) {
            return (freeP, nil)
        }
        return nil
    }
    
    /// Every player in the world except the user's own squad, paired with their club
    /// (nil for free agents). Used by the transfer search screen.
    public func transferSearchCandidates(includeOwnPlayers: Bool = false) -> [(player: Player, club: Club?)] {
        var results: [(Player, Club?)] = []
        for club in clubs where includeOwnPlayers || !club.isUserClub {
            for player in club.players where !player.isOnLoan {
                results.append((player, club))
            }
        }
        for freeAgent in freeAgents {
            results.append((freeAgent, nil))
        }
        return results
    }
    
    /// Filters transfer candidates by optional criteria.
    public func searchPlayers(
        positionCategory: PositionCategory? = nil,
        specificPosition: Position? = nil,
        minOverall: Int = 0,
        maxAge: Int = 99,
        maxFee: Int? = nil,
        includeFreeAgents: Bool = true,
        includeOwnPlayers: Bool = false
    ) -> [(player: Player, club: Club?)] {
        transferSearchCandidates(includeOwnPlayers: includeOwnPlayers).filter { entry in
            let player = entry.player
            if let category = positionCategory,
               !player.positions.contains(where: { $0.category == category }) {
                return false
            }
            if let specific = specificPosition,
               !player.positions.contains(specific) {
                return false
            }
            if player.overall < minOverall { return false }
            if player.age > maxAge { return false }
            if !includeFreeAgents && entry.club == nil { return false }
            if let maxFee = maxFee, entry.club != nil, player.value > maxFee { return false }
            return true
        }
    }
    
    // MARK: - Calendar & Progression
    
    /// Advances the in-game calendar by 1 day.
    public func advanceDay() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let currentDate = formatter.date(from: season.currentDate),
              let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) else {
            return
        }
        
        season.currentDate = formatter.string(from: nextDate)
    }
    
    /// Advances the in-game calendar day by day toward the user's next fixture.
    /// Fixtures that do not involve the user's club are simulated as their matchweek
    /// arrives, but the user's own match is left unplayed so they can manage and play it.
    /// Returns `true` when it reaches the user's match day (caller should show Match Day).
    @discardableResult
    public func advanceCalendar() -> Bool {
        if isEndOfSeason { return false }
        guard let userClubId = userClubId else { return false }
        scheduleUserEuropeanTies()
        // Run full weekly upkeep (finances, recovery, transfers, Europe) for any
        // matchweek in which the user's club does not play — a bye week in an
        // odd-sized league, for example — rather than jumping straight past it.
        var byeWeeksProcessed = 0
        while !isEndOfSeason, byeWeeksProcessed < 10,
              let upcoming = season.nextFixture(forClub: userClubId),
              upcoming.matchWeek > season.currentWeek {
            advanceWeek()
            byeWeeksProcessed += 1
        }
        if isEndOfSeason { return false }

        guard let nextFixture = season.nextFixture(forClub: userClubId) else {
            // The user's club has completed all of its fixtures for the campaign.
            // Simulate the rest of the world in one pass so the user is not forced
            // to tap Continue once per remaining matchweek.
            var weeksSimulated = 0
            while !isEndOfSeason && weeksSimulated < 100 {
                advanceWeek()
                weeksSimulated += 1
            }
            return false
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard var date = formatter.date(from: season.currentDate),
              let targetDate = formatter.date(from: nextFixture.date) else {
            return false
        }
        
        // Step one day at a time so any intervening matchweeks get simulated.
        while date < targetDate {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? targetDate
            season.currentDate = formatter.string(from: date)
            simulateDueWeeks(excludingUserMatch: true)
        }
        
        // Arrived at match day: surface the user's fixture and their matchweek.
        season.currentWeek = nextFixture.matchWeek
        activeMatchFixtureId = nextFixture.id
        return true
    }
    
    /// One tick of the animated calendar.
    public enum CalendarStep: Equatable {
        /// The calendar moved on (a day, or a whole week when the user has no
        /// match in it). Carries the new date.
        case advanced(String)
        /// The user's next match day has arrived.
        case matchDay
        /// The season is over (or there is no club to manage).
        case seasonOver
    }

    /// Advances the calendar by a single day (or one week when the user has
    /// no fixture in the current week), playing other clubs' matches as their
    /// dates arrive. The animated calendar calls this repeatedly; the result
    /// is identical to `advanceCalendar()`, just in visible steps.
    public func advanceCalendarOneDay() -> CalendarStep {
        if isEndOfSeason { return .seasonOver }
        guard let userClubId = userClubId else { return .seasonOver }
        scheduleUserEuropeanTies()
        guard let next = season.nextFixture(forClub: userClubId) else {
            // Campaign finished for the user: run the rest of the world weekly.
            advanceWeek()
            return isEndOfSeason ? .seasonOver : .advanced(season.currentDate)
        }
        if next.matchWeek > season.currentWeek {
            // A week without a match for the user (a bye or a cup round they
            // are out of): full weekly upkeep.
            advanceWeek()
            return isEndOfSeason ? .seasonOver : .advanced(season.currentDate)
        }
        if season.currentDate >= next.date {
            season.currentWeek = next.matchWeek
            activeMatchFixtureId = next.id
            return .matchDay
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: season.currentDate),
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date) else {
            return advanceCalendar() ? .matchDay : .seasonOver
        }
        season.currentDate = formatter.string(from: tomorrow)
        simulateDueWeeks(excludingUserMatch: true)
        return .advanced(season.currentDate)
    }

    /// Simulates every unplayed fixture in matchweeks whose date has already passed,
    /// optionally leaving the user's own fixtures for the player to manage.
    private func simulateDueWeeks(excludingUserMatch: Bool) {
        // Dates are stored as zero-padded "yyyy-MM-dd", which orders correctly as
        // plain strings. Comparing strings avoids parsing every fixture date on
        // every simulated day (thousands of DateFormatter calls per advance).
        let today = season.currentDate
        let excludedClubId: UUID? = excludingUserMatch ? userClubId : nil
        let dueIds = season.fixtures.compactMap { fixture -> UUID? in
            guard !fixture.isPlayed, fixture.date <= today else { return nil }
            if let excludedClubId, fixture.involves(clubId: excludedClubId) {
                return nil
            }
            return fixture.id
        }
        for id in dueIds {
            simulateFixture(id: id)
        }
    }

    /// Simulates every remaining unplayed fixture in the current matchweek, then
    /// performs weekly upkeep (fitness, finances, AI transfers), advances the
    /// calendar, and checks for season completion. Shared by `advanceWeek()` and
    /// the post-user-match flow so the rest of the league always keeps pace.
    /// Each completed matchday is auto-saved, overwriting the previous autosave.
    public func finishMatchweekAfterUserMatch() {
        // A European tie in midweek is still to be played: leave the week open
        // so the calendar takes the user to it before the round is completed.
        scheduleUserEuropeanTies()
        if let uid = userClubId,
           season.fixtures.contains(where: { $0.matchWeek == season.currentWeek && !$0.isPlayed && $0.involves(clubId: uid) }) {
            // Keep the played fixture active so the full-time report shows it.
            try? SaveManager.shared.autoSave(gameState: self)
            return
        }
        let matchDay = season.currentDate
        advanceWeek()
        // The day ends where it was played: the rest of the round is completed,
        // but the date stays on match day. Home then offers Continue (to the
        // next match day) rather than jumping straight to the next Play.
        if !isEndOfSeason, matchDay < season.currentDate {
            season.currentDate = matchDay
        }
        try? SaveManager.shared.autoSave(gameState: self)
    }

    /// Puts the manager's next European tie into the fixture list as a midweek
    /// match after this week's domestic game, so it is played as a normal
    /// match day. The European competition then uses that result.
    /// Idempotent: a tie already scheduled is left alone.
    public func scheduleUserEuropeanTies() {
        guard gameMode == .manageClub, let uid = userClubId else { return }
        // Europe advances at the end of selected domestic weeks.
        guard isEuropeanWeek(season.currentWeek + 1), !season.isSeasonFinished else { return }
        let nextEuropeanWeek = europeanMatchweek + 1
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for competition in europeanCompetitions {
            for tie in competition.fixtures where tie.matchweek == nextEuropeanWeek && !tie.isPlayed
                && (tie.homeClubId == uid || tie.awayClubId == uid) {
                guard !season.fixtures.contains(where: { $0.europeanFixtureId == tie.id }) else { continue }
                // Midweek: three days after this week's domestic game.
                let domesticDate = season.fixtures
                    .filter { $0.matchWeek == season.currentWeek && $0.involves(clubId: uid) && !$0.isEuropean }
                    .map { $0.date }.min() ?? season.currentDate
                let base = formatter.date(from: domesticDate) ?? Date()
                let midweek = Calendar.current.date(byAdding: .day, value: 3, to: base) ?? base
                let round = tie.leg > 0 && tie.stage != "League Phase" ? "\(tie.stage), leg \(tie.leg)" : tie.stage
                season.fixtures.append(Fixture(
                    homeClubId: tie.homeClubId,
                    awayClubId: tie.awayClubId,
                    matchWeek: season.currentWeek,
                    date: formatter.string(from: midweek),
                    competition: competition.competition.displayName,
                    cupRound: tie.stage == "Final" ? "Final" : round,
                    europeanFixtureId: tie.id
                ))
            }
        }
    }

    /// Advances the in-game week: simulates all pending matchweek matches, recovers fitness,
    /// runs AI transfer evaluation, updates financial balances, and checks promotion/relegation.
    public func advanceWeek() {
        // 1. Simulate all unplayed fixtures of the current matchweek
        let thisWeek = season.fixtures(forWeek: season.currentWeek)
        for fixture in thisWeek where !fixture.isPlayed {
            simulateFixture(id: fixture.id)
        }
        // A fixture left behind in an earlier week (an abandoned live match, a
        // tie added late) is played now. Left unplayed it stayed "next" for
        // ever and the same match kept coming back.
        let staleIds = season.fixtures.filter { !$0.isPlayed && $0.matchWeek < season.currentWeek }.map { $0.id }
        for id in staleIds { simulateFixture(id: id) }

        // Index this week's home fixtures and club reputations once, rather than
        // rescanning every fixture and club for every club in the world.
        var homeOpponentByClub: [UUID: UUID] = [:]
        for fixture in thisWeek where homeOpponentByClub[fixture.homeClubId] == nil {
            homeOpponentByClub[fixture.homeClubId] = fixture.awayClubId
        }
        var reputationByClub: [UUID: Int] = [:]
        for club in clubs { reputationByClub[club.id] = club.reputation }
        
        // A Wednesday cup night is not a new week: no second round of wages,
        // weekly income or training injuries.
        let isCupNight = SeasonCalendar.isMidweek(season.currentWeek) && thisWeek.allSatisfy { $0.cupRound != nil }
        let monthBefore = String(season.currentDate.prefix(7))

        // 2. The days until the next match: fitness, injuries and sharpness.
        // Runs for every slot, cup nights included, over the real number of
        // days (four from Saturday to Wednesday, three back to Saturday), so
        // two games in a week genuinely tire a squad.
        let daysToNext = max(1, SeasonCalendar.dayOffset(forSlot: season.currentWeek + 1)
                                 - SeasonCalendar.dayOffset(forSlot: season.currentWeek))
        for clubIdx in clubs.indices {
            let medical = clubs[clubIdx].medicalFacilityLevel
            let physio = clubs[clubIdx].staff.filter { $0.role == .physio }.map { $0.quality }.max() ?? 0
            let rate = InjuryEngine.recoveryRate(medicalLevel: medical, physioQuality: physio)
            for playerIdx in clubs[clubIdx].players.indices {
                let wasInjured = clubs[clubIdx].players[playerIdx].injury
                clubs[clubIdx].players[playerIdx].advanceDays(daysToNext, injuryRecoveryRate: rate)
                if clubs[clubIdx].isUserClub, let old = wasInjured, clubs[clubIdx].players[playerIdx].injury == nil,
                   old.totalDays >= 14 {
                    let player = clubs[clubIdx].players[playerIdx]
                    addNews(headline: "\(player.fullName) Back in Training",
                            body: "\(player.fullName) has recovered from his \(old.type.displayName.lowercased()). He is at \(Int(player.matchFitness))% match fitness and will need games to get up to speed; rushing him back raises the risk of breaking down again.",
                            category: .general, sender: "Medical Department")
                }
                if let injury = InjuryEngine.trainingInjury(player: clubs[clubIdx].players[playerIdx], medicalLevel: medical, days: daysToNext) {
                    clubs[clubIdx].players[playerIdx].injury = injury
                    if clubs[clubIdx].isUserClub {
                        let player = clubs[clubIdx].players[playerIdx]
                        addNews(headline: "\(player.fullName) Injured in Training",
                                body: "\(player.fullName) has a \(injury.type.displayName.lowercased()) and is expected to be out for \(injury.timeOutText).",
                                category: .general, sender: "Medical Department")
                    }
                }
            }
        }
        for clubIdx in 0..<clubs.count where !isCupNight {
            // Weekly financial accounting. Home clubs bank gate receipts scaled
            // by the calibre of the visiting side.
            let opponentId = homeOpponentByClub[clubs[clubIdx].id]
            var gate = 0
            if let opponentId, let opponentReputation = reputationByClub[opponentId] {
                gate = clubs[clubIdx].finances.matchdayRevenue(opponentReputation: opponentReputation)
                // Derbies sell out and command premium prices.
                if let derby = rivalry(between: clubs[clubIdx].id, and: opponentId) {
                    gate = Int(Double(gate) * (1.0 + 0.15 * Double(derby.intensity)))
                }
                // An owner's pricing policy and the fans' mood shape the gate.
                if gameMode == .createClub && clubs[clubIdx].isUserClub {
                    let mood = 0.85 + Double(owner.supporterConfidence) * 0.003
                    gate = Int(Double(gate) * owner.ticketPricing.revenueMultiplier * mood)
                    if Double.random(in: 0..<1) < 0.4 {
                        adjustFans(owner.ticketPricing.confidenceDrift)
                    }
                }
            }
            if clubs[clubIdx].isUserClub {
                let f = clubs[clubIdx].finances
                seasonLedger?.broadcasting += f.weeklyTvShare
                seasonLedger?.commercial += f.weeklySponsorshipShare
                seasonLedger?.merchandise += f.weeklyMerchandiseShare
                seasonLedger?.matchday += opponentId != nil ? (gate > 0 ? gate : f.matchdayIncome) : 0
                seasonLedger?.wages += f.currentWageBill
            }
            clubs[clubIdx].finances.processWeeklyCashFlow(
                isHomeMatchThisWeek: opponentId != nil,
                gateReceipts: gate
            )
        }
        
        // Draw the next round of any cup whose current round has finished.
        progressDomesticCups()
        
        // Transfer installments and add-ons that have fallen due.
        if !isCupNight { payDueInstallments() }
        // Awards nights: the Ballon d'Or in October, the Team of the Year in January.
        holdDueCeremonies()

        // 3. AI manager autonomous dealings and transfer negotiation resolution
        processAITransfers()
        processAILoans()
        processTransferNegotiations()
        processAIIncomingBids()
        
        // 4. Move to the next slot on the season calendar (a Saturday or a
        // Wednesday cup night). Taken straight from the calendar, so a midweek
        // European game can never push the date past the next match; it only
        // ever moves forward.
        let nextSlotDate = dateForWeek(season.currentWeek + 1)
        if nextSlotDate > season.currentDate {
            season.currentDate = nextSlotDate
        }
        
        // 5. Advance matchweek counter
        season.currentWeek += 1

        // A new month: a month's work on every training ground.
        if String(season.currentDate.prefix(7)) != monthBefore {
            applyMonthlyTraining()
            sendMonthlyFinanceReport()
        }

        // 5b. Advance European competitions (one European matchweek from domestic week 3).
        advanceEuropeanCompetitions()
        
        // 5c. Advance international tournaments.
        advanceInternationalTournaments()
        
        warnAboutExpiringContracts()
        reviewPlayingTime()
        reviewSupporterMood()
        runOwnerBusinessWeek()
        evaluateManagerJobSecurity()
        checkManagerContractExpiry()
        reviewFanPressureOnManager()
        checkOwnerWeeklyAchievements()

        // 5d. Promotion play-offs follow the last league round, as real matches.
        progressLeaguePlayOffs()
        // 5e. Titles and promotion are decided as soon as nobody can catch up.
        checkClinches()

        // 6. Check if season has completed
        if season.isSeasonFinished && season.currentPhase != .endOfSeason {
            // A calendar that ends before the European final (a datapack of
            // short leagues) still finishes Europe before the summer.
            var remaining = 20
            while remaining > 0 && europeanCompetitions.contains(where: { $0.stage != .complete }) {
                advanceEuropeanCompetitions(force: true)
                remaining -= 1
            }
            processEndOfSeason()
        }
    }

    /// Advances every European competition one matchweek, simulating its fixtures
    /// with an Elo-style scoreline derived from club strength. Lakes a week off to
    /// avoid clashing with the very start of the domestic season.
    /// Domestic weeks that host a European matchweek, spaced like the UEFA
    /// calendar: eight league-phase rounds from September to January, then the
    /// knockout play-off, round of 16, quarter-finals and semi-finals over two
    /// legs each, and the final in late spring.
    ///
    /// These are Saturdays of the season (Saturday 1 is early August): the
    /// tie is played on the Tuesday after, and the round is settled at the
    /// next calendar slot. (The list used to hold raw slot numbers, but slots
    /// count Wednesdays too, so the final was played around Christmas.)
    ///   league phase  mid-Sep, end Sep, mid-Oct, early Nov, late Nov,
    ///                 early Dec, mid-Jan, late Jan
    ///   play-off      mid and late Feb
    ///   last 16       March;  quarter-finals  late Mar / early Apr
    ///   semi-finals   mid and late April;  final  early May, the last week
    static let europeanSaturdays = [6, 8, 11, 13, 16, 18, 23, 25, 28, 29, 31, 32, 34, 35, 36, 37, 39]
    static let europeanDomesticWeeks = europeanSaturdays.map { SeasonCalendar.saturday($0) + 1 }

    /// Whether the end of the given domestic week plays a European round.
    func isEuropeanWeek(_ domesticWeek: Int) -> Bool {
        let weeks = GameState.europeanDomesticWeeks
        if weeks.contains(domesticWeek) { return true }
        // A competition that needs more rounds keeps going weekly afterwards.
        return domesticWeek > (weeks.last ?? 40)
            && europeanCompetitions.contains { $0.stage != .complete }
    }

    public func advanceEuropeanCompetitions(force: Bool = false) {
        guard !europeanCompetitions.isEmpty else { return }
        guard force || isEuropeanWeek(season.currentWeek) else { return }

        europeanMatchweek += 1
        let week = europeanMatchweek

        for idx in europeanCompetitions.indices {
            var competition = europeanCompetitions[idx]
            let name = competition.competition.displayName
            let alreadyPlayed = Set(competition.fixtures.filter { $0.isPlayed }.map { $0.id })
            // Ties the manager played as a match day keep their real score.
            var playedByUser: [String: MatchResult] = [:]
            for tie in competition.fixtures where tie.matchweek == week && !tie.isPlayed {
                if let mirror = season.fixtures.first(where: { $0.europeanFixtureId == tie.id }),
                   let result = mirror.result {
                    playedByUser["\(tie.homeClubId)|\(tie.awayClubId)"] = result
                }
            }
            competition.advanceMatchweek(week: week) { home, away in
                if let score = playedByUser["\(home)|\(away)"] { return score }
                return self.playEuropeanMatch(home: home, away: away, competition: name, week: week)
            }

            // Pay UEFA-style result money and report the user's results.
            let prizes = EuropeanPrizes(competition.competition)
            for fixture in competition.fixtures where fixture.isPlayed && !alreadyPlayed.contains(fixture.id) {
                let homeWon = fixture.homeGoals > fixture.awayGoals
                let draw = fixture.homeGoals == fixture.awayGoals
                payEuropeanMoney(fixture.homeClubId, homeWon ? prizes.win : (draw ? prizes.win / 3 : 0))
                payEuropeanMoney(fixture.awayClubId, !homeWon && !draw ? prizes.win : (draw ? prizes.win / 3 : 0))
                if let uid = userClubId, fixture.homeClubId == uid || fixture.awayClubId == uid {
                    let stage = fixture.stage + (fixture.leg > 0 ? ", leg \(fixture.leg)" : "")
                    addNews(
                        headline: "\(competition.competition.displayName): \(clubName(for: fixture.homeClubId)) \(fixture.homeGoals)-\(fixture.awayGoals) \(clubName(for: fixture.awayClubId))",
                        body: "\(name), \(stage)." + (fixture.shootout.map { " \($0.scoreText)." } ?? ""),
                        category: .general,
                        sender: name
                    )
                }
            }

            // Surface the final result as news when a champion is crowned.
            if competition.stage == .complete, competition.championClubId != nil,
               europeanCompetitions[idx].championClubId == nil,
               let champ = competition.championClubId {
                payEuropeanMoney(champ, prizes.championBonus)
                addNews(
                    headline: "\(clubName(for: champ)) Win the \(competition.competition.displayName)!",
                    body: "\(clubName(for: champ)) are crowned champions of Europe.",
                    category: .award,
                    sender: champ == userClubId ? "The Board" : NewsItem.newsDesk
                )
                if champ == userClubId {
                    unlockOwnerMilestone(id: "cup_winner")
                    celebrate(.europe, clubId: champ, title: "EUROPEAN CHAMPIONS!",
                              subtitle: "\(competition.competition.displayName) \(season.year)")
                }
            }

            europeanCompetitions[idx] = competition
        }
    }

    /// Plays a European tie through the full match engine, so it costs
    /// fitness, can cause injuries and counts towards player stats. UEFA
    /// discipline is separate: European cards do not change domestic bans.
    private func playEuropeanMatch(home: UUID, away: UUID, competition: String, week: Int) -> MatchResult? {
        guard let hIdx = clubs.firstIndex(where: { $0.id == home }),
              let aIdx = clubs.firstIndex(where: { $0.id == away }) else { return nil }
        var homeClub = clubs[hIdx]
        var awayClub = clubs[aIdx]
        let userManagesHome = homeClub.isUserClub && gameMode == .manageClub
        let userManagesAway = awayClub.isUserClub && gameMode == .manageClub
        if !userManagesHome { homeClub.prepareAIMatchday() }
        if !userManagesAway { awayClub.prepareAIMatchday() }
        var discipline: [UUID: (Int, Int)] = [:]
        for player in homeClub.players + awayClub.players {
            discipline[player.id] = (player.suspendedMatches, player.yellowCards)
        }
        var config = MatchEngine.SimulationConfig(
            neutralVenue: false,
            matchWeek: week,
            competition: competition,
            date: season.currentDate,
            isKnockout: false,
            derbyIntensity: rivalry(between: home, and: away)?.intensity ?? 0,
            homeCoachingMultiplier: coachingMultiplier(for: home),
            awayCoachingMultiplier: coachingMultiplier(for: away)
        )
        // A second leg level on aggregate goes to extra time and penalties
        // (the final, a single match, is a knockout too).
        if let tie = europeanTie(home: home, away: away, week: week) {
            if let carry = europeanSecondLegCarry(tieId: tie.id) {
                config.isKnockout = true
                config.isSecondLeg = true
                config.homeAggregateCarry = carry.home
                config.awayAggregateCarry = carry.away
            } else if tie.stage == "Final" {
                config.isKnockout = true
            }
        }
        let homeUsual = homeClub.tactics
        let awayUsual = awayClub.tactics
        if matchSettings.autoSelectMatchdayLineup {
            if userManagesHome {
                homeClub.tactics = MatchEngine.selectMatchdayLineup(for: homeClub, against: awayClub, isHome: true, config: config)
            } else if userManagesAway {
                awayClub.tactics = MatchEngine.selectMatchdayLineup(for: awayClub, against: homeClub, isHome: false, config: config)
            }
        } else if matchSettings.assistantRotatesTiredPlayers {
            if userManagesHome { homeClub.rotateTiredStarters() }
            if userManagesAway { awayClub.rotateTiredStarters() }
        }
        let result = MatchEngine.simulateFullMatch(home: &homeClub, away: &awayClub, config: config)
        if matchSettings.autoSelectMatchdayLineup {
            if userManagesHome { homeClub.tactics = homeUsual }
            if userManagesAway { awayClub.tactics = awayUsual }
        }
        for club in [homeClub, awayClub] {
            var updated = club
            for p in updated.players.indices {
                if let saved = discipline[updated.players[p].id] {
                    updated.players[p].suspendedMatches = saved.0
                    updated.players[p].yellowCards = saved.1
                }
            }
            // European results are not part of the domestic form record.
            updated.seasonResults.removeAll { $0.id == result.id }
            if let i = clubs.firstIndex(where: { $0.id == updated.id }) { clubs[i] = updated }
        }
        return result
    }

    /// The unplayed European tie between these clubs in this matchweek.
    private func europeanTie(home: UUID, away: UUID, week: Int) -> EuropeanFixture? {
        for competition in europeanCompetitions {
            if let tie = competition.fixtures.first(where: {
                $0.homeClubId == home && $0.awayClubId == away && $0.matchweek == week && !$0.isPlayed
            }) { return tie }
        }
        return nil
    }

    /// For the second leg of a two-legged European tie: the goals tonight's
    /// home and away sides scored in the first leg. Nil for anything else.
    func europeanSecondLegCarry(tieId: UUID) -> (home: Int, away: Int)? {
        for competition in europeanCompetitions {
            guard let tie = competition.fixtures.first(where: { $0.id == tieId }) else { continue }
            guard tie.leg == 2,
                  let first = competition.fixtures.first(where: {
                      $0.stage == tie.stage && $0.leg == 1 && $0.isPlayed
                          && $0.homeClubId == tie.awayClubId && $0.awayClubId == tie.homeClubId
                  }) else { return nil }
            return (home: first.awayGoals, away: first.homeGoals)
        }
        return nil
    }

    private func payEuropeanMoney(_ clubId: UUID, _ amount: Int) {
        guard amount > 0, let idx = clubs.firstIndex(where: { $0.id == clubId }) else { return }
        clubs[idx].finances.balance += amount
        clubs[idx].finances.transferBudget += amount / 2
        if clubs[idx].isUserClub { seasonLedger?.prizeMoney += amount }
    }

    /// Participation fees for every club entered in a European competition.
    private func payEuropeanParticipationFees() {
        for competition in europeanCompetitions {
            let fee = EuropeanPrizes(competition.competition).participation
            for id in competition.participantClubIds { payEuropeanMoney(id, fee) }
            if let uid = userClubId, competition.participantClubIds.contains(uid) {
                addNews(
                    headline: "\(competition.competition.displayName) Draw",
                    body: "We are in this season's \(competition.competition.displayName), worth \(Player.formatCurrency(fee)) just for taking part.",
                    category: .general,
                    sender: competition.competition.displayName
                )
            }
        }
    }

    // MARK: - Coaching & Owner Operations

    /// How much a club's manager lifts (or drags) its performance. AI clubs are
    /// neutral; the user's club reflects the manager's coaching ability in
    /// manager mode, or the appointed manager's quality in owner mode.
    public func coachingMultiplier(for clubId: UUID) -> Double {
        guard clubId == userClubId else { return 1.0 }
        let rating = gameMode == .createClub ? owner.managerRating : manager.overallCoaching
        return 1.0 + Double(rating - 60) / 1000.0
    }

    /// This season's manager shortlist for an owner, pitched at the club's level.
    public var managerShortlist: [ManagerCandidate] {
        guard let club = userClub else { return ManagerCandidate.shortlist }
        let yearSeed = UInt64(season.year.hashValueStable)
        return ManagerCandidate.shortlist(clubReputation: club.reputation, country: club.leagueTier.country,
                                          seed: yearSeed ^ UInt64(truncatingIfNeeded: club.name.hashValueStable))
    }

    /// In owner mode the appointed manager runs recruitment: while a window is
    /// open he looks for an upgrade on the weakest area of the starting XI that
    /// the transfer allocation and wage budget can afford. Better managers
    /// find bigger upgrades. An interim manager does not sign players.
    private func ownerManagerTransfers() {
        guard gameMode == .createClub, isTransferWindowOpen, !owner.isInAdministration,
              pendingManagerRequest == nil,
              let buyerIdx = clubs.firstIndex(where: { $0.isUserClub }),
              clubs[buyerIdx].manager != "Interim Manager",
              Double.random(in: 0..<1) < 0.3 else { return }
        let buyer = clubs[buyerIdx]
        let starters = buyer.startingXIPlayers
        guard let weakest = starters.min(by: { $0.overall < $1.overall }) else { return }
        let category = weakest.primaryPosition.category
        let policy = owner.recruitmentPolicy
        let ambition = policy.requiredUpgrade + max(0, (owner.managerRating - 55) / 8)
        var best: (player: Player, sellerIdx: Int, fee: Int, wage: Int)?
        for (sellerIdx, seller) in clubs.enumerated() where sellerIdx != buyerIdx && seller.players.count > 18 {
            guard rivalry(between: buyer.id, and: seller.id) == nil else { continue }
            for player in seller.players where !player.isOnLoan && player.primaryPosition.category == category
                && player.overall >= weakest.overall + ambition && player.age <= policy.maximumAge
                && (policy != .youth || player.potential >= player.overall + 5) {
                let fee = Int(Double(player.value) * 1.15)
                let wage = max(player.wage, Player.calculateWage(overall: player.overall, age: player.age, tier: buyer.leagueTier))
                // He will ask the owner for up to twice the allocation.
                guard fee <= max(buyer.finances.transferBudget * 2, 0),
                      buyer.totalWeeklyWageBill + wage <= Int(Double(buyer.finances.wageBudget) * 1.3) else { continue }
                // A youth policy values ceiling over current ability.
                let score = policy == .youth ? player.potential : player.overall
                let bestScore = best.map { policy == .youth ? $0.player.potential : $0.player.overall } ?? -1
                if score > bestScore {
                    best = (player, sellerIdx, fee, wage)
                }
            }
        }
        guard let deal = best else { return }
        let sellerName = clubs[deal.sellerIdx].name
        // Big deals, or deals beyond the budgets, need the owner's approval.
        let delegatedLimit = buyer.finances.transferBudget * owner.delegatedSpendPercent / 100
        if deal.fee > delegatedLimit || deal.fee > buyer.finances.transferBudget
            || buyer.totalWeeklyWageBill + deal.wage > buyer.finances.wageBudget {
            pendingManagerRequest = ManagerRequest(
                playerId: deal.player.id,
                playerName: deal.player.fullName,
                position: deal.player.primaryPosition.displayName,
                rating: deal.player.overall,
                sellerClubId: clubs[deal.sellerIdx].id,
                sellerName: sellerName,
                fee: deal.fee,
                wage: deal.wage,
                createdDate: season.currentDate
            )
            addNews(
                headline: "\(buyer.manager) Requests Funds",
                body: "Your manager wants \(Player.formatCurrency(deal.fee)) to sign \(deal.player.fullName) (\(deal.player.primaryPosition.displayName), rated \(deal.player.overall)) from \(sellerName). Decide in the Boardroom.",
                category: .transfer,
                sender: buyer.manager
            )
            return
        }
        if completeSigning(player: deal.player, buyerIdx: buyerIdx, sellerIdx: deal.sellerIdx,
                           fee: deal.fee, wage: deal.wage, years: 3) {
            clubs[buyerIdx].ensureTacticalIntegrity()
            addNews(
                headline: "\(buyer.manager) Signs \(deal.player.fullName)",
                body: "Your manager has brought in \(deal.player.fullName) (\(deal.player.primaryPosition.displayName), rated \(deal.player.overall)) from \(sellerName) for \(Player.formatCurrency(deal.fee)), funded from the transfer allocation.",
                category: .transfer,
                sender: buyer.manager
            )
        }
    }

    /// Weekly fan sentiment checks for owners: protests when confidence
    /// collapses, praise when it soars.
    private func reviewSupporterMood() {
        guard gameMode == .createClub, userClub != nil, season.currentWeek % 6 == 0 else { return }
        if owner.supporterConfidence < 25 {
            addNews(
                headline: "Fans Protest Against the Owner",
                body: "Supporters marched on the stadium before kick-off. Ticket prices, results and investment are all under fire. Attendances are falling.",
                category: .board,
                sender: "Supporters' Trust"
            )
        } else if owner.supporterConfidence > 85 {
            addNews(
                headline: "Supporters Back the Project",
                body: "Season-ticket demand is soaring and the fans are firmly behind the owner's vision.",
                category: .board,
                sender: "Supporters' Trust"
            )
        }
    }

    // MARK: - Owner Business

    /// The owner's club's current market valuation.
    public var clubValuation: Int {
        guard let club = userClub else { return 0 }
        return OwnerBusiness.valuation(of: club, debt: owner.totalDebt)
    }

    /// Loans the bank will offer: sized to the club's turnover, priced by how
    /// much the club already owes. None once debt reaches a year's turnover.
    public var loanOffers: [(amount: Int, rate: Double)] {
        guard gameMode == .createClub, let club = userClub, !owner.isInAdministration else { return [] }
        let turnover = OwnerBusiness.annualRevenue(club.finances)
        let headroom = turnover - owner.totalDebt
        guard headroom > 100_000 else { return [] }
        let gearing = Double(owner.totalDebt) / Double(max(1, turnover))
        let rate = 0.06 + gearing * 0.08
        return [0.1, 0.3, 0.6].map { share in
            (amount: max(250_000, min(headroom, Int(Double(turnover) * share))), rate: rate)
        }
    }

    /// The owner puts personal money into the club. The share set by the
    /// budget allocation is earmarked for transfers.
    @discardableResult
    public func investInClub(_ amount: Int) -> Bool {
        guard gameMode == .createClub, amount > 0, amount <= owner.personalWealth,
              let idx = clubs.firstIndex(where: { $0.isUserClub }) else { return false }
        owner.personalWealth -= amount
        owner.totalInvested += amount
        clubs[idx].finances.balance += amount
        clubs[idx].finances.transferBudget += amount * owner.budgetAllocation.transferBudgetPercent / 100
        seasonLedger?.ownerInvestment += amount
        adjustFans((amount >= 5_000_000 ? 4 : 2))
        owner.managerSatisfaction = min(100, owner.managerSatisfaction + 3)
        addNews(headline: "Owner Invests \(Player.formatCurrency(amount))",
                body: "\(owner.name) has injected \(Player.formatCurrency(amount)) of personal funds into \(clubs[idx].name).",
                category: .board, sender: "Owner's Office")
        return true
    }

    /// Where the club stands against the owner's season target right now.
    public var ownerTargetStatus: (position: Int, teams: Int, onTrack: Bool)? {
        guard let club = userClub else { return nil }
        let table = currentLeagueStandings
        guard let index = table.firstIndex(where: { $0.clubId == club.id }) else { return nil }
        let limit = owner.seasonObjective.lowestAcceptablePosition(teams: table.count)
        return (index + 1, table.count, index + 1 <= limit)
    }

    /// The most the owner can pay themselves as a dividend. Only a healthy
    /// club can: no debt, no administration, and a cash cushion stays behind.
    public var maxDividend: Int {
        guard gameMode == .createClub, let club = userClub, !owner.isInAdministration,
              owner.totalDebt == 0, owner.weeksInDebt == 0 else { return 0 }
        let cushion = max(1_000_000, OwnerBusiness.annualRevenue(club.finances) / 4)
        return max(0, (club.finances.balance - cushion) / 4)
    }

    /// Pays the owner a dividend out of club cash. Supporters and the manager
    /// notice money leaving the club.
    @discardableResult
    public func takeDividend(_ amount: Int) -> Bool {
        guard amount > 0, amount <= maxDividend,
              let idx = clubs.firstIndex(where: { $0.isUserClub }) else { return false }
        clubs[idx].finances.balance -= amount
        owner.personalWealth += amount
        owner.dividendsTaken += amount
        adjustFans(-(amount >= 5_000_000 ? 5 : 3))
        owner.managerSatisfaction = max(0, owner.managerSatisfaction - managerMoodChange(3))
        addNews(headline: "Owner Takes \(Player.formatCurrency(amount)) Dividend",
                body: "\(owner.name) has paid themselves \(Player.formatCurrency(amount)) from \(clubs[idx].name). Supporters want it spent on the team.",
                category: .board, sender: "Finance Director")
        return true
    }

    /// Judges the manager against the owner's target at the end of a season.
    func judgeSeasonObjective(position: Int, teams: Int, promoted: Bool) {
        let objective = owner.seasonObjective
        let limit = objective.lowestAcceptablePosition(teams: teams)
        let met = position <= limit || (objective == .promotionOrTopSix && promoted)
        let verdict: String
        if met {
            owner.managerSatisfaction = min(100, owner.managerSatisfaction + Int((8 * objective.stakes).rounded()))
            adjustFans(Int((3 * objective.stakes).rounded()))
            verdict = "Target met: \(objective.rawValue.lowercased()). The board is pleased."
        } else {
            let miss = position - limit
            let base = miss > 4 ? 12 : 5
            owner.managerSatisfaction = max(0, owner.managerSatisfaction - managerMoodChange(Int((Double(base) * objective.stakes).rounded())))
            adjustFans(-Int((Double(miss > 4 ? 4 : 2) * objective.stakes).rounded()))
            verdict = "Target missed: \(objective.rawValue.lowercased()). Finished \(position)\(standingRankSuffix(position)). The manager knows the board is unhappy."
        }
        addNews(headline: "Season Target Reviewed", body: verdict, category: .board, sender: "Board Secretary")
    }

    /// Takes a bank loan repaid weekly over two seasons.
    @discardableResult
    public func takeLoan(amount: Int, rate: Double) -> Bool {
        guard gameMode == .createClub, amount > 0, !owner.isInAdministration,
              let idx = clubs.firstIndex(where: { $0.isUserClub }) else { return false }
        let loan = ClubLoan(principal: amount, rate: rate, termWeeks: 104)
        owner.loans.append(loan)
        clubs[idx].finances.balance += amount
        seasonLedger?.loansReceived += amount
        addNews(headline: "Bank Loan Agreed",
                body: "A \(Player.formatCurrency(amount)) loan at \(Int((rate * 100).rounded()))% has been secured, repaid at \(Player.formatCurrency(loan.weeklyRepayment)) a week for two seasons.",
                category: .board, sender: "Finance Director")
        return true
    }

    /// Clears a loan early from club cash.
    @discardableResult
    public func repayLoan(id: UUID) -> Bool {
        guard let loanIdx = owner.loans.firstIndex(where: { $0.id == id }),
              let idx = clubs.firstIndex(where: { $0.isUserClub }),
              clubs[idx].finances.balance >= owner.loans[loanIdx].remaining else { return false }
        let amount = owner.loans[loanIdx].remaining
        clubs[idx].finances.balance -= amount
        seasonLedger?.loanRepayments += amount
        owner.loans.remove(at: loanIdx)
        return true
    }

    /// Sells the stadium's naming rights: steady commercial income, but fans
    /// dislike losing the ground's name.
    @discardableResult
    public func signNamingRights() -> Bool {
        guard gameMode == .createClub, owner.namingRightsValue == nil,
              let idx = clubs.firstIndex(where: { $0.isUserClub }) else { return false }
        let value = OwnerBusiness.namingRightsValue(capacity: clubs[idx].stadiumCapacity, reputation: clubs[idx].reputation)
        let brand = OwnerBusiness.namingRightsBrands[abs(clubs[idx].name.hashValueStable) % OwnerBusiness.namingRightsBrands.count]
        let oldName = clubs[idx].stadium
        clubs[idx].stadium = "\(brand) Stadium"
        clubs[idx].finances.sponsorshipIncome += value
        owner.namingRightsValue = value
        adjustFans(-(6))
        addNews(headline: "\(oldName) Becomes the \(brand) Stadium",
                body: "A naming-rights deal worth \(Player.formatCurrency(value)) a year has been signed. Some supporters are unhappy to see the old name go.",
                category: .board, sender: "Commercial Director")
        return true
    }

    /// Cost and size of a new stadium for the owner's club.
    public var newStadiumPlan: (capacity: Int, cost: Int)? {
        guard let club = userClub, club.stadiumCapacity < 75_000 else { return nil }
        let capacity = min(80_000, max(club.stadiumCapacity + 8_000, Int(Double(club.stadiumCapacity) * 1.8)))
        return (capacity, (capacity - club.stadiumCapacity) * 3_500)
    }

    /// Starts a year-long new-stadium build, paid from club cash up front.
    @discardableResult
    public func startStadiumProject() -> Bool {
        guard gameMode == .createClub, owner.stadiumProject == nil, let plan = newStadiumPlan,
              let idx = clubs.firstIndex(where: { $0.isUserClub }),
              clubs[idx].finances.balance >= plan.cost else { return false }
        clubs[idx].finances.balance -= plan.cost
        owner.stadiumProject = StadiumProject(newCapacity: plan.capacity, cost: plan.cost, weeks: 52)
        adjustFans(8)
        addNews(headline: "New Stadium Approved",
                body: "Work begins on a \(plan.capacity.formatted())-seat stadium costing \(Player.formatCurrency(plan.cost)). It will open in a year.",
                category: .board, sender: "Owner's Office")
        return true
    }

    /// The owner funds the manager's requested signing.
    @discardableResult
    public func approveManagerRequest() -> String {
        guard let request = pendingManagerRequest,
              let buyerIdx = clubs.firstIndex(where: { $0.isUserClub }),
              let sellerIdx = clubs.firstIndex(where: { $0.id == request.sellerClubId }),
              let player = clubs[sellerIdx].player(withId: request.playerId) else {
            pendingManagerRequest = nil
            return "The player is no longer available."
        }
        pendingManagerRequest = nil
        // The owner's approval tops the allocation up if it falls short.
        if clubs[buyerIdx].finances.transferBudget < request.fee {
            clubs[buyerIdx].finances.transferBudget = request.fee
        }
        if clubs[buyerIdx].totalWeeklyWageBill + request.wage > clubs[buyerIdx].finances.wageBudget {
            clubs[buyerIdx].finances.wageBudget = clubs[buyerIdx].totalWeeklyWageBill + request.wage
        }
        guard completeSigning(player: player, buyerIdx: buyerIdx, sellerIdx: sellerIdx,
                              fee: request.fee, wage: request.wage, years: 3) else {
            return "The deal could not be completed."
        }
        clubs[buyerIdx].ensureTacticalIntegrity()
        owner.managerSatisfaction = min(100, owner.managerSatisfaction + 8)
        addNews(headline: "\(request.playerName) Signs",
                body: "With your backing, \(clubs[buyerIdx].manager) has signed \(request.playerName) from \(request.sellerName) for \(Player.formatCurrency(request.fee)).",
                category: .transfer, sender: clubs[buyerIdx].manager)
        return "\(request.playerName) has joined the club."
    }

    /// The owner refuses the manager's request.
    public func declineManagerRequest() {
        guard pendingManagerRequest != nil else { return }
        pendingManagerRequest = nil
        owner.managerSatisfaction = max(0, owner.managerSatisfaction - managerMoodChange(12))
        checkManagerResignation()
    }

    /// A manager whose patience has run out walks away.
    private func checkManagerResignation() {
        guard gameMode == .createClub,
              owner.managerSatisfaction <= (owner.managerContract?.personality.resignationThreshold ?? 15),
              let idx = clubs.firstIndex(where: { $0.isUserClub }),
              clubs[idx].manager != "Interim Manager" else { return }
        let outgoing = clubs[idx].manager
        owner.managerContract = nil
        clubs[idx].manager = "Interim Manager"
        owner.managerRating = 45
        owner.managerSatisfaction = 55
        adjustFans(-(6))
        addNews(headline: "\(outgoing) Resigns",
                body: "\(outgoing) has resigned, citing a lack of backing from the owner. Appoint a successor from the People tab.",
                category: .board, sender: "Owner's Office")
    }

    // MARK: - Supporters' mood

    /// Moves the supporters' mood and remembers why, so the owner can see
    /// what is pleasing or angering the fans. The reason comes from the
    /// calling function unless given.
    func adjustFans(_ change: Int, reason: String = #function) {
        guard change != 0 else { return }
        owner.supporterConfidence = max(0, min(100, owner.supporterConfidence + change))
        let readable = GameState.fanReasons[reason.components(separatedBy: "(").first ?? reason] ?? reason
        if var last = owner.fanMoodLog.last, last.reason == readable, last.date.prefix(7) == season.currentDate.prefix(7) {
            last.change += change
            owner.fanMoodLog[owner.fanMoodLog.count - 1] = last
        } else {
            owner.fanMoodLog.append(FanMoodEntry(date: season.currentDate, reason: readable, change: change))
        }
        if owner.fanMoodLog.count > 40 { owner.fanMoodLog.removeFirst(owner.fanMoodLog.count - 40) }
    }

    static let fanReasons: [String: String] = [
        "advanceWeek": "Ticket prices",
        "investInClub": "Owner investing their own money",
        "takeDividend": "Owner taking money out of the club",
        "judgeSeasonObjective": "Season target",
        "signNamingRights": "Stadium renamed for a sponsor",
        "startStadiumProject": "New stadium plans",
        "checkManagerResignation": "Manager walked out",
        "declineTakeover": "Takeover bid rejected",
        "runOwnerBusinessWeek": "Club business",
        "enterAdministration": "Club in administration",
        "applyDerbyAftermath": "Derby result",
        "acceptIncomingOffer": "Selling a first-team player",
        "approveOwnerInvestment": "Investment in the club",
        "updateOwnerMatchPerformance": "Results on the pitch",
        "appointManager": "New manager appointed",
        "dismissManager": "Manager sacked"
    ]

    /// The main reasons behind the fans' mood over the last few months,
    /// largest first.
    public var fanMoodReasons: [(reason: String, change: Int)] {
        let recent = owner.fanMoodLog.suffix(30)
        var totals: [String: Int] = [:]
        for entry in recent { totals[entry.reason, default: 0] += entry.change }
        return totals.filter { $0.value != 0 }
            .map { (reason: $0.key, change: $0.value) }
            .sorted { abs($0.change) > abs($1.change) }
    }

    // MARK: - Manager contracts

    /// Wage the manager asks for to extend his contract: a rise after a
    /// good relationship and a rising reputation, a small one otherwise.
    public var managerRenewalWage: Int? {
        guard let contract = owner.managerContract else { return nil }
        let rise = owner.managerSatisfaction >= 60 ? 1.15 : 1.05
        return Int(Double(contract.weeklyWage) * rise)
    }

    /// Extends the manager's contract by `years` at his asking wage.
    @discardableResult
    public func renewManagerContract(years: Int) -> Bool {
        guard gameMode == .createClub, var contract = owner.managerContract,
              let wage = managerRenewalWage else { return false }
        if owner.managerSatisfaction < 25 {
            addNews(headline: "\(contract.managerName) Rejects New Deal",
                    body: "\(contract.managerName) feels unsupported by the board and will not sign a new contract.",
                    category: .board, sender: contract.managerName)
            return false
        }
        contract.yearsRemaining += max(1, min(4, years))
        contract.weeklyWage = wage
        owner.managerContract = contract
        owner.managerSatisfaction = min(100, owner.managerSatisfaction + 10)
        addNews(headline: "\(contract.managerName) Signs New Contract",
                body: "\(contract.managerName) has committed his future to the club until \(contract.yearsRemaining) more season\(contract.yearsRemaining == 1 ? "" : "s") are up, on \(Player.formatCurrency(wage))/w.",
                category: .board, sender: "Owner's Office")
        return true
    }

    /// Summer: a year comes off the manager's contract. One that has run out
    /// must be renewed in the first weeks of the season or he leaves.
    func ageManagerContract() {
        guard gameMode == .createClub, var contract = owner.managerContract else { return }
        contract.yearsRemaining -= 1
        contract.age += 1
        owner.managerContract = contract
        if contract.yearsRemaining <= 0 {
            addNews(headline: "\(contract.managerName)'s Contract Has Expired",
                    body: "\(contract.managerName) is working without a contract. Offer him a new deal in the People tab before the end of September or he will leave.",
                    category: .board, sender: "Owner's Office")
        }
    }

    /// A manager without a contract walks once September is over.
    func checkManagerContractExpiry() {
        guard gameMode == .createClub, let contract = owner.managerContract, contract.yearsRemaining <= 0,
              currentMonth == 10,
              let idx = clubs.firstIndex(where: { $0.isUserClub }) else { return }
        owner.managerContract = nil
        clubs[idx].manager = "Interim Manager"
        owner.managerRating = 45
        addNews(headline: "\(contract.managerName) Leaves",
                body: "With no new contract offered, \(contract.managerName) has left the club. Appoint a successor from the People tab.",
                category: .board, sender: "Owner's Office")
    }

    /// Accepts the takeover: the owner sells up and the career ends.
    /// Returns a closing summary for the UI.
    public func acceptTakeover() -> String? {
        guard let offer = pendingTakeover, let club = userClub else { return nil }
        pendingTakeover = nil
        owner.personalWealth += offer.amount
        let startValue = owner.valuationAtTakeover ?? offer.amount
        let growth = Int((Double(offer.amount) / Double(max(1, startValue)) - 1) * 100)
        return "You sold \(club.name) to \(offer.bidder) for \(Player.formatCurrency(offer.amount)), \(growth)% more than the club was worth when you founded it. You invested \(Player.formatCurrency(owner.totalInvested)) of your own money and leave with a fortune of \(Player.formatCurrency(owner.personalWealth)).\n\nThank you for running the club."
    }

    public func declineTakeover() {
        guard pendingTakeover != nil else { return }
        pendingTakeover = nil
        adjustFans(3)
    }

    /// Weekly business cycle for an owner: loan repayments, the stadium build,
    /// cash-flow distress and administration, and takeover interest.
    private func runOwnerBusinessWeek() {
        guard gameMode == .createClub, let idx = clubs.firstIndex(where: { $0.isUserClub }) else { return }

        // An unanswered request lapses when the window shuts, and the manager
        // takes it as a snub.
        if pendingManagerRequest != nil && !isTransferWindowOpen {
            pendingManagerRequest = nil
            owner.managerSatisfaction = max(0, owner.managerSatisfaction - managerMoodChange(6))
            checkManagerResignation()
        }

        // Loan repayments.
        for loanIdx in owner.loans.indices {
            let payment = min(owner.loans[loanIdx].remaining, owner.loans[loanIdx].weeklyRepayment)
            owner.loans[loanIdx].remaining -= payment
            clubs[idx].finances.balance -= payment
            seasonLedger?.loanRepayments += payment
        }
        owner.loans.removeAll { $0.remaining <= 0 }

        // Stadium construction.
        if var project = owner.stadiumProject {
            project.weeksRemaining -= 1
            if project.weeksRemaining <= 0 {
                let previous = clubs[idx].stadiumCapacity
                clubs[idx].stadiumCapacity = project.newCapacity
                clubs[idx].finances.stadiumCapacity = project.newCapacity
                clubs[idx].finances.matchdayIncome = Int(Double(clubs[idx].finances.matchdayIncome) * Double(project.newCapacity) / Double(max(1, previous)))
                clubs[idx].reputation = min(99, clubs[idx].reputation + 3)
                adjustFans(10)
                owner.stadiumProject = nil
                addNews(headline: "The New Stadium Opens!",
                        body: "\(clubs[idx].name)'s new \(project.newCapacity.formatted())-seat home is complete. Bigger crowds and a bigger profile await.",
                        category: .board, sender: "Owner's Office")
            } else {
                owner.stadiumProject = project
            }
        }

        // Cash-flow distress. Weeks overdrawn lead to warnings, then
        // administration: a points deduction, a transfer embargo and the
        // administrators selling the most valuable players.
        if clubs[idx].finances.balance < 0 {
            owner.weeksInDebt += 1
            if owner.weeksInDebt == 4 {
                addNews(headline: "Bank Warns Over Overdraft",
                        body: "The club has been overdrawn for a month. Invest, borrow or sell players, or the club will be placed into administration.",
                        category: .board, sender: "Finance Director")
            } else if owner.weeksInDebt >= 10 && !owner.isInAdministration {
                enterAdministration(clubIdx: idx)
            }
        } else {
            owner.weeksInDebt = 0
        }

        processSponsorMarketWeek()

        // Takeover bids arrive at the start of a season (ownerSeasonStartMarket).
        if gameMode == .manageClub, pendingTakeover == nil, season.currentWeek == 30,
           let start = owner.valuationAtTakeover, clubValuation > start, Double.random(in: 0..<1) < 0.35 {
            let bidders = ["a Gulf investment fund", "an American sports group", "a local consortium", "a private equity firm"]
            let amount = Int(Double(clubValuation) * Double.random(in: 1.1...1.35))
            pendingTakeover = TakeoverOffer(bidder: bidders.randomElement() ?? "a consortium", amount: amount)
            addNews(headline: "Takeover Bid Received",
                    body: "\(pendingTakeover?.bidder.capitalized ?? "A consortium") has offered \(Player.formatCurrency(amount)) to buy the club. Review it in the Boardroom.",
                    category: .board, sender: "Owner's Office")
        }
    }

    private func enterAdministration(clubIdx idx: Int) {
        owner.isInAdministration = true
        let deduction = clubs[idx].leagueTier.country == .england ? 12 : 10
        pointsDeductions[clubs[idx].id, default: 0] += deduction
        adjustFans(-(25))
        owner.managerSatisfaction = max(0, owner.managerSatisfaction - managerMoodChange(20))
        owner.legacyPoints = max(0, owner.legacyPoints - 10)

        // Administrators raise cash by selling the two most valuable players
        // to clubs that can afford them, at a discount.
        var sold: [String] = []
        let saleable = clubs[idx].players.sorted { $0.value > $1.value }.prefix(2)
        for player in saleable {
            let fee = Int(Double(player.value) * 0.7)
            guard let buyerIdx = clubs.indices.first(where: {
                $0 != idx && !clubs[$0].isUserClub && clubs[$0].finances.transferBudget >= fee
                    && clubs[$0].reputation >= clubs[idx].reputation
            }) else { continue }
            let wage = max(player.wage, Player.calculateWage(overall: player.overall, age: player.age, tier: clubs[buyerIdx].leagueTier))
            if clubs[buyerIdx].totalWeeklyWageBill + wage > clubs[buyerIdx].finances.wageBudget {
                clubs[buyerIdx].finances.wageBudget = clubs[buyerIdx].totalWeeklyWageBill + wage
            }
            if completeSigning(player: player, buyerIdx: buyerIdx, sellerIdx: idx, fee: fee, wage: wage, years: 3) {
                sold.append("\(player.fullName) (\(Player.formatCurrency(fee)))")
            }
        }
        clubs[idx].ensureTacticalIntegrity()
        addNews(headline: "\(clubs[idx].name) Enter Administration",
                body: "After ten weeks in the red the club has been placed into administration: a \(deduction)-point deduction and a transfer embargo.\(sold.isEmpty ? "" : " The administrators have sold " + sold.joined(separator: " and ") + ".")",
                category: .board, sender: "League Office")
    }

    /// Leaves administration at season's end if the books are back in the black.
    private func reviewAdministration() {
        guard owner.isInAdministration, let club = userClub else { return }
        if club.finances.balance >= 0 {
            owner.isInAdministration = false
            owner.weeksInDebt = 0
            addNews(headline: "Out of Administration",
                    body: "\(club.name) have exited administration. The transfer embargo is lifted.",
                    category: .board, sender: "League Office")
        }
    }

    /// A successful manager attracts bigger clubs, which pay compensation.
    private func reviewManagerPoaching(position: Int, leagueSize: Int) {
        guard gameMode == .createClub, owner.managerRating >= 65,
              position <= max(1, leagueSize / 3),
              let idx = clubs.firstIndex(where: { $0.isUserClub }),
              clubs[idx].manager != "Interim Manager",
              Double.random(in: 0..<1) < 0.3 * (owner.managerContract?.personality.poachingRisk ?? 1) else { return }
        let outgoing = clubs[idx].manager
        // The poaching club pays his release fee: the rest of his contract.
        let compensation = owner.managerContract?.releaseFee
            ?? 150 * max(2_000, Int(pow(1.07, Double(owner.managerRating - 40)) * 2_500))
        owner.managerContract = nil
        clubs[idx].finances.balance += compensation
        clubs[idx].manager = "Interim Manager"
        owner.managerRating = 45
        owner.managerSatisfaction = 60
        addNews(headline: "\(outgoing) Poached",
                body: "A bigger club has triggered \(outgoing)'s release clause after a fine season, paying \(Player.formatCurrency(compensation)) in compensation. You need a new manager.",
                category: .board, sender: "Owner's Office")
    }

    // MARK: - Rivalries

    /// The user's European ties this season, with the competition's name.
    public var userEuropeanFixtures: [(competition: String, fixture: EuropeanFixture)] {
        guard let uid = userClubId else { return [] }
        return europeanCompetitions.flatMap { comp in
            comp.fixtures
                .filter { $0.homeClubId == uid || $0.awayClubId == uid }
                .map { (comp.competition.shortName, $0) }
        }
        .sorted { $0.fixture.matchweek < $1.fixture.matchweek }
    }

    /// The rivalry between two clubs, if any.
    public func rivalry(between a: UUID, and b: UUID) -> Rivalry? {
        rivalries.first { $0.involves(a, b) }
    }

    /// The derby name for a fixture, e.g. "North London Derby".
    public func derbyName(for fixture: Fixture) -> String? {
        rivalry(between: fixture.homeClubId, and: fixture.awayClubId)?.name
    }

    /// Clubs the user's club counts as rivals.
    public var userRivals: [(club: Club, rivalry: Rivalry)] {
        guard let uid = userClubId else { return [] }
        return rivalries.compactMap { rivalry in
            guard rivalry.clubA == uid || rivalry.clubB == uid else { return nil }
            let otherId = rivalry.clubA == uid ? rivalry.clubB : rivalry.clubA
            return club(withId: otherId).map { ($0, rivalry) }
        }
        .sorted { $0.rivalry.intensity > $1.rivalry.intensity }
    }

    /// Fills in rivalries for saves made before they existed.
    /// Makes sure every club has two goalkeepers (old saves and source data
    /// could leave a side with none). The user hears about any emergency
    /// signing for their own club.
    public func ensureGoalkeepersEverywhere() {
        for idx in clubs.indices {
            let added = clubs[idx].ensureGoalkeepers()
            guard added > 0 else { continue }
            if clubs[idx].isUserClub {
                if !clubs[idx].tactics.startingXI.compactMap({ id in clubs[idx].players.first { $0.id == id } })
                    .contains(where: { $0.primaryPosition == .GK }) {
                    clubs[idx].autoPickStartingXI()
                }
                addNews(
                    headline: "Emergency Goalkeeper Signed",
                    body: "\(clubs[idx].name) had \(added == 2 ? "no" : "only one") senior goalkeeper, so the club has signed \(added == 1 ? "a keeper" : "two keepers") from the free market. Check your lineup.",
                    category: .transfer,
                    sender: "Director of Football"
                )
            } else {
                clubs[idx].autoPickStartingXI()
            }
        }
    }

    public func seedRivalriesIfNeeded() {
        guard rivalries.isEmpty else { return }
        rivalries = DataLoader.loadRivalries(for: clubs)
    }

    /// Derby results matter far beyond three points: the squad's morale, the
    /// board's patience and the fans' mood all swing with them.
    private func applyDerbyAftermath(_ derby: Rivalry, result: MatchResult, userWasHome: Bool) {
        guard let clubIdx = clubs.firstIndex(where: { $0.isUserClub }) else { return }
        let goalsFor = userWasHome ? result.homeGoals : result.awayGoals
        let goalsAgainst = userWasHome ? result.awayGoals : result.homeGoals
        let opponentId = userWasHome ? result.awayClubId : result.homeClubId
        let opponent = clubName(for: opponentId)
        let swing = 3 * derby.intensity

        let outcome = result.outcomeLetter(for: clubs[clubIdx].id)
        let score = "\(goalsFor)-\(goalsAgainst)" + (result.shootout.map { " (\($0.scoreText))" } ?? "")
        if outcome == "W" {
            for p in clubs[clubIdx].players.indices {
                clubs[clubIdx].players[p].boostMorale()
                if derby.intensity >= 3 { clubs[clubIdx].players[p].boostMorale() }
            }
            jobSecurity.boardConfidence = min(100, jobSecurity.boardConfidence + swing)
            adjustFans(swing)
            addNews(
                headline: "\(derby.name) Glory!",
                body: "A \(score) win over \(opponent). The fans will be talking about this one for weeks, and the dressing room is buzzing.",
                category: .general,
                sender: "Supporters' Club"
            )
        } else if outcome == "L" {
            for p in clubs[clubIdx].players.indices {
                clubs[clubIdx].players[p].dampenMorale()
            }
            jobSecurity.boardConfidence = max(0, jobSecurity.boardConfidence - swing)
            adjustFans(-(swing))
            addNews(
                headline: "\(derby.name) Misery",
                body: "Losing \(score) to \(opponent) hurts. Supporters are furious and the board expect a reaction.",
                category: .general,
                sender: "Supporters' Club"
            )
        }
    }

    // MARK: - Domestic Cups

    /// The calendar date of a matchweek, derived from the season's opening week.
    private func dateForWeek(_ week: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // The opening Saturday, worked back from any league fixture.
        guard let reference = season.fixtures.first(where: { !$0.isEuropean && $0.cupRound == nil }),
              let refDate = formatter.date(from: reference.date),
              let opening = Calendar.current.date(byAdding: .day, value: -SeasonCalendar.dayOffset(forSlot: reference.matchWeek), to: refDate),
              let date = Calendar.current.date(byAdding: .day, value: SeasonCalendar.dayOffset(forSlot: week), to: opening) else {
            return season.currentDate
        }
        return formatter.string(from: date)
    }

    /// Last season's champions and cup winners, captured when a new season
    /// begins so the super cups can be drawn. Not saved: only used at seeding.
    private var superCupSeeds: [LeagueCountry: [UUID]] = [:]

    /// Creates each country's trophies and draws their first rounds:
    /// the national cup, a league cup and lower-division trophy where the
    /// country has one, and the super cup (champions against cup winners).
    /// The strongest clubs (top division first, then reputation) receive byes
    /// so each bracket is a power of two from the second round on.
    public func seedDomesticCups() {
        let seeds = superCupSeeds
        superCupSeeds = [:]
        domesticCups = []
        var clubsByCountry: [LeagueCountry: [Club]] = [:]
        for league in leagues {
            let members = league.clubIds.compactMap { club(withId: $0) }
            clubsByCountry[league.tier.country, default: []].append(contentsOf: members)
        }
        for (country, members) in clubsByCountry where members.count >= DomesticCups.minimumEntrants {
            addKnockoutCup(country: country, name: DomesticCups.cupName(for: country), kind: .national, members: members)
            if let leagueCup = DomesticCups.leagueCup(for: country) {
                addKnockoutCup(country: country, name: leagueCup.name, kind: .league,
                               members: members.filter { leagueCup.levels.contains($0.leagueTier.level) })
            }
            if let trophy = DomesticCups.trophy(for: country) {
                addKnockoutCup(country: country, name: trophy.name, kind: .trophy,
                               members: members.filter { trophy.levels.contains($0.leagueTier.level) })
            }
            if let superCup = DomesticCups.superCupName(for: country) {
                // First season: the two strongest top-flight clubs.
                let pair = seeds[country] ?? Array(members.filter { $0.leagueTier.level == 1 }
                    .sorted { $0.reputation > $1.reputation }.prefix(2).map { $0.id })
                if pair.count == 2 {
                    var cup = DomesticCupState(country: country, name: superCup, rounds: ["Final"],
                                               roundWeeks: SeasonCalendar.cupNights(for: .superCup),
                                               byeClubIds: [], kind: .superCup)
                    drawCupRound(&cup, entrants: pair)
                    domesticCups.append(cup)
                }
            }
        }
        let order: [CupKind: Int] = [.national: 0, .league: 1, .trophy: 2, .superCup: 3]
        domesticCups.sort { lhs, rhs in
            lhs.country.index != rhs.country.index ? lhs.country.index < rhs.country.index
                : (order[lhs.kind] ?? 0) < (order[rhs.kind] ?? 0)
        }
    }

    /// Builds one knockout cup from `members` on its kind's cup nights.
    private func addKnockoutCup(country: LeagueCountry, name: String, kind: CupKind, members: [Club]) {
        guard members.count >= 4 else { return }
        let seeded = members.sorted { lhs, rhs in
            if lhs.leagueTier.level != rhs.leagueTier.level { return lhs.leagueTier.level < rhs.leagueTier.level }
            return lhs.reputation > rhs.reputation
        }
        let size = DomesticCups.bracketSize(for: seeded.count)
        let byeCount = size - seeded.count
        let roundCount = Int(log2(Double(size)).rounded())
        // Play the rounds on the last cup nights so every final lands together.
        let weeks = Array(SeasonCalendar.cupNights(for: kind).suffix(roundCount))
        guard roundCount >= 2, weeks.count == roundCount else { return }
        var cup = DomesticCupState(
            country: country,
            name: name,
            rounds: DomesticCups.roundNames(count: roundCount),
            roundWeeks: weeks,
            byeClubIds: seeded.prefix(byeCount).map { $0.id },
            kind: kind
        )
        drawCupRound(&cup, entrants: seeded.dropFirst(byeCount).map { $0.id })
        domesticCups.append(cup)
    }

    /// Champions and cup winners of the season just finished, per country.
    private func capturedSuperCupSeeds() -> [LeagueCountry: [UUID]] {
        var seeds: [LeagueCountry: [UUID]] = [:]
        for league in leagues where league.tier.level == 1 {
            let table = standings(for: league)
            guard let champion = table.first?.clubId else { continue }
            let cupWinner = domesticCups.first { $0.country == league.tier.country && $0.kind == .national }?.championClubId
            if let cupWinner, cupWinner != champion {
                seeds[league.tier.country] = [champion, cupWinner]
            } else if table.count > 1 {
                seeds[league.tier.country] = [champion, table[1].clubId]
            }
        }
        return seeds
    }

    /// Pairs `entrants` at random into ties for the cup's current round.
    private func drawCupRound(_ cup: inout DomesticCupState, entrants: [UUID]) {
        let week = cup.roundWeeks[cup.currentRoundIndex]
        let date = dateForWeek(week)
        let roundName = cup.currentRoundName
        var pool = entrants.shuffled()
        while pool.count >= 2 {
            let home = pool.removeFirst()
            let away = pool.removeFirst()
            season.fixtures.append(Fixture(
                homeClubId: home,
                awayClubId: away,
                matchWeek: week,
                date: date,
                competition: cup.name,
                cupRound: roundName
            ))
            if let uid = userClubId, home == uid || away == uid {
                let opponent = home == uid ? away : home
                addNews(
                    headline: "\(cup.name) \(roundName) Draw",
                    body: "You have been drawn \(home == uid ? "at home to" : "away to") \(clubName(for: opponent)) in the \(cup.name) \(roundName.lowercased()).",
                    category: .general,
                    sender: "\(cup.name)"
                )
            }
        }
    }

    /// Prize money for winning a tie in the given round.
    private func cupPrize(roundIndex: Int, of roundCount: Int, country: LeagueCountry) -> Int {
        let scale: Double
        switch country {
        case .england, .spain, .italy, .germany, .france: scale = 1.0
        case .portugal, .netherlands, .turkey, .scotland, .belgium, .brazil, .argentina: scale = 0.5
        default: scale = 0.3
        }
        // Escalates towards the final: the last round pays the most.
        let stepsFromFinal = roundCount - 1 - roundIndex
        let base = 2_400_000.0 / pow(2.0, Double(stepsFromFinal))
        return max(25_000, Int(base * scale))
    }

    /// Advances cups whose current round has been fully played: pays prize
    /// money, then draws the next round or crowns the winner.
    public func progressDomesticCups() {
        for index in domesticCups.indices where !domesticCups[index].isFinished {
            var cup = domesticCups[index]
            let ties = season.fixtures.filter { $0.competition == cup.name && $0.cupRound == cup.currentRoundName }
            guard !ties.isEmpty, ties.allSatisfy({ $0.isPlayed }) else { continue }

            var winners: [UUID] = []
            for tie in ties {
                // A tie can only be level if a shootout could not be staged;
                // the higher-ranked club then goes through.
                let winner: UUID
                if let decided = tie.winnerClubId {
                    winner = decided
                } else {
                    let home = club(withId: tie.homeClubId)?.reputation ?? 0
                    let away = club(withId: tie.awayClubId)?.reputation ?? 0
                    winner = home >= away ? tie.homeClubId : tie.awayClubId
                }
                winners.append(winner)
                let loser = winner == tie.homeClubId ? tie.awayClubId : tie.homeClubId
                let prize = cupPrize(roundIndex: cup.currentRoundIndex, of: cup.rounds.count, country: cup.country)
                if let w = clubs.firstIndex(where: { $0.id == winner }) {
                    clubs[w].finances.balance += prize
                    clubs[w].finances.transferBudget += prize / 2
                    if clubs[w].isUserClub { seasonLedger?.prizeMoney += prize }
                }
                if let uid = userClubId {
                    if loser == uid {
                        addNews(
                            headline: "Out of the \(cup.name)",
                            body: "\(clubName(for: winner)) knocked us out in the \(cup.currentRoundName.lowercased()).",
                            category: .general,
                            sender: "\(cup.name)"
                        )
                    } else if winner == uid && cup.currentRoundIndex < cup.rounds.count - 1 {
                        addNews(
                            headline: "Through in the \(cup.name)",
                            body: "Victory over \(clubName(for: loser)) takes us into the next round and earns \(Player.formatCurrency(prize)) in prize money.",
                            category: .general,
                            sender: "\(cup.name)"
                        )
                    }
                }
                // Giant-killing headlines: a club two or more divisions lower
                // knocking out a top-flight side.
                if let w = club(withId: winner), let l = club(withId: loser),
                   l.leagueTier.level == 1, w.leagueTier.level >= 3 {
                    addNews(
                        headline: "Giant-Killing! \(w.name) Stun \(l.name)",
                        body: "\(w.leagueTier.displayName) side \(w.name) have knocked \(l.name) out of the \(cup.name).",
                        category: .general,
                        sender: w.id == userClubId || l.id == userClubId ? "\(cup.name)" : NewsItem.newsDesk
                    )
                }
            }

            if cup.currentRoundIndex >= cup.rounds.count - 1 {
                cup.championClubId = winners.first
                if let champion = winners.first {
                    addNews(
                        headline: "\(clubName(for: champion)) Win the \(cup.name)!",
                        body: "\(clubName(for: champion)) lift the \(cup.name) after victory in the final.",
                        category: .award,
                        sender: champion == userClubId ? "\(cup.name)" : NewsItem.newsDesk
                    )
                    if champion == userClubId {
                        unlockOwnerMilestone(id: "cup_winner")
                        celebrate(.cup, clubId: champion, title: "CUP WINNERS!",
                                  subtitle: "\(cup.name) \(season.year)")
                    }
                }
            } else {
                var entrants = winners
                if cup.currentRoundIndex == 0 { entrants += cup.byeClubIds }
                cup.currentRoundIndex += 1
                drawCupRound(&cup, entrants: entrants)
            }
            domesticCups[index] = cup
        }
    }

    /// Cups the user's club has won this season, for the honours list.
    public var userCupWins: [String] {
        guard let uid = userClubId else { return [] }
        return domesticCups.filter { $0.championClubId == uid }.map { "\($0.name) Winners" }
    }

    // MARK: - International Management

    /// Builds international tournaments from the loaded national teams. Called at
    /// boot and after a data reload.
    public func seedInternationalTournaments() {
        guard !nationalTeams.isEmpty else { return }
        // Older saves hold undated, season-long tournaments: drop them.
        internationalTournaments.removeAll { $0.edition == nil }
        scheduleInternationalEditions(forSeasonStarting: seasonStartYear)
    }

    /// First calendar year of the current season ("2026-27" gives 2026).
    var seasonStartYear: Int { Int(season.year.prefix(4)) ?? 2026 }

    /// Adds the tournaments that kick off during the season starting in
    /// `startYear`. World Cups and EUROs come round every four years, AFCON
    /// every second December, the Asian Cup every four Januaries.
    func scheduleInternationalEditions(forSeasonStarting startYear: Int) {
        guard !nationalTeams.isEmpty else { return }
        for kind in InternationalTournament.Kind.allCases {
            guard let slot = kind.edition(inSeasonStarting: startYear),
                  !internationalTournaments.contains(where: { $0.kind == kind && $0.edition == slot.edition }),
                  let state = InternationalTournamentBuilder.build(kind: kind, edition: slot.edition,
                                                                   startDate: slot.date, from: nationalTeams)
            else { continue }
            internationalTournaments.append(state)
        }
    }

    /// Keeps every unfinished tournament and the latest finished edition of each kind.
    func pruneInternationalTournaments() {
        var keep: [InternationalTournament.State] = []
        for kind in InternationalTournament.Kind.allCases {
            let ofKind = internationalTournaments.filter { $0.kind == kind }
            keep += ofKind.filter { $0.stage != .complete }
            if let latest = ofKind.filter({ $0.stage == .complete }).max(by: { ($0.edition ?? 0) < ($1.edition ?? 0) }) {
                keep.append(latest)
            }
        }
        internationalTournaments = keep
    }

    /// The edition to show for a tournament: the one in progress or next up,
    /// otherwise the latest finished.
    public func currentTournament(of kind: InternationalTournament.Kind) -> InternationalTournament.State? {
        let ofKind = internationalTournaments.filter { $0.kind == kind }
        return ofKind.filter { $0.stage != .complete }.min { ($0.startDate ?? "") < ($1.startDate ?? "") }
            ?? ofKind.max { ($0.edition ?? 0) < ($1.edition ?? 0) }
    }

    public func nationalTeam(withId id: String) -> NationalTeam? {
        nationalTeams.first { $0.id == id }
    }

    /// The national team the user currently manages, if any.
    public var managedNationalTeam: NationalTeam? {
        guard let id = managedNationalTeamId else { return nil }
        return nationalTeam(withId: id)
    }

    /// Takes charge of a national team.
    public func takeOverNationalTeam(id: String) {
        guard nationalTeams.contains(where: { $0.id == id }) else { return }
        managedNationalTeamId = id
        // A new squad: the old selection no longer applies.
        nationalTactics = nil
        if let team = nationalTeam(withId: id) {
            addNews(
                headline: "You Are the New \(team.name) Manager",
                body: "The \(team.name) federation has appointed you as head coach. Your first task is to prepare the squad for international competition.",
                category: .board,
                sender: "\(team.name) Federation"
            )
        }
    }

    public func resignNationalTeam() {
        managedNationalTeamId = nil
        nationalTactics = nil
    }

    /// Plays every international fixture dated on or before the game's date
    /// (or `date`), from national-team strength. Tournaments therefore run on
    /// their real calendar: a January Asian Cup is played out week by week
    /// through the season, while a summer World Cup waits for the break.
    /// International football (tournaments, national-team jobs) is switched
    /// off for now; the code stays so it can come back.
    public static let internationalFootballEnabled = false

    public func advanceInternationalTournaments(through date: String? = nil) {
        guard Self.internationalFootballEnabled else { return }
        seedInternationalTournaments()
        let cutoff = date ?? season.currentDate
        for idx in internationalTournaments.indices {
            var tournament = internationalTournaments[idx]
            guard tournament.stage != .complete else { continue }
            // The nation the user manages plays its own matches.
            let held = gameMode == .manageClub ? managedNationalTeamId : nil
            tournament.play(through: cutoff, holdingTeam: held) { homeId, awayId in
                guard let home = nationalTeam(withId: homeId),
                      let away = nationalTeam(withId: awayId) else { return (0, 0) }
                return Self.simulateNationalScore(home: home.strength, away: away.strength)
            }

            if tournament.kickoffAnnounced != true, tournament.fixtures.contains(where: { $0.isPlayed }) {
                tournament.kickoffAnnounced = true
                addNews(
                    headline: "\(tournament.title) Kicks Off",
                    body: "\(tournament.participantIds.count) nations are in the \(tournament.title), running until \(tournament.endDate.map { Self.longDateText($0) } ?? "the final").",
                    category: .general,
                    sender: NewsItem.newsDesk
                )
            }
            if tournament.stage == .complete, let championId = tournament.championId {
                let name = nationalTeam(withId: championId)?.name ?? championId
                addNews(
                    headline: "\(name) Win the \(tournament.title)!",
                    body: "\(name) are crowned champions of the \(tournament.title).",
                    category: .award,
                    sender: championId == managedNationalTeamId ? "National Federation" : NewsItem.newsDesk
                )
            }
            internationalTournaments[idx] = tournament
        }
    }

    /// "2028-06-14" as "14 June 2028".
    static func longDateText(_ date: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let d = parser.date(from: date) else { return date }
        let out = DateFormatter()
        out.dateFormat = "d MMMM yyyy"
        out.locale = Locale(identifier: "en_GB")
        return out.string(from: d)
    }

    /// A lightweight international scoreline from two teams' strengths.
    static func simulateNationalScore(home: Double, away: Double) -> (Int, Int) {
        let diff = ((home + 2.0) - away) / 8.0   // small home advantage
        var rng = SystemRandomNumberGenerator()
        func goals(for attackDiff: Double) -> Int {
            let expected = max(0.15, 1.25 + attackDiff)
            var goals = 0
            let probability = expected / (expected + 1.0)
            for _ in 0..<6 {
                if Double.random(in: 0...1, using: &rng) < probability * 0.85 { goals += 1 }
            }
            return min(goals, 6)
        }
        return (goals(for: diff), goals(for: -diff))
    }

    /// European-night scoreline approximation from two clubs' starting XIs.
    static func simulateEuropeanScore(home: Club, away: Club) -> (Int, Int) {
        func strength(_ club: Club) -> Double {
            let xi = club.players.sorted { $0.overall > $1.overall }.prefix(11)
            guard !xi.isEmpty else { return 60 }
            return Double(xi.map { $0.overall }.reduce(0, +)) / Double(xi.count)
        }
        let homeStrength = strength(home) + 3.0   // home advantage
        let awayStrength = strength(away)
        let diff = (homeStrength - awayStrength) / 8.0

        var rng = SystemRandomNumberGenerator()
        func goals(for attackDiff: Double) -> Int {
            let base = 1.25 + attackDiff
            let expected = max(0.15, base)
            var goals = 0
            let probability = expected / (expected + 1.0)
            for _ in 0..<6 {
                if Double.random(in: 0...1, using: &rng) < probability * 0.85 { goals += 1 }
            }
            return min(goals, 6)
        }
        return (goals(for: diff), goals(for: -diff))
    }

    /// True once all fixtures are played and the end-of-season processing has run.
    public var isEndOfSeason: Bool {
        season.currentPhase == .endOfSeason
    }
    
    // MARK: - Match Engine Simulation
    
    /// Everything decided before kick-off: rotated lineups, the bans that
    /// are being served, and the engine's settings for the fixture.
    func prepareMatch(_ fixture: Fixture, homeIdx: Int, awayIdx: Int)
        -> (home: Club, away: Club, homeSuspensions: [UUID: Int], awaySuspensions: [UUID: Int], config: MatchEngine.SimulationConfig) {
        var homeClub = clubs[homeIdx]
        var awayClub = clubs[awayIdx]
        // Clubs not managed by the user rotate tired players. (An owner's club
        // is run by the appointed manager, so it rotates too.)
        let userManages: (Club) -> Bool = { $0.isUserClub && self.gameMode == .manageClub }
        let assistantRotates = matchSettings.assistantRotatesTiredPlayers
        if !userManages(homeClub) { homeClub.prepareAIMatchday() } else if assistantRotates && !matchSettings.autoSelectMatchdayLineup { homeClub.rotateTiredStarters() }
        if !userManages(awayClub) { awayClub.prepareAIMatchday() } else if assistantRotates && !matchSettings.autoSelectMatchdayLineup { awayClub.rotateTiredStarters() }
        
        // Snapshot pre-match bans. Players who were already suspended when the
        // fixture kicked off have now served one match of that ban.
        let homeSuspensionsBefore = homeClub.players
            .filter { $0.suspendedMatches > 0 }
            .reduce(into: [UUID: Int]()) { $0[$1.id] = $1.suspendedMatches }
        let awaySuspensionsBefore = awayClub.players
            .filter { $0.suspendedMatches > 0 }
            .reduce(into: [UUID: Int]()) { $0[$1.id] = $1.suspendedMatches }
        
        // European ties are two-legged: a first leg is an ordinary match, a
        // second leg level on aggregate goes to extra time and penalties.
        // Play-off semi-finals work the same way.
        let carry = fixture.europeanFixtureId.flatMap { europeanSecondLegCarry(tieId: $0) }
            ?? playOffSecondLegCarry(fixture)
        let isPlayOffFirstLeg = fixture.cupRound == Self.playOffFirstLeg
        var config = MatchEngine.SimulationConfig(
            // A play-off final is played at a neutral ground.
            neutralVenue: fixture.cupRound == "Final" && fixture.competition.hasSuffix(Self.playOffSuffix),
            matchWeek: fixture.matchWeek,
            competition: fixture.competition,
            date: fixture.date,
            isKnockout: fixture.isCupTie && !isPlayOffFirstLeg
                && (!fixture.isEuropean || fixture.cupRound == "Final" || carry != nil),
            derbyIntensity: rivalry(between: fixture.homeClubId, and: fixture.awayClubId)?.intensity ?? 0,
            homeCoachingMultiplier: coachingMultiplier(for: fixture.homeClubId),
            awayCoachingMultiplier: coachingMultiplier(for: fixture.awayClubId)
        )
        if let carry {
            config.isSecondLeg = true
            config.homeAggregateCarry = carry.home
            config.awayAggregateCarry = carry.away
        }
        // The manager's own side is his: the engine leaves its tactics and
        // substitutions alone unless he has handed subs to his assistant.
        if gameMode == .manageClub, let uid = userClubId, fixture.involves(clubId: uid) {
            config.userClubId = uid
            config.userAutoSubs = matchSettings.autoSubTiming
            config.userAutoSubAggression = matchSettings.autoSubAggression
        }
        if matchSettings.autoSelectMatchdayLineup, !hasMatchOnlyLineup, let uid = config.userClubId {
            if homeClub.id == uid {
                homeClub.tactics = MatchEngine.selectMatchdayLineup(for: homeClub, against: awayClub, isHome: true, config: config)
            } else {
                awayClub.tactics = MatchEngine.selectMatchdayLineup(for: awayClub, against: homeClub, isHome: false, config: config)
            }
        }
        return (homeClub, awayClub, homeSuspensionsBefore, awaySuspensionsBefore, config)
    }

    /// The lineup that will kick off, including an automatic matchday pick.
    func matchdayUserClub(for fixture: Fixture) -> Club? {
        guard matchSettings.autoSelectMatchdayLineup, gameMode == .manageClub, !fixture.isPlayed,
              let uid = userClubId, fixture.involves(clubId: uid), !hasMatchOnlyLineup,
              let home = clubs.firstIndex(where: { $0.id == fixture.homeClubId }),
              let away = clubs.firstIndex(where: { $0.id == fixture.awayClubId }) else { return userClub }
        let prepared = prepareMatch(fixture, homeIdx: home, awayIdx: away)
        return fixture.homeClubId == uid ? prepared.home : prepared.away
    }

    func beginEditingMatchdayLineup(for fixture: Fixture) {
        guard let idx = userClubIndex else { return }
        let preview = matchdayUserClub(for: fixture)
        beginMatchOnlyLineup()
        if let preview { clubs[idx].tactics = preview.tactics }
    }

    /// Kicks off a live match. It is then played a minute at a time with
    /// `advanceLiveMatch(through:)`, and the manager can stop it whenever he
    /// likes to make substitutions or change tactics.
    @discardableResult
    public func beginLiveMatch(fixtureId: UUID) -> Bool {
        guard let fixture = season.fixtures.first(where: { $0.id == fixtureId }), !fixture.isPlayed,
              let homeIdx = clubs.firstIndex(where: { $0.id == fixture.homeClubId }),
              let awayIdx = clubs.firstIndex(where: { $0.id == fixture.awayClubId }) else { return false }
        if liveMatch?.fixtureId == fixtureId { return true }
        var prepared = prepareMatch(fixture, homeIdx: homeIdx, awayIdx: awayIdx)
        // In a live match the manager is asked before an injured player of
        // his is replaced.
        if prepared.config.userClubId != nil { prepared.config.pauseForUserDecisions = matchSettings.stopForInjuries }
        guard let paused = MatchEngine.kickOff(home: &prepared.home, away: &prepared.away, config: prepared.config) else { return false }
        liveMatch = LiveMatchSession(fixtureId: fixtureId, paused: paused, home: prepared.home, away: prepared.away,
                                     homeSuspensions: prepared.homeSuspensions, awaySuspensions: prepared.awaySuspensions,
                                     config: prepared.config)
        // Changes for this match are for this match only; the usual lineup
        // returns afterwards unless the manager keeps it.
        if prepared.config.userClubId != nil {
            beginMatchOnlyLineup()
            syncUserLineupToPitch()
        }
        return true
    }

    /// Plays the live match on to `minute` (or until one of the manager's
    /// players is hurt). Returns false once the match is over; the result is
    /// then written by `simulateFixture(id:)` as for any other match.
    @discardableResult
    public func advanceLiveMatch(through minute: Int) -> Bool {
        guard var session = liveMatch, session.finished == nil,
              let fixture = season.fixtures.first(where: { $0.id == session.fixtureId }), !fixture.isPlayed else { return false }
        var home = session.home
        var away = session.away
        if let uid = userClubId, gameMode == .manageClub, let current = club(withId: uid) {
            if home.id == uid { home.tactics = current.tactics }
            if away.id == uid { away.tactics = current.tactics }
        }
        let (result, paused) = MatchEngine.play(session.paused, until: minute, home: &home, away: &away, config: session.config)
        session.home = home
        session.away = away
        if let paused {
            session.paused = paused
            liveMatch = session
            syncUserLineupToPitch()
            return true
        }
        session.finished = LiveMatchSession.Finished(result: result, home: home, away: away)
        liveMatch = session
        return false
    }

    /// The match so far (or the full result once finished).
    public var liveMatchSoFar: MatchResult? {
        guard let session = liveMatch else { return nil }
        return session.finished?.result ?? session.paused.snapshot
    }

    /// The lineup screen shows who is really on the pitch and on the bench
    /// (after injuries, red cards and changes) during a live match.
    private func syncUserLineupToPitch() {
        guard let session = liveMatch, let uid = session.config.userClubId,
              let userIdx = clubs.firstIndex(where: { $0.id == uid }) else { return }
        let isHome = session.home.id == uid
        clubs[userIdx].tactics.startingXI = isHome ? session.paused.homeOnPitch : session.paused.awayOnPitch
        clubs[userIdx].tactics.substitutes = isHome ? session.paused.homeBenchIds : session.paused.awayBenchIds
    }

    /// Substitutions the user can still make in the live match.
    public var liveSubsRemaining: Int {
        guard let session = liveMatch, let uid = userClubId else { return 0 }
        return session.home.id == uid ? session.paused.homeSubsRemaining : session.paused.awaySubsRemaining
    }

    /// Substitution windows the user has left (changes made at the same
    /// stoppage, or at half-time, count as one).
    public var liveWindowsRemaining: Int {
        guard let session = liveMatch, let uid = userClubId else { return 0 }
        return session.home.id == uid ? session.paused.homeWindowsRemaining : session.paused.awayWindowsRemaining
    }

    /// Simulates a single fixture by delegating to the shared `MatchEngine`, then
    /// writes the updated rosters (fatigue, injuries, stats) and result back into world state.
    ///
    /// Callers holding a fixture inside `season.fixtures` must use
    /// `simulateFixture(id:)` instead of passing `&season.fixtures[i]`: the
    /// post-match hooks (board confidence, owner milestones, news) read
    /// `season`, and reading it while an inout access to it is open is a Swift
    /// exclusivity violation that traps at runtime.
    public func simulateMatch(fixture: inout Fixture) {
        guard !fixture.isPlayed else { return }
        guard let homeIdx = clubs.firstIndex(where: { $0.id == fixture.homeClubId }),
              let awayIdx = clubs.firstIndex(where: { $0.id == fixture.awayClubId }) else {
            return
        }
        
        var homeClub: Club
        var awayClub: Club
        let homeSuspensionsBefore: [UUID: Int]
        let awaySuspensionsBefore: [UUID: Int]
        let result: MatchResult
        if let session = liveMatch, session.fixtureId == fixture.id {
            homeSuspensionsBefore = session.homeSuspensions
            awaySuspensionsBefore = session.awaySuspensions
            if let finished = session.finished {
                // Played to the end live.
                homeClub = finished.home
                awayClub = finished.away
                result = finished.result
            } else {
                // The rest of a live match (skipped to the end): pick up where
                // it stopped, with the manager's current lineup and tactics.
                homeClub = session.home
                awayClub = session.away
                if let uid = userClubId, gameMode == .manageClub, let current = club(withId: uid) {
                    if homeClub.id == uid { homeClub.tactics = current.tactics }
                    if awayClub.id == uid { awayClub.tactics = current.tactics }
                }
                // Nobody is waiting on the touchline any more.
                var config = session.config
                config.pauseForUserDecisions = false
                result = MatchEngine.resume(session.paused, home: &homeClub, away: &awayClub, config: config)
            }
            liveMatch = nil
        } else {
            let prepared = prepareMatch(fixture, homeIdx: homeIdx, awayIdx: awayIdx)
            homeClub = prepared.home
            awayClub = prepared.away
            homeSuspensionsBefore = prepared.homeSuspensions
            awaySuspensionsBefore = prepared.awaySuspensions
            result = MatchEngine.simulateFullMatch(home: &homeClub, away: &awayClub, config: prepared.config)
            if matchSettings.autoSelectMatchdayLineup, !hasMatchOnlyLineup {
                if prepared.config.userClubId == homeClub.id { homeClub.tactics = clubs[homeIdx].tactics }
                if prepared.config.userClubId == awayClub.id { awayClub.tactics = clubs[awayIdx].tactics }
            }
        }
        
        for pIdx in homeClub.players.indices {
            let id = homeClub.players[pIdx].id
            if let before = homeSuspensionsBefore[id] {
                homeClub.players[pIdx].suspendedMatches = max(0, min(homeClub.players[pIdx].suspendedMatches, before - 1))
            }
        }
        for pIdx in awayClub.players.indices {
            let id = awayClub.players[pIdx].id
            if let before = awaySuspensionsBefore[id] {
                awayClub.players[pIdx].suspendedMatches = max(0, min(awayClub.players[pIdx].suspendedMatches, before - 1))
            }
        }
        
        // Archive results the user did not take part in in compact form; keep
        // the full commentary and ratings only for the user's own matches.
        let userInvolved = userClubId.map { fixture.involves(clubId: $0) } ?? false
        let archived = userInvolved ? result : result.compactedForArchive()
        // Other clubs only ever need their recent form, so they keep the last
        // six results as scores. (Every club kept a full copy of every
        // result, a third of the save file.)
        if !homeClub.isUserClub,
           let i = homeClub.seasonResults.lastIndex(where: { $0.id == result.id }) {
            homeClub.seasonResults[i] = result.compactedForArchive()
            if homeClub.seasonResults.count > 6 { homeClub.seasonResults.removeFirst(homeClub.seasonResults.count - 6) }
        }
        if !awayClub.isUserClub,
           let i = awayClub.seasonResults.lastIndex(where: { $0.id == result.id }) {
            awayClub.seasonResults[i] = result.compactedForArchive()
            if awayClub.seasonResults.count > 6 { awayClub.seasonResults.removeFirst(awayClub.seasonResults.count - 6) }
        }

        // The medical report on the manager's players hurt in the match.
        if let uid = userClubId, fixture.involves(clubId: uid) {
            let before = homeClub.id == uid ? clubs[homeIdx] : clubs[awayIdx]
            let after = homeClub.id == uid ? homeClub : awayClub
            for player in after.players {
                guard let injury = player.injury,
                      before.players.first(where: { $0.id == player.id })?.injury == nil else { continue }
                addNews(
                    headline: "\(player.fullName): \(injury.type.displayName)",
                    body: "\(player.fullName) picked up a \(injury.type.displayName.lowercased()) against \(clubName(for: homeClub.id == uid ? awayClub.id : homeClub.id)). The medical team expect him to be out for \(injury.timeOutText).",
                    category: .general,
                    sender: "Medical Department"
                )
            }
        }

        clubs[homeIdx] = homeClub
        clubs[awayIdx] = awayClub

        fixture.isPlayed = true
        fixture.result = archived

        if let uid = userClubId, fixture.involves(clubId: uid),
           let derby = rivalry(between: fixture.homeClubId, and: fixture.awayClubId) {
            applyDerbyAftermath(derby, result: result, userWasHome: fixture.homeClubId == uid)
        }

        if fixture.involves(clubId: userClubId ?? UUID()) {
            if gameMode == .createClub {
                updateOwnerMatchPerformance(after: result, userWasHome: fixture.homeClubId == userClubId)
            } else {
                updateBoardConfidence(after: result, userWasHome: fixture.homeClubId == userClubId)
            }
        }
    }
    
    /// Simulates the fixture with the given id in place. Works on a local copy
    /// so no exclusive access to `season` is held while the match hooks run.
    /// Returns `true` when the fixture was found and is now played.
    @discardableResult
    public func simulateFixture(id: UUID) -> Bool {
        guard let idx = season.fixtures.firstIndex(where: { $0.id == id }) else { return false }
        var fixture = season.fixtures[idx]
        guard !fixture.isPlayed else { return true }
        simulateMatch(fixture: &fixture)
        // Re-resolve the index: the hooks must not reorder fixtures, but never
        // write through a stale index if they ever do.
        if idx < season.fixtures.count, season.fixtures[idx].id == id {
            season.fixtures[idx] = fixture
        } else if let freshIdx = season.fixtures.firstIndex(where: { $0.id == id }) {
            season.fixtures[freshIdx] = fixture
        }
        // A one-off lineup was only for this match.
        if fixture.isPlayed, let uid = userClubId, fixture.involves(clubId: uid) {
            if matchOnlyLineupBackup != nil { restoreUsualLineup() }
            checkMatchAchievements(fixture)
            checkClubRecords(fixture)
            payWinBonusIfDue(fixture)
        }
        return fixture.isPlayed
    }

    // MARK: - Transfer Windows

    /// The in-game month (1-12), from the "yyyy-MM-dd" calendar date.
    private var currentMonth: Int {
        let parts = season.currentDate.split(separator: "-")
        return parts.count >= 2 ? Int(parts[1]) ?? 8 : 8
    }

    /// Club-to-club transfers happen in the summer window (June to the end of
    /// August) and the January window. Free agents can be signed at any time.
    public var isTransferWindowOpen: Bool {
        [6, 7, 8, 1].contains(currentMonth)
    }

    /// A short description for the transfer screens.
    public var transferWindowStatus: String {
        switch currentMonth {
        case 6, 7, 8: return "Summer window open until 1 September"
        case 1: return "January window open until 1 February"
        case 9, 10, 11, 12: return "Window closed. Reopens 1 January"
        default: return "Window closed. Reopens in the summer"
        }
    }

    // MARK: - User Transfer Bidding
    
    /// Opens a transfer negotiation by submitting an opening bid from the user's
    /// club for a player at another club, or signing a free agent. Bids are no
    /// longer resolved instantly: they are logged as live offers and the selling
    /// club responds (accept / reject / counter) over the following weeks.
    @discardableResult
    public func submitTransferBid(
        playerId: UUID,
        fee: Int,
        offeredWage: Int,
        contractYears: Int = 3
    ) -> TransferOffer? {
        guard let userClubId = userClubId,
              let buyerIdx = clubs.firstIndex(where: { $0.id == userClubId }) else {
            return nil
        }

        // Resolve the target player and their current club (nil = free agent).
        var sellerIdx: Int? = nil
        var targetPlayer: Player? = nil
        for (idx, club) in clubs.enumerated() where !club.isUserClub {
            if let p = club.player(withId: playerId) {
                sellerIdx = idx
                targetPlayer = p
                break
            }
        }
        let isFreeAgent: Bool
        if targetPlayer == nil, let freeP = freeAgents.first(where: { $0.id == playerId }) {
            targetPlayer = freeP
            isFreeAgent = true
        } else {
            isFreeAgent = false
        }

        guard let player = targetPlayer, !player.isOnLoan else { return nil }
        guard offeredWage > 0, contractYears > 0 else { return nil }
        // Players under contract can only move while a window is open.
        guard isFreeAgent || isTransferWindowOpen else { return nil }

        // Free agents never command a fee; enforce that here so the UI or a
        // stale slider value cannot charge the buyer for an unattached player.
        let resolvedFee = isFreeAgent ? 0 : max(0, fee)

        let buyer = clubs[buyerIdx]
        // Clubs will not strengthen their fiercest rivals.
        if let sellerIdx, let derby = rivalry(between: buyer.id, and: clubs[sellerIdx].id) {
            var refused = TransferOffer(
                playerId: playerId,
                fromClubId: clubs[sellerIdx].id,
                toClubId: userClubId,
                fee: resolvedFee,
                isLoan: false,
                status: .rejected,
                offeredWage: offeredWage,
                contractYears: contractYears,
                askingPrice: 0,
                isIncoming: false,
                createdDate: season.currentDate,
                weeksUntilResponse: 0
            )
            refused.status = .rejected
            pendingTransferOffers.append(refused)
            addNews(
                headline: "\(clubs[sellerIdx].name) Refuse to Deal",
                body: "\(clubs[sellerIdx].name) will not sell \(player.fullName) to their \(derby.name) rivals at any price.",
                category: .transfer,
                sender: clubs[sellerIdx].name
            )
            return refused
        }
        let askingPrice = sellingValuation(for: player, at: sellerIdx.map { clubs[$0] }, buyerReputation: buyer.reputation)

        var offer = TransferOffer(
            playerId: playerId,
            fromClubId: sellerIdx.map { clubs[$0].id } ?? UUID(),
            toClubId: userClubId,
            fee: resolvedFee,
            isLoan: false,
            status: .pending,
            offeredWage: offeredWage,
            contractYears: contractYears,
            askingPrice: askingPrice,
            isIncoming: false,
            createdDate: season.currentDate,
            weeksUntilResponse: isFreeAgent ? 0 : 1
        )

        // Budget sanity: the buyer can never commit more than the bank or the
        // board's wage structure allows.
        let canAffordFee = isFreeAgent || resolvedFee <= buyer.finances.transferBudget
        let projectedWageBill = buyer.totalWeeklyWageBill + offeredWage
        let canAffordWage = projectedWageBill <= wageCeiling(for: buyer)
        if !canAffordFee || !canAffordWage {
            offer.status = .rejected
            pendingTransferOffers.append(offer)
            let reason = !canAffordFee
                ? "The transfer fee exceeded \(buyer.name)'s budget. Raise funds before bidding again."
                : "The proposed wage of \(Player.formatCurrency(offeredWage))/w would take the weekly wage bill to \(Player.formatCurrency(projectedWageBill))/w, far beyond the board's recommended \(Player.formatCurrency(buyer.finances.wageBudget))/w. They will not sanction it."
            addNews(
                headline: "Bid for \(player.fullName) Rejected",
                body: reason,
                category: .transfer,
                sender: "Club Secretary"
            )
            return offer
        }

        // Free agents skip the selling-club stage; resolveOffer sends the
        // sellerless pending offer straight to personal terms.
        pendingTransferOffers.append(offer)
        addNews(
            headline: "Bid Submitted for \(player.fullName)",
            body: "You have tabled a \(Player.formatCurrency(resolvedFee)) bid\(isFreeAgent ? "" : " to \(sellerIdx.map { clubs[$0].name } ?? "the club")") for \(player.fullName). Expect a response in the coming days.",
            category: .transfer,
            sender: "Director of Football",
            transferOfferId: offer.id
        )
        return offer
    }

    /// Realistic asking price: market value adjusted for the seller's need and
    /// reputation, with a premium for players on long, secure contracts.
    func sellingValuation(for player: Player, at seller: Club?, buyerReputation: Int) -> Int {
        var value = Double(player.value)
        // Long contracts mean the seller can demand a premium; expiring deals a discount.
        let years = Double(player.contract?.yearsRemaining ?? 1)
        value *= 1.0 + max(0, min(3, years - 1)) * 0.12
        // A big club selling to a smaller one digs in for more.
        if let seller = seller {
            let gap = Double(seller.reputation - buyerReputation)
            value *= 1.0 + max(-0.15, min(0.35, gap / 100.0))
        }
        // Young high-potential players carry a scarcity premium.
        if player.age <= 23, player.potential - player.overall >= 8 {
            value *= 1.15
        }
        return max(10_000, Int(value))
    }

    /// The wage a player will demand to sign, scaling with their valuation and the
    /// gap between the buyer and seller's stature.
    func wageDemand(for player: Player, buyer: Club, seller: Club?) -> Int {
        let base = max(player.wage, player.value / 250)
        var demand = Double(base)
        if let seller = seller, seller.reputation > buyer.reputation {
            demand *= 1.0 + min(0.5, Double(seller.reputation - buyer.reputation) / 120.0)
        }
        demand *= Double.random(in: 0.95...1.15)
        return max(500, Int(demand))
    }

    // MARK: - Contract Renewals

    /// The wage a player would expect when extending at the user's club. Kept
    /// deterministic so the figure shown in the renewal screen is the figure the
    /// player actually judges the offer against.
    public func contractRenewalWage(for player: Player) -> Int {
        let reputation = userClub?.reputation ?? 70
        let base = max(1_000, max(player.wage, player.value / 250))
        var multiplier = 1.08
        if player.age <= 23, player.potential - player.overall >= 8 {
            multiplier += 0.07
        }
        if player.age >= 33 {
            multiplier -= 0.04
        }
        if (player.contract?.yearsRemaining ?? 1) <= 1 {
            multiplier += 0.03
        }
        multiplier += Double(max(0, reputation - 60)) / 500.0
        return max(500, Int(Double(base) * multiplier))
    }

    /// Offers a new contract to a player already at the user's club. He has
    /// an asking wage but will come down to a limit that depends on his
    /// mood, his place in the squad, his age and the length of the deal. Offer
    /// less and he counters (coming down a little each round) until he tires
    /// of the talks. A signing-on bonus counts towards what he gets.
    @discardableResult
    public func renewContract(playerId: UUID, wage: Int, years: Int, signingBonus: Int = 0) -> ContractRenewalResult {
        guard let clubIdx = clubs.firstIndex(where: { $0.isUserClub }) else {
            return ContractRenewalResult(accepted: false, message: "You do not currently control a club.")
        }
        guard let playerIdx = clubs[clubIdx].players.firstIndex(where: { $0.id == playerId }),
              let currentContract = clubs[clubIdx].players[playerIdx].contract else {
            return ContractRenewalResult(accepted: false, message: "This player is not under contract at your club.")
        }
        guard wage > 0, years >= 1, years <= 5 else {
            return ContractRenewalResult(accepted: false, message: "Choose a positive wage and a contract length between one and five years.")
        }
        if let loan = clubs[clubIdx].players[playerIdx].loan {
            return ContractRenewalResult(accepted: false, message: "He is on loan from \(loan.parentClubName); only they can offer him a new contract.")
        }

        let player = clubs[clubIdx].players[playerIdx]
        let demand = contractRenewalWage(for: player)
        let bonus = max(0, signingBonus)
        let floor = Double(demand) * renewalFlexibility(player: player, club: clubs[clubIdx], years: years)
        let effective = Double(wage) + Double(bonus) / Double(52 * years) * 0.85
        if effective < floor {
            var rounds = (renewalRounds[playerId] ?? 0) + 1
            if effective < floor * 0.7 { rounds += 1 }
            renewalRounds[playerId] = rounds
            // He meets you part of the way: from his last figure he comes
            // about 40% of the way towards your offer (much less for a
            // lowball), never below what he would really sign for, and
            // never back up.
            let lastAsk = Double(renewalCounters[playerId] ?? demand)
            let give = effective < floor * 0.7 ? 0.1 : 0.4
            let ask = max(floor, lastAsk - (lastAsk - effective) * give)
            let counter = min(Int(lastAsk), max(wage + 1, Self.roundedWage(Int(ask.rounded(.up)))))
            renewalCounters[playerId] = counter
            if rounds > 7 {
                return ContractRenewalResult(
                    accepted: false,
                    demandedWage: counter,
                    message: "\(player.fullName) is tired of haggling. His final word: \(Player.formatCurrency(counter))/w over \(years) year\(years == 1 ? "" : "s"), or he will run his contract down."
                )
            }
            return ContractRenewalResult(
                accepted: false,
                demandedWage: counter,
                message: "\(player.fullName) turns down \(Player.formatCurrency(wage))/w. He would sign for \(Player.formatCurrency(counter))/w over \(years) year\(years == 1 ? "" : "s")."
            )
        }
        renewalRounds[playerId] = nil
        renewalCounters[playerId] = nil
        if bonus > 0 {
            clubs[clubIdx].finances.balance -= bonus
            seasonLedger?.wages += bonus
        }

        // The wage budget is the board's guidance, not a wall: keeping your
        // own players is always the manager's call.
        let projectedBill = clubs[clubIdx].totalWeeklyWageBill - currentContract.wage + wage
        let recommended = clubs[clubIdx].finances.wageBudget
        let budgetNote = projectedBill > recommended
            ? " The wage bill is now \(Player.formatCurrency(projectedBill))/w, above the board's recommended \(Player.formatCurrency(recommended))/w."
            : ""

        var updated = currentContract
        updated.wage = wage
        updated.yearsRemaining = years
        updated.signingDate = season.currentDate
        clubs[clubIdx].players[playerIdx].contract = updated
        clubs[clubIdx].finances.currentWageBill = clubs[clubIdx].totalWeeklyWageBill

        addNews(
            headline: "\(player.fullName) Signs New Contract",
            body: "\(player.fullName) has committed to \(clubs[clubIdx].name) on a \(years)-year deal worth \(Player.formatCurrency(wage))/w\(bonus > 0 ? " plus a \(Player.formatCurrency(bonus)) signing-on bonus" : "").",
            category: .contractExpiry,
            sender: "Director of Football"
        )

        return ContractRenewalResult(
            accepted: true,
            message: "\(player.fullName) has signed a new \(years)-year contract at \(Player.formatCurrency(wage))/w\(bonus > 0 ? " plus a \(Player.formatCurrency(bonus)) signing-on bonus" : "").\(budgetNote)"
        )
    }

    /// The wage budget is a recommendation for the user's club, set by its
    /// stature and income. The board only steps in when a new signing would
    /// take the bill half as high again; AI clubs stick to the figure.
    func wageCeiling(for club: Club) -> Int {
        club.isUserClub ? Int(Double(club.finances.wageBudget) * 1.5) : club.finances.wageBudget
    }

    /// Resolves every live transfer negotiation one step: selling clubs evaluate
    /// bids (accept / reject / counter), players decide personal terms, and stances
    /// are surfaced to the inbox. Runs each week from `advanceWeek`.
    public func processTransferNegotiations() {
        guard let userClubId = userClubId else {
            // Even without a user club, age out stale offers.
            pendingTransferOffers.removeAll { !$0.isLive && $0.weeksUntilResponse <= 0 }
            return
        }

        for idx in pendingTransferOffers.indices {
            guard pendingTransferOffers[idx].isLive else { continue }

            // AI bids for the user's players wait on the user. Give them a
            // deadline so an ignored bid does not stay actionable forever.
            if pendingTransferOffers[idx].isIncoming {
                if pendingTransferOffers[idx].weeksUntilResponse > 0 {
                    pendingTransferOffers[idx].weeksUntilResponse -= 1
                }
                if pendingTransferOffers[idx].weeksUntilResponse <= 0 {
                    let offer = pendingTransferOffers[idx]
                    pendingTransferOffers[idx].status = .withdrawn
                    pendingTransferOffers[idx].weeksUntilResponse = 0
                    markOfferMailRead(offerId: offer.id)
                    addNews(
                        headline: "\(club(withId: offer.toClubId)?.name ?? "The bidding club") Withdraw Their Bid",
                        body: offer.isLoan
                            ? "With no response, the loan request for \(playerName(for: offer.playerId)) has lapsed."
                            : "With no response from the club, the \(Player.formatCurrency(offer.fee)) offer for \(playerName(for: offer.playerId)) has been withdrawn.",
                        category: .transfer,
                        sender: "Director of Football"
                    )
                }
                continue
            }

            // Once the user has a counter or wage demand to answer, the clock is
            // on them. Do not let the counterparty auto-resolve the offer on the
            // user's behalf; expire it if they never respond.
            let status = pendingTransferOffers[idx].status
            if status == .counterOffer || status == .personalTerms {
                if pendingTransferOffers[idx].weeksUntilResponse > 0 {
                    pendingTransferOffers[idx].weeksUntilResponse -= 1
                }
                if pendingTransferOffers[idx].weeksUntilResponse <= 0 {
                    expireAwaitingUserDecision(at: idx)
                }
                continue
            }

            // Count down the response timer.
            if pendingTransferOffers[idx].weeksUntilResponse > 0 {
                pendingTransferOffers[idx].weeksUntilResponse -= 1
                continue
            }

            resolveOffer(at: idx, userClubId: userClubId)
        }

        // Drop offers that have been dead for a while to stop the array growing forever.
        pruneResolvedOffers()
    }

    /// Drops an offer whose counter or wage demand was left unanswered by the
    /// user. Without this, stale offers linger forever and can auto-complete.
    private func expireAwaitingUserDecision(at idx: Int) {
        var offer = pendingTransferOffers[idx]
        let name = playerName(for: offer.playerId)
        let clubName = club(withId: offer.fromClubId)?.name ?? "The selling club"
        let wasCounter = offer.status == .counterOffer
        offer.status = .withdrawn
        offer.counterFee = nil
        offer.demandedWage = nil
        offer.weeksUntilResponse = 0
        pendingTransferOffers[idx] = offer

        addNews(
            headline: wasCounter ? "Counter-Offer Expires" : "Contract Talks Expire",
            body: wasCounter
                ? "\(clubName)'s counter-offer for \(name) has expired. Submit a fresh bid if you still want to sign the player."
                : "\(name)'s wage demands went unanswered and talks have ended. You can reopen negotiations from the transfer list.",
            category: .transfer,
            sender: "Director of Football",
            transferOfferId: offer.id
        )
    }

    /// Resolves a single live offer based on its current status.
    private func resolveOffer(at idx: Int, userClubId: UUID) {
        var offer = pendingTransferOffers[idx]
        guard let (player, _) = player(withId: offer.playerId) else {
            offer.status = .withdrawn
            pendingTransferOffers[idx] = offer
            return
        }

        // Incoming bids (AI club bidding for a user player) are handled elsewhere;
        // here we only auto-resolve outgoing user bids and free-agent terms.
        guard !offer.isIncoming else { return }

        switch offer.status {
        case .personalTerms:
            resolvePersonalTerms(at: idx, player: player, userClubId: userClubId)
        case .pending, .accepted:
            // Free agents have no selling club; a revised wage offer must go
            // back to the player rather than through the club-fee ladder.
            if clubs.contains(where: { $0.id == offer.fromClubId }) {
                resolveClubFee(at: idx, player: player, userClubId: userClubId)
            } else {
                resolvePersonalTerms(at: idx, player: player, userClubId: userClubId)
            }
        case .counterOffer:
            resolveClubFee(at: idx, player: player, userClubId: userClubId)
        default:
            break
        }
    }

    /// The selling club evaluates the (possibly countered) fee.
    private func resolveClubFee(at idx: Int, player: Player, userClubId: UUID) {
        var offer = pendingTransferOffers[idx]
        guard let buyerIdx = clubs.firstIndex(where: { $0.id == userClubId }),
              let sellerIdx = clubs.firstIndex(where: { $0.id == offer.fromClubId }) else {
            offer.status = .rejected
            pendingTransferOffers[idx] = offer
            return
        }
        let seller = clubs[sellerIdx]
        let bid = Double(offer.fee)
        let asking = Double(offer.askingPrice)

        // Ladder of tolerance: met-or-beat is done; near-misses get a counter or a
        // random accept; lowballs are rejected.
        if bid >= asking {
            if completeSigning(player: player, buyerIdx: buyerIdx, sellerIdx: sellerIdx, fee: offer.fee, wage: offer.offeredWage ?? player.wage, years: offer.contractYears ?? 3) {
                offer.status = .completed
                completeOfferMessage(offer, player: player)
            } else {
                offer.status = .rejected
                addNews(
                    headline: "Deal for \(player.fullName) Collapses",
                    body: "\(clubs[buyerIdx].name) could no longer afford the agreed fee and wages, so the transfer has fallen through.",
                    category: .transfer,
                    sender: "Director of Football"
                )
            }
            pendingTransferOffers[idx] = offer
            return
        }

        if bid >= asking * 0.9 {
            // Close enough — the club usually accepts, sometimes counters once more.
            if offer.negotiationRound >= 2 || Double.random(in: 0...1) < 0.6 {
                if completeSigning(player: player, buyerIdx: buyerIdx, sellerIdx: sellerIdx, fee: offer.fee, wage: offer.offeredWage ?? player.wage, years: offer.contractYears ?? 3) {
                    offer.status = .completed
                    completeOfferMessage(offer, player: player)
                } else {
                    offer.status = .rejected
                    addNews(
                        headline: "Deal for \(player.fullName) Collapses",
                        body: "\(clubs[buyerIdx].name) could no longer afford the agreed fee and wages, so the transfer has fallen through.",
                        category: .transfer,
                        sender: "Director of Football"
                    )
                }
                pendingTransferOffers[idx] = offer
            } else {
                // issueCounter persists the updated offer itself.
                issueCounter(at: idx, offer: offer, seller: seller, player: player)
            }
            return
        }

        if bid >= asking * 0.7 {
            // Meaningfully short — counter with a figure they can accept.
            // issueCounter writes the counter state into the array; do not
            // overwrite it with the stale local copy afterwards.
            issueCounter(at: idx, offer: offer, seller: seller, player: player)
            return
        }

        // Lowball rejection.
        offer.status = .rejected
        pendingTransferOffers[idx] = offer
        addNews(
            headline: "Bid for \(player.fullName) Rejected",
            body: "\(seller.name) dismissed your \(Player.formatCurrency(offer.fee)) bid as far below their valuation of \(Player.formatCurrency(offer.askingPrice)).",
            category: .transfer,
            sender: "Director of Football"
        )
    }

    /// Issues a counter-offer from the selling club, routed to the inbox.
    private func issueCounter(at idx: Int, offer: TransferOffer, seller: Club, player: Player) {
        var offer = offer
        let target: Double
        if let existing = offer.counterFee {
            // Converge toward the asking price from the last counter.
            target = Double(existing) + (Double(offer.askingPrice) - Double(existing)) * 0.5
        } else {
            target = Double(offer.askingPrice)
        }
        offer.counterFee = Int(max(Double(offer.fee), target))
        offer.negotiationRound += 1
        offer.status = .counterOffer
        offer.weeksUntilResponse = 2
        pendingTransferOffers[idx] = offer

        addNews(
            headline: "\(seller.name) Counter Your Bid for \(player.fullName)",
            body: "\(seller.name) want \(Player.formatCurrency(offer.counterFee ?? offer.askingPrice)) for \(player.fullName) — your offer was \(Player.formatCurrency(offer.fee)). Accept, reject, or raise your bid.",
            category: .transfer,
            sender: seller.name,
            transferOfferId: offer.id
        )
    }

    /// A free agent (or a club-approved move) settles personal terms with the player.
    private func resolvePersonalTerms(at idx: Int, player: Player, userClubId: UUID) {
        var offer = pendingTransferOffers[idx]
        guard let buyerIdx = clubs.firstIndex(where: { $0.id == userClubId }) else {
            offer.status = .rejected
            pendingTransferOffers[idx] = offer
            return
        }
        let buyer = clubs[buyerIdx]
        let sellerIdx = clubs.firstIndex(where: { $0.id == offer.fromClubId })
        // Honour a demand that has already been stated to the user. Re-rolling
        // it each week made meeting the displayed figure feel arbitrary.
        let demand = offer.demandedWage ?? wageDemand(for: player, buyer: buyer, seller: sellerIdx.map { clubs[$0] })

        if let offered = offer.offeredWage, offered >= demand {
            if completeSigning(player: player, buyerIdx: buyerIdx, sellerIdx: sellerIdx, fee: offer.fee, wage: offered, years: offer.contractYears ?? 3) {
                offer.status = .completed
                offer.demandedWage = nil
                completeOfferMessage(offer, player: player)
            } else {
                offer.status = .rejected
                addNews(
                    headline: "Deal for \(player.fullName) Collapses",
                    body: "\(buyer.name) could not fit the agreed wage into the club's budget, so the move has fallen through.",
                    category: .transfer,
                    sender: "Director of Football"
                )
            }
            pendingTransferOffers[idx] = offer
            return
        }

        // Player wants more — allow one counter, then accept or walk away.
        if offer.negotiationRound < 1 {
            offer.demandedWage = demand
            offer.negotiationRound += 1
            offer.status = .personalTerms
            offer.weeksUntilResponse = 2
            pendingTransferOffers[idx] = offer
            addNews(
                headline: "\(player.fullName)'s Agent Responds",
                body: "\(player.fullName) is holding out for \(Player.formatCurrency(demand))/w. He is currently being offered \(Player.formatCurrency(offer.offeredWage ?? 0))/w. Meet the demand or withdraw.",
                category: .transfer,
                sender: "Agent of \(player.fullName)",
                transferOfferId: offer.id
            )
        } else {
            offer.status = .withdrawn
            pendingTransferOffers[idx] = offer
            addNews(
                headline: "\(player.fullName) Talks Collapse",
                body: "\(player.fullName) rejected your personal terms and the deal is off.",
                category: .transfer,
                sender: "Director of Football"
            )
        }
    }

    /// Records a completed signing in the inbox (user-facing).
    private func completeOfferMessage(_ offer: TransferOffer, player: Player) {
        guard let buyer = club(withId: offer.toClubId) else { return }
        addNews(
            headline: "\(player.fullName) Signs for \(buyer.name)!",
            body: "The deal is done — \(player.fullName) joins \(buyer.name) for \(Player.formatCurrency(offer.fee)).",
            category: .transfer,
            sender: "Director of Football"
        )
    }

    /// Removes resolved and ignored offers that have gone stale.
    private func pruneResolvedOffers() {
        pendingTransferOffers.removeAll { offer in
            if offer.isLive { return false }
            // Keep finished offers visible for a few weeks, then forget them.
            return offer.weeksUntilResponse <= -3
        }
        // Tick down the display timer for dead offers.
        for idx in pendingTransferOffers.indices where !pendingTransferOffers[idx].isLive {
            pendingTransferOffers[idx].weeksUntilResponse -= 1
        }
    }

    // MARK: - User Actions on Offers

    /// The user accepts a counter-offer from a selling club, continuing the deal.
    /// The user accepts the selling club's counter-offer. The club named the
    /// price, so the deal completes immediately (budgets permitting).
    @discardableResult
    public func acceptCounter(offerId: UUID) -> Bool {
        guard let idx = pendingTransferOffers.firstIndex(where: { $0.id == offerId }) else { return false }
        var offer = pendingTransferOffers[idx]
        guard offer.isLive, !offer.isIncoming, let counter = offer.counterFee,
              let player = player(withId: offer.playerId)?.player,
              let buyerIdx = clubs.firstIndex(where: { $0.id == userClubId }) else { return false }
        offer.fee = counter
        offer.weeksUntilResponse = 0
        markOfferMailRead(offerId: offerId)
        let sellerIdx = clubs.firstIndex(where: { $0.id == offer.fromClubId })
        let completed = completeSigning(player: player, buyerIdx: buyerIdx, sellerIdx: sellerIdx,
                                        fee: counter, wage: offer.offeredWage ?? player.wage,
                                        years: offer.contractYears ?? 3)
        offer.status = completed ? .completed : .rejected
        pendingTransferOffers[idx] = offer
        if completed {
            clubs[buyerIdx].ensureTacticalIntegrity()
            completeOfferMessage(offer, player: player)
        } else {
            addNews(
                headline: "Deal for \(player.fullName) Collapses",
                body: "The \(Player.formatCurrency(counter)) fee or his wage no longer fits your budgets (transfer budget \(Player.formatCurrency(clubs[buyerIdx].finances.transferBudget)), wage headroom \(Player.formatCurrency(max(0, clubs[buyerIdx].finances.wageBudget - clubs[buyerIdx].totalWeeklyWageBill)))/w).",
                category: .transfer,
                sender: "Director of Football"
            )
        }
        return completed
    }

    /// The user walks away from an offer.
    public func withdrawOffer(offerId: UUID) {
        guard let idx = pendingTransferOffers.firstIndex(where: { $0.id == offerId }),
              pendingTransferOffers[idx].isLive else { return }
        pendingTransferOffers[idx].status = .withdrawn
        pendingTransferOffers[idx].weeksUntilResponse = 0
        markOfferMailRead(offerId: offerId)
        addNews(
            headline: "Offer Withdrawn",
            body: "You have withdrawn your bid for \(playerName(for: pendingTransferOffers[idx].playerId)).",
            category: .transfer,
            sender: "Director of Football"
        )
    }

    /// The user raises their bid on an outgoing offer (renegotiation from the inbox).
    public func bumpOffer(offerId: UUID, newFee: Int, newWage: Int? = nil) {
        guard let idx = pendingTransferOffers.firstIndex(where: { $0.id == offerId }),
              pendingTransferOffers[idx].isLive, !pendingTransferOffers[idx].isIncoming else { return }
        var offer = pendingTransferOffers[idx]
        // Meeting a player's stated wage demand settles personal terms on the
        // spot (it used to wait a week and could still fall through).
        if offer.status == .personalTerms, let demand = offer.demandedWage, let w = newWage, w >= demand,
           let uid = userClubId, let player = player(withId: offer.playerId)?.player {
            pendingTransferOffers[idx].offeredWage = w
            markOfferMailRead(offerId: offerId)
            resolvePersonalTerms(at: idx, player: player, userClubId: uid)
            if pendingTransferOffers[idx].status == .completed,
               let buyerIdx = clubs.firstIndex(where: { $0.id == uid }) {
                clubs[buyerIdx].ensureTacticalIntegrity()
            }
            return
        }
        // Free agents never carry a fee, and a revised bid can never be negative.
        let isFreeAgentDeal = !clubs.contains(where: { $0.id == offer.fromClubId })
        offer.fee = isFreeAgentDeal ? 0 : max(0, newFee)
        if let w = newWage { offer.offeredWage = w }
        // A revised offer is a normal response from the user. Free agents have
        // no selling club, so resolveOffer routes it back to personal terms.
        offer.status = .pending
        offer.weeksUntilResponse = 1
        pendingTransferOffers[idx] = offer
        markOfferMailRead(offerId: offerId)

        addNews(
            headline: "Revised Bid Submitted",
            body: "You have raised your bid for \(playerName(for: offer.playerId)) to \(Player.formatCurrency(offer.fee)).",
            category: .transfer,
            sender: "Director of Football"
        )
    }

    /// The user accepts an AI club's incoming bid for one of their players.
    public func acceptIncomingOffer(offerId: UUID) {
        guard let idx = pendingTransferOffers.firstIndex(where: { $0.id == offerId }) else { return }
        var offer = pendingTransferOffers[idx]
        guard offer.isIncoming, offer.isLive,
              let (player, _) = player(withId: offer.playerId),
              let sellerIdx = clubs.firstIndex(where: { $0.id == userClubId }),
              let buyerIdx = clubs.firstIndex(where: { $0.id == offer.toClubId }) else { return }

        let wasKeyPlayer = !offer.isLoan
            && Double(player.overall) >= clubs[sellerIdx].startingXIAverageOverall - 1
        let completed: Bool
        if offer.isLoan {
            let share = player.wage > 0 ? min(100, (offer.offeredWage ?? player.wage) * 100 / player.wage) : 100
            completed = completeAgreedLoan(playerId: player.id, fromIdx: sellerIdx, toIdx: buyerIdx, wageShare: share)
        } else {
            completed = completeSigning(player: player, buyerIdx: buyerIdx, sellerIdx: sellerIdx, fee: offer.fee, wage: offer.offeredWage ?? player.wage, years: offer.contractYears ?? 3)
        }
        if completed && wasKeyPlayer && gameMode == .createClub {
            // Selling a first-team regular costs the owner goodwill.
            let rival = rivalry(between: clubs[sellerIdx].id, and: offer.toClubId) != nil
            adjustFans(-((rival ? 12 : 5)))
            owner.managerSatisfaction = max(0, owner.managerSatisfaction - managerMoodChange(6))
            addNews(
                headline: "Fans Unhappy at \(player.fullName) Sale",
                body: "Supporters have reacted angrily to the sale of \(player.fullName) to \(club(withId: offer.toClubId)?.name ?? "another club"), and \(clubs[sellerIdx].manager) is frustrated to lose a first-team regular.",
                category: .board,
                sender: "Supporters' Trust"
            )
        }
        if completed {
            offer.status = .completed
            offer.weeksUntilResponse = 0
            pendingTransferOffers[idx] = offer
            markOfferMailRead(offerId: offerId)
        } else {
            offer.status = .rejected
            offer.weeksUntilResponse = 0
            pendingTransferOffers[idx] = offer
            markOfferMailRead(offerId: offerId)
            addNews(
                headline: "Transfer Collapses",
                body: "\(club(withId: offer.toClubId)?.name ?? "The buyer") could no longer complete the signing of \(player.fullName), so the deal is off.",
                category: .transfer,
                sender: "Director of Football"
            )
        }
    }

    /// The user rejects an AI club's incoming bid.
    public func rejectIncomingOffer(offerId: UUID) {
        guard let idx = pendingTransferOffers.firstIndex(where: { $0.id == offerId }) else { return }
        var offer = pendingTransferOffers[idx]
        guard offer.isIncoming, offer.isLive else { return }
        offer.status = .rejected
        offer.weeksUntilResponse = 0
        pendingTransferOffers[idx] = offer
        markOfferMailRead(offerId: offerId)

        addNews(
            headline: "Bid for \(playerName(for: offer.playerId)) Rejected",
            body: offer.isLoan
                ? "You have turned down \(club(withId: offer.toClubId)?.name ?? "the club")'s loan request."
                : "You have turned down \(club(withId: offer.toClubId)?.name ?? "the club")'s \(Player.formatCurrency(offer.fee)) offer.",
            category: .transfer,
            sender: "Director of Football"
        )
    }

    /// Marks any inbox message linked to an offer as read.
    private func markOfferMailRead(offerId: UUID) {
        for idx in news.indices where news[idx].transferOfferId == offerId {
            news[idx].isRead = true
        }
    }

    /// Returns the live offers the user still needs to act on.
    public var actionableOffers: [TransferOffer] {
        pendingTransferOffers.filter { $0.isLive }
    }

    func playerName(for id: UUID) -> String {
        player(withId: id)?.player.fullName ?? "the player"
    }

    // MARK: - AI Bidding for User Players

    /// AI clubs occasionally bid for members of the user's squad, generating an
    /// actionable inbox message the user must accept or reject.
    public func processAIIncomingBids() {
        guard let userIdx = clubs.firstIndex(where: { $0.isUserClub }) else { return }
        let userClub = clubs[userIdx]
        guard userClub.players.count > 18 else { return }

        // Only a handful of realistic bids per week, and only in a window.
        guard isTransferWindowOpen else { return }
        guard Double.random(in: 0...1) < 0.6 else { return }

        // Transfer-listed players attract most of the interest; players marked
        // not for sale are left alone. Otherwise clubs target a non-star the
        // user might be willing to sell.
        let open = userClub.players.filter { !$0.isOnLoan && $0.transferStatus != .notForSale }
        let listed = open.filter { $0.transferStatus == .transferListed }
        let sellable = open
            .filter { $0.overall < 88 && (($0.contract?.yearsRemaining ?? 0) <= 2) }
            .sorted { $0.value < $1.value }
        let target: Player
        if let pick = listed.randomElement(), Double.random(in: 0..<1) < 0.75 {
            target = pick
        } else if let pick = sellable.first ?? open.min(by: { $0.overall < $1.overall }) {
            target = pick
        } else {
            return
        }

        // Clubs know a listed player is available and bid nearer his value.
        let bid = Int(Double(target.value) * (target.transferStatus == .transferListed
            ? Double.random(in: 0.8...1.15) : Double.random(in: 1.0...1.6)))

        // Avoid duplicate live bids for the same player.
        guard !pendingTransferOffers.contains(where: { $0.playerId == target.id && $0.isLive }) else { return }

        // The bidder is a club that can actually afford him and would improve
        // with him: picking any club at random meant most weeks no bid came.
        let wage = max(target.wage, Int(Double(bid) / 250))
        let candidates = clubs.filter { club in
            !club.isUserClub
                && club.finances.transferBudget >= bid
                && club.totalWeeklyWageBill + wage <= club.finances.wageBudget
                && club.players.count < 30
                && Double(target.overall) >= club.startingXIAverageOverall - 6
                && rivalry(between: club.id, and: userClub.id) == nil
        }
        // Mostly domestic interest, sometimes from abroad.
        let domestic = candidates.filter { $0.leagueTier.country == userClub.leagueTier.country }
        guard let bidder = (Double.random(in: 0..<1) < 0.7 && !domestic.isEmpty ? domestic : candidates).randomElement() else { return }
        var offer = TransferOffer(
            playerId: target.id,
            fromClubId: userClub.id,
            toClubId: bidder.id,
            fee: bid,
            status: .pending,
            offeredWage: wage,
            contractYears: 3,
            askingPrice: bid,
            isIncoming: true,
            createdDate: season.currentDate,
            weeksUntilResponse: 3
        )
        offer.isIncoming = true
        pendingTransferOffers.append(offer)

        addNews(
            headline: "\(bidder.name) Bid for \(target.fullName)",
            body: "\(bidder.name) have offered \(Player.formatCurrency(bid)) for \(target.fullName). Accept the offer, reject it, or negotiate.",
            category: .transfer,
            sender: bidder.name,
            transferOfferId: offer.id
        )
    }

    
    /// Executes the movement of a player between clubs (or free agency) and records it.
    /// Returns `false` when the buyer can no longer afford the fee or the wage, so
    /// stale negotiations cannot push a club into debt.
    ///
    /// The fee can be paid in yearly `installments` (the first now), the
    /// selling club can keep a `sellOnPercent` share of the next sale, and an
    /// `addOn` is paid after a year if the player is still at the buyer.
    @discardableResult
    func completeSigning(
        player: Player,
        buyerIdx: Int,
        sellerIdx: Int?,
        fee: Int,
        wage: Int,
        years: Int,
        installments: Int = 1,
        sellOnPercent: Int = 0,
        addOn: Int = 0,
        signingBonus: Int = 0
    ) -> Bool {
        guard buyerIdx >= 0, buyerIdx < clubs.count else { return false }
        if let sellerIdx = sellerIdx, sellerIdx == buyerIdx { return false }
        guard fee >= 0, wage > 0, years > 0 else { return false }

        // The player may have moved (or been signed from the free-agent pool) in
        // the weeks since the bid was made. Never complete against a stale club.
        if let sellerIdx = sellerIdx {
            // A player on loan belongs to another club and cannot be sold.
            guard let current = clubs[sellerIdx].player(withId: player.id), !current.isOnLoan else { return false }
        } else {
            guard freeAgents.contains(where: { $0.id == player.id }) else { return false }
        }

        // Budgets may have changed since the bid was submitted, so validate the
        // whole deal again at the moment of completion.
        let buyer = clubs[buyerIdx]
        let parts = max(1, min(4, installments))
        // Only the first installment is due now; the rest come out of future budgets.
        let upfront = parts == 1 ? fee : fee - (fee / parts) * (parts - 1)
        guard upfront + signingBonus <= buyer.finances.transferBudget else { return false }
        guard buyer.totalWeeklyWageBill + wage <= wageCeiling(for: buyer) else { return false }

        var signed = player
        signed.transferStatus = nil
        let previousContract = player.contract

        // Any sell-on attached to the old contract is settled by this transfer.
        // The new contract carries the sell-on agreed in this deal, if any,
        // in favour of the club selling him now.
        signed.contract = Contract(
            wage: wage,
            yearsRemaining: years,
            sellOnPercentage: sellerIdx != nil && sellOnPercent > 0 ? Double(sellOnPercent) / 100.0 : nil,
            formerClubId: sellOnPercent > 0 ? sellerIdx.map { clubs[$0].id } : nil,
            signingDate: season.currentDate
        )
        
        var fromClubName = "Free Agent"
        var fromClubId = UUID()
        
        if let sellerIdx = sellerIdx {
            fromClubName = clubs[sellerIdx].name
            fromClubId = clubs[sellerIdx].id
            _ = clubs[sellerIdx].removePlayer(withId: player.id)

            // The seller receives the fee (now, the first installment) minus
            // any sell-on share owed to the club that sold the player before.
            var sellerProceeds = upfront
            if let sellOn = previousContract?.sellOnPercentage, sellOn > 0,
               let entitledClubId = previousContract?.formerClubId,
               entitledClubId != clubs[sellerIdx].id,
               let entitledIdx = clubs.firstIndex(where: { $0.id == entitledClubId }) {
                let owed = min(sellerProceeds, max(0, Int(Double(fee) * sellOn)))
                sellerProceeds = max(0, sellerProceeds - owed)
                clubs[entitledIdx].finances.transferBudget += owed
                clubs[entitledIdx].finances.balance += owed
                if clubs[entitledIdx].isUserClub {
                    seasonLedger?.playerSales += owed
                    addNews(
                        headline: "Sell-On Fee for \(player.fullName)",
                        body: "\(player.fullName) has moved from \(clubs[sellerIdx].name) for \(Player.formatCurrency(fee)). Our \(Int(sellOn * 100))% sell-on clause earns us \(Player.formatCurrency(owed)).",
                        category: .transfer,
                        sender: "Director of Football"
                    )
                }
            }
            // Later installments and any add-on are paid when due.
            let sellerId = clubs[sellerIdx].id
            if parts > 1 {
                for n in 1..<parts {
                    transferInstallments.append(TransferInstallment(
                        playerId: player.id, playerName: player.fullName,
                        payerClubId: clubs[buyerIdx].id, payeeClubId: sellerId,
                        amount: fee / parts, dueDate: Self.dateAdding(years: n, to: season.currentDate)))
                }
            }
            if addOn > 0 {
                transferInstallments.append(TransferInstallment(
                    playerId: player.id, playerName: player.fullName,
                    payerClubId: clubs[buyerIdx].id, payeeClubId: sellerId,
                    amount: addOn, dueDate: Self.dateAdding(years: 1, to: season.currentDate),
                    isConditionalAddOn: true))
            }
            clubs[sellerIdx].finances.transferBudget += sellerProceeds
            // The fee is real money: it lands in the seller's bank account.
            clubs[sellerIdx].finances.balance += sellerProceeds
            if clubs[sellerIdx].isUserClub { seasonLedger?.playerSales += sellerProceeds }
        } else {
            freeAgents.removeAll { $0.id == player.id }
        }
        
        // A free agent's fee is always zero; a signing-on bonus goes to the player.
        let paidNow = (sellerIdx == nil ? 0 : upfront) + signingBonus
        clubs[buyerIdx].finances.transferBudget -= paidNow
        clubs[buyerIdx].finances.balance -= paidNow
        if clubs[buyerIdx].isUserClub { seasonLedger?.transfers += paidNow; checkTransferAchievements(fee: fee, userBought: true) }
        if let sellerIdx, clubs[sellerIdx].isUserClub { checkTransferAchievements(fee: fee, userBought: false) }
        clubs[buyerIdx].addPlayer(signed)
        clubs[buyerIdx].finances.currentWageBill = clubs[buyerIdx].totalWeeklyWageBill
        
        transferHistory.append(
            TransferRecord(
                playerId: signed.id,
                playerName: signed.fullName,
                fromClubId: fromClubId,
                fromClubName: fromClubName,
                toClubId: clubs[buyerIdx].id,
                toClubName: clubs[buyerIdx].name,
                fee: fee,
                date: season.currentDate
            )
        )
        return true
    }
    
    // MARK: - Free Agent Bootstrapping
    
    /// Populates every club with an initial youth academy cohort. Idempotent:
    /// clubs that already have prospects are skipped.
    public func seedAcademies() {
        for cIdx in 0..<clubs.count where clubs[cIdx].academyProspects.isEmpty {
            let intake = max(2, min(5, clubs[cIdx].youthAcademyLevel + 1))
            let prospects = DataLoader.generateAcademyProspects(count: intake, club: clubs[cIdx])
            clubs[cIdx].academyProspects = prospects
        }
    }
    
    /// Populates the free-agent market with a pool of unattached players so the
    /// user (and AI clubs) always have signings available from day one.
    public func seedFreeAgents(count: Int = 40, force: Bool = false) {
        // Idempotent at bootstrap; `force` tops the pool up between seasons.
        guard force || freeAgents.count < 8 else { return }
        
        let firstNames = ["Jack", "Liam", "Marcus", "Tom", "Sam", "Ollie", "Callum", "Reuben",
                          "Tyrese", "Kwame", "Diego", "Bruno", "Yuki", "Andrei", "Mateo", "Idris",
                          "Finley", "Kai", "Noah", "Ethan", "Leo", "Rafael", "Adam", "Isaac"]
        let lastNames = ["Bennett", "Okafor", "Silva", "Mensah", "Vargas", "Novak", "Petrov",
                         "Haddad", "Bauer", "Rossi", "Tanaka", "Adebayo", "Clarke", "Murphy",
                         "Fernandes", "Kovac", "Larsson", "Diallo", "Moretti", "Suzuki"]
        let nationalities = ["England", "Scotland", "Wales", "Ireland", "France", "Spain",
                             "Portugal", "Germany", "Italy", "Brazil", "Nigeria", "Ghana",
                             "Netherlands", "Belgium", "Denmark", "Sweden", "Japan", "USA"]
        
        for _ in 0..<count {
            let position = Position.allCases.randomElement() ?? .CM
            let tierRoll = Int.random(in: 0...100)
            let overall: Int
            if tierRoll < 10 { overall = Int.random(in: 68...76) }
            else if tierRoll < 40 { overall = Int.random(in: 58...67) }
            else { overall = Int.random(in: 46...57) }
            
            let age = Int.random(in: 18...35)
            let potential = min(99, overall + (age <= 23 ? Int.random(in: 3...12) : Int.random(in: 0...3)))
            let attrs = DataLoader.generateAttributes(overall: overall, position: position)
            
            let player = Player(
                firstName: firstNames.randomElement() ?? "Alex",
                lastName: lastNames.randomElement() ?? "Smith",
                nationality: nationalities.randomElement() ?? "England",
                age: age,
                height: Int.random(in: 172...192),
                weight: Int.random(in: 66...88),
                preferredFoot: [Foot.right, Foot.right, Foot.left, Foot.both].randomElement() ?? .right,
                positions: [position],
                attributes: attrs,
                overall: overall,
                potential: potential
            )
            freeAgents.append(player)
        }
    }
    
    // MARK: - AI Manager Transfer Engine
    
    public func processAITransfers() {
        ownerManagerTransfers()
        // AI clubs look to fill vacancies or offload surplus players
        for clubIdx in 0..<clubs.count {
            if clubs[clubIdx].isUserClub { continue }
            
            // AI dips into free agency when its squad is genuinely thin. With
            // hundreds of AI clubs, signing every week whenever a squad was
            // under 20 emptied the whole market in the first week of a career.
            let squadSize = clubs[clubIdx].players.count
            let needsCover = squadSize < 16 || (squadSize < 20 && Double.random(in: 0..<1) < 0.08)
            if needsCover && !freeAgents.isEmpty {
                let candidateIdx = Int.random(in: 0..<freeAgents.count)
                let candidate = freeAgents[candidateIdx]
                let weeklyWage = max(500, candidate.overall * 35)
                // Respect the board's wage ceiling before committing to a deal.
                guard clubs[clubIdx].totalWeeklyWageBill + weeklyWage <= clubs[clubIdx].finances.wageBudget else { continue }
                var signedPlayer = freeAgents.remove(at: candidateIdx)
                signedPlayer.contract = Contract(wage: weeklyWage, yearsRemaining: 2, signingDate: season.currentDate)
                clubs[clubIdx].addPlayer(signedPlayer)
                
                transferHistory.append(
                    TransferRecord(
                        playerId: signedPlayer.id,
                        playerName: signedPlayer.fullName,
                        fromClubId: UUID(),
                        fromClubName: "Free Agent",
                        toClubId: clubs[clubIdx].id,
                        toClubName: clubs[clubIdx].name,
                        fee: 0,
                        date: season.currentDate
                    )
                )
            }
        }

        signNotableFreeAgents()
        processAIMarket()
    }

    /// Good unattached players do not sit on the market for long. Each week
    /// the best free agents are picked up by the biggest club they would walk
    /// into the side at; the better the player, the sooner he finds a club.
    /// (Before, AI clubs only took a random free agent when their squad was
    /// thin, so a released 90-rated centre-back could go unsigned for years.)
    private func signNotableFreeAgents() {
        guard !freeAgents.isEmpty else { return }
        let ranked = freeAgents.sorted { $0.overall > $1.overall }.prefix(30)
        let eliteClubs = Array(clubs.indices.sorted { clubs[$0].reputation > clubs[$1].reputation }.prefix(60))
        var moves = 0
        for agent in ranked where moves < 8 {
            // Weaker players wait longer; veterans longer still.
            var chance: Double
            switch agent.overall {
            case 80...: chance = 0.7
            case 74..<80: chance = 0.45
            case 68..<74: chance = 0.22
            case 62..<68: chance = 0.1
            default: chance = 0.03
            }
            if agent.age >= 34 { chance *= 0.4 } else if agent.age >= 32 { chance *= 0.7 }
            guard Double.random(in: 0..<1) < chance else { continue }

            let category = agent.primaryPosition.category
            // A player without a fee is easier to fit in: boards stretch the
            // wage budget a little for him.
            var candidates: [(idx: Int, wage: Int)] = []
            let scouted = Set(eliteClubs + Array(clubs.indices.shuffled().prefix(80)))
            for idx in scouted {
                let club = clubs[idx]
                if club.isUserClub || club.players.count >= 28 { continue }
                let starters = club.startingXIPlayers.filter { $0.primaryPosition.category == category }
                guard let weakest = starters.min(by: { $0.overall < $1.overall }),
                      agent.overall >= weakest.overall + 2 else { continue }
                // Unattached for a while, he settles for a little below market.
                let wage = max(500, Int(Double(Player.calculateWage(overall: agent.overall, age: agent.age, tier: club.leagueTier)) * 0.9))
                guard club.totalWeeklyWageBill + wage <= Int(Double(club.finances.wageBudget) * 1.15),
                      club.finances.balance > wage * 26 else { continue }
                candidates.append((idx, wage))
            }
            // He joins one of the biggest clubs that want him.
            guard let pick = candidates.sorted(by: { clubs[$0.idx].reputation > clubs[$1.idx].reputation }).prefix(3).randomElement(),
                  let agentIdx = freeAgents.firstIndex(where: { $0.id == agent.id }) else { continue }
            var signed = freeAgents.remove(at: agentIdx)
            signed.transferStatus = nil
            signed.contract = Contract(wage: pick.wage,
                                       yearsRemaining: signed.age >= 31 ? 1 : Int.random(in: 2...4),
                                       signingDate: season.currentDate)
            clubs[pick.idx].addPlayer(signed)
            // Make room by letting the weakest squad player go.
            if clubs[pick.idx].players.count > 27,
               let surplus = clubs[pick.idx].players
                .filter({ !$0.isOnLoan && $0.id != signed.id && !clubs[pick.idx].tactics.startingXI.contains($0.id) })
                .min(by: { $0.overall < $1.overall }),
               var released = clubs[pick.idx].removePlayer(withId: surplus.id) {
                released.contract = nil
                freeAgents.append(released)
            }
            clubs[pick.idx].finances.currentWageBill = clubs[pick.idx].totalWeeklyWageBill
            clubs[pick.idx].ensureTacticalIntegrity()
            transferHistory.append(
                TransferRecord(
                    playerId: signed.id,
                    playerName: signed.fullName,
                    fromClubId: UUID(),
                    fromClubName: "Free Agent",
                    toClubId: clubs[pick.idx].id,
                    toClubName: clubs[pick.idx].name,
                    fee: 0,
                    date: season.currentDate
                )
            )
            if signed.overall >= 75 && isNewsworthy(clubs[pick.idx].leagueTier) {
                addNews(
                    headline: "\(clubs[pick.idx].name) Sign \(signed.fullName) on a Free",
                    body: "Free agent \(signed.fullName) (\(signed.primaryPosition.displayName), \(signed.overall)) has joined \(clubs[pick.idx].name) on a \(signed.contract?.yearsRemaining ?? 1)-year deal.",
                    category: .transfer,
                    sender: "Transfer Desk"
                )
            }
            moves += 1
        }
    }

    /// The AI transfer market. While a window is open, clubs with money to
    /// spend try to upgrade their weakest starter. A selling club lets a
    /// player go when he is not a regular, or when the buyer is the bigger
    /// club and pays a premium; nobody sells to a fierce rival.
    private func processAIMarket() {
        guard isTransferWindowOpen else { return }
        let summer = currentMonth != 1
        let userManages = gameMode == .manageClub
        let eligible = clubs.indices.filter { !(clubs[$0].isUserClub) && clubs[$0].finances.transferBudget > 250_000 }
        guard !eligible.isEmpty else { return }
        let attempts = max(1, clubs.count / (summer ? 12 : 24))
        // The biggest clubs are always on every scout's list.
        let eliteClubs = clubs.indices.sorted { clubs[$0].reputation > clubs[$1].reputation }.prefix(40)
        // Players signed in this window or the last one are not resold.
        let windowCutoff: String = {
            let year = Int(season.currentDate.prefix(4)) ?? 2026
            return summer ? "\(year - 1)-12-31" : "\(year - 1)-05-31"
        }()
        for buyerIdx in eligible.shuffled().prefix(attempts) {
            let buyer = clubs[buyerIdx]
            guard buyer.players.count < 30,
                  let weakest = buyer.startingXIPlayers.min(by: { $0.overall < $1.overall }) else { continue }
            let category = weakest.primaryPosition.category
            let budget = buyer.finances.transferBudget
            let wageRoom = buyer.finances.wageBudget - buyer.totalWeeklyWageBill
            var best: (sellerIdx: Int, player: Player, fee: Int, wage: Int, regular: Bool)?
            // Scout a sample of clubs: mostly at home, sometimes abroad.
            var scouted = Array(clubs.indices.shuffled().prefix(30))
            if buyer.reputation >= 70 { scouted += eliteClubs.shuffled().prefix(15) }
            for sellerIdx in Set(scouted) where sellerIdx != buyerIdx {
                let seller = clubs[sellerIdx]
                if seller.isUserClub && userManages { continue }
                guard seller.players.count > 19 else { continue }
                if seller.leagueTier.country != buyer.leagueTier.country && Double.random(in: 0..<1) < 0.5 { continue }
                let sellerXI = Set(seller.tactics.startingXI)
                let sellerLevel = seller.startingXIAverageOverall
                for player in seller.players where !player.isOnLoan
                    && (player.contract?.signingDate ?? "") < windowCutoff
                    && player.primaryPosition.category == category
                    && player.overall >= weakest.overall + 2
                    && player.age <= 31
                    && player.injury == nil {
                    // Never strip a club of its last two goalkeepers.
                    if player.primaryPosition == .GK
                        && seller.players.filter({ $0.primaryPosition == .GK }).count <= 2 { continue }
                    // A club only sells a regular to a bigger club.
                    let isRegular = sellerXI.contains(player.id) || Double(player.overall) >= sellerLevel - 1
                    if isRegular && seller.reputation >= buyer.reputation - 5 { continue }
                    let premium = isRegular ? 1.3 : 1.05
                    let fee = Int(Double(sellingValuation(for: player, at: seller, buyerReputation: buyer.reputation)) * premium)
                    let wage = max(player.wage, Player.calculateWage(overall: player.overall, age: player.age, tier: buyer.leagueTier))
                    guard fee <= budget, wage <= wageRoom else { continue }
                    if rivalry(between: buyer.id, and: seller.id) != nil { continue }
                    if best == nil || player.overall > best!.player.overall
                        || (player.overall == best!.player.overall && fee < best!.fee) {
                        best = (sellerIdx, player, fee, wage, isRegular)
                    }
                }
            }
            guard let deal = best else { continue }
            let sellerWasUser = clubs[deal.sellerIdx].isUserClub
            // An owner signs off on the sale of a first-team player: the bid
            // goes to the inbox instead of being completed by the manager.
            if sellerWasUser && deal.regular {
                guard !pendingTransferOffers.contains(where: { $0.playerId == deal.player.id && $0.isLive }) else { continue }
                let offer = TransferOffer(
                    playerId: deal.player.id,
                    fromClubId: clubs[deal.sellerIdx].id,
                    toClubId: buyer.id,
                    fee: deal.fee,
                    status: .pending,
                    offeredWage: deal.wage,
                    contractYears: 3,
                    askingPrice: deal.fee,
                    isIncoming: true,
                    createdDate: season.currentDate,
                    weeksUntilResponse: 3
                )
                pendingTransferOffers.append(offer)
                addNews(
                    headline: "\(buyer.name) Bid \(Player.formatCurrency(deal.fee)) for \(deal.player.fullName)",
                    body: "\(buyer.name) want \(deal.player.fullName) (\(deal.player.primaryPosition.displayName), \(deal.player.overall)). He is a first-team regular, so the decision is yours: accept or reject the offer.",
                    category: .transfer,
                    sender: buyer.name,
                    transferOfferId: offer.id
                )
                continue
            }
            if completeSigning(player: deal.player, buyerIdx: buyerIdx, sellerIdx: deal.sellerIdx,
                               fee: deal.fee, wage: deal.wage, years: deal.player.age >= 29 ? 2 : Int.random(in: 3...5)) {
                clubs[deal.sellerIdx].ensureTacticalIntegrity()
                // Agents' and intermediaries' fees: about a tenth of the fee leaves the game.
                clubs[buyerIdx].finances.balance -= deal.fee / 10
                // The buyer moves on a surplus squad player to make room.
                if clubs[buyerIdx].players.count > 27,
                   let surplus = clubs[buyerIdx].players
                    .filter({ !$0.isOnLoan && !clubs[buyerIdx].tactics.startingXI.contains($0.id) })
                    .min(by: { $0.overall < $1.overall }),
                   var released = clubs[buyerIdx].removePlayer(withId: surplus.id) {
                    released.contract = nil
                    freeAgents.append(released)
                }
                if sellerWasUser {
                    addNews(
                        headline: "\(deal.player.fullName) Sold to \(clubs[buyerIdx].name)",
                        body: "Your manager has sold \(deal.player.fullName) to \(clubs[buyerIdx].name) for \(Player.formatCurrency(deal.fee)).",
                        category: .transfer,
                        sender: clubs[deal.sellerIdx].manager
                    )
                } else if deal.fee >= 40_000_000 {
                    addNews(
                        headline: "\(clubs[buyerIdx].name) Sign \(deal.player.fullName)",
                        body: "\(clubs[buyerIdx].name) have paid \(clubs[deal.sellerIdx].name) \(Player.formatCurrency(deal.fee)) for \(deal.player.fullName) (\(deal.player.primaryPosition.displayName), \(deal.player.overall)).",
                        category: .transfer,
                        sender: "Transfer Desk"
                    )
                }
            }
        }
    }
    
    // MARK: - Club Creation Helper
    
    public func createCustomClub(
        name: String,
        shortName: String,
        stadium: String,
        stadiumCapacity: Int = 5000,
        city: String,
        primaryColor: String,
        secondaryColor: String,
        replaceClubId: UUID
    ) -> Club? {
        guard let replacedIdx = clubs.firstIndex(where: { $0.id == replaceClubId }) else {
            return nil
        }
        
        let replacedClub = clubs[replacedIdx]
        
        // Free up players of replaced club into free agents pool
        for player in replacedClub.players {
            freeAgents.append(player)
        }
        
        var userClub = Club(
            name: name,
            shortName: shortName.uppercased(),
            stadium: stadium,
            stadiumCapacity: stadiumCapacity,
            city: city,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            leagueTier: replacedClub.leagueTier,
            reputation: 45,
            isUserClub: true,
            players: [],
            manager: gameMode == .createClub ? "Interim Manager" : manager.fullName
        )

        // Found a senior squad immediately so the club is playable from day one.
        // The wage bill is recomputed after the squad is assigned (the Club
        // initializer only sees the empty player list).
        userClub.players = DataLoader.generateProceduralSquad(
            targetCount: 22,
            tier: replacedClub.leagueTier
        )
        userClub.autoPickStartingXI()
        userClub.ensureWageHeadroom()
        
        // Substitute in clubs array
        clubs[replacedIdx] = userClub
        self.userClubId = userClub.id
        
        // Update League clubIds
        if let leagueIdx = leagues.firstIndex(where: { $0.tier == replacedClub.leagueTier }) {
            if let idIdx = leagues[leagueIdx].clubIds.firstIndex(of: replaceClubId) {
                leagues[leagueIdx].clubIds[idIdx] = userClub.id
            }
        }
        
        // Update fixtures containing replaced club
        for fIdx in 0..<season.fixtures.count {
            if season.fixtures[fIdx].homeClubId == replaceClubId {
                season.fixtures[fIdx].homeClubId = userClub.id
            }
            if season.fixtures[fIdx].awayClubId == replaceClubId {
                season.fixtures[fIdx].awayClubId = userClub.id
            }
        }

        // European competitions are seeded when the world is bootstrapped.
        // Replacing a club after that point used to leave their participant and
        // fixture IDs pointing at a club which no longer exists.  Preserve the
        // qualification slot, but transfer it to the newly founded club.
        for competitionIndex in europeanCompetitions.indices {
            europeanCompetitions[competitionIndex].participantClubIds = europeanCompetitions[competitionIndex].participantClubIds.map {
                $0 == replaceClubId ? userClub.id : $0
            }
            for fixtureIndex in europeanCompetitions[competitionIndex].fixtures.indices {
                if europeanCompetitions[competitionIndex].fixtures[fixtureIndex].homeClubId == replaceClubId {
                    europeanCompetitions[competitionIndex].fixtures[fixtureIndex].homeClubId = userClub.id
                }
                if europeanCompetitions[competitionIndex].fixtures[fixtureIndex].awayClubId == replaceClubId {
                    europeanCompetitions[competitionIndex].fixtures[fixtureIndex].awayClubId = userClub.id
                }
            }
            if europeanCompetitions[competitionIndex].championClubId == replaceClubId {
                europeanCompetitions[competitionIndex].championClubId = userClub.id
            }
        }
        rivalries = rivalries.map { r in
            Rivalry(
                clubA: r.clubA == replaceClubId ? userClub.id : r.clubA,
                clubB: r.clubB == replaceClubId ? userClub.id : r.clubB,
                name: r.name,
                intensity: r.intensity
            )
        }
        for cupIndex in domesticCups.indices {
            domesticCups[cupIndex].byeClubIds = domesticCups[cupIndex].byeClubIds.map {
                $0 == replaceClubId ? userClub.id : $0
            }
        }
        
        addNews(
            headline: "\(userClub.name) Enters \(userClub.leagueTier.displayName)!",
            body: gameMode == .createClub
                ? "\(owner.name) has founded \(userClub.name). Your first decision is who will lead the football department."
                : "\(userClub.name) has officially taken over at \(userClub.stadium).",
            category: .board,
            sender: "The Board — \(userClub.name)"
        )
        if gameMode != .createClub { seedManagerInbox() }
        seedAcademies()
        hasStartedCareer = true
        if let created = self.userClub {
            seasonLedger = FinanceLedger(startingBalance: created.finances.balance)
            if gameMode == .createClub {
                owner.valuationAtTakeover = OwnerBusiness.valuation(of: created, debt: owner.totalDebt)
            }
        }
        
        return userClub
    }

    /// An owner advances the club's week as an observer. Fixtures are fully
    /// simulated; the owner then reacts through appointments and investment.
    public func advanceOwnerWeek() {
        guard gameMode == .createClub, userClub != nil else { return }
        checkWinBonusRequest()
        if isEndOfSeason {
            startNewSeason()
            try? SaveManager.shared.autoSave(gameState: self)
            return
        }
        advanceWeek()
        // Once the club's own league campaign is over, play out the rest of the
        // world in one go instead of making the owner tap through idle weeks
        // while longer leagues elsewhere finish.
        if let uid = userClubId, season.nextFixture(forClub: uid) == nil {
            var guardWeeks = 0
            while !isEndOfSeason && guardWeeks < 100 {
                advanceWeek()
                guardWeeks += 1
            }
        }
        checkOwnerWeeklyMilestones()
        try? SaveManager.shared.autoSave(gameState: self)
    }

    /// Allows owners to shape resources and public sentiment without selecting
    /// the team or changing match tactics.
    @discardableResult
    public func approveOwnerInvestment(_ investment: OwnerInvestment) -> Bool {
        guard gameMode == .createClub,
              owner.legacyPoints >= investment.cost,
              let index = clubs.firstIndex(where: { $0.isUserClub }) else { return false }

        owner.legacyPoints -= investment.cost
        switch investment {
        case .recruitment:
            clubs[index].finances.transferBudget += 650_000
            adjustFans(1)
        case .facilities:
            clubs[index].finances.balance += 450_000
            adjustFans(2)
        case .community:
            adjustFans(6)
            clubs[index].reputation = min(100, clubs[index].reputation + 1)
        }
        addNews(
            headline: "Board Approves \(investment.title)",
            body: investment.detail,
            category: .board,
            sender: "Owner's Office"
        )
        try? SaveManager.shared.autoSave(gameState: self)
        return true
    }

    /// Runs one intentional training session per matchweek. Dedicated sessions
    /// trade one form of readiness for another, so preparation remains a choice.
    @discardableResult
    public func runTrainingSession(_ focus: TrainingFocus) -> Bool {
        guard gameMode != .createClub,
              lastTrainingWeek != season.currentWeek,
              let clubIndex = clubs.firstIndex(where: { $0.isUserClub }) else { return false }

        for playerIndex in clubs[clubIndex].players.indices where clubs[clubIndex].players[playerIndex].injury == nil {
            switch focus {
            case .balanced:
                clubs[clubIndex].players[playerIndex].recoverFitness(amount: 3)
                clubs[clubIndex].players[playerIndex].sharpness = min(100, clubs[clubIndex].players[playerIndex].sharpness + 3)
            case .fitness:
                clubs[clubIndex].players[playerIndex].recoverFitness(amount: 7)
                clubs[clubIndex].players[playerIndex].sharpness = min(100, clubs[clubIndex].players[playerIndex].sharpness + 1)
            case .sharpness:
                clubs[clubIndex].players[playerIndex].consumeFitness(amount: 2)
                clubs[clubIndex].players[playerIndex].sharpness = min(100, clubs[clubIndex].players[playerIndex].sharpness + 7)
            case .morale:
                clubs[clubIndex].players[playerIndex].boostMorale()
                clubs[clubIndex].players[playerIndex].recoverFitness(amount: 1)
            }
        }
        lastTrainingWeek = season.currentWeek
        addNews(
            headline: "\(focus.title) Session Complete",
            body: "The first team completed a focused \(focus.title.lowercased()) session ahead of the next fixture.",
            category: .board,
            sender: "Coaching Staff"
        )
        try? SaveManager.shared.autoSave(gameState: self)
        return true
    }

    /// Sets a matchweek team talk. It is intentionally a small, temporary edge:
    /// preparation and player quality still decide the match.
    @discardableResult
    public func chooseTeamTalk(_ style: TeamTalkStyle) -> Bool {
        guard gameMode != .createClub, userClub != nil else { return false }
        teamTalk = style
        teamTalkAppliedWeek = nil
        addNews(headline: "Team Talk Set: \(style.rawValue)", body: style.effectSummary, category: .board, sender: "Manager's Office")
        return true
    }

    /// Applies the selected talk once, immediately before the user fixture is simulated.
    public func applyTeamTalkIfNeeded() {
        guard let style = teamTalk,
              teamTalkAppliedWeek != season.currentWeek,
              let clubIndex = clubs.firstIndex(where: { $0.isUserClub }) else { return }
        for playerIndex in clubs[clubIndex].players.indices where clubs[clubIndex].players[playerIndex].injury == nil {
            switch style {
            case .calm, .rally, .protect:
                clubs[clubIndex].players[playerIndex].boostMorale()
            case .firedUp:
                clubs[clubIndex].players[playerIndex].boostMorale()
                clubs[clubIndex].players[playerIndex].sharpness = min(100, clubs[clubIndex].players[playerIndex].sharpness + 2)
            case .demand:
                clubs[clubIndex].players[playerIndex].sharpness = min(100, clubs[clubIndex].players[playerIndex].sharpness + 4)
                if clubs[clubIndex].players[playerIndex].morale == .furious { clubs[clubIndex].players[playerIndex].dampenMorale() }
            }
        }
        teamTalkAppliedWeek = season.currentWeek
    }

    private func updateBoardConfidence(after result: MatchResult, userWasHome: Bool) {
        let previousStatus = jobSecurity.status
        let goalsFor = userWasHome ? result.homeGoals : result.awayGoals
        let goalsAgainst = userWasHome ? result.awayGoals : result.homeGoals
        let won = result.winnerClubId == (userWasHome ? result.homeClubId : result.awayClubId)
        let drawn = result.isDraw
        if won {
            jobSecurity.gamesWithoutWin = 0
            jobSecurity.underperformingWeeks = max(0, jobSecurity.underperformingWeeks - 1)
            jobSecurity.boardConfidence = min(100, jobSecurity.boardConfidence + (goalsFor - goalsAgainst >= 3 ? 6 : 3))
        } else {
            jobSecurity.gamesWithoutWin += 1
            if !drawn { jobSecurity.underperformingWeeks += 1 }
            let drop = drawn ? 1 : min(8, 3 + jobSecurity.gamesWithoutWin / 2)
            jobSecurity.boardConfidence = max(0, jobSecurity.boardConfidence - drop)
        }
        // Only write to the inbox when the board's stance actually changes;
        // a message after every match buried everything else.
        guard jobSecurity.status != previousStatus else { return }
        let tone = jobSecurity.boardConfidence < 40 ? "The board need an immediate improvement." : "The board remain focused on the season objective."
        addNews(headline: "Board Confidence: \(jobSecurity.status)", body: "Confidence is \(jobSecurity.boardConfidence) out of 100. \(tone)", category: .board, sender: "The Board")
    }

    /// The board sacks a manager whose confidence has collapsed during a poor
    /// run. Called once a matchweek has been completed.
    private func evaluateManagerJobSecurity() {
        guard gameMode == .manageClub,
              let clubIdx = clubs.firstIndex(where: { $0.isUserClub }) else { return }
        // The board watch the table as well as results: a side well below
        // its target loses their patience week by week, one above it earns
        // some. (Before, only a long winless run with confidence near zero
        // could cost a manager his job, so it almost never happened.)
        let table = currentLeagueStandings
        let round = currentLeague.map { currentLeagueRound(competition: $0.name) } ?? 1
        var belowTarget = 0
        if round >= 8, let target = boardTarget(for: clubs[clubIdx]),
           let position = table.firstIndex(where: { $0.clubId == clubs[clubIdx].id }).map({ $0 + 1 }) {
            belowTarget = position - target.position
            if belowTarget >= 6 {
                jobSecurity.boardConfidence = max(0, jobSecurity.boardConfidence - 2)
            } else if belowTarget >= 3 {
                jobSecurity.boardConfidence = max(0, jobSecurity.boardConfidence - 1)
            } else if belowTarget <= 0 {
                jobSecurity.boardConfidence = min(100, jobSecurity.boardConfidence + 1)
            }
        }
        let collapsed = jobSecurity.boardConfidence <= 12
        let poorRun = jobSecurity.gamesWithoutWin >= 4 || belowTarget >= 6
        guard round >= 8, collapsed, poorRun else { return }
        let sackedFrom = clubs[clubIdx]
        abandonLiveTransferTalks()
        clubs[clubIdx].isUserClub = false
        clubs[clubIdx].manager = "Caretaker Manager"
        userClubId = nil
        manager.reputation = max(5, manager.reputation - 8)
        jobSecurity = JobSecurity()
        teamTalk = nil
        addNews(
            headline: "Sacked by \(sackedFrom.name)",
            body: "After \(sackedFrom.name)'s poor run, the board have relieved you of your duties. Other clubs may still be interested — check your job offers.",
            category: .board,
            sender: "The Board — \(sackedFrom.name)"
        )
        generateJobOffers(maxCount: 4, excludeUserClub: false)
        jobOffers.removeAll { $0.clubId == sackedFrom.id }
    }

    /// In January, established players who are rarely picked grow unhappy
    /// and say so. Rotation and squad size become real decisions.
    private func reviewPlayingTime() {
        guard gameMode == .manageClub,
              let clubIdx = clubs.firstIndex(where: { $0.isUserClub }) else { return }
        let parts = season.currentDate.split(separator: "-")
        guard parts.count == 3, parts[1] == "01", let day = Int(parts[2]), day <= 7 else { return }
        let club = clubs[clubIdx]
        let matchesPlayed = season.completedFixtures(forClub: club.id).count
        guard matchesPlayed >= 10 else { return }
        let squadLevel = club.squadAverageOverall
        let unhappy = club.players.filter { player in
            player.age >= 20 && player.age <= 31 && !player.isOnLoan
                && Double(player.overall) >= squadLevel
                && player.injury == nil
                && Double(player.seasonStats.appearances) < Double(matchesPlayed) * 0.3
        }
        .sorted { $0.overall > $1.overall }
        .prefix(2)
        for player in unhappy {
            guard let pIdx = clubs[clubIdx].players.firstIndex(where: { $0.id == player.id }) else { continue }
            clubs[clubIdx].players[pIdx].dampenMorale()
            clubs[clubIdx].players[pIdx].dampenMorale()
            addNews(
                headline: "\(player.fullName) Unhappy With Playing Time",
                body: "\(player.fullName) has started only \(player.seasonStats.appearances) of our \(matchesPlayed) matches and wants regular football. Pick him more often or consider offers.",
                category: .general,
                sender: "Agent of \(player.fullName)"
            )
        }
    }

    /// January reminder of the user's contracts that expire in the summer.
    private func warnAboutExpiringContracts() {
        guard gameMode == .manageClub, let club = userClub else { return }
        let parts = season.currentDate.split(separator: "-")
        guard parts.count == 3, parts[1] == "01", let day = Int(parts[2]), day <= 7 else { return }
        let expiring = club.players.filter { !$0.isOnLoan && ($0.contract?.yearsRemaining ?? 2) <= 1 }
        guard !expiring.isEmpty else { return }
        let names = expiring.sorted { $0.overall > $1.overall }.prefix(6).map { $0.fullName }.joined(separator: ", ")
        addNews(
            headline: "\(expiring.count) Contract\(expiring.count == 1 ? "" : "s") Expire This Summer",
            body: "\(names)\(expiring.count > 6 ? " and others" : "") will leave on free transfers unless offered new deals. Open a player's profile to negotiate.",
            category: .contractExpiry,
            sender: "Director of Football"
        )
    }

    private func updateOwnerMatchPerformance(after result: MatchResult, userWasHome: Bool) {
        let goalsFor = userWasHome ? result.homeGoals : result.awayGoals
        let goalsAgainst = userWasHome ? result.awayGoals : result.homeGoals
        let won = result.winnerClubId == (userWasHome ? result.homeClubId : result.awayClubId)
        let drawn = result.isDraw

        var pointsEarned = 0
        if won {
            pointsEarned += 2
            adjustFans(3)
            unlockOwnerMilestone(id: "first_win")
            if goalsAgainst == 0 {
                pointsEarned += 1
                unlockOwnerMilestone(id: "clean_sheet")
            }
            if goalsFor >= 3 {
                pointsEarned += 1
            }
        } else if drawn {
            pointsEarned += 1
            if goalsAgainst == 0 {
                pointsEarned += 1
                unlockOwnerMilestone(id: "clean_sheet")
            }
        } else {
            adjustFans(-(3))
        }

        owner.legacyPoints += pointsEarned
        owner.managerSatisfaction = max(0, min(100, owner.managerSatisfaction + (won ? 1 : (drawn ? 0 : -1))))

        // Check 5 games unbeaten
        if let userClub = userClub {
            let recent = userClub.seasonResults.suffix(5)
            if recent.count == 5 {
                let unbeaten = recent.allSatisfy { r in
                    let isHome = r.homeClubId == userClub.id
                    let gf = isHome ? r.homeGoals : r.awayGoals
                    let ga = isHome ? r.awayGoals : r.homeGoals
                    return gf >= ga
                }
                if unbeaten {
                    unlockOwnerMilestone(id: "five_unbeaten")
                }
            }
        }
    }

    public func unlockOwnerMilestone(id: String) {
        guard gameMode == .createClub else { return }
        guard let idx = owner.milestones.firstIndex(where: { $0.id == id && !$0.isUnlocked }) else { return }
        owner.milestones[idx].isUnlocked = true
        let ms = owner.milestones[idx]
        owner.legacyPoints += ms.bonusPoints
        addNews(
            headline: "Milestone: \(ms.title)",
            body: "\(ms.detail). +\(ms.bonusPoints) Legacy Points awarded.",
            category: .award,
            sender: "Boardroom"
        )
    }

    public func checkOwnerWeeklyMilestones() {
        guard gameMode == .createClub, let userClub = userClub else { return }
        if userClub.finances.balance >= 2_500_000 {
            unlockOwnerMilestone(id: "reserves")
        }
        if !owner.sponsorshipDeals.isEmpty {
            unlockOwnerMilestone(id: "commercial_partner")
        }
    }

    /// Owner-only budget split. Reallocating cash is capped by available balance,
    /// so the owner cannot manufacture funds by changing a percentage.
    @discardableResult
    public func setOwnerBudgetAllocation(transferPercent: Int) -> Bool {
        guard gameMode == .createClub, let index = clubs.firstIndex(where: { $0.isUserClub }) else { return false }
        let transfer = max(0, min(100, transferPercent))
        owner.budgetAllocation = BudgetAllocation(transferBudgetPercent: transfer, wageBudgetPercent: 100 - transfer)
        // Re-split the existing annualised football budget rather than only ever
        // increasing each pot. Lowering the transfer share therefore actually
        // reduces the transfer budget and moves the money to wages.
        let annualWageBudget = clubs[index].finances.wageBudget * 52
        let totalPool = max(1, clubs[index].finances.transferBudget + annualWageBudget)
        let newTransferBudget = totalPool * transfer / 100
        let newAnnualWageBudget = totalPool - newTransferBudget
        clubs[index].finances.transferBudget = newTransferBudget
        clubs[index].finances.wageBudget = max(1, newAnnualWageBudget / 52)
        return true
    }

    /// Signs one sensible commercial partner per owner career. The annual value
    /// scales with club reputation and is credited to sponsorship income.
    @discardableResult
    public func signSponsorshipDeal(_ tier: SponsorshipTier) -> Bool {
        guard gameMode == .createClub,
              owner.sponsorshipDeals.count < 3,
              let index = clubs.firstIndex(where: { $0.isUserClub }) else { return false }
        let reputationFactor = 0.55 + Double(clubs[index].reputation) / 200.0
        let annualValue = Int(Double(tier.baseIncome) * reputationFactor)
        let names = ["Northstar", "Civic", "Vertex", "Harbour", "Summit"]
        let deal = SponsorshipDeal(sponsorName: "\(names[owner.sponsorshipDeals.count]) \(tier.rawValue)", tier: tier, annualValue: annualValue, performanceBonus: annualValue / 10)
        owner.sponsorshipDeals.append(deal)
        clubs[index].finances.sponsorshipIncome += annualValue
        addNews(headline: "New Commercial Partner", body: "\(deal.sponsorName) has agreed a \(Player.formatCurrency(annualValue)) per year deal, plus performance bonuses.", category: .board, sender: "Commercial Director")
        return true
    }

    /// How strongly a setback moves the manager's mood, by personality.
    func managerMoodChange(_ base: Int) -> Int {
        Int((Double(base) * (owner.managerContract?.personality.sensitivity ?? 1.0)).rounded())
    }

    public func appointManager(_ candidate: ManagerCandidate, years: Int = 2) -> Bool {
        guard gameMode == .createClub,
              let index = clubs.firstIndex(where: { $0.isUserClub }),
              clubs[index].finances.balance >= candidate.compensation else { return false }
        clubs[index].finances.balance -= candidate.compensation
        clubs[index].finances.wageBudget = max(clubs[index].finances.wageBudget, candidate.wage + 2_000)
        clubs[index].manager = candidate.name
        owner.managerContract = ManagerContract(managerName: candidate.name, weeklyWage: candidate.wage,
                                                yearsRemaining: max(1, min(4, years)), age: candidate.age,
                                                personality: candidate.personality, style: candidate.style)
        owner.managerSatisfaction = 60
        owner.managerRating = candidate.reputation
        adjustFans(5)
        addNews(headline: "\(candidate.name) Appointed Manager", body: "The board have appointed \(candidate.name). Their stated approach: \(candidate.style).", category: .board, sender: "Owner's Office")
        return true
    }

    public func dismissManager() -> Bool {
        guard gameMode == .createClub,
              let index = clubs.firstIndex(where: { $0.isUserClub }),
              clubs[index].manager != "Interim Manager" else { return false }
        let outgoing = clubs[index].manager
        // Severance: half the wages left on his contract.
        let settlement = owner.managerContract?.severance ?? max(250_000, clubs[index].finances.wageBudget * 8)
        guard clubs[index].finances.balance >= settlement else { return false }
        clubs[index].finances.balance -= settlement
        seasonLedger?.wages += settlement
        owner.managerContract = nil
        clubs[index].manager = "Interim Manager"
        owner.managerRating = 45
        adjustFans(-(4))
        addNews(headline: "\(outgoing) Leaves \(clubs[index].name)", body: "The manager has been relieved of duties. A compensation payment of \(Player.formatCurrency(settlement)) has been made; appoint a successor promptly.", category: .board, sender: "Owner's Office")
        return true
    }
    
    // MARK: - Existing Club Take-Over Helper
    
    /// Assigns an existing club as the user's club (Manage Existing Club mode),
    /// ensuring a valid starting XI and flagging it as the user-controlled side.
    @discardableResult
    public func takeOverExistingClub(clubId: UUID) -> Club? {
        guard let idx = clubs.firstIndex(where: { $0.id == clubId }) else { return nil }
        
        for otherIdx in 0..<clubs.count {
            clubs[otherIdx].isUserClub = (otherIdx == idx)
        }
        clubs[idx].ensureTacticalIntegrity()
        clubs[idx].manager = manager.fullName
        self.userClubId = clubId
        hasStartedCareer = true
        seasonLedger = FinanceLedger(startingBalance: clubs[idx].finances.balance)
        seedAcademies()
        
        addNews(
            headline: "You Are Now the Manager of \(clubs[idx].name)!",
            body: "The board at \(clubs[idx].name) have appointed you as first-team manager at \(clubs[idx].stadium). Transfer budget: \(Player.formatCurrency(clubs[idx].finances.transferBudget)).",
            category: .board,
            sender: "The Board — \(clubs[idx].name)"
        )
        seedManagerInbox()
        if !freeAgents.isEmpty {
            addNews(
                headline: "\(freeAgents.count) Free Agents Available",
                body: "Our scouts have identified \(freeAgents.count) unattached players. Several could improve the squad at no transfer cost.",
                category: .transfer,
                sender: "Chief Scout"
            )
        }
        return clubs[idx]
    }
    
    // MARK: - Club Mutation Helpers

    /// Replaces a club in world state with an updated copy, matched by id.
    public func updateClub(_ updated: Club) {
        guard let idx = clubs.firstIndex(where: { $0.id == updated.id }) else { return }
        clubs[idx] = updated
    }

    /// Swaps a bench player into the starting XI (and the outgoing starter to the bench).
    /// Used by the squad screen's tap-to-select substitution flow.
    public func swapIntoStartingXI(playerId: UUID, replacing starterId: UUID) {
        guard let idx = clubs.firstIndex(where: { $0.isUserClub }) else { return }
        var club = clubs[idx]

        guard let starterIdx = club.tactics.startingXI.firstIndex(of: starterId),
              let benchIdx = club.tactics.substitutes.firstIndex(of: playerId) else {
            return
        }

        club.tactics.startingXI[starterIdx] = playerId
        club.tactics.substitutes[benchIdx] = starterId

        clubs[idx] = club
    }

    // MARK: - Season Transition

    public func startNewSeason() {
        // Loanees go home before contracts, retirements and squad sizes are reviewed.
        returnLoanedPlayers()
        // Older saves: leagues no longer in the game leave between seasons.
        pruneLeaguesOutsideTheGame()
        clinchedHonours = []
        ageManagerContract()
        // Keep three seasons of world transfer history (and all of the user's).
        if let startYear = Int(season.year.prefix(4)) {
            let cutoff = "\(startYear - 2)-06-01"
            let userId = userClubId
            transferHistory.removeAll { $0.date < cutoff && $0.toClubId != userId && $0.fromClubId != userId }
        }
        let years = season.year.components(separatedBy: "-")
        let startYearInt: Int
        let endYearInt: Int
        if years.count == 2, let y1 = Int(years[0]), let y2 = Int(years[1]) {
            startYearInt = y1 + 1
            endYearInt = y2 + 1
        } else {
            startYearInt = 2027
            endYearInt = 2028
        }
        let nextYear = "\(startYearInt)-\(String(format: "%02d", endYearInt % 100))"
        
        // Champions and cup winners meet in the super cups.
        superCupSeeds = capturedSuperCupSeeds()

        // Derive fixture start date and preseason date dynamically from the new season year.
        let seasonStartDate = String(format: "%d-08-09", startYearInt)
        let preseasonDate = String(format: "%d-08-01", startYearInt)
        
        // Regenerate fixtures for all leagues
        var allNewFixtures: [Fixture] = []
        for league in leagues {
            let generated = FixtureGenerator.generateLeagueSeason(
                clubIds: league.clubIds,
                competitionName: league.name,
                startDateString: seasonStartDate,
                rounds: league.tier.seasonRounds(clubCount: league.clubIds.count)
            )
            allNewFixtures.append(contentsOf: generated)
        }
        
        self.season = Season(
            year: nextYear,
            currentWeek: 1,
            currentPhase: .preseason,
            fixtures: allNewFixtures,
            currentDate: preseasonDate
        )
        activeMatchFixtureId = nil
        isMatchInProgress = false
        seedDomesticCups()

        pointsDeductions = [:]
        if let club = userClub {
            seasonLedger = FinanceLedger(startingBalance: club.finances.balance)
        }

        // A new season brings renewed (if partial) patience from the board.
        jobSecurity.boardConfidence = max(45, (jobSecurity.boardConfidence + 70) / 2)
        jobSecurity.gamesWithoutWin = 0
        jobSecurity.underperformingWeeks = 0

        // Rebuild the European competitions for the new season from the clubs
        // that earned their places (the bundled real entry list is only used
        // for the very first season).
        var qualifiers: [EuropeanCompetition: [UUID]] = [:]
        for competition in EuropeanCompetition.allCases {
            if let ids = europeanQualifiers[competition.rawValue] { qualifiers[competition] = ids }
        }
        europeanCompetitions = EuropeanCompetitionBuilder.build(from: clubs, qualifiers: qualifiers.isEmpty ? nil : qualifiers)
        europeanQualifiers = [:]
        payEuropeanParticipationFees()
        europeanMatchweek = 0

        // International tournaments follow their own cycle, not the club season.
        // The summer's tournaments finished while the clubs were on holiday;
        // play them out, then schedule the ones in the season ahead.
        advanceInternationalTournaments(through: String(format: "%d-07-31", startYearInt))
        scheduleInternationalEditions(forSeasonStarting: startYearInt)
        pruneInternationalTournaments()
        
        // Reset player seasonal match statistics and roll contracts forward.
        var renewedUserContracts: [String] = []
        var potentialChanges: [(name: String, change: Int)] = []
        for cIdx in 0..<clubs.count {
            clubs[cIdx].seasonResults = []
            for pIdx in 0..<clubs[cIdx].players.count {
                let appearances = clubs[cIdx].players[pIdx].seasonStats.appearances
                let averageRating = clubs[cIdx].players[pIdx].seasonStats.averageRating
                let finished = clubs[cIdx].players[pIdx].seasonStats
                let potentialBefore = clubs[cIdx].players[pIdx].potential
                clubs[cIdx].players[pIdx].seasonStats = SeasonStats()
                clubs[cIdx].players[pIdx].yellowCards = 0
                // Players age one year each summer. Preseason rest clears injuries
                // and restores fitness, while sharpness starts below peak because
                // nobody has played competitive football for several weeks.
                clubs[cIdx].players[pIdx].age += 1
                // Young players develop, veterans decline; values are re-rated.
                clubs[cIdx].players[pIdx].applySeasonalDevelopment(appearances: appearances,
                                                                    trainingLevel: clubs[cIdx].trainingFacilityLevel,
                                                                    averageRating: averageRating,
                                                                    goals: finished.goals, assists: finished.assists,
                                                                    cleanSheets: finished.cleanSheets)
                if clubs[cIdx].isUserClub && clubs[cIdx].players[pIdx].age <= 34 {
                    let change = clubs[cIdx].players[pIdx].potential - potentialBefore
                    if change >= 2 || change <= -2 { potentialChanges.append((clubs[cIdx].players[pIdx].fullName, change)) }
                }
                // The summer (about ten weeks) heals most injuries, but a
                // long-term one carries into the new season.
                clubs[cIdx].players[pIdx].matchFitness = 100.0
                clubs[cIdx].players[pIdx].advanceDays(70, injuryRecoveryRate: 1.0)
                clubs[cIdx].players[pIdx].sharpness = 65.0
                if clubs[cIdx].players[pIdx].injury == nil {
                    clubs[cIdx].players[pIdx].matchFitness = 100.0
                }
                // Suspensions carry across seasons; they are served match by match.
                // Decrement contract duration.
                if var contract = clubs[cIdx].players[pIdx].contract {
                    contract.yearsRemaining -= 1
                    clubs[cIdx].players[pIdx].contract = contract
                }
            }
            clubs[cIdx].finances.currentWageBill = clubs[cIdx].totalWeeklyWageBill
        }

        // Expired contracts. A manager's own players who were not offered a new
        // deal leave on a free; every other club renews the players it values
        // and releases the rest into the free-agent market.
        var departedUserPlayers: [String] = []
        for cIdx in clubs.indices {
            let managedByUser = clubs[cIdx].isUserClub && gameMode == .manageClub
            let squadLevel = clubs[cIdx].squadAverageOverall
            let expired = clubs[cIdx].players.filter { ($0.contract?.yearsRemaining ?? 1) <= 0 }
            for player in expired {
                // Good veterans get one-year deals, as at real clubs.
                let valued = (Double(player.overall) >= squadLevel - 4 && player.age <= 31)
                    || (Double(player.overall) >= squadLevel - 1 && player.age <= 35)
                let squadNeedsHim = clubs[cIdx].players.count <= 18
                if !managedByUser && (valued || squadNeedsHim),
                   let pIdx = clubs[cIdx].players.firstIndex(where: { $0.id == player.id }) {
                    let market = Player.calculateWage(overall: player.overall, age: player.age, tier: clubs[cIdx].leagueTier)
                    let wage = max(player.wage, market)
                    clubs[cIdx].players[pIdx].contract = Contract(
                        wage: wage,
                        yearsRemaining: player.age >= 30 ? 1 : Int.random(in: 2...4),
                        signingDate: preseasonDate
                    )
                    if clubs[cIdx].isUserClub { renewedUserContracts.append(player.fullName) }
                } else if var released = clubs[cIdx].removePlayer(withId: player.id) {
                    released.contract = nil
                    freeAgents.append(released)
                    if clubs[cIdx].isUserClub { departedUserPlayers.append(player.fullName) }
                }
            }
            clubs[cIdx].finances.currentWageBill = clubs[cIdx].totalWeeklyWageBill
        }

        if !departedUserPlayers.isEmpty {
            let names = departedUserPlayers.prefix(5).joined(separator: ", ")
            let remainder = departedUserPlayers.count > 5 ? " and \(departedUserPlayers.count - 5) more" : ""
            addNews(
                headline: departedUserPlayers.count == 1 ? "Player Leaves on a Free" : "Players Leave on Free Transfers",
                body: "\(names)\(remainder) left the club when \(departedUserPlayers.count == 1 ? "his contract" : "their contracts") expired.",
                category: .contractExpiry,
                sender: "Club Secretary"
            )
        }

        if !potentialChanges.isEmpty {
            let risers = potentialChanges.filter { $0.change > 0 }.sorted { $0.change > $1.change }
            let fallers = potentialChanges.filter { $0.change < 0 }.sorted { $0.change < $1.change }
            var lines: [String] = []
            if !risers.isEmpty {
                lines.append("Rising: " + risers.prefix(5).map { "\($0.name) (+\($0.change))" }.joined(separator: ", ") + ".")
            }
            if !fallers.isEmpty {
                lines.append("Falling: " + fallers.prefix(5).map { "\($0.name) (\($0.change))" }.joined(separator: ", ") + ".")
            }
            addNews(
                headline: "Scouts Revise Potential Ratings",
                body: "After last season's performances the staff have reassessed our players' ceilings. " + lines.joined(separator: " "),
                category: .general,
                sender: "Head of Youth Development"
            )
        }

        if !renewedUserContracts.isEmpty {
            let names = renewedUserContracts.prefix(3).joined(separator: ", ")
            let remainder = renewedUserContracts.count > 3 ? " and \(renewedUserContracts.count - 3) more" : ""
            addNews(
                headline: "Contracts Extended",
                body: "\(names)\(remainder) \(renewedUserContracts.count == 1 ? "has" : "have") agreed new contracts with the club.",
                category: .contractExpiry,
                sender: "Club Secretary"
            )
        }

        // Tick down commercial partnerships. Expired deals stop contributing to
        // the club's annual sponsorship income.
        if !owner.sponsorshipDeals.isEmpty {
            var activeDeals: [SponsorshipDeal] = []
            var expiredValue = 0
            var expiredNames: [String] = []
            for var deal in owner.sponsorshipDeals {
                deal.yearsRemaining -= 1
                if deal.yearsRemaining > 0 {
                    activeDeals.append(deal)
                } else {
                    expiredValue += deal.annualValue
                    expiredNames.append(deal.sponsorName)
                }
            }
            owner.sponsorshipDeals = activeDeals
            if let index = clubs.firstIndex(where: { $0.isUserClub }), expiredValue > 0 {
                clubs[index].finances.sponsorshipIncome = max(0, clubs[index].finances.sponsorshipIncome - expiredValue)
            }
            if !expiredNames.isEmpty {
                addNews(
                    headline: "Commercial Deal Expires",
                    body: "\(expiredNames.joined(separator: ", ")) \(expiredNames.count == 1 ? "has" : "have") reached the end of the agreement. Sign a replacement partner to restore sponsorship income.",
                    category: .board,
                    sender: "Commercial Director"
                )
            }
        }

        processRetirementsAndSquadRenewal()
        settleAIClubFinances()

        // Refresh the board's transfer kitty and repair any stale lineups.
        for cIdx in 0..<clubs.count {
            clubs[cIdx].finances.rolloverForNewSeason(reputation: clubs[cIdx].reputation)
            if !clubs[cIdx].isUserClub {
                // Cash-rich boards let the wage bill run hotter, as real clubs do.
                let cashRich = clubs[cIdx].finances.balance > OwnerBusiness.annualRevenue(clubs[cIdx].finances)
                applyWageInflation(clubIdx: cIdx, targetShare: cashRich ? 0.68 : 0.58)
            }
            clubs[cIdx].ensureWageHeadroom()
            clubs[cIdx].ensureTacticalIntegrity()
        }
        
        // Youth academy: age and develop existing prospects, then perform a new
        // intake whose size scales with the club's academy level.
        for cIdx in 0..<clubs.count {
            var club = clubs[cIdx]

            // Age existing prospects; develop them toward their potential.
            for pIdx in club.academyProspects.indices {
                club.academyProspects[pIdx].age += 1
                let ceiling = club.academyProspects[pIdx].potential
                if club.academyProspects[pIdx].overall < ceiling {
                    let growth = Int.random(in: 1...max(1, (ceiling - club.academyProspects[pIdx].overall)))
                    club.academyProspects[pIdx].overall = min(ceiling, club.academyProspects[pIdx].overall + growth)
                }
            }

            // Annual intake: 2-4 new prospects, more for better academies.
            let intake = max(2, min(5, club.youthAcademyLevel + 1))
            let newProspects = DataLoader.generateAcademyProspects(count: intake, club: club)
            for prospect in newProspects {
                club.addProspect(prospect)
            }
            // Keep the academy from ballooning.
            if club.academyProspects.count > 10 {
                club.academyProspects.sort { $0.potential > $1.potential }
                club.academyProspects = Array(club.academyProspects.prefix(10))
            }
            clubs[cIdx] = club
        }

        if let userClub = userClub {
            let standout = userClub.academyProspects.max { $0.potential < $1.potential }
            if let standout = standout, standout.potential >= 75 {
                addNews(
                    headline: "Academy Starlet Emerges",
                    body: "Your academy staff are excited about \(standout.fullName) (\(standout.primaryPosition.displayName), age \(standout.age)) — potential rated \(standout.potential). Consider promoting them to the senior squad.",
                    category: .board,
                    sender: "Head of Youth Development"
                )
            } else {
                addNews(
                    headline: "Youth Intake Complete",
                    body: "The academy has welcomed a new crop of prospects this summer. Review them in the Youth Academy screen.",
                    category: .board,
                    sender: "Head of Youth Development"
                )
            }
        }

        // Retirements and departures must not leave anyone without a keeper.
        ensureGoalkeepersEverywhere()

        addNews(
            headline: "Welcome to Season \(nextYear)!",
            body: "The new league season is officially underway. Training camps are open.",
            category: .general
        )
        ownerSeasonStartMarket()
    }
    
    /// Veterans retire each summer and every club is topped back up to a
    /// playable squad with young players, so the world does not slowly fill
    /// with 45-year-olds or collapse into squads that cannot field a team.
    /// Summer housekeeping for AI club finances. Clubs deep in debt sell
    /// their most valuable players to survive; clubs sitting on more than a
    /// year's turnover in cash see a third of the excess leave the club
    /// (owners' dividends, debt service and infrastructure), as real clubs
    /// do not hoard billions.
    private func settleAIClubFinances() {
        let userManages = gameMode == .manageClub
        for idx in clubs.indices where !clubs[idx].isUserClub {
            let turnover = OwnerBusiness.annualRevenue(clubs[idx].finances)
            let surplus = clubs[idx].finances.balance - turnover
            if surplus > 0 { clubs[idx].finances.balance -= surplus / 3 }

            var sales = 0
            while clubs[idx].finances.balance < -(turnover / 10), sales < 2, clubs[idx].players.count > 18 {
                guard let star = clubs[idx].players.filter({ !$0.isOnLoan }).max(by: { $0.value < $1.value }) else { break }
                let fee = max(10_000, star.value * 85 / 100)
                let wage = max(star.wage, 1)
                let buyers = clubs.indices.filter { b in
                    b != idx && !(clubs[b].isUserClub && userManages) && !clubs[b].isUserClub
                        && clubs[b].players.count < 27
                        && clubs[b].finances.transferBudget >= fee
                        && clubs[b].finances.balance >= fee
                        && clubs[b].totalWeeklyWageBill + wage <= clubs[b].finances.wageBudget
                        && rivalry(between: clubs[b].id, and: clubs[idx].id) == nil
                }
                guard let buyerIdx = buyers.sorted(by: { clubs[$0].reputation > clubs[$1].reputation }).prefix(5).randomElement(),
                      completeSigning(player: star, buyerIdx: buyerIdx, sellerIdx: idx, fee: fee, wage: wage, years: 3) else { break }
                sales += 1
                if isNewsworthy(clubs[idx].leagueTier) {
                    addNews(
                        headline: "\(clubs[idx].name) Forced to Sell \(star.fullName)",
                        body: "Debt-ridden \(clubs[idx].name) have sold \(star.fullName) to \(clubs[buyerIdx].name) for \(Player.formatCurrency(fee)) to balance the books.",
                        category: .transfer,
                        sender: "Transfer Desk"
                    )
                }
            }
            clubs[idx].ensureTacticalIntegrity()
        }
    }

    private func processRetirementsAndSquadRenewal() {
        let minimumSquad = 18
        var userRetirements: [String] = []
        var userGraduates: [String] = []

        for cIdx in clubs.indices {
            let retiring = clubs[cIdx].players.filter { Double.random(in: 0..<1) < $0.retirementChance }
            for player in retiring {
                // Keep at least a skeleton squad even if many veterans would go.
                guard clubs[cIdx].players.count > 14 else { break }
                clubs[cIdx].removePlayer(withId: player.id)
                if clubs[cIdx].isUserClub {
                    userRetirements.append("\(player.fullName) (\(player.age))")
                }
            }

            // Owner-mode and AI clubs are topped up automatically. A manager's
            // own squad is only topped up to the bare minimum needed to field a
            // team; recruitment is otherwise their job.
            let isManagedByUser = clubs[cIdx].isUserClub && gameMode == .manageClub

            if !isManagedByUser {
                // AI clubs renew from their own academy each summer...
                let ready = clubs[cIdx].academyProspects
                    .filter { $0.age >= 17 }
                    .sorted { ($0.overall + $0.potential) > ($1.overall + $1.potential) }
                    .prefix(2)
                for prospect in ready {
                    guard clubs[cIdx].promoteProspect(withId: prospect.id) != nil,
                          let pIdx = clubs[cIdx].players.firstIndex(where: { $0.id == prospect.id }) else { continue }
                    if clubs[cIdx].players[pIdx].contract == nil {
                        let wage = Player.calculateWage(overall: prospect.overall, age: prospect.age, tier: clubs[cIdx].leagueTier)
                        clubs[cIdx].players[pIdx].contract = Contract(wage: wage, yearsRemaining: 3, signingDate: season.currentDate)
                    }
                    if clubs[cIdx].isUserClub { userGraduates.append(prospect.fullName) }
                }

                // ...and release surplus players, oldest and weakest first, so
                // squads turn over instead of ageing indefinitely.
                let maximumSquad = 26
                if clubs[cIdx].players.count > maximumSquad {
                    let surplus = clubs[cIdx].players.count - maximumSquad
                    let releaseOrder = clubs[cIdx].players.sorted { lhs, rhs in
                        // Lower score = released first: weak, older players go.
                        let l = lhs.overall - max(0, lhs.age - 30)
                        let r = rhs.overall - max(0, rhs.age - 30)
                        return l < r
                    }
                    for player in releaseOrder.prefix(surplus) {
                        if var released = clubs[cIdx].removePlayer(withId: player.id) {
                            released.contract = nil
                            freeAgents.append(released)
                        }
                    }
                }
            }
            // AI squads are kept at a realistic size (about 22), not the bare
            // minimum; otherwise squads shrink every summer as veterans retire.
            let target = isManagedByUser ? 16 : (clubs[cIdx].isUserClub ? minimumSquad : 22)
            while clubs[cIdx].players.count < target {
                let regen = makeYouthRegen(for: clubs[cIdx])
                clubs[cIdx].addPlayer(regen)
                if clubs[cIdx].isUserClub { userGraduates.append(regen.fullName) }
            }
            clubs[cIdx].finances.currentWageBill = clubs[cIdx].totalWeeklyWageBill
        }

        // Free agents age and retire too; otherwise the pool never turns over.
        for idx in freeAgents.indices {
            freeAgents[idx].age += 1
            freeAgents[idx].applySeasonalDevelopment(appearances: 0)
        }
        freeAgents.removeAll { Double.random(in: 0..<1) < $0.retirementChance }
        // Keep the market a browsable size: unattached players nobody wants
        // eventually drop out of the game.
        let freeAgentCap = 400
        if freeAgents.count > freeAgentCap {
            freeAgents.sort { ($0.overall + max(0, $0.potential - $0.overall) / 2) > ($1.overall + max(0, $1.potential - $1.overall) / 2) }
            freeAgents = Array(freeAgents.prefix(freeAgentCap))
        }
        if freeAgents.count < 120 {
            seedFreeAgents(count: 150 - freeAgents.count, force: true)
        }

        if !userRetirements.isEmpty {
            let names = userRetirements.prefix(4).joined(separator: ", ")
            let remainder = userRetirements.count > 4 ? " and \(userRetirements.count - 4) more" : ""
            addNews(
                headline: userRetirements.count == 1 ? "A Club Servant Retires" : "Retirements Announced",
                body: "\(names)\(remainder) \(userRetirements.count == 1 ? "has" : "have") retired from professional football. Thank you for the memories.",
                category: .general,
                sender: "Club Secretary"
            )
        }
        if !userGraduates.isEmpty {
            addNews(
                headline: "Youngsters Promoted to the First Team",
                body: "\(userGraduates.joined(separator: ", ")) \(userGraduates.count == 1 ? "has" : "have") been promoted from the youth ranks to keep the squad at a playable size.",
                category: .board,
                sender: "Head of Youth Development"
            )
        }
    }

    /// A young player generated to replace a retiree, pitched a little below
    /// the club's current squad level with room to grow.
    private func makeYouthRegen(for club: Club) -> Player {
        // Fill whichever area of the pitch is thinnest.
        let categoryCounts = Dictionary(grouping: club.players, by: { $0.primaryPosition.category })
            .mapValues { $0.count }
        let ideals: [(PositionCategory, Int, [Position])] = [
            (.goalkeeper, 2, [.GK]),
            (.defender, 6, [.CB, .CB, .LB, .RB]),
            (.midfielder, 6, [.CM, .CM, .CDM, .CAM, .LM, .RM]),
            (.forward, 4, [.ST, .ST, .LW, .RW])
        ]
        var position: Position = .CM
        var biggestShortfall = Int.min
        for (category, ideal, options) in ideals {
            let shortfall = ideal - (categoryCounts[category] ?? 0)
            if shortfall > biggestShortfall {
                biggestShortfall = shortfall
                position = options.randomElement() ?? .CM
            }
        }

        let squadLevel = Int(club.squadAverageOverall.rounded())
        // Regens should mature around the squad's level, not above it: a
        // potential 6-16 above an entry rating 6 below the squad pushed the
        // whole world's ratings up every season.
        let overall = max(35, min(80, squadLevel - 10 + Int.random(in: -4...2)))
        let age = Int.random(in: 17...20)
        // Roughly one academy graduate in twenty-five is a genuine wonderkid
        // with a ceiling far above his first-team level; without them the
        // world ran short of new stars as the current generation aged.
        let wonderkid = Double.random(in: 0..<1) < 0.04
        let potential = min(wonderkid ? 95 : 92, overall + (wonderkid ? Int.random(in: 15...24) : Int.random(in: 3...12)))
        let identity = NamePools.randomIdentity(for: club.leagueTier.country)
        let wage = Player.calculateWage(overall: overall, age: age, tier: club.leagueTier)
        return Player(
            firstName: identity.first,
            lastName: identity.last,
            nationality: identity.nationality,
            age: age,
            height: position == .GK ? Int.random(in: 185...196) : Int.random(in: 170...190),
            weight: position == .GK ? Int.random(in: 78...90) : Int.random(in: 64...84),
            preferredFoot: Double.random(in: 0...1) < 0.25 ? .left : .right,
            positions: [position],
            attributes: DataLoader.generateAttributes(overall: overall, position: position),
            overall: overall,
            potential: potential,
            contract: Contract(wage: wage, yearsRemaining: 3, signingDate: season.currentDate)
        )
    }

    public func processEndOfSeason() {
        // Prize money, promotions and awards must only ever be settled once.
        guard season.currentPhase != .endOfSeason else { return }
        season.currentPhase = .endOfSeason
        
        // Determine final tables per tier before any movement occurs.
        var finalTables: [LeagueTier: [LeagueStanding]] = [:]
        for league in leagues {
            finalTables[league.tier] = standings(for: league)
        }
        // Merit money is paid at the rates of the division the club played
        // in, so record broadcast income before anyone changes division.
        var broadcastIncomeThisSeason: [UUID: Int] = [:]
        for club in clubs { broadcastIncomeThisSeason[club.id] = club.finances.tvIncome }
        // The record books: champions, world awards and the Hall of Fame.
        recordSeasonHistory(finalTables: finalTables)

        // Snapshot the user's campaign before promotions and relegations change
        // their leagueTier. `recordManagerSeason` needs the club/tier they
        // actually competed in, not the division they are moving to.
        var userSeasonSnapshot: (club: Club, position: Int, standing: LeagueStanding, honours: [String])?
        if gameMode == .manageClub,
           let userClub = userClub,
           let table = finalTables[userClub.leagueTier],
           let position = table.firstIndex(where: { $0.clubId == userClub.id }) {
            var honours: [String] = []
            if position == 0 {
                honours.append("\(userClub.leagueTier.displayName) Champions")
            }
            honours.append(contentsOf: userCupWins)
            userSeasonSnapshot = (
                club: userClub,
                position: position + 1,
                standing: table[position],
                honours: honours
            )
        }
        
        // The board's target is judged against the division the club played in.
        let userSeasonTarget = userSeasonSnapshot.flatMap { boardTarget(for: $0.club) }
        lastSeasonReview = buildSeasonReview(finalTables: finalTables, target: userSeasonTarget)
        if gameMode == .createClub {
            reviewAdministration()
            if let review = lastSeasonReview {
                reviewManagerPoaching(position: review.position, leagueSize: review.leagueSize)
            }
        }

        // Accumulate the club movements to apply after computing all tables.
        var promotions: [LeagueTier: [UUID]] = [:]
        var relegations: [LeagueTier: [UUID]] = [:]
        var playOffPromotions: [LeagueTier: [UUID]] = [:]
        
        for tier in LeagueTier.allCases {
            guard let table = finalTables[tier] else { continue }
            let n = table.count
            guard n > 0 else { continue }
            
            // Relegation from the bottom of the table.
            let relegationCount = min(tier.relegationCount, n)
            if relegationCount > 0 {
                let relegated = table.suffix(relegationCount).map { $0.clubId }
                relegations[tier] = relegated
            }
            
            // Automatic promotion from the top of the table (never a top flight).
            if !tier.isTopFlight {
                let autoCount = min(tier.autoPromotionCount, n)
                if autoCount > 0 {
                    promotions[tier] = table.prefix(autoCount).map { $0.clubId }
                }
                
                // Playoff promotion decided among the clubs immediately below the auto slots.
                if tier.playoffPromotionCount > 0 {
                    let lower = autoCount
                    let upper = min(autoCount + 4, n)
                    if lower < upper {
                        let playOffClubs = Array(table[lower..<upper])
                        let winner = playedPlayOffWinner(for: tier, contenders: playOffClubs)
                            ?? simulatePlayOffFinal(for: tier, contenders: playOffClubs)
                        playOffPromotions[tier] = [winner.clubId]
                        if winner.clubId == userClubId {
                            celebrate(.promotion, clubId: winner.clubId, title: "PROMOTED!",
                                      subtitle: "\(tier.displayName) play-off winners \(season.year)")
                        }
                        addNews(
                            headline: "\(clubName(for: winner.clubId)) Win the \(tier.displayName) Play-Off Final!",
                            body: "\(clubName(for: winner.clubId)) have secured promotion via the play-offs.",
                            category: .promotion,
                            sender: winner.clubId == userClubId ? "The Board" : NewsItem.newsDesk
                        )
                    }
                }
            }
        }
        
        // Map each promoted club to the destination tier and each relegated club downward.
        // Only move between tiers that actually exist this season (countries whose lower
        // divisions are not yet populated must not send clubs into a phantom league).
        let existingTiers = Set(leagues.map { $0.tier })

        func destinationTierForPromotion(from tier: LeagueTier) -> LeagueTier? {
            guard let dest = tier.higherTier, existingTiers.contains(dest) else { return nil }
            return dest
        }
        
        func destinationTierForRelegation(from tier: LeagueTier) -> LeagueTier? {
            guard let dest = tier.lowerTier, existingTiers.contains(dest) else { return nil }
            return dest
        }
        
        // Apply promotions.
        for (fromTier, clubIds) in promotions {
            guard let toTier = destinationTierForPromotion(from: fromTier) else { continue }
            for clubId in clubIds {
                moveClub(clubId, to: toTier)
                addNews(
                    headline: "\(clubName(for: clubId)) Promoted to the \(toTier.displayName)!",
                    body: "\(clubName(for: clubId)) finish in the automatic promotion places and go up.",
                    category: .promotion,
                    sender: clubId == userClubId ? "The Board" : NewsItem.newsDesk
                )
            }
        }
        
        for (fromTier, clubIds) in playOffPromotions {
            guard let toTier = destinationTierForPromotion(from: fromTier) else { continue }
            for clubId in clubIds {
                moveClub(clubId, to: toTier)
            }
        }
        
        // Apply relegations.
        for (fromTier, clubIds) in relegations {
            guard let toTier = destinationTierForRelegation(from: fromTier) else { continue }
            for clubId in clubIds {
                moveClub(clubId, to: toTier)
                addNews(
                    headline: "\(clubName(for: clubId)) Relegated to the \(toTier.displayName)",
                    body: "\(clubName(for: clubId)) drop down to the \(toTier.displayName) for next season.",
                    category: .relegation,
                    sender: clubId == userClubId ? "The Board" : NewsItem.newsDesk
                )
            }
        }

        // Club stature evolves with results. Only moves that actually happened
        // count (countries without lower divisions relegate nobody).
        let moved = Set(clubs.map { $0.id }.filter { id in
            finalTables.contains { tier, table in table.contains { $0.clubId == id } && club(withId: id)?.leagueTier != tier }
        })
        let promotedIds = Set((promotions.values.flatMap { $0 } + playOffPromotions.values.flatMap { $0 }).filter { moved.contains($0) })
        let relegatedIds = Set(relegations.values.flatMap { $0 }.filter { moved.contains($0) })
        evolveClubReputations(finalTables: finalTables, promoted: promotedIds, relegated: relegatedIds)
        checkSeasonAchievements(finalTables: finalTables, promoted: userClubId.map { promotedIds.contains($0) } ?? false)

        // The owner's tenure record.
        if gameMode == .createClub, let review = lastSeasonReview, let uid = userClubId {
            var honours: [String] = []
            if review.position == 1 { honours.append("\(review.leagueName) Champions") }
            honours.append(contentsOf: userCupWins)
            for competition in europeanCompetitions where competition.championClubId == uid {
                honours.append("\(competition.competition.displayName) Winners")
            }
            if promotedIds.contains(uid) { honours.append("Promoted") }
            if relegatedIds.contains(uid) { honours.append("Relegated") }
            owner.seasonHistory.append(ManagerSeasonRecord(
                seasonYear: review.season,
                clubName: review.clubName,
                leagueName: review.leagueName,
                played: review.won + review.drawn + review.lost,
                won: review.won,
                drawn: review.drawn,
                lost: review.lost,
                finalPosition: review.position,
                honours: honours
            ))
            let teams = finalTables.values.first { table in table.contains { $0.clubId == uid } }?.count ?? 20
            judgeSeasonObjective(position: review.position, teams: teams, promoted: promotedIds.contains(uid))
        }

        // Distribute merit prize money based on final standings.
        // Merit money is a share of each club's own broadcast income (which
        // already reflects its country and division): champions earn half as
        // much again, the bottom club a tenth. Flat Premier League-sized sums
        // used to pay Scottish and French clubs fortunes.
        for (tier, table) in finalTables {
            let n = max(1, table.count)
            for (idx, standing) in table.enumerated() {
                let ratio = Double(n - idx) / Double(n)
                guard let clubTv = broadcastIncomeThisSeason[standing.clubId] else { continue }
                let prize = max(50_000, Int(Double(clubTv) * (0.1 + 0.4 * ratio)))
                if let cIdx = clubs.firstIndex(where: { $0.id == standing.clubId }) {
                    clubs[cIdx].finances.balance += prize
                    clubs[cIdx].finances.transferBudget += prize / 2
                    if standing.clubId == userClubId {
                        seasonLedger?.prizeMoney += prize
                        addNews(
                            headline: "Prize Money: \(Player.formatCurrency(prize)) Awarded",
                            body: "\(clubs[cIdx].name) banked \(Player.formatCurrency(prize)) for finishing in \(idx + 1)\(standingRankSuffix(idx + 1)) place in the \(tier.displayName).",
                            category: .board,
                            sender: "League Committee"
                        )
                    }
                }
            }
        }

        if let uid = userClubId, gameMode == .createClub {
            let wasPromoted = promotions.values.contains(where: { $0.contains(uid) }) ||
                              playOffPromotions.values.contains(where: { $0.contains(uid) })
            if wasPromoted {
                unlockOwnerMilestone(id: "promotion")
            }
        }
        
        // Crown each tier champion.
        for tier in LeagueTier.allCases {
            guard let table = finalTables[tier], let champion = table.first else { continue }
            addNews(
                headline: "\(clubName(for: champion.clubId)) Crowned \(tier.displayName) Champions!",
                body: "\(clubName(for: champion.clubId)) finish top of the table with \(champion.points) points.",
                category: .award,
                sender: champion.clubId == userClubId ? "The Board" : NewsItem.newsDesk
            )
        }
        
        announceSeasonAwards(finalTables: finalTables)
        decideEuropeanQualification(finalTables: finalTables)
        runManagerialMerryGoRound(finalTables: finalTables)

        // Record the user's season into their managerial career history using the
        // pre-movement snapshot captured above.
        if let snapshot = userSeasonSnapshot, let target = userSeasonTarget {
            deliverBoardVerdict(club: snapshot.club, position: snapshot.position, target: target)
        }
        if let snapshot = userSeasonSnapshot {
            recordManagerSeason(
                club: snapshot.club,
                position: snapshot.position,
                played: snapshot.standing.played,
                won: snapshot.standing.won,
                drawn: snapshot.standing.drawn,
                lost: snapshot.standing.lost,
                honours: snapshot.honours
            )
        }
        
        addNews(
            headline: "Season \(season.year) Concludes!",
            body: "The final standings have been locked. Congratulations to all champions and promoted clubs. Tap 'Start New Season' on the Home screen to begin the next campaign.",
            category: .general,
            sender: "Club Secretary"
        )
    }
    
    /// Awards next season's European places from the final tables: league
    /// positions by country allocation, plus each domestic cup winner's
    /// Europa League place (passed down the table if the winner already
    /// qualified through the league). Countries are taken in allocation
    /// order, so the strongest leagues fill the competitions first.
    private func decideEuropeanQualification(finalTables: [LeagueTier: [LeagueStanding]]) {
        var ucl: [UUID] = [], uel: [UUID] = [], uecl: [UUID] = []
        let countries = LeagueCountry.allCases
            .filter { $0.competesInEurope }
            .sorted { $0.europeanAllocation.championsLeague > $1.europeanAllocation.championsLeague }
        for country in countries {
            guard let tier = LeagueTier.pyramid(for: country).first,
                  let table = finalTables[tier] else { continue }
            let order = table.map { $0.clubId }
            let allocation = country.europeanAllocation
            var cursor = 0
            func take(_ count: Int) -> [UUID] {
                let slice = Array(order.dropFirst(cursor).prefix(count))
                cursor += slice.count
                return slice
            }
            ucl += take(allocation.championsLeague)
            var europa = take(allocation.europaLeague)
            if let cupWinner = domesticCups.first(where: { $0.country == country && $0.kind == .national })?.championClubId,
               order.contains(cupWinner), !ucl.contains(cupWinner), !europa.contains(cupWinner),
               !Array(order.prefix(cursor)).contains(cupWinner) {
                europa.append(cupWinner)
            } else {
                europa += take(1)
            }
            uel += europa
            uecl += take(allocation.conferenceLeague).filter { !europa.contains($0) }
        }
        europeanQualifiers = [
            EuropeanCompetition.championsLeague.rawValue: ucl,
            EuropeanCompetition.europaLeague.rawValue: uel,
            EuropeanCompetition.conferenceLeague.rawValue: uecl,
        ]

        if let uid = userClubId {
            let qualified: String?
            if ucl.contains(uid) { qualified = EuropeanCompetition.championsLeague.displayName }
            else if uel.contains(uid) { qualified = EuropeanCompetition.europaLeague.displayName }
            else if uecl.contains(uid) { qualified = EuropeanCompetition.conferenceLeague.displayName }
            else { qualified = nil }
            if let qualified {
                lastSeasonReview?.europe = qualified
                addNews(
                    headline: "We're in the \(qualified)!",
                    body: "Our finishing position has earned a place in next season's \(qualified). European nights are coming.",
                    category: .award,
                    sender: "The Board"
                )
            }
        }
    }

    /// Whether events in a division are covered in the user's news feed: the
    /// user's own division, their country's top flight and Europe's big five.
    /// Covering all 39 leagues buried everything else in the inbox.
    private func isNewsworthy(_ tier: LeagueTier) -> Bool {
        if let userTier = userClub?.leagueTier {
            if tier == userTier { return true }
            if tier.isTopFlight && tier.country == userTier.country { return true }
        }
        let bigFive: Set<LeagueCountry> = [.england, .spain, .italy, .germany, .france]
        return tier.isTopFlight && bigFive.contains(tier.country)
    }

    /// AI boards act on a disappointing season: clubs finishing in the drop
    /// zone, or far below where their reputation says they should, often
    /// change manager. Changes in the top flights and the user's division
    /// make the news, and vacancies are offered to an unemployed user.
    private func runManagerialMerryGoRound(finalTables: [LeagueTier: [LeagueStanding]]) {
        var vacancies: [UUID] = []
        for (tier, table) in finalTables {
            let n = table.count
            guard n >= 4 else { continue }
            // Expected finishing order by reputation.
            let expectedOrder = table.map { $0.clubId }.sorted {
                (club(withId: $0)?.reputation ?? 0) > (club(withId: $1)?.reputation ?? 0)
            }
            for (index, standing) in table.enumerated() {
                guard let cIdx = clubs.firstIndex(where: { $0.id == standing.clubId }),
                      !clubs[cIdx].isUserClub else { continue }
                let position = index + 1
                let expected = (expectedOrder.firstIndex(of: standing.clubId) ?? index) + 1
                let inDropZone = position > n - max(2, tier.relegationCount)
                let underperformed = position - expected >= max(5, n / 3)
                let chance = inDropZone ? 0.55 : (underperformed ? 0.45 : 0.04)
                guard Double.random(in: 0..<1) < chance else { continue }

                let outgoing = clubs[cIdx].manager
                let identity = NamePools.randomIdentity(for: tier.country)
                let incoming = "\(identity.first) \(identity.last)"
                clubs[cIdx].manager = incoming
                vacancies.append(clubs[cIdx].id)
                if isNewsworthy(tier) {
                    addNews(
                        headline: "\(clubs[cIdx].name) Part Ways With \(outgoing)",
                        body: "After finishing \(position)\(standingRankSuffix(position)) in the \(tier.displayName), \(clubs[cIdx].name) have appointed \(incoming) as their new manager.",
                        category: .general,
                        sender: "Football News"
                    )
                }
            }
        }
        // An unemployed manager hears about some of the openings.
        if gameMode == .manageClub, userClubId == nil, !vacancies.isEmpty {
            generateJobOffers(maxCount: 4, excludeUserClub: false)
        }
    }

    /// Reputations move with performance: finishing above the place a club's
    /// stature predicts raises it, falling short lowers it, and promotion,
    /// relegation, trophies and European football add their own weight. A
    /// gentle pull back toward the division's norm stops runaway values.
    /// Attendance follows reputation.
    private func evolveClubReputations(finalTables: [LeagueTier: [LeagueStanding]],
                                       promoted: Set<UUID>, relegated: Set<UUID>) {
        let europeans = Set(europeanCompetitions.flatMap { $0.participantClubIds })
        let trophyWinners = Set(domesticCups.compactMap { $0.championClubId }
                                + europeanCompetitions.compactMap { $0.championClubId })
        for (_, table) in finalTables {
            let n = table.count
            guard n > 1 else { continue }
            let ids = table.map { $0.clubId }
            let byReputation = ids.sorted { (club(withId: $0)?.reputation ?? 0) > (club(withId: $1)?.reputation ?? 0) }
            let divisionAverage = Double(ids.compactMap { club(withId: $0)?.reputation }.reduce(0, +)) / Double(n)
            for (index, id) in ids.enumerated() {
                guard let cIdx = clubs.firstIndex(where: { $0.id == id }) else { continue }
                let position = index + 1
                let expected = (byReputation.firstIndex(of: id) ?? index) + 1
                var delta = Double(expected - position) / max(2.0, Double(n) / 6.0)
                delta = max(-3, min(3, delta))
                if index == 0 { delta += 2 }                 // champions
                if promoted.contains(id) { delta += 4 }
                if relegated.contains(id) { delta -= 4 }
                if trophyWinners.contains(id) { delta += 2 }
                if europeans.contains(id) { delta += 1 }
                // Mean reversion toward the division's typical stature.
                delta += (divisionAverage - Double(clubs[cIdx].reputation)) * 0.03
                let newRep = max(15, min(99, clubs[cIdx].reputation + Int(delta.rounded())))
                if clubs[cIdx].isUserClub && newRep != clubs[cIdx].reputation {
                    addNews(
                        headline: newRep > clubs[cIdx].reputation ? "Club Profile Rising" : "Club Profile Slipping",
                        body: "\(clubs[cIdx].name)'s reputation moves from \(clubs[cIdx].reputation) to \(newRep) after this season.",
                        category: .board,
                        sender: "Football Analysts"
                    )
                }
                clubs[cIdx].reputation = newRep
                let rep = Double(max(20, min(95, newRep)))
                clubs[cIdx].finances.averageAttendancePct = min(0.98, 0.55 + (rep - 20) / 120.0)
            }
        }
    }

    /// AI clubs spend what they earn: wages drift up (at most 15% a year)
    /// toward about 58% of turnover, the real-world norm. Without this, AI
    /// wage bills stayed near 40% of income and clubs banked ever-growing
    /// surpluses.
    private func applyWageInflation(clubIdx cIdx: Int, maximumRise: Double = 1.15, targetShare: Double = 0.58) {
        let turnover = OwnerBusiness.annualRevenue(clubs[cIdx].finances)
        let targetWeekly = Double(turnover) * targetShare / 52.0
        let currentPlayerBill = Double(clubs[cIdx].totalPlayerWageBill)
        guard currentPlayerBill > 0, currentPlayerBill < targetWeekly else { return }
        let factor = min(maximumRise, targetWeekly / currentPlayerBill)
        for p in clubs[cIdx].players.indices {
            if var contract = clubs[cIdx].players[p].contract {
                contract.wage = Int(Double(contract.wage) * factor)
                clubs[cIdx].players[p].contract = contract
            }
        }
        clubs[cIdx].finances.currentWageBill = clubs[cIdx].totalWeeklyWageBill
    }

    /// Summarises the user's season for the review card (both modes).
    private func buildSeasonReview(finalTables: [LeagueTier: [LeagueStanding]],
                                   target: (goal: String, position: Int)?) -> SeasonReview? {
        guard let club = userClub,
              let competition = season.fixtures.first(where: { $0.involves(clubId: club.id) && !$0.isCupTie })?.competition,
              let league = leagues.first(where: { $0.name == competition }),
              let table = finalTables[league.tier],
              let index = table.firstIndex(where: { $0.clubId == club.id }) else { return nil }
        let standing = table[index]
        let position = index + 1

        var cupRun: String?
        if let cup = domesticCups.first(where: { $0.country == league.tier.country && $0.kind == .national }) {
            if cup.championClubId == club.id {
                cupRun = "\(cup.name) winners"
            } else if let lastTie = season.fixtures.filter({ $0.competition == cup.name && $0.involves(clubId: club.id) }).last,
                      let round = lastTie.cupRound {
                cupRun = "\(cup.name): out in the \(round.lowercased())"
            } else {
                cupRun = "\(cup.name): bye to a later round"
            }
        }

        let topScorer = club.players.max { $0.seasonStats.goals < $1.seasonStats.goals }
        let best = club.players.filter { $0.seasonStats.appearances >= 10 }
            .max { $0.seasonStats.averageRating < $1.seasonStats.averageRating }

        var review = SeasonReview(
            season: season.year,
            clubName: club.name,
            leagueName: league.name,
            position: position,
            leagueSize: table.count,
            points: standing.points,
            won: standing.won,
            drawn: standing.drawn,
            lost: standing.lost,
            goalsFor: standing.goalsFor,
            goalsAgainst: standing.goalsAgainst,
            targetGoal: target?.goal,
            targetMet: target.map { position <= $0.position },
            cupRun: cupRun,
            topScorer: topScorer.flatMap { $0.seasonStats.goals > 0 ? "\($0.fullName) (\($0.seasonStats.goals))" : nil },
            playerOfSeason: best.map { "\($0.fullName) (\(String(format: "%.2f", $0.seasonStats.averageRating)))" }
        )
        let runs = otherCompetitionRuns(for: club.id, country: league.tier.country)
        review.leagueCupRun = runs.leagueCup
        review.europeanRuns = runs.europe.isEmpty ? nil : runs.europe
        addDivisionHonours(to: &review, table: table, finalTables: finalTables)
        return review
    }

    /// Golden Boot and Player of the Season for every top flight, plus the
    /// user's own division. Announced in the news feed.
    private func announceSeasonAwards(finalTables: [LeagueTier: [LeagueStanding]]) {
        for league in leagues where isNewsworthy(league.tier) {
            // Use the final table: promotions and relegations have already
            // changed the league's membership by the time awards are announced.
            let memberIds = finalTables[league.tier]?.map { $0.clubId } ?? league.clubIds
            let members = memberIds.compactMap { club(withId: $0) }
            let squad = members.flatMap { club in club.players.map { (player: $0, club: club) } }
            guard !squad.isEmpty else { continue }

            if let scorer = squad.max(by: { $0.player.seasonStats.goals < $1.player.seasonStats.goals }),
               scorer.player.seasonStats.goals > 0 {
                addNews(
                    headline: "\(league.name) Golden Boot: \(scorer.player.fullName)",
                    body: "\(scorer.player.fullName) of \(scorer.club.name) finishes as the \(league.name)'s top scorer with \(scorer.player.seasonStats.goals) goals.",
                    category: .award,
                    sender: scorer.club.id == userClubId ? league.name : NewsItem.newsDesk
                )
            }
            let regulars = squad.filter { $0.player.seasonStats.appearances >= 15 }
            if let best = regulars.max(by: { $0.player.seasonStats.averageRating < $1.player.seasonStats.averageRating }) {
                let stats = best.player.seasonStats
                addNews(
                    headline: "\(league.name) Player of the Season: \(best.player.fullName)",
                    body: "\(best.club.name)'s \(best.player.fullName) is named Player of the Season after averaging \(String(format: "%.2f", stats.averageRating)) across \(stats.appearances) games, with \(stats.goals) goals and \(stats.assists) assists.",
                    category: .award,
                    sender: best.club.id == userClubId ? league.name : NewsItem.newsDesk
                )
            }
        }
    }

    // MARK: - Season End Helpers
    
    /// Returns a club's display name, falling back to a placeholder when unknown.
    public func clubName(for id: UUID) -> String {
        return clubs.first { $0.id == id }?.name ?? "Unknown Club"
    }

    private func standingRankSuffix(_ rank: Int) -> String {
        switch rank % 10 {
        case 1 where rank % 100 != 11: return "st"
        case 2 where rank % 100 != 12: return "nd"
        case 3 where rank % 100 != 13: return "rd"
        default: return "th"
        }
    }
    
    /// Moves a club into a new tier, updating both the club record and the league membership lists.
    public func moveClub(_ clubId: UUID, to newTier: LeagueTier) {
        guard let clubIdx = clubs.firstIndex(where: { $0.id == clubId }) else { return }
        let oldTier = clubs[clubIdx].leagueTier
        guard oldTier != newTier else { return }
        
        clubs[clubIdx].leagueTier = newTier
        
        // Adjust finances baseline for the new division's economics, preserving balance/history.
        // Use the club's actual reputation and stadium capacity so promotion or
        // relegation does not silently reset its commercial stature to a generic club.
        let newFinances = ClubFinances.defaultFor(
            tier: newTier,
            reputation: clubs[clubIdx].reputation,
            capacity: clubs[clubIdx].stadiumCapacity
        )
        clubs[clubIdx].finances.transferBudget = newFinances.transferBudget
        clubs[clubIdx].finances.wageBudget = newFinances.wageBudget
        clubs[clubIdx].finances.tvIncome = newFinances.tvIncome
        clubs[clubIdx].finances.matchdayIncome = newFinances.matchdayIncome
        clubs[clubIdx].finances.sponsorshipIncome = newFinances.sponsorshipIncome
        clubs[clubIdx].finances.merchandiseIncome = newFinances.merchandiseIncome
        clubs[clubIdx].finances.averageTicketPrice = newFinances.averageTicketPrice
        clubs[clubIdx].finances.averageAttendancePct = newFinances.averageAttendancePct
        clubs[clubIdx].finances.stadiumCapacity = clubs[clubIdx].stadiumCapacity
        // The new tier baseline is only an estimate; the squad's actual wage
        // bill must still drive the weekly ledger.
        clubs[clubIdx].finances.currentWageBill = clubs[clubIdx].totalWeeklyWageBill
        if clubs[clubIdx].isUserClub {
            // Preserve active commercial partnerships when the tier baseline is reset.
            clubs[clubIdx].finances.sponsorshipIncome += owner.sponsorshipDeals.reduce(0) { $0 + $1.annualValue }
        }
        
        // Remove from the old league's membership.
        if let oldLeagueIdx = leagues.firstIndex(where: { $0.tier == oldTier }) {
            leagues[oldLeagueIdx].clubIds.removeAll { $0 == clubId }
        }
        // Add to the new league's membership.
        if let newLeagueIdx = leagues.firstIndex(where: { $0.tier == newTier }) {
            if !leagues[newLeagueIdx].clubIds.contains(clubId) {
                leagues[newLeagueIdx].clubIds.append(clubId)
            }
        }
    }
    
    // MARK: - Promotion Play-Offs

    static let playOffSuffix = " Play-Offs"
    static let playOffFirstLeg = "Semi-Final, leg 1"
    static let playOffSecondLeg = "Semi-Final, leg 2"

    /// Promotion play-offs are real matches, run as in the English Football
    /// League. Once all of a division's league games are played, the four
    /// clubs below the automatic places meet in two-legged semi-finals (the
    /// higher seed plays the lowest, the middle two each other). The lower
    /// seed hosts the first leg; the second leg, at the higher seed's ground,
    /// goes to extra time and penalties if the tie is level on aggregate
    /// (there are no away goals). The winners meet in a one-off final at a
    /// neutral ground, with extra time and penalties if needed.
    private func progressLeaguePlayOffs() {
        let existingTiers = Set(leagues.map { $0.tier })
        // Runs every slot: skip divisions still playing without rescanning
        // every fixture for each of them.
        let stillPlaying = Set(season.fixtures.lazy.filter { !$0.isPlayed }.map { $0.competition })
        for league in leagues where !stillPlaying.contains(league.name) {
            let tier = league.tier
            guard !tier.isTopFlight, tier.playoffPromotionCount > 0,
                  let higher = tier.higherTier, existingTiers.contains(higher) else { continue }
            guard season.fixtures.contains(where: { $0.competition == league.name }) else { continue }
            let name = league.name + Self.playOffSuffix
            let playOffs = season.fixtures.filter { $0.competition == name }
            let order = standings(for: league).map { $0.clubId }

            if playOffs.isEmpty {
                let automatic = min(tier.autoPromotionCount, order.count)
                let contenders = Array(order.dropFirst(automatic).prefix(4))
                guard contenders.count >= 2 else { continue }
                let slot = nextSaturdaySlot(after: season.currentWeek)
                if contenders.count == 4 {
                    // First legs at the lower seed's ground.
                    addPlayOffFixture(home: contenders[3], away: contenders[0], round: Self.playOffFirstLeg, competition: name, slot: slot)
                    addPlayOffFixture(home: contenders[2], away: contenders[1], round: Self.playOffFirstLeg, competition: name, slot: slot)
                } else {
                    addPlayOffFixture(home: contenders[0], away: contenders[1], round: "Final", competition: name, slot: slot)
                }
                if let uid = userClubId, let seed = contenders.firstIndex(of: uid),
                   let tie = season.fixtures.last(where: { $0.competition == name && $0.involves(clubId: uid) }),
                   let opponent = tie.opponentId(for: uid) {
                    let position = automatic + seed + 1
                    let format = tie.cupRound == "Final"
                        ? "in the play-off final at a neutral ground"
                        : "in the play-off semi-final, first leg \(tie.homeClubId == uid ? "at home" : "away") and the return leg a week later"
                    addNews(
                        headline: "Into the \(tier.displayName) Play-Offs",
                        body: "We finished \(position)\(standingRankSuffix(position)) and face \(clubName(for: opponent)) \(format), starting \(Self.longDateText(tie.date)). Get through to the final and win it, and we are promoted.",
                        category: .promotion,
                        sender: "The Board"
                    )
                }
                continue
            }

            // First legs played: the return legs, at the higher seed's ground.
            let firstLegs = playOffs.filter { $0.cupRound == Self.playOffFirstLeg }
            let secondLegs = playOffs.filter { $0.cupRound == Self.playOffSecondLeg }
            if !firstLegs.isEmpty && secondLegs.isEmpty {
                guard firstLegs.allSatisfy({ $0.isPlayed }) else { continue }
                let slot = nextSaturdaySlot(after: season.currentWeek)
                for leg in firstLegs {
                    addPlayOffFixture(home: leg.awayClubId, away: leg.homeClubId, round: Self.playOffSecondLeg, competition: name, slot: slot)
                }
                continue
            }

            // Both semi-finals decided: draw up the final.
            guard !playOffs.contains(where: { $0.cupRound == "Final" }) else { continue }
            let semis: [Fixture]
            let winners: [UUID]
            if !secondLegs.isEmpty {
                guard secondLegs.allSatisfy({ $0.isPlayed }) else { continue }
                semis = firstLegs + secondLegs
                winners = secondLegs.map { leg in playOffAggregateWinner(secondLeg: leg, firstLegs: firstLegs) }
            } else {
                // A single-match semi-final from an older save.
                semis = playOffs.filter { $0.cupRound == "Semi-Final" }
                guard semis.count == 2, semis.allSatisfy({ $0.isPlayed }) else { continue }
                winners = semis.map { $0.winnerClubId ?? $0.homeClubId }
            }
            guard winners.count == 2 else { continue }
            let seeded = winners.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
            let slot = nextSaturdaySlot(after: season.currentWeek)
            addPlayOffFixture(home: seeded[0], away: seeded[1], round: "Final", competition: name, slot: slot)
            if let uid = userClubId {
                if let opponent = seeded.first(where: { $0 != uid }), seeded.contains(uid) {
                    addNews(
                        headline: "Play-Off Final!",
                        body: "We are one game from promotion. \(clubName(for: opponent)) stand in the way in the \(tier.displayName) play-off final at a neutral ground on \(Self.longDateText(dateForWeek(slot))).",
                        category: .promotion,
                        sender: "The Board"
                    )
                } else if semis.contains(where: { $0.involves(clubId: uid) }) {
                    addNews(
                        headline: "Play-Off Heartbreak",
                        body: "Our promotion bid ends in the play-off semi-final. We go again next season in the \(tier.displayName).",
                        category: .promotion,
                        sender: "The Board"
                    )
                }
            }
        }
    }

    /// Who went through a two-legged play-off semi-final: aggregate score
    /// or a second-leg shootout, with the
    /// higher seed, at home in the second leg, if it is somehow still level.
    private func playOffAggregateWinner(secondLeg: Fixture, firstLegs: [Fixture]) -> UUID {
        let higher = secondLeg.homeClubId, lower = secondLeg.awayClubId
        guard let second = secondLeg.result else { return higher }
        if let winner = second.shootoutWinnerClubId { return winner }
        let first = firstLegs.first { $0.homeClubId == lower && $0.awayClubId == higher }?.result
        let higherGoals = second.homeGoals + (first?.awayGoals ?? 0)
        let lowerGoals = second.awayGoals + (first?.homeGoals ?? 0)
        return lowerGoals > higherGoals ? lower : higher
    }

    /// For the second leg of a play-off semi-final: the goals tonight's home
    /// and away sides scored in the first leg.
    func playOffSecondLegCarry(_ fixture: Fixture) -> (home: Int, away: Int)? {
        guard fixture.cupRound == Self.playOffSecondLeg,
              let first = season.fixtures.first(where: {
                  $0.competition == fixture.competition && $0.cupRound == Self.playOffFirstLeg
                      && $0.homeClubId == fixture.awayClubId && $0.awayClubId == fixture.homeClubId
              }), let result = first.result else { return nil }
        return (home: result.awayGoals, away: result.homeGoals)
    }

    /// The first Saturday on the calendar after the given slot.
    private func nextSaturdaySlot(after slot: Int) -> Int {
        for n in 1...60 where SeasonCalendar.saturday(n) > slot {
            return SeasonCalendar.saturday(n)
        }
        return slot + 1
    }

    private func addPlayOffFixture(home: UUID, away: UUID, round: String, competition: String, slot: Int) {
        season.fixtures.append(Fixture(
            homeClubId: home,
            awayClubId: away,
            matchWeek: slot,
            date: dateForWeek(slot),
            competition: competition,
            cupRound: round
        ))
    }

    /// The winner of a division's play-off final, when it was played.
    private func playedPlayOffWinner(for tier: LeagueTier, contenders: [LeagueStanding]) -> LeagueStanding? {
        guard let league = leagues.first(where: { $0.tier == tier }),
              let final = season.fixtures.first(where: {
                  $0.competition == league.name + Self.playOffSuffix && $0.cupRound == "Final" && $0.isPlayed
              }) else { return nil }
        let winnerId = final.winnerClubId ?? final.homeClubId
        return contenders.first { $0.clubId == winnerId } ?? LeagueStanding(clubId: winnerId)
    }

    private func simulatePlayOffFinal(for tier: LeagueTier, contenders: [LeagueStanding]) -> LeagueStanding {
        guard !contenders.isEmpty else {
            return LeagueStanding(clubId: UUID())
        }
        guard contenders.count > 1 else { return contenders[0] }
        
        // Seeded bracket: 1st vs 4th, 2nd vs 3rd, with the higher seed hosting.
        var bracket = contenders
        while bracket.count > 1 {
            var nextRound: [LeagueStanding] = []
            var i = 0
            while i < bracket.count {
                if i + 1 < bracket.count {
                    nextRound.append(playOffWinner(bracket[i], bracket[i + 1]))
                } else {
                    nextRound.append(bracket[i])
                }
                i += 2
            }
            bracket = nextRound
        }
        return bracket[0]
    }
    
    /// Favours the higher-placed club but allows an upset based on relative points.
    private func playOffWinner(_ higher: LeagueStanding, _ lower: LeagueStanding) -> LeagueStanding {
        let pointGap = Double(higher.points - lower.points)
        // Base probability the better side advances, scaled by the points gap.
        let higherChance = max(0.35, min(0.80, 0.55 + pointGap / 100.0))
        return Double.random(in: 0...1) < higherChance ? higher : lower
    }
    
    // MARK: - Managerial Career & Job Offers

    /// Clears any club association, leaving the user unemployed but with a
    /// manager profile intact.
    public func goUnemployed() {
        guard gameMode == .manageClub else { return }
        abandonLiveTransferTalks()
        if let previousIdx = clubs.firstIndex(where: { $0.isUserClub }) {
            clubs[previousIdx].manager = "Caretaker Manager"
        }
        userClubId = nil
        activeMatchFixtureId = nil
        for idx in 0..<clubs.count {
            clubs[idx].isUserClub = false
        }
    }

    /// Out of a club job (perhaps running a national team instead): a week
    /// passes while the rest of the world plays on, and clubs or federations
    /// may call. At the end of a season, the next one begins.
    public func advanceWhileUnemployed() {
        guard gameMode == .manageClub, userClubId == nil else { return }
        if isEndOfSeason {
            startNewSeason()
        } else {
            advanceWeek()
        }
        if Double.random(in: 0..<1) < 0.35 {
            generateJobOffers(maxCount: 2, excludeUserClub: false)
        }
    }

    /// Ends every live negotiation tied to the user's current club. Called when
    /// the manager leaves, so a bid made for the old club cannot complete for
    /// (or charge) the new one, and old inbox actions stop being actionable.
    private func abandonLiveTransferTalks() {
        for idx in pendingTransferOffers.indices where pendingTransferOffers[idx].isLive {
            pendingTransferOffers[idx].status = .withdrawn
            pendingTransferOffers[idx].weeksUntilResponse = 0
            markOfferMailRead(offerId: pendingTransferOffers[idx].id)
        }
        negotiationTargetPlayerId = nil
    }

    /// Builds a pool of realistic job offers for the user based on their current
    /// reputation. Vacancies skew toward clubs whose reputation is within reach
    /// of the manager's own standing; unemployed users see more low-reputation
    /// openings, successful managers attract bigger clubs.
    public func generateJobOffers(maxCount: Int = 4, excludeUserClub: Bool = true) {
        guard gameMode == .manageClub, clubs.count > 2 else { return }
        let requestedCount = max(1, maxCount)

        let userRep = manager.reputation
        let userClubIdLocal = userClubId

        var candidates = clubs.filter { club in
            if excludeUserClub, let uid = userClubIdLocal, club.id == uid { return false }
            // Only clubs at or below the manager's reach (allow some stretch upward).
            return club.reputation <= userRep + 15
        }
        // A manager whose reputation has collapsed can always find work at the
        // smallest clubs; without this, a second sacking could leave the user
        // with no offers at all, permanently stuck in unemployment.
        if candidates.count < requestedCount * 3 {
            let fallback = clubs
                .filter { club in !(excludeUserClub && club.id == userClubIdLocal) && !candidates.contains(where: { $0.id == club.id }) }
                .sorted { $0.reputation < $1.reputation }
                .prefix(requestedCount * 3 - candidates.count)
            candidates.append(contentsOf: fallback)
        }

        // Clubs already offering are not asked again, and the rest are drawn
        // from across the manager's whole range (most near his level, some a
        // step up, some a step down), not just the biggest dozen, so every
        // search turns up different clubs.
        let alreadyOffering = Set(jobOffers.compactMap { $0.clubId })
        candidates.removeAll { alreadyOffering.contains($0.id) }
        func fit(_ club: Club) -> Double {
            let gap = Double(club.reputation - userRep)
            return gap > 0 ? max(0.15, 1 - gap / 18) : max(0.25, 1 + gap / 40)
        }
        var weighted = candidates.map { ($0, fit($0) * Double.random(in: 0.3...1.0)) }
        weighted.sort { $0.1 > $1.1 }
        let sorted = weighted.map { $0.0 }
        var newOffers: [JobOffer] = []
        for club in sorted.prefix(requestedCount * 3) {
            let league = leagues.first { $0.tier == club.leagueTier }
            let wage = max(1_000, club.finances.wageBudget / 40)
            newOffers.append(
                JobOffer(
                    clubId: club.id,
                    kind: .club,
                    teamName: club.name,
                    leagueName: league?.name ?? club.leagueTier.displayName,
                    reputation: club.reputation,
                    offeredWage: wage,
                    seasonYear: season.year
                )
            )
        }

        let chosen = Array(newOffers.prefix(requestedCount)).shuffled()

        // De-duplicate against offers we already hold.
        let existingClubIds = Set(jobOffers.compactMap { $0.clubId })
        let fresh = chosen.filter { offer in
            guard let cid = offer.clubId else { return true }
            return !existingClubIds.contains(cid)
        }
        jobOffers.append(contentsOf: fresh)

        for offer in fresh {
            addNews(
                headline: "\(offer.teamName) Approach You",
                body: "\(offer.teamName) of the \(offer.leagueName) would like you to become their next manager. Visit Job Offers to respond.",
                category: .board,
                sender: "\(offer.teamName) Board"
            )
        }
        generateNationalTeamOffers()
    }

    /// The standing a national team asks of its manager: its strength, a bit
    /// more for the very best sides.
    func nationalTeamReputation(_ team: NationalTeam) -> Int {
        let ranked = team.fifaRanking.map { $0 <= 10 ? 8 : $0 <= 30 ? 4 : 0 } ?? 0
        return min(99, Int(team.strength) + ranked)
    }

    /// National federations looking for a manager approach the user if his
    /// reputation is high enough. An international post can be held alongside
    /// a club job, or on its own.
    func generateNationalTeamOffers() {
        guard Self.internationalFootballEnabled else { return }
        guard gameMode == .manageClub, managedNationalTeamId == nil, !nationalTeams.isEmpty else { return }
        // Not every search: federations change managers rarely.
        guard Double.random(in: 0..<1) < (userClubId == nil ? 0.6 : 0.35) else { return }
        let rep = manager.reputation
        let offered = Set(jobOffers.compactMap { $0.nationalTeamId })
        let candidates = nationalTeams.filter { team in
            !offered.contains(team.id) && nationalTeamReputation(team) <= rep + 8 && nationalTeamReputation(team) >= rep - 30
        }
        for team in candidates.shuffled().prefix(Int.random(in: 1...2)) {
            let offer = JobOffer(
                clubId: nil,
                kind: .nationalTeam,
                teamName: team.name,
                leagueName: "\(team.confederation.rawValue) national team",
                reputation: nationalTeamReputation(team),
                offeredWage: max(2_000, nationalTeamReputation(team) * 600),
                seasonYear: season.year,
                nationalTeamId: team.id
            )
            jobOffers.append(offer)
            addNews(
                headline: "\(team.name) Want You as Head Coach",
                body: "The \(team.name) federation would like you to lead the national team. You can take it on alongside your club job, or on its own. Visit Job Offers to respond.",
                category: .board,
                sender: "\(team.name) Federation"
            )
        }
    }

    /// Accepts an international post. It does not affect the club job.
    @discardableResult
    public func acceptNationalTeamOffer(_ offer: JobOffer) -> Bool {
        guard let id = offer.nationalTeamId, nationalTeams.contains(where: { $0.id == id }) else {
            jobOffers.removeAll { $0.id == offer.id }
            return false
        }
        takeOverNationalTeam(id: id)
        hasStartedCareer = true
        manager.reputation = min(100, max(manager.reputation, min(offer.reputation, manager.reputation + 5)))
        // Only one national team at a time.
        jobOffers.removeAll { $0.kind == .nationalTeam }
        return true
    }

    /// Accepts a job offer, moving the user to that club. Any current club is
    /// vacated first. Returns the new club on success.
    @discardableResult
    public func acceptJobOffer(_ offer: JobOffer) -> Club? {
        guard gameMode == .manageClub else { return nil }
        guard let clubId = offer.clubId,
              let idx = clubs.firstIndex(where: { $0.id == clubId }) else {
            // National-team offers are handled by a later stage; just drop them.
            jobOffers.removeAll { $0.id == offer.id }
            return nil
        }

        abandonLiveTransferTalks()
        if let previousIdx = clubs.firstIndex(where: { $0.isUserClub }), previousIdx != idx {
            clubs[previousIdx].manager = "Caretaker Manager"
        }
        for otherIdx in 0..<clubs.count {
            clubs[otherIdx].isUserClub = (otherIdx == idx)
        }
        clubs[idx].ensureTacticalIntegrity()
        userClubId = clubId
        hasStartedCareer = true
        jobOffers.removeAll()

        // A new job starts with a clean slate: the previous board's patience,
        // team talk and training week do not carry over.
        jobSecurity = JobSecurity()
        teamTalk = nil
        teamTalkAppliedWeek = nil
        lastTrainingWeek = nil
        activeMatchFixtureId = nil

        // Reputation is nudged toward the new role's standing.
        manager.reputation = min(100, max(manager.reputation, min(offer.reputation, manager.reputation + 10)))
        clubs[idx].manager = manager.fullName

        addNews(
            headline: "You Are Now the Manager of \(clubs[idx].name)!",
            body: "\(clubs[idx].name) have appointed \(manager.fullName) as first-team manager.",
            category: .board,
            sender: "The Board — \(clubs[idx].name)"
        )
        seedManagerInbox()
        seedAcademies()
        return clubs[idx]
    }

    /// Declines a single job offer.
    public func declineJobOffer(_ offer: JobOffer) {
        jobOffers.removeAll { $0.id == offer.id }
    }

    /// Declines every outstanding offer.
    public func declineAllJobOffers() {
        jobOffers.removeAll()
    }

    /// Appends a completed season to the manager's career history and lightly
    /// adjusts reputation based on final position and the division's strength.
    public func recordManagerSeason(
        club: Club,
        position: Int,
        played: Int,
        won: Int,
        drawn: Int,
        lost: Int,
        honours: [String] = []
    ) {
        let league = leagues.first { $0.tier == club.leagueTier }
        let record = ManagerSeasonRecord(
            seasonYear: season.year,
            clubName: club.name,
            leagueName: league?.name ?? club.leagueTier.displayName,
            played: played,
            won: won,
            drawn: drawn,
            lost: lost,
            finalPosition: position,
            honours: honours
        )
        manager.careerHistory.append(record)

        // Reputation drifts toward a target based on league strength and finish.
        let tierBonus: Int
        switch club.leagueTier.level {
        case 1: tierBonus = club.leagueTier.country == .england ? 25 : 20
        case 2: tierBonus = 15
        case 3: tierBonus = 8
        default: tierBonus = 3
        }
        let positionPenalty = min(20, max(0, position - 1) * 2)
        let target = min(100, max(5, club.reputation / 2 + tierBonus - positionPenalty))
        manager.reputation = (manager.reputation * 2 + target) / 3
        manager.age += 1

        // Coaching is judged against expectations: where the club "should"
        // have finished (its standing among the division's clubs) against
        // where it did, plus every trophy. Winning the treble with a side
        // expected to finish mid-table is a career-making season; finishing
        // where you were expected to adds a little; falling well short
        // costs. Coaching ability feeds straight into match performance.
        let tableSize = max(1, finalTableSize(for: club))
        let divisionClubs = clubs.filter { $0.leagueTier == club.leagueTier }
        let expected = min(tableSize, (divisionClubs.filter { $0.reputation > club.reputation }.count) + 1)
        let beatBy = expected - position                       // places above expectation
        let trophies = honours.filter { $0 != "Relegated" }.count
        var gains = 1 + max(0, min(10, beatBy)) + trophies * 3
        if trophies >= 3 { gains += 4 }                         // a treble (or better)
        let losses = beatBy <= -6 ? 2 : (beatBy <= -3 ? 1 : 0)
        for _ in 0..<gains {
            switch Int.random(in: 0..<4) {
            case 0: manager.tactical = min(99, manager.tactical + 1)
            case 1: manager.attacking = min(99, manager.attacking + 1)
            case 2: manager.defending = min(99, manager.defending + 1)
            default: manager.youthDevelopment = min(99, manager.youthDevelopment + 1)
            }
        }
        for _ in 0..<losses {
            switch Int.random(in: 0..<3) {
            case 0: manager.tactical = max(1, manager.tactical - 1)
            case 1: manager.attacking = max(1, manager.attacking - 1)
            default: manager.defending = max(1, manager.defending - 1)
            }
        }
        // Overachieving and silverware make a manager's name, too.
        manager.reputation = min(100, manager.reputation + max(0, beatBy) / 2 + trophies * 3)
        if gains >= 4 {
            let summary = trophies > 0
                ? "\(trophies) \(trophies == 1 ? "trophy" : "trophies") and a\(position)\(position == 1 ? "st" : position == 2 ? "nd" : position == 3 ? "rd" : "th")-place finish with a side expected to come \(expected)\(expected == 1 ? "st" : expected == 2 ? "nd" : expected == 3 ? "rd" : "th")"
                : "finishing \(position)\(position == 1 ? "st" : position == 2 ? "nd" : position == 3 ? "rd" : "th") with a side expected to come \(expected)\(expected == 1 ? "st" : expected == 2 ? "nd" : expected == 3 ? "rd" : "th")"
            addNews(
                headline: "Your Coaching Reputation Grows",
                body: "The game has noticed: \(summary). Your coaching rating rises to \(manager.overallCoaching) and your reputation to \(manager.reputation).",
                category: .award,
                sender: "League Managers Association"
            )
        } else if losses > 0 {
            addNews(
                headline: "A Disappointing Season",
                body: "Finishing \(position) with a side expected to come \(expected) has cost you some standing. Your coaching rating is now \(manager.overallCoaching).",
                category: .board,
                sender: "League Managers Association"
            )
        }
    }

    /// Clubs in the division the club finished the season in.
    private func finalTableSize(for club: Club) -> Int {
        let competition = season.fixtures.first { $0.involves(clubId: club.id) && !$0.isCupTie }?.competition
        return leagues.first { $0.name == competition }?.clubIds.count ?? 20
    }

    public func addNews(headline: String, body: String, category: NewsCategory, sender: String = "Club News Desk", transferOfferId: UUID? = nil) {
        let item = NewsItem(
            headline: headline,
            body: body,
            date: season.currentDate,
            category: category,
            sender: sender,
            transferOfferId: transferOfferId
        )
        news.insert(item, at: 0)
    }

    /// Number of unread manager messages.
    public var unreadMailCount: Int {
        news.reduce(0) { $0 + ($1.isRead || !$1.isInboxMessage ? 0 : 1) }
    }

    /// Marks every message in the inbox as read.
    public func markAllMailRead() {
        for idx in news.indices where news[idx].isInboxMessage && !news[idx].isRead {
            news[idx].isRead = true
        }
    }

    /// Marks a single message as read.
    public func markMailRead(id: UUID) {
        guard let idx = news.firstIndex(where: { $0.id == id }) else { return }
        news[idx].isRead = true
    }

    /// Removes a message without altering any transfer offer it references.
    public func deleteMail(id: UUID) {
        news.removeAll { $0.id == id && $0.isInboxMessage }
    }

    /// Clears club correspondence while preserving the world news feed.
    public func deleteAllMail() {
        news.removeAll { $0.isInboxMessage }
    }

    /// Seeds the manager's inbox with the board's welcome and season objectives the
    /// first time a club is taken over.
    public func seedManagerInbox() {
        guard let club = userClub else { return }
        let boardTone = club.reputation >= 70 ? "a club of our standing"
            : club.reputation >= 45 ? "an ambitious club"
            : "a club with real potential"
        addNews(
            headline: "Welcome to \(club.name)",
            body: "The board is delighted to appoint you as first-team manager. We see \(boardTone) and believe you are the right person to lead it. The squad is yours — good luck.",
            category: .board,
            sender: "The Board — \(club.name)"
        )
        addNews(
            headline: "Season Objectives",
            body: "Our minimum expectation this season is a \(boardExpectation(for: club)). Exceed it and the board will back you in the transfer market and reward you with a new contract.",
            category: .board,
            sender: "The Board — \(club.name)"
        )
        addNews(
            headline: "Transfer Window Open",
            body: "You have until the end of the window to strengthen the squad. Your available budget and wage headroom are shown in the Transfer Hub.",
            category: .transfer,
            sender: "Club Secretary"
        )
    }

    /// Board's minimum season expectation, in words.
    private func boardExpectation(for club: Club) -> String {
        boardTarget(for: club)?.goal.lowercased() ?? "solid season"
    }

    /// The board's target for the user's club: where its reputation ranks in
    /// its division decides the ambition, with a little slack.
    public func boardTarget(for club: Club) -> (goal: String, position: Int)? {
        guard let league = currentLeague ?? leagues.first(where: { $0.tier == club.leagueTier }) else { return nil }
        let members = league.clubIds.compactMap { self.club(withId: $0) }
        let n = members.count
        guard n > 1 else { return nil }
        let rank = (members.sorted { $0.reputation > $1.reputation }.firstIndex { $0.id == club.id } ?? n / 2) + 1
        let tier = league.tier
        // Single-division countries have nobody to relegate to.
        let hasLowerDivision = tier.lowerTier.map { lower in leagues.contains { $0.tier == lower } } ?? false
        let survivalGoal = hasLowerDivision
            ? ("Avoid relegation", max(1, n - max(tier.relegationCount, 2)))
            : ("Finish clear of the bottom two", max(1, n - 2))
        if tier.isTopFlight {
            let europe = max(1, tier.country.europeanAllocation.championsLeague + tier.country.europeanAllocation.europaLeague)
            if rank == 1 { return ("Win the league", 1) }
            if rank <= 3 { return ("Challenge for the title", 3) }
            if rank <= europe + 1 { return ("Qualify for Europe", europe + 1) }
            if rank <= n / 2 { return ("Finish in the top half", n / 2) }
            return survivalGoal
        }
        if rank <= 2 { return ("Win promotion", max(1, tier.autoPromotionCount)) }
        if rank <= 6 { return ("Reach the play-offs", tier.autoPromotionCount + 4) }
        if rank <= n / 2 { return ("Finish in the top half", n / 2) }
        return survivalGoal
    }

    /// End-of-season verdict on the board's target: rewards for beating it,
    /// and a summer sacking for missing it badly with confidence already low.
    private func deliverBoardVerdict(club: Club, position: Int, target: (goal: String, position: Int)) {
        guard gameMode == .manageClub, let clubIdx = clubs.firstIndex(where: { $0.id == club.id }) else { return }
        if position <= target.position {
            let bonus = max(100_000, clubs[clubIdx].finances.transferBudget / 5)
            clubs[clubIdx].finances.transferBudget += bonus
            jobSecurity.boardConfidence = min(100, jobSecurity.boardConfidence + 15)
            manager.reputation = min(100, manager.reputation + 3)
            addNews(
                headline: "Board Target Achieved",
                body: "The board asked you to \(target.goal.lowercased()) and you delivered with a \(position)\(standingRankSuffix(position))-place finish. They have added \(Player.formatCurrency(bonus)) to the transfer budget.",
                category: .board,
                sender: "The Board"
            )
        } else if position > target.position + 4 {
            jobSecurity.boardConfidence = max(0, jobSecurity.boardConfidence - 20)
            if jobSecurity.boardConfidence < 30 {
                let sackedFrom = clubs[clubIdx]
                abandonLiveTransferTalks()
                clubs[clubIdx].isUserClub = false
                clubs[clubIdx].manager = "Caretaker Manager"
                userClubId = nil
                manager.reputation = max(5, manager.reputation - 6)
                jobSecurity = JobSecurity()
                addNews(
                    headline: "Sacked by \(sackedFrom.name)",
                    body: "The board asked you to \(target.goal.lowercased()). A \(position)\(standingRankSuffix(position))-place finish was not good enough and they have decided to make a change.",
                    category: .board,
                    sender: "The Board — \(sackedFrom.name)"
                )
                generateJobOffers(maxCount: 4, excludeUserClub: false)
                jobOffers.removeAll { $0.clubId == sackedFrom.id }
            } else {
                addNews(
                    headline: "Board Disappointed",
                    body: "The target was to \(target.goal.lowercased()); we finished \(position)\(standingRankSuffix(position)). The board expect a significant improvement next season.",
                    category: .board,
                    sender: "The Board"
                )
            }
        }
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case gameMode
        case clubs
        case leagues
        case season
        case userClubId
        case freeAgents
        case transferHistory
        case pendingTransferOffers
        case news
        case currentScreen
        case isMatchInProgress
        case activeMatchFixtureId
        case negotiationTargetPlayerId
        case soundEnabled
        case matchSettings
        case manager
        case jobOffers
        case owner
        case lastTrainingWeek
        case jobSecurity
        case teamTalk
        case teamTalkAppliedWeek
        case europeanCompetitions
        case europeanMatchweek
        case nationalTeams
        case internationalTournaments
        case managedNationalTeamId
        case hasStartedCareer
        case domesticCups
        case rivalries
        case europeanQualifiers
        case lastSeasonReview
        case history
        case shortlist
        case matchOnlyLineupBackup
        case pendingWinBonusRequest
        case winBonusAskedSeason
        case winBonusPercent
        case pendingRecordMoment
        case clubRecords
        case dismissedTips
        case achievements
        case pendingOwnerDecision
        case answeredPressFixtureIds
        case seasonLedger
        case pointsDeductions
        case pendingManagerRequest
        case pendingTakeover
        case pendingSponsorOffers
        case sponsorAgencyCooldown
        case awaitingClubPurchase
        case transferInstallments
        case pendingCeremonies
        case ceremonyToShow
        case nationalTactics
        case clinchedHonours
        case celebrationToShow
        case lastFinanceSnapshot
        case lastInternationalReport
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gameMode, forKey: .gameMode)
        try container.encode(clubs, forKey: .clubs)
        try container.encode(leagues, forKey: .leagues)
        try container.encode(season, forKey: .season)
        try container.encodeIfPresent(userClubId, forKey: .userClubId)
        try container.encode(freeAgents, forKey: .freeAgents)
        try container.encode(transferHistory, forKey: .transferHistory)
        try container.encode(pendingTransferOffers, forKey: .pendingTransferOffers)
        try container.encode(news, forKey: .news)
        try container.encode(currentScreen, forKey: .currentScreen)
        try container.encode(isMatchInProgress, forKey: .isMatchInProgress)
        try container.encodeIfPresent(activeMatchFixtureId, forKey: .activeMatchFixtureId)
        try container.encodeIfPresent(negotiationTargetPlayerId, forKey: .negotiationTargetPlayerId)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(matchSettings, forKey: .matchSettings)
        try container.encode(manager, forKey: .manager)
        try container.encode(jobOffers, forKey: .jobOffers)
        try container.encode(owner, forKey: .owner)
        try container.encodeIfPresent(lastTrainingWeek, forKey: .lastTrainingWeek)
        try container.encode(jobSecurity, forKey: .jobSecurity)
        try container.encodeIfPresent(teamTalk, forKey: .teamTalk)
        try container.encodeIfPresent(teamTalkAppliedWeek, forKey: .teamTalkAppliedWeek)
        try container.encode(europeanCompetitions, forKey: .europeanCompetitions)
        try container.encode(europeanMatchweek, forKey: .europeanMatchweek)
        try container.encode(nationalTeams, forKey: .nationalTeams)
        try container.encode(internationalTournaments, forKey: .internationalTournaments)
        try container.encodeIfPresent(managedNationalTeamId, forKey: .managedNationalTeamId)
        try container.encode(hasStartedCareer, forKey: .hasStartedCareer)
        try container.encode(domesticCups, forKey: .domesticCups)
        try container.encode(rivalries, forKey: .rivalries)
        try container.encode(europeanQualifiers, forKey: .europeanQualifiers)
        try container.encodeIfPresent(lastSeasonReview, forKey: .lastSeasonReview)
        try container.encode(history, forKey: .history)
        try container.encode(shortlist, forKey: .shortlist)
        try container.encodeIfPresent(matchOnlyLineupBackup, forKey: .matchOnlyLineupBackup)
        try container.encode(pendingWinBonusRequest, forKey: .pendingWinBonusRequest)
        try container.encode(winBonusAskedSeason, forKey: .winBonusAskedSeason)
        try container.encode(winBonusPercent, forKey: .winBonusPercent)
        try container.encodeIfPresent(pendingRecordMoment, forKey: .pendingRecordMoment)
        try container.encode(clubRecords, forKey: .clubRecords)
        try container.encode(dismissedTips, forKey: .dismissedTips)
        try container.encode(achievements, forKey: .achievements)
        try container.encodeIfPresent(pendingOwnerDecision, forKey: .pendingOwnerDecision)
        try container.encode(answeredPressFixtureIds, forKey: .answeredPressFixtureIds)
        try container.encodeIfPresent(seasonLedger, forKey: .seasonLedger)
        try container.encode(pointsDeductions, forKey: .pointsDeductions)
        try container.encodeIfPresent(pendingManagerRequest, forKey: .pendingManagerRequest)
        try container.encodeIfPresent(pendingTakeover, forKey: .pendingTakeover)
        try container.encode(pendingSponsorOffers, forKey: .pendingSponsorOffers)
        try container.encode(sponsorAgencyCooldown, forKey: .sponsorAgencyCooldown)
        try container.encode(awaitingClubPurchase, forKey: .awaitingClubPurchase)
        try container.encode(transferInstallments, forKey: .transferInstallments)
        try container.encode(pendingCeremonies, forKey: .pendingCeremonies)
        try container.encodeIfPresent(ceremonyToShow, forKey: .ceremonyToShow)
        try container.encodeIfPresent(nationalTactics, forKey: .nationalTactics)
        try container.encode(clinchedHonours, forKey: .clinchedHonours)
        try container.encodeIfPresent(celebrationToShow, forKey: .celebrationToShow)
        try container.encodeIfPresent(lastFinanceSnapshot, forKey: .lastFinanceSnapshot)
        try container.encodeIfPresent(lastInternationalReport, forKey: .lastInternationalReport)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.gameMode = try container.decode(GameMode.self, forKey: .gameMode)
        self.clubs = try container.decode([Club].self, forKey: .clubs)
        self.leagues = try container.decode([League].self, forKey: .leagues)
        self.season = try container.decode(Season.self, forKey: .season)
        self.userClubId = try container.decodeIfPresent(UUID.self, forKey: .userClubId)
        self.freeAgents = try container.decode([Player].self, forKey: .freeAgents)
        self.transferHistory = try container.decode([TransferRecord].self, forKey: .transferHistory)
        self.pendingTransferOffers = try container.decode([TransferOffer].self, forKey: .pendingTransferOffers)
        self.news = try container.decode([NewsItem].self, forKey: .news)
        self.currentScreen = try container.decode(AppScreen.self, forKey: .currentScreen)
        self.isMatchInProgress = try container.decode(Bool.self, forKey: .isMatchInProgress)
        self.activeMatchFixtureId = try container.decodeIfPresent(UUID.self, forKey: .activeMatchFixtureId)
        self.negotiationTargetPlayerId = try container.decodeIfPresent(UUID.self, forKey: .negotiationTargetPlayerId)
        self.soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        self.matchSettings = try container.decodeIfPresent(MatchSettings.self, forKey: .matchSettings) ?? MatchSettings()
        self.manager = try container.decodeIfPresent(ManagerProfile.self, forKey: .manager) ?? ManagerProfile()
        self.jobOffers = try container.decodeIfPresent([JobOffer].self, forKey: .jobOffers) ?? []
        self.owner = try container.decodeIfPresent(OwnerProfile.self, forKey: .owner) ?? OwnerProfile()
        self.lastTrainingWeek = try container.decodeIfPresent(Int.self, forKey: .lastTrainingWeek)
        self.jobSecurity = try container.decodeIfPresent(JobSecurity.self, forKey: .jobSecurity) ?? JobSecurity()
        self.teamTalk = try container.decodeIfPresent(TeamTalkStyle.self, forKey: .teamTalk)
        self.teamTalkAppliedWeek = try container.decodeIfPresent(Int.self, forKey: .teamTalkAppliedWeek)
        self.europeanCompetitions = try container.decodeIfPresent([EuropeanCompetitionState].self, forKey: .europeanCompetitions) ?? []
        self.europeanMatchweek = try container.decodeIfPresent(Int.self, forKey: .europeanMatchweek) ?? 0
        self.nationalTeams = try container.decodeIfPresent([NationalTeam].self, forKey: .nationalTeams) ?? []
        self.internationalTournaments = try container.decodeIfPresent([InternationalTournament.State].self, forKey: .internationalTournaments) ?? []
        self.managedNationalTeamId = try container.decodeIfPresent(String.self, forKey: .managedNationalTeamId)
        // Saves from before cups existed simply have none until next season.
        self.domesticCups = try container.decodeIfPresent([DomesticCupState].self, forKey: .domesticCups) ?? []
        // Older saves have none; `seedRivalriesIfNeeded()` fills them in on load.
        self.rivalries = try container.decodeIfPresent([Rivalry].self, forKey: .rivalries) ?? []
        self.europeanQualifiers = try container.decodeIfPresent([String: [UUID]].self, forKey: .europeanQualifiers) ?? [:]
        self.lastSeasonReview = try container.decodeIfPresent(SeasonReview.self, forKey: .lastSeasonReview)
        self.history = try container.decodeIfPresent(WorldHistory.self, forKey: .history) ?? WorldHistory()
        self.shortlist = try container.decodeIfPresent([UUID].self, forKey: .shortlist) ?? []
        self.matchOnlyLineupBackup = try container.decodeIfPresent(Tactics.self, forKey: .matchOnlyLineupBackup)
        self.pendingWinBonusRequest = try container.decodeIfPresent(Bool.self, forKey: .pendingWinBonusRequest) ?? false
        self.winBonusAskedSeason = try container.decodeIfPresent(String.self, forKey: .winBonusAskedSeason) ?? ""
        self.winBonusPercent = try container.decodeIfPresent(Int.self, forKey: .winBonusPercent) ?? 0
        self.pendingRecordMoment = try container.decodeIfPresent(ClubRecordMoment.self, forKey: .pendingRecordMoment)
        self.clubRecords = try container.decodeIfPresent(ClubRecords.self, forKey: .clubRecords) ?? ClubRecords()
        self.dismissedTips = try container.decodeIfPresent([String].self, forKey: .dismissedTips) ?? []
        self.achievements = try container.decodeIfPresent([String: String].self, forKey: .achievements) ?? [:]
        self.pendingOwnerDecision = try container.decodeIfPresent(OwnerDecision.self, forKey: .pendingOwnerDecision)
        self.answeredPressFixtureIds = try container.decodeIfPresent([UUID].self, forKey: .answeredPressFixtureIds) ?? []
        self.seasonLedger = try container.decodeIfPresent(FinanceLedger.self, forKey: .seasonLedger)
        self.pointsDeductions = try container.decodeIfPresent([UUID: Int].self, forKey: .pointsDeductions) ?? [:]
        self.pendingManagerRequest = try container.decodeIfPresent(ManagerRequest.self, forKey: .pendingManagerRequest)
        self.pendingTakeover = try container.decodeIfPresent(TakeoverOffer.self, forKey: .pendingTakeover)
        self.pendingSponsorOffers = try container.decodeIfPresent([SponsorOffer].self, forKey: .pendingSponsorOffers) ?? []
        self.sponsorAgencyCooldown = try container.decodeIfPresent(Int.self, forKey: .sponsorAgencyCooldown) ?? 0
        self.awaitingClubPurchase = try container.decodeIfPresent(Bool.self, forKey: .awaitingClubPurchase) ?? false
        self.transferInstallments = try container.decodeIfPresent([TransferInstallment].self, forKey: .transferInstallments) ?? []
        self.pendingCeremonies = try container.decodeIfPresent([AwardCeremony].self, forKey: .pendingCeremonies) ?? []
        self.ceremonyToShow = try container.decodeIfPresent(AwardCeremony.self, forKey: .ceremonyToShow)
        self.nationalTactics = try container.decodeIfPresent(Tactics.self, forKey: .nationalTactics)
        self.clinchedHonours = try container.decodeIfPresent([String].self, forKey: .clinchedHonours) ?? []
        self.celebrationToShow = try container.decodeIfPresent(Celebration.self, forKey: .celebrationToShow)
        self.lastFinanceSnapshot = try? container.decodeIfPresent(FinanceLedger.self, forKey: .lastFinanceSnapshot)
        self.lastInternationalReport = try container.decodeIfPresent(InternationalReport.self, forKey: .lastInternationalReport)
        // Saves written before this flag existed: any save with a user club, or
        // a manager career (possibly between jobs), is a real career.
        // (Re-decoded into locals: reading `self` properties is not allowed until
        // every stored property is initialised.)
        if let storedFlag = try container.decodeIfPresent(Bool.self, forKey: .hasStartedCareer) {
            self.hasStartedCareer = storedFlag
        } else {
            let decodedMode = try container.decode(GameMode.self, forKey: .gameMode)
            let decodedUserClubId = try container.decodeIfPresent(UUID.self, forKey: .userClubId)
            let decodedManager = try container.decodeIfPresent(ManagerProfile.self, forKey: .manager)
            let decodedOffers = try container.decodeIfPresent([JobOffer].self, forKey: .jobOffers) ?? []
            let hasManagerHistory = !(decodedManager?.careerHistory.isEmpty ?? true)
            self.hasStartedCareer = decodedUserClubId != nil
                || (decodedMode == .manageClub && (hasManagerHistory || !decodedOffers.isEmpty))
        }
        // Older saves gave every club the same five named staff.
        for idx in self.clubs.indices { self.clubs[idx].replaceLegacyStaff() }
    }
}

extension String {
    /// FNV-1a hash that is stable across launches (Swift's `hashValue` is
    /// randomised per process), for deterministic per-club choices.
    var hashValueStable: Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(truncatingIfNeeded: hash & 0x7fffffffffffffff)
    }
}

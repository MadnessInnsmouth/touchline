//
//  ContentView.swift
//  Touchline
//
//  Created for Touchline - iOS Football Manager Game.
//  Root navigation coordinator presenting screen flows based on GameState.currentScreen.
//  Employs NavigationStack and an accessible tabbed interface for managerial operations.
//

import SwiftUI

public struct ContentView: View {
    @Environment(GameState.self) private var gameState
    @AppStorage("gfStadiumTheme") private var stadiumTheme = true

    public init() {}

    private var isOwner: Bool { gameState.gameMode == .createClub }

    public var body: some View {
        // Money in the currency of the user's league (pounds, euros, ...).
        let _ = Currency.update(for: gameState.userClub?.leagueTier.country)
        NavigationStack {
            Group {
            switch gameState.currentScreen {
            case .mainMenu:
                MainMenuView()
            case .clubCreation:
                ClubCreationView()
            case .clubSelect:
                ClubSelectView()
            case .managerCreation:
                ManagerCreationView()
            case .jobOffers:
                JobOffersView()
            case .managerProfile:
                ManagerProfileView()
            case .staff:
                if isOwner { OwnerCareerTabView() } else { StaffView() }
            case .dashboard, .fixtures, .results:
                if isOwner { OwnerCareerTabView() } else { DashboardView() }
            case .news:
                NewsFeedView()
            case .history:
                HistoryView()
            case .squad:
                if isOwner { OwnerCareerTabView() } else { SquadView().hubScreen("Squad") }
            case .tactics:
                if isOwner { OwnerCareerTabView() } else { TacticsView().hubScreen("Tactics") }
            case .standings:
                StandingsView().hubScreen("League Table")
            case .transferHub, .playerSearch:
                if isOwner { OwnerCareerTabView() } else { TransferHubView().hubScreen("Transfers") }
            case .training:
                if isOwner { OwnerCareerTabView() } else { TrainingView() }
            case .finances:
                FinancesView()
            case .matchDay:
                MatchDayView()
            case .liveMatch:
                LiveMatchView()
            case .postMatch:
                PostMatchView()
            case .negotiation:
                NegotiationView()
            case .settings:
                SettingsView()
            case .mailbox:
                MailboxView()
            case .matchHistory:
                MatchHistoryView()
            case .europeanCompetitions:
                EuropeanCompetitionsView()
            case .youthAcademy:
                YouthAcademyView()
            case .international:
                InternationalHubView()
            case .playerDetail(let playerId):
                PlayerDetailView(playerId: playerId)
            }
            }
            .stadiumBackground()
        }
        // Awards nights (the Ballon d'Or in October, the Team of the Year in
        // January) take over the screen when they are held.
        // Held for the Home screen, never in the middle of a match or another screen.
        .fullScreenCover(item: Binding(get: {
            if case .dashboard = gameState.currentScreen { return gameState.ceremonyToShow }
            return nil
        }, set: { gameState.ceremonyToShow = $0 })) { ceremony in
            AwardCeremonyView(ceremony: ceremony)
                .environment(gameState)
        }
        // Text only, everywhere: every row and button label shows its words
        // without an icon, so VoiceOver never reads an image name.
        .labelStyle(.titleOnly)
        // Titles, promotions and trophies get their cutscene on the Home
        // screen (after any awards night).
        .fullScreenCover(item: Binding(get: {
            if case .dashboard = gameState.currentScreen, gameState.ceremonyToShow == nil { return gameState.celebrationToShow }
            return nil
        }, set: { gameState.celebrationToShow = $0 })) { celebration in
            CelebrationView(celebration: celebration)
                .environment(gameState)
        }
        .groupBoxStyle(GFGroupBoxStyle())
        .environment(\.stadiumTheme, stadiumTheme)
        .preferredColorScheme(stadiumTheme ? .dark : nil)
        .tint(stadiumTheme ? Color(hex: "FF8A65") : nil)
        .toolbarBackground(stadiumTheme ? Color(hex: "07171A").opacity(0.92) : Color(UIColor.systemBackground), for: .navigationBar)
        .dynamicTypeBounds()
    }
}

// MARK: - Main Menu Screen

/// A main-menu row: an icon disc, the title with its description, and an arrow.
struct MenuRowLabel: View {
    let icon: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).accessibilityHidden(true)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .opacity(0.8)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .opacity(0.6)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }
}

public struct MainMenuView: View {
    @Environment(GameState.self) private var gameState
    @State private var pendingNewCareerMode: GameMode?
    @State private var showingEditor = false

    /// Whether there is a career in memory worth continuing (or protecting).
    private var hasCareerToContinue: Bool {
        guard gameState.hasStartedCareer else { return false }
        return gameState.userClub != nil || (gameState.gameMode == .manageClub && gameState.isUnemployed)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // The Touchline mark: a white T standing on a coral touchline.
                HStack(alignment: .center, spacing: 16) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: "1B4D52"), Color(hex: "07171A")], startPoint: .topTrailing, endPoint: .bottomLeading))
                            .frame(width: 76, height: 76)
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.white).frame(width: 42, height: 9)
                            Rectangle().fill(Color.white).frame(width: 9, height: 36)
                        }
                        .offset(y: -16)
                        Capsule().fill(Color(hex: "E4573D")).frame(width: 56, height: 4).offset(y: -10)
                    }
                    .shadow(color: Color(hex: "2EC4B6").opacity(0.35), radius: 14, y: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Touchline")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Football Management")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: "FFC857"))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 36)
                .padding(.bottom, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Touchline Football Management")
                .accessibilityAddTraits(.isHeader)

                VStack(spacing: 14) {
                    if hasCareerToContinue {
                        Button {
                            gameState.currentScreen = gameState.userClub == nil ? .jobOffers : .dashboard
                        } label: {
                            MenuRowLabel(icon: "play.fill",
                                         title: "Continue",
                                         detail: "\(gameState.userClub?.name ?? "Job search") · \(gameState.season.year)")
                        }
                        .buttonStyle(.gfPrimary)
                        .accessibilityLabel("Continue career\(gameState.userClub.map { " with \($0.name)" } ?? " in the job market")")
                    }
                    ForEach(GameMode.allCases) { mode in
                        Button {
                            startMode(mode)
                        } label: {
                            MenuRowLabel(icon: mode == .createClub ? "building.columns.fill" : "person.fill.badge.plus",
                                         title: mode == .createClub ? "New Owner Career" : "New Manager Career",
                                         detail: mode == .createClub ? "Run the club as chairman" : "Pick the team, tactics and transfers")
                        }
                        .buttonStyle(.gfOutline)
                        .accessibilityLabel("\(mode.displayName). \(mode.modeDescription)")
                    }
                    Button {
                        showingEditor = true
                    } label: {
                        MenuRowLabel(icon: "square.and.pencil",
                                     title: "Editor",
                                     detail: DatapackStore.shared.activeName.map { "Datapack in use: \($0)" } ?? "Create and edit datapacks")
                    }
                    .buttonStyle(.gfOutline)
                    .accessibilityLabel("Editor. Create and edit datapacks")
                    .fullScreenCover(isPresented: $showingEditor, onDismiss: {
                        // The world on the menu was built before the editor
                        // opened; rebuild it so a new career uses the chosen pack.
                        if !gameState.hasStartedCareer {
                            gameState.resetForNewCareer(mode: gameState.gameMode)
                        }
                    }) {
                        DatapackListView()
                    }
                    Button { gameState.currentScreen = .settings } label: {
                        MenuRowLabel(icon: "gearshape.fill", title: "Settings & Saves", detail: nil)
                    }
                    .buttonStyle(.gfOutline)
                    .accessibilityLabel("Settings & Saves")
                }
                .padding(.horizontal, 4)

                Text("An offline football management simulation. Player and club names are used for identification only; all badges and faces are procedurally generated.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .stadiumBackground()
        .confirmationDialog(
            "Start a New Career?",
            isPresented: Binding(
                get: { pendingNewCareerMode != nil },
                set: { if !$0 { pendingNewCareerMode = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingNewCareerMode
        ) { mode in
            Button("Start New Career", role: .destructive) {
                pendingNewCareerMode = nil
                beginNewCareer(mode)
            }
            Button("Cancel", role: .cancel) { pendingNewCareerMode = nil }
        } message: { _ in
            Text("A brand-new world will be created. Your current career stays in the autosave until you launch the new one, and manual save slots are never touched.")
        }
    }
    
    private func startMode(_ mode: GameMode) {
        if hasCareerToContinue {
            // Never mutate the live career just because a mode card was tapped:
            // confirm first, then start from a clean world.
            pendingNewCareerMode = mode
        } else {
            beginNewCareer(mode)
        }
    }

    private func beginNewCareer(_ mode: GameMode) {
        if gameState.hasStartedCareer {
            // Previously a second career reused the old, mutated world: the old
            // club kept `isUserClub`, news and offers leaked across careers, and
            // owner/manager modes could be mixed. Always start from scratch.
            gameState.resetForNewCareer(mode: mode)
        } else {
            gameState.gameMode = mode
        }
        // Owner careers begin by founding their club; manager careers begin by
        // creating the person who will run training and matches.
        gameState.currentScreen = mode == .createClub ? .clubCreation : .managerCreation
    }
}

// MARK: - Game Mode Card

public struct GameModeCard: View {
    public let mode: GameMode
    public let action: () -> Void
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: iconName).accessibilityHidden(true)
                    .font(.title)
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(colors: mode == .createClub ? [Color(hex: "8E44AD"), Color(hex: "3498DB")] : [Color.pitchGreen, Color(hex: "1ABC9C")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(.white)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(mode.modeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
            }
            .gfCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.displayName). \(mode.modeDescription)")
        .accessibilityHint("Double tap to start \(mode.displayName)")
    }
    
    private var iconName: String {
        switch mode {
        case .createClub: return "shield.lefthalf.filled"
        case .manageClub: return "person.badge.shield.checkmark.fill"
        }
    }
}

// MARK: - Club Creation Screen

public struct ClubCreationView: View {
    @Environment(GameState.self) private var gameState
    
    @State private var clubName = "Harbour Town"
    @State private var stadiumName = "Quayside Park"
    @State private var cityName = "Bristol"
    @State private var primaryColor = "#1F7A6E"
    @State private var secondaryColor = "#E4573D"
    @State private var selectedReplaceClubId: UUID?
    @State private var ownerName = "Sam Carter"
    @State private var clubVision: ClubVision = .sustainable
    @State private var creationError: String?
    
    private var leagueTwoClubs: [Club] {
        return gameState.clubs.filter { $0.leagueTier == .leagueTwo }
    }
    
    public var body: some View {
        Form {
            if gameState.gameMode == .createClub {
                Section(header: Text("Ownership"), footer: Text("As owner, you appoint the manager and build the football operation. You will not control tactics or the matchday team.")) {
                    TextField("Owner Name", text: $ownerName)
                        .accessibilityLabel("Owner name input")
                    Picker("Club Vision", selection: $clubVision) {
                        ForEach(ClubVision.allCases) { vision in
                            Text(vision.rawValue).tag(vision)
                        }
                    }
                    Text(clubVision.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(header: Text("Club Identity")) {
                TextField("Club Name", text: $clubName)
                    .accessibilityLabel("Club Name input")
                TextField("Stadium Name", text: $stadiumName)
                    .accessibilityLabel("Stadium Name input")
                TextField("Home City", text: $cityName)
                    .accessibilityLabel("Home City input")
            }
            
            Section(header: Text("Kit & Badge Colors")) {
                HStack {
                    Text("Primary Color")
                    Spacer()
                    TextField("Hex Code", text: $primaryColor)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Secondary Color")
                    Spacer()
                    TextField("Hex Code", text: $secondaryColor)
                        .multilineTextAlignment(.trailing)
                }
            }
            
            Section(header: Text("League Two Club to Replace")) {
                Picker("Club to Replace", selection: $selectedReplaceClubId) {
                    Text("Select Club").tag(nil as UUID?)
                    ForEach(leagueTwoClubs) { club in
                        Text(club.name).tag(club.id as UUID?)
                    }
                }
                .accessibilityLabel("Select League Two Club to Replace")
            }
            
            Section {
                Button(action: {
                    guard validIdentity else {
                        creationError = "Enter a club name, a stadium, a city, and two six-digit hex colours such as #2D8B4E."
                        return
                    }
                    guard let targetId = selectedReplaceClubId else {
                        creationError = "Choose a League Two club to replace before launching your career."
                        return
                    }
                    if gameState.gameMode == .createClub {
                        gameState.owner = OwnerProfile(name: ownerName.trimmingCharacters(in: .whitespaces).isEmpty ? "Club Owner" : ownerName, vision: clubVision)
                    }
                    guard gameState.createCustomClub(
                        name: clubName,
                        // Used only internally; screens always show the full name.
                        shortName: { let l = String(clubName.filter { $0.isLetter }.uppercased().prefix(3)); return l.count == 3 ? l : "CLB" }(),
                        stadium: stadiumName,
                        stadiumCapacity: 5000,
                        city: cityName,
                        primaryColor: primaryColor,
                        secondaryColor: secondaryColor,
                        replaceClubId: targetId
                    ) != nil else {
                        creationError = "That club is no longer available to replace. Please choose another club."
                        return
                    }
                    
                    try? SaveManager.shared.autoSave(gameState: gameState)
                    gameState.currentScreen = .dashboard
                }) {
                    Text(gameState.gameMode == .createClub ? "Launch Owner Career" : "Launch Club")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!validIdentity || selectedReplaceClubId == nil)
                .accessibilityLabel("Launch club career")
                .accessibilityHint("Finalizes club creation and opens your career hub")
            }
        }
        .navigationTitle(gameState.gameMode == .createClub ? "Found Your Club" : "Create Your Club")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedReplaceClubId == nil {
                selectedReplaceClubId = leagueTwoClubs.first?.id
            }
        }
        .alert("Check Club Details", isPresented: Binding(get: { creationError != nil }, set: { if !$0 { creationError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(creationError ?? "")
        }
    }

    private var validIdentity: Bool {
        !clubName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !stadiumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isHexColour(primaryColor)
            && isHexColour(secondaryColor)
    }

    private func isHexColour(_ value: String) -> Bool {
        value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }
}

// MARK: - Club Select Screen (Manage Existing Club)

public struct ClubSelectView: View {
    @Environment(GameState.self) private var gameState
    
    @State private var searchText = ""
    @State private var selectedTier: LeagueTier? = nil
    
    private var filteredClubs: [Club] {
        gameState.clubs
            .filter { selectedTier == nil || $0.leagueTier == selectedTier }
            .filter {
                searchText.isEmpty
                || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.shortName.localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                if $0.leagueTier != $1.leagueTier { return $0.leagueTier < $1.leagueTier }
                return $0.name < $1.name
            }
    }
    
    public var body: some View {
        List {
            Section {
                Menu {
                    Button("All Divisions") { selectedTier = nil }
                    ForEach(LeagueCountry.allCases) { country in
                        let tiers = LeagueTier.pyramid(for: country).filter { tier in
                            gameState.clubs.contains { $0.leagueTier == tier }
                        }
                        if !tiers.isEmpty {
                            Menu("\(country.flag) \(country.displayName)") {
                                ForEach(tiers) { tier in
                                    Button(tier.displayName) { selectedTier = tier }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Division")
                        Spacer()
                        Text(selectedTier?.displayName ?? "All Divisions")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Filter by division")
            }
            
            Section(header: Text("\(filteredClubs.count) Clubs")) {
                ForEach(filteredClubs) { club in
                    Button {
                        select(club)
                    } label: {
                        HStack(spacing: 14) {
                            CrestView(club: club, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(club.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(club.leagueTier.displayName) • \(club.stadium)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Rep \(club.reputation)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(club.name), \(club.leagueTier.displayName), reputation \(club.reputation)")
                    .accessibilityHint("Double tap to become the manager of \(club.name)")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search clubs")
        .navigationTitle("Select a Club")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func select(_ club: Club) {
        guard gameState.takeOverExistingClub(clubId: club.id) != nil else { return }
        try? SaveManager.shared.autoSave(gameState: gameState)
        gameState.currentScreen = .dashboard
    }
}

// MARK: - Manager Creation Screen

public struct ManagerCreationView: View {
    @Environment(GameState.self) private var gameState

    @State private var firstName = "Sam"
    @State private var lastName = "Carter"
    @State private var nationality: ManagerNationality = .england
    @State private var age = 38
    @State private var background: ManagerBackground = .journeyman

    private var previewProfile: ManagerProfile {
        let attrs = background.attributes
        return ManagerProfile(
            firstName: firstName.isEmpty ? "New" : firstName,
            lastName: lastName.isEmpty ? "Manager" : lastName,
            nationality: nationality.rawValue,
            age: age,
            faceSeed: ManagerProfile.generateSeed(first: firstName, last: lastName),
            tactical: attrs.tactical,
            attacking: attrs.attacking,
            defending: attrs.defending,
            youthDevelopment: attrs.youth,
            reputation: reputationForMode
        )
    }

    /// Reputation the manager starts with, seeded by the chosen career mode.
    private var reputationForMode: Int {
        switch gameState.gameMode {
        case .createClub: return 10
        case .manageClub: return 40
        }
    }

    public var body: some View {
        Form {
            Section(header: Text("Manager Identity")) {
                TextField("First Name", text: $firstName)
                    .accessibilityLabel("Manager first name")
                TextField("Last Name", text: $lastName)
                    .accessibilityLabel("Manager last name")
                Picker("Nationality", selection: $nationality) {
                    ForEach(ManagerNationality.allCases) { nat in
                        Text("\(nat.flag) \(nat.rawValue)").tag(nat)
                    }
                }
                Stepper("Age: \(age)", value: $age, in: 30...70)
            }

            Section(header: Text("Preview")) {
                HStack(spacing: 16) {
                    FaceView(seed: previewProfile.faceSeed, size: 72, style: .full)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(previewProfile.fullName)
                            .font(.headline)
                        Text("\(previewProfile.flag) \(nationality.rawValue) • Age \(age)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Reputation \(reputationForMode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Coaching Background")) {
                Picker("Background", selection: $background) {
                    ForEach(ManagerBackground.allCases) { bg in
                        Text(bg.rawValue).tag(bg)
                    }
                }
                .accessibilityHint("Sets your starting coaching strengths")
                Text(background.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                attributeRow(.tactical, value: background.attributes.tactical)
                attributeRow(.attacking, value: background.attributes.attacking)
                attributeRow(.defending, value: background.attributes.defending)
                attributeRow(.youthDevelopment, value: background.attributes.youth)
            }

            Section {
                Button(action: launch) {
                    Text("Confirm Manager")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Confirm manager and continue")
            }
        }
        .navigationTitle("Create Your Manager")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Read-only coaching attribute bar for the chosen background.
    private func attributeRow(_ attr: CoachingAttribute, value: Int) -> some View {
        HStack {
            Image(systemName: attr.iconName).accessibilityHidden(true)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(attr.displayName)
                .font(.subheadline)
            Spacer()
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.bold)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(attr.displayName) \(value) out of 99")
    }

    private func launch() {
        gameState.manager = previewProfile
        switch gameState.gameMode {
        case .createClub:
            gameState.currentScreen = .clubCreation
        case .manageClub:
            gameState.currentScreen = .clubSelect
        }
    }
}

// MARK: - Job Offers Screen

public struct JobOffersView: View {
    @Environment(GameState.self) private var gameState
    @State private var actionError: String?

    public var body: some View {
        List {
            Section {
                if gameState.isUnemployed {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Currently Unemployed", systemImage: "briefcase")
                            .font(.headline)
                        Text("You have no club. Accept a role below to begin your managerial career.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let club = gameState.userClub {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("In Charge of \(club.name)", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Accepting another role will end your current stint at \(club.name).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Offers (\(gameState.jobOffers.count))")) {
                if gameState.jobOffers.isEmpty {
                    VStack(spacing: 10) {
                        Text("No offers on the table right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Search for Vacancies") {
                            gameState.generateJobOffers(maxCount: 5)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                } else {
                    ForEach(gameState.jobOffers) { offer in
                        offerRow(offer)
                    }
                    Button {
                        gameState.generateJobOffers(maxCount: 5)
                    } label: {
                        Label("Look for More Vacancies", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityHint("Other clubs, and sometimes national teams, may approach you")
                }
            }
        }
        .navigationTitle("Job Offers")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unable to Accept Role", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    gameState.currentScreen = .dashboard
                }
                .accessibilityLabel("Close job offers")
            }
        }
    }

    private func offerRow(_ offer: JobOffer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: offer.kind.iconName).accessibilityHidden(true)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.teamName)
                        .font(.headline)
                    Text("\(offer.leagueName) • Reputation \(offer.reputation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if offer.kind == .nationalTeam {
                        Text(gameState.userClub.map { "International post: you keep your job at \($0.name)." } ?? "International post.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    if offer.kind == .nationalTeam {
                        if gameState.acceptNationalTeamOffer(offer) {
                            try? SaveManager.shared.autoSave(gameState: gameState)
                        } else {
                            actionError = "That post is no longer available."
                        }
                    } else if gameState.acceptJobOffer(offer) != nil {
                        try? SaveManager.shared.autoSave(gameState: gameState)
                        gameState.currentScreen = .dashboard
                    } else {
                        actionError = "That role is no longer available. Search for new vacancies and try again."
                    }
                } label: {
                    Label("Accept", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    gameState.declineJobOffer(offer)
                } label: {
                    Label("Decline", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(offer.kind.displayName), \(offer.teamName), \(offer.leagueName), reputation \(offer.reputation)")
    }
}

// MARK: - Manager Profile Screen

public struct ManagerProfileView: View {
    @Environment(GameState.self) private var gameState
    @State private var showResignationConfirmation = false

    public var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    FaceView(seed: gameState.manager.faceSeed, size: 72, style: .full)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gameState.manager.fullName)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("\(gameState.manager.flag) \(gameState.manager.nationality) • Age \(gameState.manager.age)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let club = gameState.userClub {
                            Text("Manager of \(club.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Currently Unemployed")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section(header: Text("Reputation")) {
                HStack {
                    Text("Reputation")
                    Spacer()
                    Text("\(gameState.manager.reputation)")
                        .fontWeight(.bold)
                }
                ProgressView(value: Double(gameState.manager.reputation), total: 100)
            }

            Section(header: Text("Coaching Attributes")) {
                attributeRow(.tactical, value: gameState.manager.tactical)
                attributeRow(.attacking, value: gameState.manager.attacking)
                attributeRow(.defending, value: gameState.manager.defending)
                attributeRow(.youthDevelopment, value: gameState.manager.youthDevelopment)
            }

            Section(header: Text("Career History")) {
                if gameState.manager.careerHistory.isEmpty {
                    Text("No completed seasons yet. Finish a campaign to build your record.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(gameState.manager.careerHistory.reversed()) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(record.seasonYear) — \(record.clubName)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(record.finalPosition > 0 ? "P\(record.finalPosition)" : "—")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            Text("\(record.leagueName) • P\(record.played) W\(record.won) D\(record.drawn) L\(record.lost) • \(Int(record.winPercentage))% win rate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(record.honours, id: \.self) { honour in
                                Label(honour, systemImage: "trophy.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
            }

            if gameState.gameMode == .manageClub, gameState.userClub != nil {
                Section("Career Options") {
                    Button("Resign From Current Club", role: .destructive) {
                        showResignationConfirmation = true
                    }
                    .accessibilityHint("Leaves your current club and opens the job market")
                }
            }
        }
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Resign From Your Current Club?",
            isPresented: $showResignationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Resign", role: .destructive) {
                gameState.goUnemployed()
                gameState.generateJobOffers(maxCount: 5, excludeUserClub: false)
                try? SaveManager.shared.autoSave(gameState: gameState)
                gameState.currentScreen = .jobOffers
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will leave your current role and enter the job market. Your managerial history will be retained.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    gameState.currentScreen = .dashboard
                }
                .accessibilityLabel("Close profile")
            }
        }
    }

    private func attributeRow(_ attr: CoachingAttribute, value: Int) -> some View {
        HStack {
            Label(attr.displayName, systemImage: attr.iconName)
                .font(.subheadline)
            Spacer()
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.bold)
        }
    }
}

// MARK: - Owner Career

public enum OwnerTab: String, CaseIterable, Identifiable {
    case board = "Boardroom"
    case people = "People"
    case facilities = "Facilities"
    case league = "League"
    case club = "Business"
    public var id: String { rawValue }
    var icon: String {
        switch self {
        case .board: return "building.columns.fill"
        case .people: return "person.3.fill"
        case .facilities: return "hammer.fill"
        case .league: return "trophy.fill"
        case .club: return "briefcase.fill"
        }
    }
}

/// End-of-season summary shared by the manager dashboard and the boardroom.
struct SeasonReviewCard: View {
    let review: SeasonReview

    private var ordinal: String {
        let n = review.position
        if (11...13).contains(n % 100) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Season \(review.season) Review")
                .font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(ordinal)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                VStack(alignment: .leading, spacing: 2) {
                    Text("of \(review.leagueSize) in the \(review.leagueName)")
                        .font(.subheadline)
                    Text("\(review.points) pts • \(review.won)W \(review.drawn)D \(review.lost)L • \(review.goalsFor)-\(review.goalsAgainst)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let goal = review.targetGoal, let met = review.targetMet {
                Label("Board target: \(goal) — \(met ? "achieved" : "missed")",
                      systemImage: met ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(met ? Color.winGreen : Color.lossRed)
            }
            if let europe = review.europe {
                Label("Qualified for the \(europe)", systemImage: "star.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.goldAccent)
            }
            if let cup = review.cupRun {
                Label(cup, systemImage: "trophy")
                    .font(.subheadline)
            }
            if let leagueCup = review.leagueCupRun {
                Label(leagueCup, systemImage: "trophy")
                    .font(.subheadline)
            }
            ForEach(review.europeanRuns ?? [], id: \.self) { run in
                Label(run, systemImage: "star.circle")
                    .font(.subheadline)
            }
            if let scorer = review.topScorer {
                Label("Top scorer: \(scorer)", systemImage: "soccerball")
                    .font(.subheadline)
            }
            if let best = review.playerOfSeason {
                Label("Player of the season: \(best)", systemImage: "star.fill")
                    .font(.subheadline)
            }
        }
        .gfCard()
        .accessibilityElement(children: .combine)
    }
}

private struct ManagerReadinessMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }
}

// MARK: - Squad Screen

public struct SquadView: View {
    @Environment(GameState.self) private var gameState
    @State private var showFullSquad = true
    @State private var section: SquadSection = .lineup

    enum SquadSection: String, CaseIterable { case lineup = "Lineup", players = "Players", contracts = "Contracts", loans = "Loans" }

    private var expiringContracts: [Player] {
        guard let userClub = gameState.userClub else { return [] }
        return userClub.players
            .filter { !$0.isOnLoan && ($0.contract?.yearsRemaining ?? 99) <= 1 }
            .sorted { $0.overall > $1.overall }
    }

    public var body: some View {
        ScrollView {
            if let club = gameState.userClub {
                VStack(spacing: 12) {
                    GFTabs(selection: $section, compact: true)
                    switch section {
                    case .lineup:
                        Text("XI \(String(format: "%.1f", club.startingXIAverageOverall)) · Squad \(String(format: "%.1f", club.squadAverageOverall)) · Injured \(club.injuredPlayers.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        lineupBar(club)
                        if gameState.matchLineupDiffersFromUsual && gameState.liveMatch == nil {
                            KeepLineupBar()
                        }
                        LineupEditorView(onProfile: { gameState.openProfile($0) })
                    case .players:
                        fullSquad(club)
                    case .contracts:
                        if expiringContracts.isEmpty {
                            Text("No contracts are running out.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            contractsCard
                        }
                    case .loans:
                        outOnLoanCard
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            } else {
                ContentUnavailableView("No Club", systemImage: "person.3", description: Text("Take charge of a club to view your squad."))
            }
        }
        .stadiumBackground()
    }

    // MARK: Header

    private func header(_ club: Club) -> some View {
        let text = Color.readable(on: club.primaryColor)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CrestView(club: club, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(club.name).font(.title3.weight(.heavy))
                    Text("\(club.players.count) players • \(club.leagueTier.displayName)")
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                metric("Starting XI", String(format: "%.1f", club.startingXIAverageOverall), text)
                metric("Squad", String(format: "%.1f", club.squadAverageOverall), text)
                metric("Injured", "\(club.injuredPlayers.count)", text)
            }
        }
        .foregroundStyle(text)
        .padding(18)
        .background(ClubGradient(club: club))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// "TACTICS   AUTO   4-3-3 ▾" above the pitch.
    private func lineupBar(_ club: Club) -> some View {
        HStack(spacing: 10) {
            Button { gameState.currentScreen = .tactics } label: {
                Text("TACTICS").font(.gfLabel(13))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
            }
            .accessibilityHint("Opens tactics and roles")
            Spacer()
            Button { gameState.autoPickUserLineup() } label: {
                Text("AUTO").font(.gfLabel(13))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
            }
            .accessibilityLabel("Auto pick best eleven")
            Spacer()
            Menu {
                ForEach(FormationPreset.allCases) { formation in
                    Button(formation.rawValue) {
                        if let idx = gameState.clubs.firstIndex(where: { $0.isUserClub }) {
                            gameState.clubs[idx].tactics.formation = formation
                            // Your eleven, rearranged for the new shape.
                            gameState.clubs[idx].fitLineupToFormation(repair: gameState.liveMatch == nil)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(club.tactics.formation.rawValue).font(.gfLabel(13))
                    Image(systemName: "arrowtriangle.down.fill").accessibilityHidden(true).font(.system(size: 7))
                }
                .foregroundStyle(Color.gfNight)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Color.white))
            }
            .accessibilityLabel("Formation \(club.tactics.formation.rawValue). Change formation")
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.heavy).monospacedDigit())
            Text(title).font(.caption2.weight(.semibold)).opacity(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Full squad

    private func fullSquad(_ club: Club) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { showFullSquad.toggle() }
            } label: {
                HStack {
                    GFSectionHeader(title: "Full Squad", icon: "person.3.fill")
                    Image(systemName: "chevron.down").accessibilityHidden(true)
                        .rotationEffect(.degrees(showFullSquad ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showFullSquad {
                ForEach(PositionCategory.allCases) { category in
                    let group = club.players
                        .filter { $0.primaryPosition.category == category }
                        .sorted { $0.overall > $1.overall }
                    if !group.isEmpty {
                        Text(category.displayName.uppercased() + "S")
                            .font(.caption2.weight(.heavy))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(group) { player in
                            NavigationLink(destination: PlayerDetailView(playerId: player.id)) {
                                PlayerRowView(player: player)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessiblePlayerCard(player: player, clubName: club.name)
                        }
                    }
                }
            }
        }
        .gfCard()
    }

    // MARK: Contracts & loans

    private var contractsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            GFSectionHeader(title: "Contracts Expiring", icon: "doc.text.fill")
            Text("\(expiringContracts.count) \(expiringContracts.count == 1 ? "player is" : "players are") in the final year. Open a profile to offer a renewal.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(expiringContracts.prefix(6)) { player in
                NavigationLink(destination: PlayerDetailView(playerId: player.id)) {
                    HStack {
                        RatingBadge(rating: player.overall, size: 28)
                        Text(player.fullName).font(.subheadline)
                        Spacer()
                        Text(player.contract?.yearsRemaining == 0 ? "Expiring" : "1 year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").accessibilityHidden(true).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .gfCard()
    }

    @ViewBuilder
    private var outOnLoanCard: some View {
        let outOnLoan = gameState.userPlayersOutOnLoan
        if !outOnLoan.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                GFSectionHeader(title: "Out on Loan", icon: "arrow.triangle.swap")
                ForEach(outOnLoan, id: \.player.id) { entry in
                    NavigationLink(destination: PlayerDetailView(playerId: entry.player.id)) {
                        HStack {
                            RatingBadge(rating: entry.player.overall, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.player.fullName).font(.subheadline)
                                Text("\(entry.club.name) • \(entry.player.seasonStatSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").accessibilityHidden(true).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .gfCard()
        }
    }
}

// MARK: - Player Row

public struct PlayerRowView: View {
    public let player: Player
    @AppStorage("gfShowMatchRating") private var showMatchRating = false
    
    public var body: some View {
        HStack(spacing: 12) {
            FaceView(player: player, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if player.isOnLoan { GFPill(text: "LOAN", color: .secondary) }
                    if player.transferStatus == .transferListed { GFPill(text: "LISTED", color: .orange) }
                }
                HStack(spacing: 6) {
                    Text(player.primaryPosition.abbreviation)
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(player.primaryPosition.category.accentColor.opacity(0.22), in: Capsule())
                    Text("Age \(player.age) • \(player.statusBadgeText)")
                        .font(.caption2)
                        .foregroundStyle(player.statusSeverity == 2 ? Color.lossRed : (player.statusSeverity == 1 ? Color.bronzeAccent : .secondary))
                        .lineLimit(1)
                }
                FaceStatStripView(player: player)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                RatingBadge(rating: player.overall, size: 36)
                if showMatchRating {
                    let m = player.matchRating
                    Text("Match \(m)")
                        .font(.caption2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(m > player.overall ? Color.winGreen : m < player.overall ? Color.lossRed : .secondary)
                        .accessibilityLabel("Match rating \(m)")
                }
                Text(player.formattedValue)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Tactics Screen

public struct TacticsView: View {
    @Environment(GameState.self) private var gameState
    
    /// Applies a mutation to the user's club tactics and writes the club back
    /// into the world state.
    private func updateTactics(_ mutate: (inout Tactics) -> Void) {
        // Update in place: removing and re-appending the club reordered the
        // whole world's club list on every tactical tweak.
        guard let idx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
        var tactics = gameState.clubs[idx].tactics
        mutate(&tactics)
        gameState.clubs[idx].tactics = tactics
    }
    
    @State private var pane: Pane = .tactics
    enum Pane: String, CaseIterable { case tactics = "Tactics", roles = "Roles" }

    public var body: some View {
        ScrollView {
            if let userClub = gameState.userClub {
                VStack(spacing: 16) {
                    GFTabs(selection: $pane)
                    if pane == .tactics {
                        tacticsCard(userClub)
                        Button("Auto-Pick Best XI") { gameState.autoPickUserLineup() }
                            .buttonStyle(.gfPrimary)
                            .padding(.horizontal, 40)
                            .accessibilityHint("Selects the highest rated available players for each position")
                    } else {
                        roleCard("Captain", info: "Leads the side. Leadership counts.", keyPath: \.captain, club: userClub) { $0.attributes.leadership }
                        roleCard("Penalty Taker", info: "Takes every spot kick. Penalties and composure count.", keyPath: \.penaltyTaker, club: userClub) { $0.attributes.penalties }
                        roleCard("Free Kick Taker", info: "Shoots or crosses from free kicks.", keyPath: \.freeKickTaker, club: userClub) { $0.attributes.freeKicks }
                        roleCard("Corner Taker", info: "Delivers corners. Crossing counts.", keyPath: \.cornerTaker, club: userClub) { $0.attributes.crossing }
                        Text("Chosen from the starting XI. If a taker is left out or injured, the best remaining player takes over.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
        }
    }

    private func tacticsCard(_ club: Club) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            cycler("Formation", value: club.tactics.formation.rawValue, options: FormationPreset.allCases,
                   current: club.tactics.formation) { preset in
                guard let idx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
                gameState.clubs[idx].tactics.formation = preset
                // Same players, rearranged for the new shape (no one is
                // dropped). During a live match the bench stays as named.
                gameState.clubs[idx].fitLineupToFormation(repair: gameState.liveMatch == nil)
            }
            cycler("Mentality", value: club.tactics.mentality.displayName, options: Mentality.allCases,
                   current: club.tactics.mentality) { m in updateTactics { $0.mentality = m } }
            chipGrid("Pressing", options: PressingIntensity.allCases, selected: club.tactics.pressing,
                     name: { $0.displayName }) { p in updateTactics { $0.pressing = p } }
            chipGrid("Passing", options: PassingStyle.allCases, selected: club.tactics.passingStyle,
                     name: { $0.displayName }) { p in updateTactics { $0.passingStyle = p } }
            chipGrid("Width", options: Width.allCases, selected: club.tactics.width,
                     name: { $0.displayName }) { w in updateTactics { $0.width = w } }
            chipGrid("Tempo", options: Tempo.allCases, selected: club.tactics.tempo,
                     name: { $0.displayName }) { t in updateTactics { $0.tempo = t } }
            chipGrid("Assistant's Subs", options: MatchSettings.AutoSubTiming.allCases, selected: gameState.matchSettings.autoSubTiming,
                     name: { $0 == .off ? "None: I decide" : $0 == .halfTime ? "Half-time" : $0 == .secondHalf ? "From 60'" : "Throughout" }) { t in
                gameState.matchSettings.autoSubTiming = t
            }
            chipGrid("Team Selection", options: [false, true], selected: gameState.matchSettings.assistantRotatesTiredPlayers,
                     name: { $0 ? "Assistant rests tired" : "I pick the team" }) { v in
                gameState.matchSettings.assistantRotatesTiredPlayers = v
            }
            Text("Every choice is a trade-off. Attacking mentality makes chances and leaves gaps for counter-attacks; a high press wins the ball high but tires legs and leaves space behind; a low block concedes shots, but few good ones; short passing keeps the ball, direct play makes more (poorer) chances. Players are rated for the position they play, so a player out of position is a weakness.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .gfCard(padding: 18)
    }

    /// "‹ BALANCED ›": arrows step through the options.
    private func cycler<T: Hashable>(_ title: String, value: String, options: [T], current: T, set: @escaping (T) -> Void) -> some View {
        let index = options.firstIndex(of: current) ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.gfLabel(13)).foregroundStyle(.secondary)
            HStack {
                Button { set(options[(index - 1 + options.count) % options.count]) } label: {
                    Image(systemName: "chevron.left").font(.headline.weight(.bold)).frame(width: 36, height: 32)
                }
                .accessibilityHidden(true)
                Text(value.uppercased()).font(.gfDisplay(19)).frame(maxWidth: .infinity)
                Button { set(options[(index + 1) % options.count]) } label: {
                    Image(systemName: "chevron.right").font(.headline.weight(.bold)).frame(width: 36, height: 32)
                }
                .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAdjustableAction { dir in
                set(options[(index + (dir == .increment ? 1 : options.count - 1)) % options.count])
            }
        }
    }

    /// A caption over capsule buttons, the chosen one filled white.
    private func chipGrid<T: Hashable>(_ title: String, options: [T], selected: T, name: @escaping (T) -> String,
                                       set: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.gfLabel(13)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isOn = option == selected
                    Button { set(option) } label: {
                        Text(name(option).uppercased())
                            .font(.gfLabel(13))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(isOn ? Color.gfNight : .white)
                            .background(Capsule().fill(isOn ? Color.white : Color.clear))
                            .overlay(Capsule().stroke(Color.white.opacity(isOn ? 0 : 0.7), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(name(option))")
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    /// "CAPTAIN ⓘ  [CAM  B. FERNANDES  93]  CHANGE".
    private func roleCard(_ title: String, info: String, keyPath: WritableKeyPath<Tactics, UUID?>, club: Club,
                          score: @escaping (Player) -> Int) -> some View {
        let options = club.startingXIPlayers.sorted { score($0) > score($1) }
        let chosen = club.tactics[keyPath: keyPath].flatMap { id in club.startingXIPlayers.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.gfDisplay(19))
            Text(info).font(.caption).foregroundStyle(.secondary)
            if let p = chosen {
                HStack(spacing: 8) {
                    Text(p.primaryPosition.abbreviation)
                        .font(.gfLabel(12)).foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(p.primaryPosition.category.accentColor))
                    Text(p.displayName.uppercased()).font(.gfLabel(15)).lineLimit(1)
                    Spacer()
                    Text("\(score(p))")
                        .font(.gfLabel(13).monospacedDigit()).foregroundStyle(Color.gfNight)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white))
                }
                .padding(10)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .accessibilityElement(children: .combine)
            } else {
                Text("Automatic: the best player in the side").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Menu {
                    Button("Automatic") {
                        if let idx = gameState.clubs.firstIndex(where: { $0.isUserClub }) { gameState.clubs[idx].tactics[keyPath: keyPath] = nil }
                    }
                    ForEach(options) { player in
                        Button("\(player.displayName) (\(score(player)))") {
                            if let idx = gameState.clubs.firstIndex(where: { $0.isUserClub }) { gameState.clubs[idx].tactics[keyPath: keyPath] = player.id }
                        }
                    }
                } label: {
                    Text(chosen == nil ? "ADD" : "CHANGE")
                        .font(.gfLabel(13))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                }
                .accessibilityLabel("Choose \(title.lowercased())")
            }
        }
        .gfCard()
    }
}

extension TacticsView {
    /// A picker over the starting XI for a captain or set-piece role, best
    /// suited first, with the relevant attribute shown.
    fileprivate func setPiecePicker(_ title: String, keyPath: WritableKeyPath<Tactics, UUID?>, club: Club,
                                    score: @escaping (Player) -> Int) -> some View {
        let options = club.startingXIPlayers.sorted { score($0) > score($1) }
        return Picker(title, selection: Binding<UUID?>(
            get: { club.tactics[keyPath: keyPath] },
            set: { newValue in
                if let idx = gameState.clubs.firstIndex(where: { $0.isUserClub }) {
                    gameState.clubs[idx].tactics[keyPath: keyPath] = newValue
                }
            }
        )) {
            ForEach(options) { player in
                Text("\(player.displayName) (\(score(player)))").tag(UUID?.some(player.id))
            }
        }
    }
}

// MARK: - Training Ground

public struct TrainingView: View {
    @Environment(GameState.self) private var gameState
    @State private var message: String?

    private var isAvailable: Bool {
        gameState.lastTrainingWeek != gameState.season.currentWeek
    }

    public var body: some View {
        List {
            if let club = gameState.userClub {
                Section("This Week's Session") {
                    HStack {
                        Label(isAvailable ? "Session available" : "Session complete", systemImage: isAvailable ? "checkmark.circle.fill" : "lock.fill")
                            .foregroundStyle(isAvailable ? Color.winGreen : Color.secondary)
                        Spacer()
                        Text("Week \(gameState.season.currentWeek)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(isAvailable
                         ? "Choose one focused session. The choice matters, and you can run only one per matchweek."
                         : "Your staff have completed this week’s dedicated session. Advance to the next week to plan another.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Training Focus") {
                    ForEach(TrainingFocus.allCases) { focus in
                        Button { run(focus) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: focus.icon).accessibilityHidden(true)
                                    .frame(width: 28)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(focus.title).fontWeight(.semibold).foregroundStyle(.primary)
                                    Text(focus.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(!isAvailable)
                        .accessibilityLabel("\(focus.title) training")
                        .accessibilityHint(isAvailable ? focus.detail : "Training is already complete for this matchweek")
                    }
                }

                Section("Pre-Match Team Talk") {
                    Text("Choose one message for the next match. It applies once when the match begins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(TeamTalkStyle.allCases) { style in
                        Button {
                            _ = gameState.chooseTeamTalk(style)
                            message = "\(style.rawValue) selected. \(style.effectSummary)"
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(style.rawValue).fontWeight(gameState.teamTalk == style ? .bold : .regular)
                                    Text(style.effectSummary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if gameState.teamTalk == style {
                                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true).foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .accessibilityLabel("\(style.rawValue) team talk")
                        .accessibilityHint(style.effectSummary)
                    }
                }

                Section(header: Text("Facilities"),
                        footer: Text("Better training facilities mean players improve during the season, month by month, as well as in the summer. Good form helps too.")) {
                    ForEach(FacilityKind.allCases) { kind in
                        let level = gameState.facilityLevel(kind)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(kind.title).fontWeight(.semibold)
                                Spacer()
                                Text("Level \(level) of 5").font(.subheadline.monospacedDigit())
                            }
                            Text(kind.effect).font(.caption).foregroundStyle(.secondary)
                            if level < 5 {
                                Button("Ask the Board to Upgrade (\(Player.formatCurrency(gameState.facilityUpgradeCost(kind))))") {
                                    message = gameState.requestFacilityUpgrade(kind)
                                    try? SaveManager.shared.autoSave(gameState: gameState)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }

                Section("Squad Pulse") {
                    let healthy = club.players.filter { $0.injury == nil }
                    LabeledContent("Healthy players", value: "\(healthy.count) / \(club.players.count)")
                    LabeledContent("Average fitness", value: "\(average(healthy.map(\.matchFitness)))%")
                    LabeledContent("Average sharpness", value: "\(average(healthy.map(\.sharpness)))%")
                }
            } else {
                ContentUnavailableView("No Squad", systemImage: "figure.run", description: Text("Take charge of a club before planning training."))
            }
        }
        .navigationTitle("Training Ground")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { gameState.currentScreen = .dashboard }
                    .accessibilityLabel("Close training and return to manager home")
            }
        }
        .alert("Training Report", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func average(_ values: [Double]) -> Int {
        guard !values.isEmpty else { return 0 }
        return Int(values.reduce(0, +) / Double(values.count))
    }

    private func run(_ focus: TrainingFocus) {
        let succeeded = gameState.runTrainingSession(focus)
        message = succeeded ? "\(focus.title) complete. \(focus.detail)" : "A dedicated session has already been completed this matchweek."
    }
}

// MARK: - Standings Screen

public struct StandingsView: View {
    @Environment(GameState.self) private var gameState
    /// The league being browsed; nil means "the user's own league".
    @State private var selectedLeagueId: UUID?
    /// Table, domestic cup or player leaderboards.
    @State private var view: LeagueView = .table
    /// Which of the country's trophies the Cup tab shows.
    @State private var selectedCupName: String?
    @State private var leaderboard: Leaderboard = .goals

    enum LeagueView: String, CaseIterable { case table = "Table", cup = "Cup", stats = "Stats" }
    enum Leaderboard: String, CaseIterable { case goals = "Goals", assists = "Assists", ratings = "Ratings" }

    private var displayedLeague: League? {
        if let id = selectedLeagueId, let league = gameState.leagues.first(where: { $0.id == id }) {
            return league
        }
        return gameState.currentLeague ?? gameState.leagues.first
    }

    private struct LeagueGroup: Identifiable {
        let country: LeagueCountry
        let leagues: [League]
        var id: String { country.rawValue }
    }

    /// Leagues grouped by country, top divisions first, for the picker.
    private var leagueMenu: [LeagueGroup] {
        let grouped = Dictionary(grouping: gameState.leagues, by: { $0.tier.country })
        return grouped
            .map { LeagueGroup(country: $0.key, leagues: $0.value.sorted { $0.tier.rawValue < $1.tier.rawValue }) }
            .sorted { lhs, rhs in
                if lhs.country == .england { return true }
                if rhs.country == .england { return false }
                return lhs.country.displayName < rhs.country.displayName
            }
    }
    
    public var body: some View {
        List {
            if let league = displayedLeague {
                let standings = gameState.standings(for: league)
                let existingTiers = Set(gameState.leagues.map { $0.tier })
                let hasHigher = league.tier.higherTier.map { existingTiers.contains($0) } ?? false
                let hasLower = league.tier.lowerTier.map { existingTiers.contains($0) } ?? false

                Section {
                    leaguePicker(current: league)
                    let hasCup = gameState.domesticCups.contains(where: { $0.country == league.tier.country })
                    GFTabs(selection: $view, options: LeagueView.allCases.filter { hasCup || $0 != .cup }.map { ($0, $0.rawValue) })
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                let countryCups = gameState.domesticCups.filter { $0.country == league.tier.country }
                if view == .cup, let cup = countryCups.first(where: { $0.name == selectedCupName }) ?? countryCups.first {
                    if countryCups.count > 1 {
                        Section {
                            GFTabs(selection: Binding(get: { cup.name }, set: { selectedCupName = $0 }),
                                   options: countryCups.map { ($0.name, $0.name) }, compact: true)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }
                    }
                    cupSections(cup)
                } else if view == .stats {
                    leaderboardSections(league)
                } else {
                Section(header: standingsHeader) {
                    ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                        let rank = index + 1
                        let zone = league.tier.zone(forPosition: rank, clubCount: standings.count, hasHigherTier: hasHigher, hasLowerTier: hasLower)
                        standingRow(rank: rank, standing: standing, zone: zone)
                    }
                }

                Section {
                    zoneLegend(for: league, clubCount: standings.count, hasHigher: hasHigher, hasLower: hasLower)
                }
                }
            } else {
                ContentUnavailableView("No League Data", systemImage: "trophy")
            }
        }
    }

    /// The division's top scorers, assisters and best-rated players.
    @ViewBuilder
    private func leaderboardSections(_ league: League) -> some View {
        Section {
            GFTabs(selection: $leaderboard, compact: true)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
        let clubs = league.clubIds.compactMap { gameState.club(withId: $0) }
        let entries: [(player: Player, club: Club, value: Double)] = clubs.flatMap { club in
            club.players.compactMap { p -> (player: Player, club: Club, value: Double)? in
                let stats = p.seasonStats
                switch leaderboard {
                case .goals: return stats.goals > 0 ? (p, club, Double(stats.goals)) : nil
                case .assists: return stats.assists > 0 ? (p, club, Double(stats.assists)) : nil
                case .ratings:
                    let needed = max(3, gameState.season.currentWeek / 3)
                    return stats.appearances >= needed && stats.averageRating > 0 ? (p, club, stats.averageRating) : nil
                }
            }
        }
        .sorted { $0.value > $1.value }
        Section(header: HStack { Text("Name"); Spacer(); Text(leaderboard.rawValue) }) {
            if entries.isEmpty {
                Text("No one yet. The leaderboards fill in as matches are played.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entries.prefix(25).enumerated()), id: \.element.player.id) { index, entry in
                Button {
                    gameState.openProfile(entry.player.id)
                } label: {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        CrestView(club: entry.club, size: 20)
                        Text("\(entry.player.displayName.uppercased()) (\(entry.club.name))")
                            .font(.subheadline.weight(entry.club.isUserClub ? .heavy : .regular))
                            .lineLimit(1)
                        Spacer()
                        Text(leaderboard == .ratings ? String(format: "%.2f", entry.value) : "\(Int(entry.value))")
                            .font(.gfLabel(13).monospacedDigit())
                            .foregroundStyle(Color.gfNight)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(leaderboard == .ratings && entry.value >= 7.5 ? Color.gfMint : Color.white))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// One section per round drawn so far, latest round first.
    @ViewBuilder
    private func cupSections(_ cup: DomesticCupState) -> some View {
        if let championId = cup.championClubId, let champion = gameState.club(withId: championId) {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill").accessibilityHidden(true).foregroundStyle(Color.goldAccent)
                    CrestView(club: champion, size: 26)
                    Text("\(champion.name) — \(cup.name) winners")
                        .font(.headline)
                }
                .accessibilityElement(children: .combine)
            }
        }
        ForEach(Array(Array(cup.rounds.prefix(cup.currentRoundIndex + 1).enumerated()).reversed()), id: \.offset) { _, roundName in
            let ties = gameState.season.fixtures.filter { $0.competition == cup.name && $0.cupRound == roundName }
            Section(header: Text("\(cup.name) • \(roundName)")) {
                ForEach(ties) { tie in
                    cupTieRow(tie)
                }
            }
        }
    }

    private func cupTieRow(_ tie: Fixture) -> some View {
        let home = gameState.club(withId: tie.homeClubId)
        let away = gameState.club(withId: tie.awayClubId)
        let involvesUser = gameState.userClubId.map { tie.involves(clubId: $0) } ?? false
        let winner = tie.winnerClubId
        let score = tie.result.map { "\($0.homeGoals) - \($0.awayGoals)" } ?? "v"
        return HStack(spacing: 6) {
            Text(home?.name ?? "Club")
                .fontWeight(winner == tie.homeClubId ? .bold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(score)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 52)
            Text(away?.name ?? "Club")
                .fontWeight(winner == tie.awayClubId ? .bold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .listRowBackground(involvesUser ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tie.isPlayed
            ? "\(home?.name ?? "Club") \(tie.result?.homeGoals ?? 0), \(away?.name ?? "Club") \(tie.result?.awayGoals ?? 0). \(winner.flatMap { gameState.club(withId: $0)?.name } ?? "") go through."
            : "\(home?.name ?? "Club") versus \(away?.name ?? "Club"), to be played.")
    }

    private func leaguePicker(current: League) -> some View {
        Menu {
            Button {
                selectedLeagueId = nil
            } label: {
                Label("My League", systemImage: "star.fill")
            }
            ForEach(leagueMenu) { group in
                Section(group.country.displayName) {
                    ForEach(group.leagues) { league in
                        Button(league.name) { selectedLeagueId = league.id }
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(current.tier.country.displayName) • Matchweek \(gameState.currentLeagueRound(competition: current.name)) •\(gameState.season.year)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("League: \(current.name). Double tap to choose another league.")
    }

    private func standingRow(rank: Int, standing: LeagueStanding, zone: TableZone) -> some View {
        let club = gameState.club(withId: standing.clubId)
        let isUser = club?.isUserClub == true
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(zoneColor(zone))
                .frame(width: 4, height: 30)
            Text("\(rank)")
                .font(.caption.monospacedDigit())
                .frame(width: 22, alignment: .leading)
            if let club {
                CrestView(club: club, size: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(club?.name ?? "Club")
                    .font(.subheadline)
                    .fontWeight(isUser ? .bold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                formGuide(standing.form)
            }
            Spacer(minLength: 4)
            Text("\(standing.played)")
                .font(.caption.monospacedDigit())
                .frame(width: 24, alignment: .trailing)
            Text(standing.goalDifference > 0 ? "+\(standing.goalDifference)" : "\(standing.goalDifference)")
                .font(.caption.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
            Text("\(standing.points)")
                .font(.subheadline.monospacedDigit())
                .fontWeight(.bold)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .listRowBackground(isUser ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityFormatter.standingRow(rank: rank, clubName: club?.name ?? "Club", standing: standing)
            + (zone == .none ? "" : " \(zone.displayName).")
            + (standing.form.isEmpty ? "" : " Form: \(standing.form.joined(separator: " ")).")
        )
    }

    private func formGuide(_ form: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(form.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(formColor(letter))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    private func zoneLegend(for league: League, clubCount: Int, hasHigher: Bool, hasLower: Bool) -> some View {
        let zones = Set((1...max(1, clubCount)).map {
            league.tier.zone(forPosition: $0, clubCount: clubCount, hasHigherTier: hasHigher, hasLowerTier: hasLower)
        })
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(TableZone.allCases.filter { $0 != .none && zones.contains($0) }, id: \.self) { zone in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(zoneColor(zone))
                        .frame(width: 12, height: 12)
                    Text(zone.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func zoneColor(_ zone: TableZone) -> Color {
        switch zone {
        case .champions: return .goldAccent
        case .europe: return .defColor
        case .promotion: return .winGreen
        case .playOff: return .bronzeAccent
        case .relegation: return .lossRed
        case .none: return .clear
        }
    }

    private func formColor(_ letter: String) -> Color {
        switch letter {
        case "W": return .winGreen
        case "D": return .drawGray
        default: return .lossRed
        }
    }
    
    private var standingsHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 4, height: 1)
            Text("#").frame(width: 22, alignment: .leading)
            Text("Club")
            Spacer()
            Text("P").frame(width: 24, alignment: .trailing)
            Text("GD").frame(width: 32, alignment: .trailing)
            Text("Pts").frame(width: 32, alignment: .trailing)
        }
        .font(.caption)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Transfer Hub Screen

public struct TransferHubView: View {
    @Environment(GameState.self) private var gameState
    @State private var showFreeAgents = false
    @State private var marketFeed = 0
    
    public var body: some View {
        List {
            Section {
                VStack(alignment: .center, spacing: 14) {
                    GFScreenTitle(title: "Transfer Market", subtitle: gameState.transferWindowStatus)
                    if let userClub = gameState.userClub {
                        HStack(spacing: 12) {
                            GFValuePill(title: "Budget", value: Player.formatCurrency(userClub.finances.transferBudget),
                                        tone: userClub.finances.transferBudget > 0 ? .good : .bad)
                            GFValuePill(title: "Wage Room", value: "\(Player.formatCurrency(userClub.finances.weeklyWageSurplus))/w",
                                        tone: userClub.finances.weeklyWageSurplus >= 0 ? .good : .bad)
                        }
                        NavigationLink(destination: PlayerSearchView()) {
                            Label("Search Players", systemImage: "magnifyingglass")
                                .font(.gfLabel(16))
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .foregroundStyle(Color.gfNight)
                                .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Browse the transfer market with filters")
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Transfer window: \(gameState.transferWindowStatus)")
            }
            
            if !gameState.actionableOffers.isEmpty {
                Section(header: Text("Active Negotiations (\(gameState.actionableOffers.count))")) {
                    ForEach(gameState.actionableOffers) { offer in
                        ActiveOfferRow(offer: offer)
                    }
                }
                .accessibilityHint("Bids and offers awaiting a response")
            }

            Section(header: Text("Shortlist (\(gameState.shortlist.count))"),
                    footer: Text(gameState.shortlist.isEmpty ? "Tap the star on a player's profile to track him here." : "")) {
                ForEach(gameState.shortlistedPlayers, id: \.player.id) { entry in
                    NavigationLink(destination: PlayerDetailView(playerId: entry.player.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.player.fullName).font(.subheadline.weight(.semibold))
                                Text("\(entry.player.primaryPosition.abbreviation) • \(entry.player.age) • \(entry.club?.name ?? "Free agent")\(entry.player.isOnLoan ? " (on loan)" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(entry.player.overall)").font(.headline)
                                Text(entry.player.formattedValue).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            gameState.toggleShortlist(entry.player.id)
                        } label: {
                            Label("Remove", systemImage: "star.slash")
                        }
                    }
                }
            }

            Section(header: Text("Free Agent Market")) {
                Toggle(isOn: $showFreeAgents) {
                    Label("Browse Free Agents (\(gameState.freeAgents.count))", systemImage: "person.crop.circle.badge.questionmark")
                }
                .accessibilityHint("Free agents are hidden unless this is switched on")
                if showFreeAgents {
                    if gameState.freeAgents.isEmpty {
                        Text("No free agents currently scouting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(gameState.freeAgents.prefix(15)) { player in
                            NavigationLink(destination: PlayerDetailView(playerId: player.id)) {
                                PlayerRowView(player: player)
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Around the World")) {
                GFTabs(selection: $marketFeed, options: [(0, "Latest"), (1, "Record Fees"), (2, "Loans")], compact: true)
                let records = feedRecords
                if records.isEmpty {
                    Text(marketFeed == 2 ? "No loan moves yet this season." : "No transfers yet this season.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(record.playerName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(record.formattedFee)
                                    .font(.subheadline.monospacedDigit())
                                    .fontWeight(.semibold)
                            }
                            Text("\(record.fromClubName) to \(record.toClubName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func budgetTile(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// This season's moves for the selected feed.
    private var feedRecords: [TransferRecord] {
        let seasonStart = "\(gameState.season.year.prefix(4))-06-01"
        let thisSeason = gameState.transferHistory.filter { $0.date >= seasonStart }
        switch marketFeed {
        case 1:
            return Array(thisSeason.filter { !$0.isLoan && $0.fee > 0 }.sorted { $0.fee > $1.fee }.prefix(12))
        case 2:
            return Array(thisSeason.filter { $0.isLoan }.suffix(12).reversed())
        default:
            return Array(thisSeason.filter { !$0.isLoan }.suffix(12).reversed())
        }
    }
}

// MARK: - Active Offer Row

private struct ActiveOfferRow: View {
    @Environment(GameState.self) private var gameState
    let offer: TransferOffer

    private var playerName: String {
        gameState.player(withId: offer.playerId)?.player.fullName ?? "Player"
    }

    private var otherClubName: String {
        let clubId = offer.isIncoming ? offer.toClubId : offer.fromClubId
        return gameState.club(withId: clubId)?.name ?? "Club"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playerName)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(offer.isIncoming
                 ? (offer.isLoan ? "\(otherClubName) want him on loan" : "\(otherClubName) bid \(Player.formatCurrency(offer.fee))")
                 : "Your bid to \(otherClubName): \(Player.formatCurrency(offer.fee))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if offer.isIncoming {
                HStack(spacing: 10) {
                    Button(offer.isLoan ? "Agree Loan" : "Accept") {
                        gameState.acceptIncomingOffer(offerId: offer.id)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reject", role: .destructive) {
                        gameState.rejectIncomingOffer(offerId: offer.id)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
                .padding(.top, 2)
            } else {
                statusLabel
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(playerName), \(offer.isIncoming ? (offer.isLoan ? "loan request" : "incoming offer") : "outgoing bid"), \(offer.isIncoming ? "awaiting your decision" : statusDescription)")
    }

    private var statusDescription: String {
        switch offer.status {
        case .counterOffer: return "counter offer of \(Player.formatCurrency(offer.counterFee ?? offer.askingPrice))"
        case .personalTerms: return "awaiting personal terms"
        case .pending: return "awaiting response"
        default: return offer.status.displayName
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch offer.status {
        case .counterOffer:
            Text("Counter: \(Player.formatCurrency(offer.counterFee ?? offer.askingPrice)) — check your inbox")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .personalTerms:
            Text("Personal terms — check your inbox")
                .font(.caption2)
                .foregroundStyle(.orange)
        default:
            Text("Awaiting response")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Player Search / Transfer Market

public struct PlayerSearchView: View {
    @Environment(GameState.self) private var gameState
    @State private var tab: MarketTab = .players
    @State private var filters = MarketFilters()
    @State private var sortMode: SortMode = .overall
    @State private var page = 0

    private let pageSize = 25

    enum MarketTab: String, CaseIterable { case players = "Players", filters = "Filters", deals = "Deals" }

    enum SortMode: String, CaseIterable, Identifiable {
        case overall = "Rating"
        case value = "Value"
        case age = "Age"
        case name = "Name"
        case role = "Role"
        var id: String { rawValue }
    }

    /// Everything the Filters tab can narrow down.
    struct MarketFilters: Equatable {
        var minRating = 0
        var maxRating = 100
        var minAge = 14
        var maxAge = 45
        var maxValue: Int? = nil
        var nationality: String? = nil
        var role: Position? = nil
        var category: PositionCategory? = nil
        var status: StatusFilter = .all
        var name = ""
    }

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case listed = "Transfer listed"
        case loanListed = "Loan listed"
        case loanable = "Loan candidates"
        case freeAgent = "Free agents"
        case affordable = "Within budget"
        case mine = "My players"
    }

    private var budget: Int { gameState.userClub?.finances.transferBudget ?? 0 }

    private var results: [(player: Player, club: Club?)] {
        let f = filters
        let query = f.name.trimmingCharacters(in: .whitespaces).lowercased()
        let base = gameState.searchPlayers(
            positionCategory: f.category,
            specificPosition: f.role,
            minOverall: f.minRating,
            maxAge: f.maxAge,
            maxFee: f.maxValue,
            includeFreeAgents: true,
            // Your own players are listed too, so you can see where they rank.
            includeOwnPlayers: true
        )
        .filter { entry in
            let p = entry.player
            if p.overall > f.maxRating || p.age < f.minAge { return false }
            if let nat = f.nationality, p.nationality != nat { return false }
            if !query.isEmpty && !p.fullName.lowercased().contains(query) { return false }
            switch f.status {
            case .all: return true
            case .listed: return p.transferStatus == .transferListed
            case .loanListed: return p.transferStatus == .loanListed
            case .loanable:
                guard let club = entry.club, !club.isUserClub else { return false }
                return gameState.isLoanable(p, at: club)
            case .freeAgent: return entry.club == nil
            case .affordable:
                guard let club = entry.club else { return true }
                return !club.isUserClub && p.value <= budget
            case .mine: return entry.club?.isUserClub == true
            }
        }
        switch sortMode {
        case .overall: return base.sorted { ($0.player.overall, $0.player.value) > ($1.player.overall, $1.player.value) }
        case .value: return base.sorted { $0.player.value > $1.player.value }
        case .age: return base.sorted { $0.player.age < $1.player.age }
        case .name: return base.sorted { $0.player.lastName < $1.player.lastName }
        case .role: return base.sorted { ($0.player.primaryPosition.sortIndex, -$0.player.overall) < ($1.player.primaryPosition.sortIndex, -$1.player.overall) }
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            GFScreenTitle(title: "Transfer Market", subtitle: gameState.transferWindowStatus)
            GFTabs(selection: $tab)
                .padding(.horizontal)
            switch tab {
            case .players: playersTab
            case .filters: filtersTab
            case .deals: dealsTab
            }
        }
        .padding(.top, 8)
        .stadiumBackground()
        .navigationTitle("Transfer Market")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: filters) { _, _ in page = 0 }
        .onChange(of: sortMode) { _, _ in page = 0 }
    }

    // MARK: Players

    private var playersTab: some View {
        let all = results
        let pages = max(1, (all.count + pageSize - 1) / pageSize)
        let current = min(page, pages - 1)
        let slice = Array(all.dropFirst(current * pageSize).prefix(pageSize))
        return VStack(spacing: 10) {
            HStack {
                Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(current == 0)
                    .accessibilityLabel("Previous page")
                Spacer()
                Text("PAGE \(current + 1) OF \(pages) · \(all.count) PLAYERS")
                    .font(.gfLabel(14))
                Spacer()
                Button { page = min(pages - 1, current + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(current >= pages - 1)
                    .accessibilityLabel("Next page")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.gfNavy.opacity(0.9)))
            .padding(.horizontal)

            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        sortHeader("Role", .role).frame(width: 44, alignment: .leading)
                        sortHeader("Name", .name)
                        Spacer()
                        sortHeader("Age", .age).frame(width: 36)
                        sortHeader("Val", .overall).frame(width: 44)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    if slice.isEmpty {
                        Text("No players match your filters.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(30)
                    }
                    ForEach(Array(slice.enumerated()), id: \.element.player.id) { offset, entry in
                        NavigationLink(destination: PlayerDetailView(playerId: entry.player.id)) {
                            marketRow(entry.player, club: entry.club, rank: current * pageSize + offset + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .gfCard(padding: 0)
                .padding(.horizontal)
            }
        }
    }

    private func sortHeader(_ title: String, _ mode: SortMode) -> some View {
        Button {
            sortMode = mode
        } label: {
            HStack(spacing: 2) {
                Text(title.uppercased()).font(.gfLabel(13))
                if sortMode == mode { Image(systemName: "chevron.down").accessibilityHidden(true).font(.caption2.weight(.bold)) }
            }
            .foregroundStyle(sortMode == mode ? Color.white : Color.white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(mode.rawValue)")
        .accessibilityAddTraits(sortMode == mode ? [.isButton, .isSelected] : .isButton)
    }

    private func marketRow(_ player: Player, club: Club?, rank: Int) -> some View {
        let mine = club?.isUserClub == true
        return HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
            Text(player.primaryPosition.abbreviation)
                .font(.gfLabel(12))
                .foregroundStyle(.black)
                .frame(width: 40)
                .padding(.vertical, 3)
                .background(Capsule().fill(player.primaryPosition.category.accentColor))
            VStack(alignment: .leading, spacing: 1) {
                Text(player.displayName.uppercased())
                    .font(.gfLabel(14))
                    .lineLimit(1)
                Text(mine ? "YOUR PLAYER" : (club?.name ?? "Free agent"))
                    .font(.caption2.weight(mine ? .bold : .regular))
                    .foregroundStyle(mine ? Color.gfMint : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if player.transferStatus == .transferListed {
                Image(systemName: "tag.fill").accessibilityHidden(true).font(.caption2).foregroundStyle(Color.gfBanner)
            }
            Text("\(player.age)")
                .font(.gfLabel(14).monospacedDigit())
                .frame(width: 36)
            Text("\(player.overall)")
                .font(.gfLabel(13).monospacedDigit())
                .foregroundStyle(Color.gfNight)
                .frame(width: 40)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(mine ? Color.gfMint.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Number \(rank). \(player.primaryPosition.displayName), \(player.fullName), \(mine ? "your player" : (club?.name ?? "free agent")), age \(player.age), rated \(player.overall), value \(Player.spokenCurrency(player.value))\(player.transferStatus == .transferListed ? ", transfer listed" : "")")
    }

    // MARK: Filters

    private var nationalities: [String] {
        let all = gameState.clubs.flatMap { $0.players.map(\.nationality) } + gameState.freeAgents.map(\.nationality)
        let counts = Dictionary(all.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.keys.sorted()
    }

    private var filtersTab: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("FILTERS").font(.gfDisplay(22))
                Grid(horizontalSpacing: 16, verticalSpacing: 18) {
                    GridRow {
                        filterCell("Rating range", "\(filters.minRating) - \(filters.maxRating)") {
                            Menu("Minimum") { ForEach([0, 50, 55, 60, 65, 70, 75, 80, 85], id: \.self) { v in Button("\(v)") { filters.minRating = v; filters.maxRating = max(filters.maxRating, v) } } }
                            Menu("Maximum") { ForEach([100, 90, 85, 80, 75, 70, 65, 60], id: \.self) { v in Button("\(v)") { filters.maxRating = v; filters.minRating = min(filters.minRating, v) } } }
                        }
                        filterCell("Market value", filters.maxValue.map { "Up to \(Player.formatCurrency($0))" } ?? "All") {
                            Button("All") { filters.maxValue = nil }
                            Button("Within my budget (\(Player.formatCurrency(budget)))") { filters.maxValue = max(0, budget) }
                            ForEach([500_000, 2_000_000, 5_000_000, 10_000_000, 25_000_000, 50_000_000], id: \.self) { v in
                                Button("Up to \(Player.formatCurrency(v))") { filters.maxValue = v }
                            }
                        }
                    }
                    GridRow {
                        filterCell("Age range", "\(filters.minAge) - \(filters.maxAge)") {
                            Menu("Youngest") { ForEach([14, 17, 19, 21, 23, 25, 28, 30], id: \.self) { v in Button("\(v)") { filters.minAge = v; filters.maxAge = max(filters.maxAge, v) } } }
                            Menu("Oldest") { ForEach([45, 33, 30, 28, 25, 23, 21, 19], id: \.self) { v in Button("\(v)") { filters.maxAge = v; filters.minAge = min(filters.minAge, v) } } }
                        }
                        filterCell("Nationality", filters.nationality ?? "All") {
                            Button("All") { filters.nationality = nil }
                            ForEach(nationalities, id: \.self) { n in Button(n) { filters.nationality = n } }
                        }
                    }
                    GridRow {
                        filterCell("Role", filters.role?.abbreviation ?? filters.category?.displayName ?? "All") {
                            Button("All") { filters.role = nil; filters.category = nil }
                            ForEach(PositionCategory.allCases) { c in
                                Button("Any \(c.displayName)") { filters.category = c; filters.role = nil }
                            }
                            Divider()
                            ForEach(Position.allCases, id: \.self) { pos in
                                Button("\(pos.abbreviation) · \(pos.displayName)") { filters.role = pos; filters.category = nil }
                            }
                        }
                        filterCell("Status", filters.status.rawValue) {
                            ForEach(StatusFilter.allCases, id: \.self) { st in Button(st.rawValue) { filters.status = st } }
                        }
                    }
                }
                VStack(spacing: 6) {
                    Text("PLAYER NAME").font(.gfLabel(13)).foregroundStyle(.secondary)
                    TextField("Player", text: $filters.name)
                        .multilineTextAlignment(.center)
                        .font(.gfLabel(16))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .accessibilityLabel("Player name")
                }
                Button("Reset Filters") { filters = MarketFilters() }
                    .buttonStyle(.gfOutline)
                    .padding(.horizontal, 50)
                Button("Show \(results.count) Players") { tab = .players }
                    .buttonStyle(.gfSolid)
                    .padding(.horizontal, 30)
            }
            .gfCard(padding: 20)
            .padding(.horizontal)
        }
    }

    private func filterCell<Content: View>(_ title: String, _ value: String, @ViewBuilder menu: () -> Content) -> some View {
        Menu {
            menu()
        } label: {
            VStack(spacing: 4) {
                Text(title.uppercased()).font(.gfLabel(13)).foregroundStyle(.secondary)
                Text(value.uppercased()).font(.gfLabel(16)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint("Double tap to change")
    }

    // MARK: Deals

    private struct DealCard: Identifiable {
        let id: UUID
        let player: String
        let from: String
        let to: String
        let fee: String
        let date: String
        let badge: String
        let badgeColor: Color
    }

    private var deals: [DealCard] {
        guard let userId = gameState.userClubId else { return [] }
        func name(_ id: UUID) -> String { gameState.club(withId: id)?.name ?? "Free agent" }
        var cards: [DealCard] = gameState.pendingTransferOffers
            .filter { ($0.toClubId == userId || $0.fromClubId == userId) && $0.isLive }
            .map { offer in
                let player = gameState.player(withId: offer.playerId)?.player.fullName ?? "Player"
                return DealCard(id: offer.id, player: player, from: name(offer.fromClubId), to: name(offer.toClubId),
                                fee: offer.isLoan ? "LOAN" : Player.formatCurrency(offer.counterFee ?? offer.fee),
                                date: offer.createdDate, badge: offer.status.displayName.uppercased(), badgeColor: .gfBanner)
            }
        cards += gameState.transferHistory
            .filter { $0.toClubId == userId || $0.fromClubId == userId }
            .suffix(40).reversed()
            .map { r in
                let incoming = r.toClubId == userId
                let badge = r.isLoan ? (incoming ? "LOAN IN" : "LOAN OUT") : (r.fee == 0 && !incoming ? "RELEASE" : (incoming ? "SIGNED" : "SOLD"))
                return DealCard(id: r.id, player: r.playerName, from: r.fromClubName, to: r.toClubName,
                                fee: r.isLoan ? "LOAN" : (r.fee == 0 ? "FREE" : Player.formatCurrency(r.fee)),
                                date: r.date, badge: badge,
                                badgeColor: incoming ? Color.gfMint : Color.gfCoral)
            }
        return cards
    }

    private var dealsTab: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                let list = deals
                if list.isEmpty {
                    Text("No deals yet. Bids, sales and signings appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(30)
                }
                ForEach(list) { deal in
                    VStack(spacing: 6) {
                        Text(deal.player.uppercased()).font(.gfLabel(16))
                        HStack {
                            Text(deal.from.uppercased()).font(.gfLabel(13)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").accessibilityHidden(true).font(.caption.weight(.bold))
                            Text(deal.to.uppercased()).font(.gfLabel(13)).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Text(deal.fee).font(.gfDisplay(20))
                        HStack {
                            Text(DashboardView.shortDate(deal.date)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(deal.badge)
                                .font(.gfLabel(11))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(deal.badgeColor.opacity(0.85)))
                        }
                    }
                    .gfCard(padding: 14)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(deal.player), from \(deal.from) to \(deal.to), \(deal.fee), \(deal.badge.lowercased())")
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Match Day Screen

public struct MatchDayView: View {
    @Environment(GameState.self) private var gameState
    @State private var editingLineup = false
    @State private var zone: Zone = .info

    enum Zone: String, CaseIterable { case info = "Info", team = "Team", opponent = "Opponent" }

    public var body: some View {
        ScrollView {
            if let fixture = gameState.activeMatchFixture,
               let home = gameState.club(withId: fixture.homeClubId),
               let away = gameState.club(withId: fixture.awayClubId) {
                VStack(spacing: 16) {
                    GFScreenTitle(title: "Pre-Match Zone",
                                  subtitle: fixture.cupRound.map { "\(fixture.competition) · \($0)" } ?? "\(fixture.competition) · Matchweek \(gameState.leagueRound(of: fixture))")
                    GFTabs(selection: $zone)
                    switch zone {
                    case .info:
                        hero(fixture: fixture, home: home, away: away)
                        oddsRow(fixture: fixture)
                        MatchPreviewCard(fixture: fixture, home: home, away: away)
                    case .team:
                        lineupCard
                    case .opponent:
                        let opponent = home.isUserClub ? away : home
                        teamSheet(opponent)
                    }
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let fixture = gameState.activeMatchFixture {
                actions(fixture: fixture)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 8)
            }
        }
        .hubScreen("Match Day")
        .onAppear {
            // Always the fixture being played today, never a finished one.
            if gameState.activeMatchFixture?.isPlayed ?? true {
                if !gameState.selectTodaysUserFixture() { gameState.currentScreen = .dashboard }
            }
        }
        .sheet(isPresented: $editingLineup) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        KeepLineupBar()
                        LineupEditorView()
                    }
                    .padding()
                }
                .stadiumBackground()
                .navigationTitle("Lineup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { editingLineup = false }
                    }
                }
            }        }
    }

    private func hero(fixture: Fixture, home: Club, away: Club) -> some View {
        VStack(spacing: 12) {
            Text(fixture.cupRound.map { "\(fixture.competition) • \($0)" } ?? "\(fixture.competition) • Matchweek \(gameState.leagueRound(of: fixture))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
            HStack {
                VStack(spacing: 6) {
                    CrestView(club: home, size: 40)
                    Text(home.name).font(.caption.weight(.bold)).multilineTextAlignment(.center).lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    Text("VS").font(.system(size: 28, weight: .black, design: .rounded))
                    Text(fixture.date).font(.caption2.monospacedDigit()).opacity(0.8)
                }
                VStack(spacing: 6) {
                    CrestView(club: away, size: 40)
                    Text(away.name).font(.caption.weight(.bold)).multilineTextAlignment(.center).lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.white)
            Text("\(home.stadium) (\(home.stadiumCapacity.formatted()) seats)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            HStack {
                Text(String(format: "%.0f", home.startingXIAverageOverall)).font(.gfDisplay(22))
                Spacer()
                Text("STRENGTH").font(.gfLabel(14)).opacity(0.8)
                Spacer()
                Text(String(format: "%.0f", away.startingXIAverageOverall)).font(.gfDisplay(22))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            if let derby = gameState.rivalry(between: fixture.homeClubId, and: fixture.awayClubId) {
                VStack(spacing: 4) {
                    GFPill(text: derby.name, color: .white, icon: "flame.fill")
                    Text(derby.intensity >= 3 ? "The biggest game of the season. Form counts for little today." : "A local rivalry. Expect a fierce contest.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: home.primaryColor), Color(hex: away.primaryColor)],
                               startPoint: .leading, endPoint: .trailing)
                Color.black.opacity(0.3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Home win, draw and away win prices: "1 / X / 2".
    @ViewBuilder
    private func oddsRow(fixture: Fixture) -> some View {
        if let odds = gameState.matchOdds(for: fixture) {
            HStack(spacing: 12) {
                ForEach([("1", odds.home), ("X", odds.draw), ("2", odds.away)], id: \.0) { label, p in
                    GFValuePill(title: label, value: String(format: "%.2f", MatchOdds.decimal(p)))
                }
            }
            .gfCard(padding: 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: "Odds: home win %.2f, draw %.2f, away win %.2f",
                                       MatchOdds.decimal(odds.home), MatchOdds.decimal(odds.draw), MatchOdds.decimal(odds.away)))
        }
    }

    /// "LEEDS UNITED (4-3-3)" over the side drawn on a pitch.
    private func teamSheet(_ club: Club) -> some View {
        VStack(spacing: 12) {
            Text("\(club.name.uppercased()) (\(club.tactics.formation.rawValue))")
                .font(.gfLabel(17))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.gfNavy.opacity(0.9)))
            FormationPitchView(formation: club.tactics.formation, players: club.startingXIPlayers,
                               selectedPlayerId: nil, onSelect: { _ in })
            let bench = club.substitutePlayers
            if !bench.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(bench) { player in
                            SquadPlayerCard(player: player)
                        }
                    }
                }
                .gfCard(padding: 10)
            }
        }
    }

    @ViewBuilder
    private var lineupCard: some View {
        if let club = gameState.userClub {
            VStack(spacing: 12) {
                teamSheet(club)
                Button {
                    // Changes from here on are for this match only.
                    gameState.beginMatchOnlyLineup()
                    editingLineup = true
                } label: {
                    Label("Manage Lineup", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.gfOutline)
                .padding(.horizontal, 30)
                .accessibilityHint("Change your starting eleven and bench")
            }
        }
    }

    private func actions(fixture: Fixture) -> some View {
        VStack(spacing: 12) {
            Button {
                gameState.currentScreen = .liveMatch
            } label: {
                Text("Play Match")
            }
            .buttonStyle(.gfPrimary)
            .accessibilityLabel("Play the match with live commentary")
            Button {
                // The team talk must be applied before kick-off, exactly as in
                // live commentary.
                gameState.applyTeamTalkIfNeeded()
                if gameState.simulateFixture(id: fixture.id) {
                    gameState.finishMatchweekAfterUserMatch()
                    gameState.currentScreen = .postMatch
                }
            } label: {
                Text("Simulate Match")
            }
            .buttonStyle(.gfOutline)
            .accessibilityLabel("Simulate an instant match result")
        }
    }
}

// MARK: - Post Match Screen

/// Pre-match scouting: team strength, table position, form and danger man.
struct MatchPreviewCard: View {
    @Environment(GameState.self) private var gameState
    let fixture: Fixture
    let home: Club
    let away: Club

    private func form(_ club: Club) -> [String] {
        gameState.season.completedFixtures(forClub: club.id).suffix(5).compactMap { $0.result?.outcomeLetter(for: club.id) }
    }

    private func position(_ club: Club) -> String {
        let table = gameState.currentLeagueStandings
        guard let index = table.firstIndex(where: { $0.clubId == club.id }) else { return club.leagueTier.displayName }
        return "\(index + 1) of \(table.count)"
    }

    private var verdict: String {
        let gap = (home.startingXIAverageOverall + 2) - away.startingXIAverageOverall
        let userIsHome = home.isUserClub
        let userEdge = userIsHome ? gap : -gap
        switch userEdge {
        case 6...: return "Bookmakers make us clear favourites"
        case 2..<6: return "We go in as slight favourites"
        case -2..<2: return "Bookmakers can't separate the sides"
        case -6 ..< -2: return "We are slight underdogs"
        default: return "Bookmakers expect us to lose"
        }
    }

    var body: some View {
        let opponent = home.isUserClub ? away : home
        let dangerMan = opponent.startingXIPlayers.max { $0.overall < $1.overall }
        VStack(alignment: .leading, spacing: 10) {
            Text("Scouting Report").font(.headline)
            previewRow("Starting XI", String(format: "%.0f", home.startingXIAverageOverall), String(format: "%.0f", away.startingXIAverageOverall))
            if !fixture.isCupTie || home.leagueTier == away.leagueTier {
                previewRow("League position", position(home), position(away))
            } else {
                previewRow("Division", home.leagueTier.displayName, away.leagueTier.displayName)
            }
            previewRow("Form", form(home).joined(separator: " "), form(away).joined(separator: " "))
            if let dangerMan {
                Label("Danger man: \(dangerMan.fullName) (\(dangerMan.primaryPosition.abbreviation), \(dangerMan.overall))", systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
            if let odds = gameState.matchOdds(for: fixture) {
                oddsBar(odds)
            }
            Label(verdict, systemImage: "chart.bar.xaxis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .gfCard()
        .accessibilityElement(children: .combine)
    }

    /// Pre-match odds: a split bar with each outcome's chance and price.
    private func oddsBar(_ odds: MatchOdds) -> some View {
        let parts: [(label: String, p: Double, color: Color)] = [
            (home.name, odds.home, Color.winGreen),
            ("Draw", odds.draw, Color.secondary),
            (away.name, odds.away, Color.lossRed)
        ]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Pre-Match Odds").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.label) { part in
                        Rectangle()
                            .fill(part.color.opacity(0.8))
                            .frame(width: max(4, geo.size.width * part.p - 2))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            HStack {
                ForEach(parts, id: \.label) { part in
                    VStack(spacing: 1) {
                        Text("\(part.label) \(Int((part.p * 100).rounded()))%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                        Text(String(format: "%.2f", MatchOdds.decimal(part.p)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Odds: \(home.name) win \(Int(odds.home * 100)) percent, draw \(Int(odds.draw * 100)) percent, \(away.name) win \(Int(odds.away * 100)) percent")
    }

    private func previewRow(_ title: String, _ homeValue: String, _ awayValue: String) -> some View {
        HStack {
            Text(homeValue.isEmpty ? "–" : homeValue)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(awayValue.isEmpty ? "–" : awayValue)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(home.name) \(homeValue.isEmpty ? "none" : homeValue), \(away.name) \(awayValue.isEmpty ? "none" : awayValue)")
    }
}

public struct StatComparisonRow: View {
    public let title: String
    public let home: String
    public let away: String
    
    public var body: some View {
        HStack {
            Text(home).frame(width: 60, alignment: .leading).fontWeight(.semibold)
            Spacer()
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(away).frame(width: 60, alignment: .trailing).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

// MARK: - Player Detail Screen

public struct PlayerDetailView: View {
    @Environment(GameState.self) private var gameState
    public let playerId: UUID
    @State private var showingRenewal = false
    @State private var confirmingRelease = false
    @State private var releaseMessage: String?
    @State private var showingNegotiation = false
    @State private var profileTab: ProfileTab = .general
    @State private var detailTab: DetailTab = .stats
    @Environment(\.dismiss) private var dismiss

    enum ProfileTab: String, CaseIterable { case general = "General", attributes = "Attributes", contract = "Contract", details = "Details" }
    enum DetailTab: String, CaseIterable { case stats = "Stats", awards = "Awards", transfers = "Transfers" }
    
    public var body: some View {
        ScrollView {
            if let lookup = gameState.player(withId: playerId) {
                let player = lookup.player
                let club = lookup.club
                
                VStack(spacing: 14) {
                    GFTabs(selection: $profileTab, compact: true)
                    switch profileTab {
                    case .general: generalTab(player, club)
                    case .attributes: attributesTab(player)
                    case .contract: contractTab(player, club)
                    case .details: detailsTab(player, club)
                    }
                }
                .padding()
                .navigationTitle(player.fullName)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let lookup = gameState.player(withId: playerId) {
                actionsButton(lookup.player, lookup.club)
            }
        }
        .stadiumBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if gameState.userClub?.player(withId: playerId) == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        gameState.toggleShortlist(playerId)
                    } label: {
                        Image(systemName: gameState.isShortlisted(playerId) ? "star.fill" : "star")
                    }
                    .accessibilityLabel(gameState.isShortlisted(playerId) ? "Remove from shortlist" : "Add to shortlist")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    if case .playerDetail = gameState.currentScreen {
                        gameState.closeProfile()
                    } else {
                        dismiss()
                    }
                }
                    .accessibilityLabel("Close player profile")
            }
        }
        .sheet(isPresented: $showingRenewal) {
            ContractRenewalView(playerId: playerId)
        }
        .sheet(isPresented: $showingNegotiation) {
            NavigationStack {
                NegotiationView(onClose: { showingNegotiation = false })
            }
        }
        .confirmationDialog("Release this player?", isPresented: $confirmingRelease, titleVisibility: .visible) {
            Button("Terminate Contract", role: .destructive) {
                let message = gameState.releasePlayer(playerId: playerId)
                if gameState.userClub?.player(withId: playerId) == nil {
                    try? SaveManager.shared.autoSave(gameState: gameState)
                    dismiss()
                } else {
                    releaseMessage = message
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("He leaves as a free agent and is paid half of the wages left on his contract.")
        }
    }
}

extension PlayerDetailView {
    fileprivate func playerHeader(player: Player, club: Club?) -> some View {
        let potential = gameState.potentialEstimate(for: player)
        let tint = club.map { Color(hex: $0.primaryColor) } ?? Color.gray
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                FaceView(player: player, size: 80, style: .full)
                    .frame(width: 80, height: 96)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(player.fullName)
                        .font(.title2.weight(.heavy))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        if let club {
                            CrestView(club: club, size: 18)
                            Text(club.name).font(.subheadline.weight(.semibold))
                        } else {
                            Text("Free Agent").font(.subheadline.weight(.semibold))
                        }
                    }
                    Text("\(player.primaryPosition.displayName) • Age \(player.age) • \(player.nationality)")
                        .font(.caption)
                        .opacity(0.85)
                    if player.positions.count > 1 {
                        Text("Also: " + player.positions.dropFirst().map { $0.abbreviation }.joined(separator: ", "))
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                Spacer(minLength: 0)
                RatingBadge(rating: player.overall, size: 54)
            }
            HStack(spacing: 8) {
                headerTile("Potential", potential.lowerBound == potential.upperBound ? "\(potential.lowerBound)" : "\(potential.lowerBound)–\(potential.upperBound)")
                headerTile("Value", player.formattedValue)
                headerTile("Wage", player.formattedWage)
                headerTile("Contract", player.contract.map { "\($0.yearsRemaining) yr" } ?? "—")
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(
            ZStack {
                LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Color.black.opacity(0.28)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    fileprivate func headerTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.heavy).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2.weight(.semibold)).opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    fileprivate func seasonTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.heavy).monospacedDigit())
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Profile tabs

extension PlayerDetailView {

    private func isMine(_ club: Club?) -> Bool {
        guard let club, let user = gameState.userClub else { return false }
        return club.id == user.id
    }

    /// "FORM ......... → NEUTRAL": a caption on the left, a value on the right.
    private func statusRow(_ title: String, _ value: String, icon: String? = nil, tint: Color = .white) -> some View {
        HStack {
            Text(title.uppercased()).font(.gfLabel(14)).foregroundStyle(.secondary)
            Spacer()
            if let icon { Image(systemName: icon).accessibilityHidden(true).font(.caption.weight(.bold)).foregroundStyle(tint) }
            Text(value.uppercased()).font(.gfLabel(15)).foregroundStyle(tint == .white ? Color.white : tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    private func bigStat(_ value: String, _ title: String, tint: Color = .white) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.gfDisplay(20).monospacedDigit()).foregroundStyle(tint)
            Text(title.uppercased()).font(.gfLabel(11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: General

    @ViewBuilder
    fileprivate func generalTab(_ player: Player, _ club: Club?) -> some View {
        let stats = player.seasonStats
        // Identity card
        HStack(alignment: .top, spacing: 16) {
            FaceView(player: player, size: 72, style: .full)
                .frame(width: 104, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text("\(player.overall)")
                        .font(.gfLabel(14)).foregroundStyle(Color.gfNight)
                        .padding(.horizontal, 12).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white))
                        .offset(x: 8, y: 8)
                }
            VStack(spacing: 8) {
                Text(player.positions.map(\.abbreviation).joined(separator: " · "))
                    .font(.gfLabel(14)).foregroundStyle(Color.gfNight)
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .background(Capsule().fill(player.primaryPosition.category.accentColor))
                Text(player.nationality.uppercased()).font(.gfLabel(16))
                HStack(spacing: 6) {
                    if let club { CrestView(club: club, size: 18) }
                    Text((club?.name ?? "Free agent").uppercased()).font(.gfLabel(16)).lineLimit(1).minimumScaleFactor(0.6)
                }
                HStack {
                    bigStat("\(player.age)", "Age")
                    bigStat("\(player.height) cm", "Height")
                    bigStat(player.preferredFoot.rawValue, "Foot")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .gfCard()
        .accessibilityElement(children: .combine)

        // Season stats
        VStack(spacing: 12) {
            HStack {
                Text("SEASON STATS").font(.gfDisplay(18))
                Spacer()
                Button { profileTab = .details } label: { Text("DETAILS ›").font(.gfLabel(13)).foregroundStyle(.secondary) }
            }
            HStack {
                bigStat("\(stats.appearances)", "Matches")
                if player.primaryPosition == .GK {
                    bigStat("\(stats.cleanSheets)", "Clean sheets")
                } else {
                    bigStat("\(stats.goals)", "Goals")
                }
                bigStat(player.primaryPosition == .GK ? "\(stats.goalsConceded)" : "\(stats.assists)",
                        player.primaryPosition == .GK ? "Conceded" : "Assists")
            }
            HStack {
                bigStat(stats.appearances > 0 ? String(format: "%.2f", stats.averageRating) : "–", "Avg rating",
                        tint: stats.averageRating >= 7 ? Color.gfMint : .white)
                bigStat("\(stats.yellowCards)", "Yellows", tint: Color(hex: "F2D15C"))
                bigStat("\(stats.redCards)", "Reds", tint: Color.gfCoral)
            }
        }
        .gfCard()

        // Status
        let recent = player.form.suffix(3)
        let formAvg = recent.isEmpty ? 6.5 : recent.reduce(0, +) / Double(recent.count)
        let delta = player.matchRating - player.overall
        VStack(spacing: 11) {
            Text("PLAYER STATUS").font(.gfDisplay(18)).frame(maxWidth: .infinity, alignment: .leading)
            statusRow("Form", formAvg >= 7.2 ? "Excellent" : formAvg >= 6.7 ? "Good" : formAvg >= 6.2 ? "Neutral" : "Poor",
                      icon: formAvg >= 6.7 ? "arrow.up.right" : formAvg >= 6.2 ? "arrow.right" : "arrow.down.right",
                      tint: formAvg >= 6.7 ? Color.gfMint : formAvg >= 6.2 ? Color.gfBanner : Color.gfCoral)
            statusRow("Morale", player.morale.displayName, icon: "face.smiling")
            statusRow("Condition", "\(Int(player.matchFitness))%", icon: "circle.dotted",
                      tint: player.matchFitness >= 85 ? Color.gfMint : player.matchFitness >= 70 ? Color.gfBanner : Color.gfCoral)
            statusRow("Availability", player.isInjured ? "Injured" : player.isSuspended ? "Suspended" : "Available",
                      icon: player.isInjured || player.isSuspended ? "xmark" : "checkmark",
                      tint: player.isInjured || player.isSuspended ? Color.gfCoral : Color.gfMint)
            statusRow("In match", delta == 0 ? "\(player.matchRating)" : "\(player.matchRating) (\(delta > 0 ? "+" : "")\(delta))",
                      tint: delta > 0 ? Color.gfMint : delta < 0 ? Color.gfCoral : .white)
            Divider()
            statusRow("Market value", player.formattedValue)
            statusRow("Salary", "\(Player.formatCurrency(player.wage * 52)) /y")
            statusRow("Contract", player.contract.map { "\($0.yearsRemaining) year\($0.yearsRemaining == 1 ? "" : "s")" } ?? "None")
            if let club {
                statusRow("Squad role", gameState.squadRole(of: player, at: club).displayName)
            }
            let potential = gameState.potentialEstimate(for: player)
            statusRow("Potential", potential.lowerBound == potential.upperBound ? "\(potential.lowerBound)" : "\(potential.lowerBound)–\(potential.upperBound)")
        }
        .gfCard()
    }

    // MARK: Attributes

    private func skillBar(_ name: String, _ value: Int) -> some View {
        let color: Color = value >= 70 ? Color.gfMint : value >= 50 ? Color(hex: "B8DC7A") : value >= 30 ? Color(hex: "F2D15C") : Color.gfCoral
        return HStack(spacing: 10) {
            Text(name.uppercased()).font(.gfLabel(14)).foregroundStyle(.secondary).frame(width: 108, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(max(2, min(99, value))) / 99)
                }
            }
            .frame(height: 8)
            Text("\(value)").font(.gfLabel(15).monospacedDigit()).frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(value)")
    }

    @ViewBuilder
    fileprivate func attributesTab(_ player: Player) -> some View {
        let a = player.attributes
        VStack(alignment: .leading, spacing: 12) {
            Text("PLAYER SKILLS").font(.gfDisplay(18))
            skillBar("Defense", (a.tackling + a.marking + a.positioning) / 3)
            skillBar("Passing", (a.passing + a.vision + a.crossing) / 3)
            skillBar("Shooting", (a.shooting + a.longShots + a.penalties) / 3)
            skillBar("Dribbling", (a.dribbling + a.firstTouch + a.agility) / 3)
            skillBar("Pace", a.pace)
            skillBar("Physical", (a.strength + a.stamina + a.jumping) / 3)
            skillBar("Mental", (a.composure + a.decisions + a.workRate + a.teamwork) / 4)
            skillBar("Consistency", (a.concentration + a.decisions) / 2)
            if player.primaryPosition == .GK {
                skillBar("Goalkeeping", (a.reflexes + a.handling + a.gkPositioning + a.oneOnOnes) / 4)
            }
        }
        .gfCard()

        VStack(alignment: .leading, spacing: 12) {
            Text("ROLES LEVEL").font(.gfDisplay(18))
            Text("How well he would play in each position.").font(.caption).foregroundStyle(.secondary)
            let rows: [[Position]] = [[.LW, .ST, .RW], [.CAM], [.LM, .CM, .RM], [.CDM], [.LB, .CB, .RB], [.GK]]
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { pos in
                            let rating = player.roleRating(at: pos)
                            let natural = player.positions.contains(pos)
                            Text("\(pos.abbreviation) \(rating)")
                                .font(.gfLabel(13).monospacedDigit())
                                .foregroundStyle(natural ? Color.gfNight : Color.white.opacity(rating >= player.overall - 6 ? 0.95 : 0.55))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(natural ? Color.gfMint : Color.clear))
                                .overlay(Capsule().stroke(natural ? Color.clear : pos.category.accentColor.opacity(0.7), lineWidth: 1.5))
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("\(pos.displayName): \(rating)\(natural ? ", natural position" : "")")
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.pitchGreen.opacity(0.18)))
        }
        .gfCard()

        VStack(alignment: .leading, spacing: 10) {
            Text("ALL ATTRIBUTES").font(.gfDisplay(18))
            Group {
                skillBar("Passing", a.passing); skillBar("Shooting", a.shooting); skillBar("Dribbling", a.dribbling)
                skillBar("First touch", a.firstTouch); skillBar("Crossing", a.crossing); skillBar("Heading", a.heading)
                skillBar("Tackling", a.tackling); skillBar("Marking", a.marking)
            }
            Group {
                skillBar("Stamina", a.stamina); skillBar("Strength", a.strength); skillBar("Agility", a.agility)
                skillBar("Vision", a.vision); skillBar("Composure", a.composure); skillBar("Leadership", a.leadership)
                skillBar("Free kicks", a.freeKicks); skillBar("Penalties", a.penalties)
            }
        }
        .gfCard()

        if let log = player.careerLog, !log.isEmpty {
            CareerHistoryCard(log: log, isKeeper: player.primaryPosition == .GK)
        }
    }

    // MARK: Contract

    @ViewBuilder
    fileprivate func contractTab(_ player: Player, _ club: Club?) -> some View {
        let mine = isMine(club)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CONTRACT").font(.gfDisplay(18))
                Spacer()
                if let c = player.contract {
                    Text("\(c.yearsRemaining)Y").font(.gfLabel(13))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
            }
            if let c = player.contract {
                Text("EXPIRES").font(.gfLabel(12)).foregroundStyle(.secondary)
                let endYear = (Int(gameState.season.year.prefix(4)) ?? 2026) + max(1, c.yearsRemaining)
                Text("30TH JUNE \(String(endYear))").font(.gfDisplay(22))
                HStack(spacing: 12) {
                    GFValuePill(title: "Salary", value: "\(Player.formatCurrency(c.wage))/w")
                    GFValuePill(title: "Market value", value: player.formattedValue, tone: .good)
                }
                if let clause = c.releaseClause {
                    statusRow("Release clause", Player.formatCurrency(clause))
                }
            } else {
                Text("No contract: he is a free agent.").font(.subheadline).foregroundStyle(.secondary)
            }
            if mine && !player.isOnLoan {
                Button("Renew") { showingRenewal = true }
                    .buttonStyle(.gfSolid)
                    .accessibilityLabel("Offer \(player.fullName) a new contract")
            }
        }
        .gfCard()

        if let club {
            let share = gameState.minutesShare(of: player, at: club)
            let expected = gameState.expectedMinutesShare(of: player, at: club)
            VStack(alignment: .leading, spacing: 10) {
                Text("SQUAD ROLE").font(.gfDisplay(18))
                Text(gameState.squadRole(of: player, at: club).displayName.uppercased()).font(.gfDisplay(22))
                HStack {
                    Text("MINUTES PLAYED").font(.gfLabel(13)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(share * 100))%").font(.gfLabel(15))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(share >= expected - 0.15 ? Color.gfMint : Color.gfCoral)
                            .frame(width: max(4, geo.size.width * share))
                        Rectangle().fill(Color.white).frame(width: 2, height: 16)
                            .offset(x: geo.size.width * expected)
                    }
                }
                .frame(height: 10)
                Text("EXPECTED \(Int(expected * 100))%").font(.gfLabel(12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .gfCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Squad role: \(gameState.squadRole(of: player, at: club).displayName). Played \(Int(share * 100)) percent of minutes, expects \(Int(expected * 100)) percent.")

            if mine && !player.isOnLoan && gameState.gameMode == .manageClub {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MARKET").font(.gfDisplay(18))
                    marketToggle("Transfer list", .transferListed, player)
                    marketToggle("Loan list", .loanListed, player)
                    marketToggle("Block offers", .notForSale, player)
                    Text("Listed players attract offers; blocked players are left alone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .gfCard()
            }

            let thoughts = gameState.thoughts(of: player, at: club)
            if !thoughts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHAT HE THINKS").font(.gfDisplay(18))
                    ForEach(thoughts, id: \.self) { thought in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(thought.tone == .good ? Color.gfMint : thought.tone == .bad ? Color.gfCoral : Color.gfBanner)
                                .frame(width: 7, height: 7)
                            Text(thought.text).font(.subheadline)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .gfCard()
            }

            if gameState.gameMode == .manageClub || player.isOnLoan {
                LoanActionsCard(player: player, club: club)
            }
        }
        if let releaseMessage {
            Text(releaseMessage).font(.caption.weight(.semibold))
        }
    }

    private func marketToggle(_ title: String, _ status: TransferStatus, _ player: Player) -> some View {
        let isOn = player.transferStatus == status
        return Button {
            gameState.setTransferStatus(playerId: player.id, to: isOn ? .available : status)
        } label: {
            HStack {
                Text(title.uppercased()).font(.gfLabel(15))
                Spacer()
                Image(systemName: isOn ? "checkmark.square.fill" : "square").accessibilityHidden(true)
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.gfMint : .white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    // MARK: Details

    @ViewBuilder
    fileprivate func detailsTab(_ player: Player, _ club: Club?) -> some View {
        GFTabs(selection: $detailTab, compact: true)
        switch detailTab {
        case .stats:
            let isKeeper = player.primaryPosition == .GK
            let log = player.careerLog ?? []
            let now = player.seasonStats
            VStack(spacing: 8) {
                HStack {
                    Text("YEAR").frame(width: 62, alignment: .leading)
                    Text("TEAM").frame(maxWidth: .infinity, alignment: .leading)
                    Text("P").frame(width: 30)
                    // Keepers: clean sheets and goals conceded.
                    Text(isKeeper ? "CS" : "").frame(width: 30)
                        .overlay { if !isKeeper { Image(systemName: "soccerball").accessibilityHidden(true) } }
                    Text(isKeeper ? "GA" : "").frame(width: 30)
                        .overlay { if !isKeeper { Image(systemName: "shoe.fill").accessibilityHidden(true) } }
                    Image(systemName: "star.circle.fill").frame(width: 42)
                }
                .font(.gfLabel(13))
                .accessibilityHidden(true)
                Divider()
                ForEach(log) { line in
                    statLine(year: line.season, team: line.club, p: line.appearances,
                             a: isKeeper ? (line.cleanSheets ?? 0) : line.goals,
                             b: isKeeper ? (line.goalsConceded ?? 0) : line.assists,
                             rating: line.averageRating, bold: false, isKeeper: isKeeper)
                }
                statLine(year: gameState.season.year, team: club?.name ?? "–", p: now.appearances,
                         a: isKeeper ? now.cleanSheets : now.goals, b: isKeeper ? now.goalsConceded : now.assists,
                         rating: now.averageRating, bold: false, isKeeper: isKeeper)
                Divider()
                let totalP = log.reduce(0) { $0 + $1.appearances } + now.appearances
                statLine(year: "", team: "TOTAL", p: totalP,
                         a: log.reduce(0) { $0 + (isKeeper ? ($1.cleanSheets ?? 0) : $1.goals) } + (isKeeper ? now.cleanSheets : now.goals),
                         b: log.reduce(0) { $0 + (isKeeper ? ($1.goalsConceded ?? 0) : $1.assists) } + (isKeeper ? now.goalsConceded : now.assists),
                         rating: 0, bold: true, isKeeper: isKeeper)
            }
            .gfCard()
        case .awards:
            let awards = gameState.history.awards.filter { $0.playerId == player.id }
            if awards.isEmpty {
                Label("NO AWARDS YET", systemImage: "xmark.circle.fill").font(.gfLabel(16)).padding(.top, 60)
            }
            ForEach(awards) { award in
                VStack(alignment: .leading, spacing: 3) {
                    Text(award.award.uppercased()).font(.gfLabel(16)).foregroundStyle(Color.goldAccent)
                    Text("\(award.season) · \(award.clubName)").font(.subheadline.weight(.semibold))
                    Text(award.detail).font(.caption).foregroundStyle(.secondary)
                }
                .gfCard()
                .accessibilityElement(children: .combine)
            }
        case .transfers:
            let moves = gameState.transferHistory.filter { $0.playerId == player.id }.reversed()
            if moves.isEmpty {
                Label("NO TRANSFERS YET", systemImage: "xmark.circle.fill").font(.gfLabel(16)).padding(.top, 60)
            }
            ForEach(Array(moves)) { move in
                VStack(spacing: 6) {
                    HStack {
                        Text(move.fromClubName.uppercased()).font(.gfLabel(14)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").accessibilityHidden(true).font(.caption.weight(.bold))
                        Text(move.toClubName.uppercased()).font(.gfLabel(14)).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Text(move.isLoan ? "LOAN" : move.fee == 0 ? "FREE" : Player.formatCurrency(move.fee)).font(.gfDisplay(20))
                    Text(DashboardView.longDate(move.date)).font(.caption).foregroundStyle(.secondary)
                }
                .gfCard()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(move.fromClubName) to \(move.toClubName), \(move.isLoan ? "loan" : move.fee == 0 ? "free" : Player.spokenCurrency(move.fee)), \(DashboardView.longDate(move.date))")
            }
        }
    }

    private func statLine(year: String, team: String, p: Int, a: Int, b: Int, rating: Double, bold: Bool, isKeeper: Bool = false) -> some View {
        HStack {
            Text(year).frame(width: 62, alignment: .leading)
            Text(team).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Text("\(p)").frame(width: 30)
            Text("\(a)").frame(width: 30)
            Text("\(b)").frame(width: 30)
            Text(rating > 0 ? String(format: "%.2f", rating) : "–").frame(width: 42)
                .foregroundStyle(rating >= 7 ? Color.gfMint : .white)
        }
        .font(bold ? .gfLabel(15).monospacedDigit() : .subheadline.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(year) \(team): \(p) played, \(a) \(isKeeper ? "clean sheets" : "goals"), \(b) \(isKeeper ? "goals conceded" : "assists"), rating \(rating > 0 ? String(format: "%.2f", rating) : "none")")
    }

    // MARK: Actions

    @ViewBuilder
    fileprivate func actionsButton(_ player: Player, _ club: Club?) -> some View {
        let mine = isMine(club)
        Menu {
            if !mine && !player.isOnLoan, gameState.userClub != nil {
                Button {
                    gameState.negotiationTargetPlayerId = player.id
                    showingNegotiation = true
                } label: { Label(club == nil ? "Offer contract" : "Make transfer bid", systemImage: "arrow.left.arrow.right") }
                Button { gameState.toggleShortlist(player.id) } label: {
                    Label(gameState.isShortlisted(player.id) ? "Remove from shortlist" : "Add to shortlist", systemImage: "star")
                }
            }
            if mine && !player.isOnLoan {
                Button { showingRenewal = true } label: { Label("Renew contract", systemImage: "square.and.pencil") }
                if gameState.gameMode == .manageClub {
                    Button { gameState.setTransferStatus(playerId: player.id, to: player.transferStatus == .transferListed ? .available : .transferListed) } label: {
                        Label(player.transferStatus == .transferListed ? "Remove from transfer list" : "Transfer list", systemImage: "tag")
                    }
                    Button(role: .destructive) { confirmingRelease = true } label: {
                        Label("Release (\(Player.formatCurrency(gameState.releaseCost(for: player))) settlement)", systemImage: "person.badge.minus")
                    }
                }
            }
            Button { profileTab = .contract } label: { Label("Contract and loans", systemImage: "doc.text") }
        } label: {
            Text("ACTIONS")
                .font(.gfLabel(17))
                .padding(.horizontal, 44).padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color(hex: "E4573D")))
                .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 2))
        }
        .padding(.vertical, 8)
        .accessibilityLabel("Actions for \(player.fullName)")
    }
}

// MARK: - Loans

/// Loan status and actions for a player: loan out, recall, borrow or send back.
private struct LoanActionsCard: View {
    @Environment(GameState.self) private var gameState
    let player: Player
    let club: Club
    @State private var showingDestinations = false
    @State private var wageShare = 100
    @State private var terms: LoanTerms = .plain
    @State private var outcome: String?

    private var isUsersClub: Bool { club.isUserClub }
    private var managing: Bool { gameState.gameMode == .manageClub }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Loans", systemImage: "arrow.triangle.swap").font(.headline)
            if let loan = player.loan {
                Text(isUsersClub
                     ? "On loan from \(loan.parentClubName). You cover \(loan.wageSharePercent)% of his wages."
                     : "On loan at \(club.name) from \(loan.parentClubName) until the end of the season.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(player.seasonStatSummary) this season")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let option = loan.buyOptionFee {
                    Label("Option to buy: \(Player.formatCurrency(option))", systemImage: "signature")
                        .font(.caption.weight(.semibold))
                }
                if let obligation = loan.obligationFee {
                    Label("Obligation to buy: \(Player.formatCurrency(obligation)) when the loan ends", systemImage: "signature")
                        .font(.caption.weight(.semibold))
                }
                if managing && isUsersClub, let fee = loan.buyOptionFee ?? loan.obligationFee {
                    actionButton("Sign Permanently for \(Player.formatCurrency(fee))", icon: "checkmark.seal") {
                        outcome = gameState.exerciseLoanOption(playerId: player.id)
                    }
                }
                if managing && isUsersClub {
                    actionButton("Send Back to \(loan.parentClubName)", icon: "arrow.uturn.backward") {
                        outcome = gameState.endLoanEarly(playerId: player.id)
                            ? "\(player.fullName) has returned to \(loan.parentClubName)."
                            : "Loans can only be ended while a transfer window is open, and you need at least 17 players."
                    }
                } else if managing && loan.parentClubId == gameState.userClubId {
                    actionButton("Recall \(player.lastName)", icon: "arrow.uturn.backward") {
                        outcome = gameState.recallLoanedPlayer(playerId: player.id)
                            ? "\(player.fullName) is back in your squad."
                            : "Players can only be recalled while a transfer window is open."
                    }
                }
            } else if isUsersClub {
                Text(gameState.isTransferWindowOpen
                     ? "Send him somewhere he will play every week. Young players who play regularly develop faster."
                     : "Loans can be arranged when the transfer window opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if gameState.isTransferWindowOpen {
                    actionButton("Find a Loan Club", icon: "magnifyingglass") { showingDestinations = true }
                }
            } else if gameState.isLoanable(player, at: club) {
                Text("\(club.name) would consider lending him out. Fee: \(gameState.loanFee(for: player) == 0 ? "none" : Player.formatCurrency(gameState.loanFee(for: player))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Wage share", selection: $wageShare) {
                    Text("50%").tag(50)
                    Text("75%").tag(75)
                    Text("100%").tag(100)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Share of his wages you will pay")
                Picker("Purchase clause", selection: $terms) {
                    ForEach(LoanTerms.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if let fee = gameState.loanPurchaseFee(for: player, terms: terms) {
                    Text(terms == .option ? "You may sign him for \(Player.formatCurrency(fee)) during the loan." : "You must sign him for \(Player.formatCurrency(fee)) when the loan ends.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                actionButton("Request Season Loan", icon: "hand.raised") {
                    switch gameState.requestLoan(playerId: player.id, wageShare: wageShare, terms: terms) {
                    case .agreed(let share, let fee):
                        outcome = "Deal done: \(player.fullName) joins on loan (\(share)% wages\(fee > 0 ? ", \(Player.formatCurrency(fee)) fee" : "")."
                    case .refused(let reason):
                        outcome = reason
                    }
                }
            } else {
                Text("\(club.name) consider him a first-team player and will not lend him out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let outcome {
                Text(outcome)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .gfCard()
        .confirmationDialog("Loan \(player.fullName) to…", isPresented: $showingDestinations, titleVisibility: .visible) {
            let destinations = gameState.loanDestinations(forPlayerId: player.id)
            ForEach(destinations) { destination in
                Button("\(destination.name) (\(destination.leagueTier.displayName))") {
                    outcome = gameState.loanOutPlayer(playerId: player.id, to: destination.id)
                        ? "\(player.fullName) has joined \(destination.name) on loan."
                        : "The loan could not be completed."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if gameState.loanDestinations(forPlayerId: player.id).isEmpty {
                Text("No club can currently offer him regular football and afford his wages.")
            } else {
                Text("Clubs where he would start and who can cover at least part of his wages.")
            }
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Contract Renewal

public struct ContractRenewalView: View {
    @Environment(GameState.self) private var gameState
    @Environment(\.dismiss) private var dismiss

    public let playerId: UUID

    @State private var wage: Double = 1_000
    @State private var years = 3
    @State private var signingBonus: Double = 0
    @State private var outcomeMessage: String?
    @State private var showOutcome = false
    @State private var acceptedOffer = false
    /// His latest answer, when he countered.
    @State private var lastAnswer: ContractRenewalResult?

    private var lookup: (player: Player, club: Club?)? {
        gameState.player(withId: playerId)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let lookup = lookup {
                    form(for: lookup.player)
                } else {
                    ContentUnavailableView("Player Not Found", systemImage: "person.slash")
                }
            }
            .navigationTitle("Renew Contract")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: primeFields)
            .alert("Contract Offer", isPresented: $showOutcome) {
                Button("OK") {
                    showOutcome = false
                    if acceptedOffer { dismiss() }
                }
            } message: {
                Text(outcomeMessage ?? "")
            }
        }
    }

    private func form(for player: Player) -> some View {
        Form {
            Section(header: Text("Current Contract")) {
                row("Weekly Wage", Player.formatCurrency(player.contract?.wage ?? 0))
                row("Years Remaining", "\(player.contract?.yearsRemaining ?? 0)")
                row("Expected Wage", "\(Player.formatCurrency(gameState.contractRenewalWage(for: player)))/w")
            }

            Section(header: Text("New Terms")) {
                VStack(alignment: .leading) {
                    Text("Weekly Wage: \(Player.formatCurrency(Int(wage)))/w")
                    Slider(value: $wage, in: 500...wageUpperBound(for: player), step: 500)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("New weekly wage")
                .accessibilityValue("\(Player.formatCurrency(Int(wage))) per week")

                Stepper("Contract Length: \(years) \(years == 1 ? "year" : "years")", value: $years, in: 1...5)

                VStack(alignment: .leading) {
                    Text("Signing-on Bonus: \(signingBonus == 0 ? "None" : Player.formatCurrency(Int(signingBonus)))")
                    Slider(value: $signingBonus, in: 0...max(50_000, wageUpperBound(for: player) * 26), step: 10_000)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Signing-on bonus")
                .accessibilityValue(signingBonus == 0 ? "None" : Player.formatCurrency(Int(signingBonus)))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: signingBonus = min(max(50_000, wageUpperBound(for: player) * 26), signingBonus + 10_000)
                    case .decrement: signingBonus = max(0, signingBonus - 10_000)
                    @unknown default: break
                    }
                }
                Text("He may take less than his expected wage if he is happy, not a regular, or a veteran offered security. A bonus, paid now, also lets you offer a lower wage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let answer = lastAnswer, !answer.accepted {
                Section(header: Text("His Response")) {
                    Text(answer.message)
                    if let counter = answer.demandedWage {
                        Button("Accept \(Player.formatCurrency(counter))/w") {
                            wage = Double(counter)
                            submit()
                        }
                        .accessibilityLabel("Accept his counter of \(Player.formatCurrency(counter)) a week")
                    }
                }
            }

            if let userClub = gameState.userClub {
                Section(header: Text("Budget Check")) {
                    row("Wage Headroom", "\(Player.formatCurrency(userClub.finances.weeklyWageSurplus))/w")
                }
            }

            Section {
                Button(action: submit) {
                    Text("Offer Contract")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Offer \(player.fullName) a new contract")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private func wageUpperBound(for player: Player) -> Double {
        let demand = Double(gameState.contractRenewalWage(for: player))
        let currentBased = max(Double(player.wage) * 4, 80_000)
        return max(demand * 1.25, currentBased)
    }

    private func primeFields() {
        guard let player = lookup?.player else { return }
        wage = Double(gameState.contractRenewalWage(for: player))
        let currentYears = player.contract?.yearsRemaining ?? 1
        years = min(5, max(2, currentYears + 1))
    }

    private func submit() {
        guard let player = lookup?.player else { return }
        let result = gameState.renewContract(playerId: player.id, wage: Int(wage), years: years,
                                             signingBonus: Int(signingBonus))
        acceptedOffer = result.accepted
        lastAnswer = result
        if result.accepted {
            outcomeMessage = result.message
            showOutcome = true
            try? SaveManager.shared.autoSave(gameState: gameState)
        } else {
            // He countered: his answer and an Accept button appear in the form.
            AccessibilityNotification.Announcement(result.message).post()
        }
    }
}

public struct AttributeBarView: View {
    public let name: String
    public let value: Int
    
    public var body: some View {
        HStack {
            Text(name)
                .font(.caption)
                .frame(width: 90, alignment: .leading)
            
            ProgressView(value: Double(value), total: 99.0)
                .tint(colorForStat(value))
            
            Text("\(value)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibleStatBar(statName: name, value: value)
    }
    
    private func colorForStat(_ stat: Int) -> Color {
        switch stat {
        case 80...99: return .green
        case 65...79: return .blue
        case 50...64: return .orange
        default: return .red
        }
    }
}

// MARK: - Settings & Saves Screen

public struct SettingsView: View {
    @Environment(GameState.self) private var gameState
    @State private var alertMessage: String?
    @State private var showAlert = false
    /// Slot headers are read once on appear and after each save/delete. Reading
    /// them inside `body` re-parsed every multi-megabyte save on every redraw.
    @State private var slotMetadata: [SaveSlot: SaveSlotMetadata] = [:]
    @State private var slotPendingLoad: SaveSlot?
    @State private var slotPendingDelete: SaveSlot?
    @State private var storageUsed = 0
    @State private var backupSize = 0
    @AppStorage("gfStadiumTheme") private var stadiumTheme = true
    @AppStorage("gfShowMatchRating") private var showMatchRating = false
    @AppStorage(CrowdAtmosphere.enabledKey) private var crowdSound = true
    @AppStorage(CrowdAtmosphere.volumeKey) private var crowdVolume = 0.8
    @AppStorage(Haptics.enabledKey) private var haptics = true

    private func refreshStorage() {
        storageUsed = SaveManager.shared.storageUsed()
        backupSize = SaveManager.shared.quarantinedBackupSize()
    }

    private func refreshSlotMetadata() {
        var result: [SaveSlot: SaveSlotMetadata] = [:]
        for slot in SaveSlot.allCases {
            if let meta = SaveManager.shared.getMetadata(for: slot) {
                result[slot] = meta
            }
        }
        slotMetadata = result
    }

    private func load(_ slot: SaveSlot) {
        do {
            let loaded = try SaveManager.shared.load(from: slot)
            gameState.loadCareer(from: loaded)
            // Make the loaded career the one that "Continue" resumes next launch.
            if gameState.hasStartedCareer {
                try? SaveManager.shared.autoSave(gameState: gameState)
            }
        } catch {
            alertMessage = "Could not load \(slot.displayName): \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    public var body: some View {
        List {
            Section(header: Text("Preferences")) {
                Toggle(isOn: Binding(
                    get: { gameState.soundEnabled },
                    set: { gameState.soundEnabled = $0 }
                )) {
                    Label("Sound Effects", systemImage: "speaker.wave.2.fill")
                }
                .accessibilityHint("Plays sound and haptic feedback for goals, wins and losses")
                Toggle(isOn: $stadiumTheme) {
                    Label("Stadium Theme", systemImage: "sparkles.tv")
                }
                .accessibilityHint("A dark floodlit-stadium look. Turn off to follow the system appearance")
            }

            Section(header: Text("Crowd and Haptics"), footer: Text("Real stadium recordings: the home crowd roars, groans, boos and sings as the match unfolds.")) {
                Toggle(isOn: $crowdSound) {
                    Label("Crowd Sound", systemImage: "person.3.sequence.fill")
                }
                .accessibilityHint("Plays a live stadium crowd during matches")
                if crowdSound {
                    Slider(value: $crowdVolume, in: 0.1...1, step: 0.1) {
                        Text("Crowd Volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
                    }
                    .accessibilityLabel("Crowd volume")
                    .accessibilityValue("\(Int(crowdVolume * 100)) percent")
                }
                Toggle(isOn: $haptics) {
                    Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                }
                .accessibilityHint("Vibrations for goals, cards, saves and the woodwork during matches")
            }

            Section(header: Text("Lineups"),
                    footer: Text("The match rating is the base rating adjusted for match fitness, sharpness, recent form and morale: how well the player is likely to play next. Green means above his base rating, red below.")) {
                Toggle(isOn: $showMatchRating) {
                    Label("Show Match Rating", systemImage: "gauge.with.dots.needle.67percent")
                }
                .accessibilityHint("Lineup cards show the match rating instead of the base rating")
            }
            
            Section(header: Text("Match Playback")) {
                Picker("Replay Speed", selection: Binding(
                    get: { gameState.matchSettings.speed },
                    set: { gameState.matchSettings.speed = $0 }
                )) {
                    ForEach(MatchSettings.Speed.allCases) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
                .accessibilityHint("Sets how fast the live match replay runs")
                
                Toggle(isOn: Binding(
                    get: { gameState.matchSettings.stopAtHalfTime },
                    set: { gameState.matchSettings.stopAtHalfTime = $0 }
                )) {
                    Label("Stop at Half-Time", systemImage: "pause.circle")
                }
                .accessibilityHint("Pauses the replay at half-time so you can make substitutions")

                Toggle(isOn: Binding(
                    get: { gameState.matchSettings.stopForInjuries },
                    set: { gameState.matchSettings.stopForInjuries = $0 }
                )) {
                    Label("Stop When a Player Is Hurt", systemImage: "cross.case")
                }
                .accessibilityHint("A live match stops when one of your players cannot carry on, so you choose his replacement")
            }

            Section(header: Text("Assistant Manager")) {
                Picker("Auto-Substitutions", selection: Binding(
                    get: { gameState.matchSettings.autoSubTiming },
                    set: { gameState.matchSettings.autoSubTiming = $0 }
                )) {
                    ForEach(MatchSettings.AutoSubTiming.allCases) { timing in
                        Text(timing.displayName).tag(timing)
                    }
                }
                .accessibilityHint("Controls when the assistant manager makes automatic substitutions")
                
                Picker("Rotation Aggression", selection: Binding(
                    get: { gameState.matchSettings.autoSubAggression },
                    set: { gameState.matchSettings.autoSubAggression = $0 }
                )) {
                    ForEach(MatchSettings.AutoSubAggression.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .accessibilityHint("How readily tired players are rotated off")

                Toggle("Assistant rests tired starters", isOn: Binding(
                    get: { gameState.matchSettings.assistantRotatesTiredPlayers },
                    set: { gameState.matchSettings.assistantRotatesTiredPlayers = $0 }
                ))
                .accessibilityHint("Before each match, starters short of fitness are replaced by fresh squad players of similar quality")

                Toggle("Animated calendar", isOn: Binding(
                    get: { gameState.matchSettings.animateCalendar },
                    set: { gameState.matchSettings.animateCalendar = $0 }
                ))
                .accessibilityHint("Continue shows the days passing with results and news, instead of jumping straight to match day")

                Toggle("Pause calendar for new mail", isOn: Binding(
                    get: { gameState.matchSettings.pauseCalendarForMail },
                    set: { gameState.matchSettings.pauseCalendarForMail = $0 }
                ))
                .disabled(!gameState.matchSettings.animateCalendar)
                .accessibilityHint("The calendar stops to show bids, board messages, contracts and injuries as they arrive")
            }
            
            Section(
                header: Text("Save Slots"),
                footer: Text("Loading replaces the career in progress. Save it to a slot first if you want to keep it.")
            ) {
                ForEach(SaveSlot.allCases) { slot in
                    let metadata = slotMetadata[slot]
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(slot.displayName)
                                .font(.headline)
                            if let meta = metadata {
                                Text("\(meta.clubName) • Season \(meta.seasonYear)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Saved: \(meta.formattedRealDate)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("Empty Slot")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()

                        if metadata != nil {
                            Button("Load") { slotPendingLoad = slot }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Load \(slot.displayName)")
                        }
                        
                        if slot != .autoSave {
                            Button("Save") {
                                guard gameState.hasStartedCareer else {
                                    alertMessage = "Start or continue a career before saving."
                                    showAlert = true
                                    return
                                }
                                do {
                                    try SaveManager.shared.save(gameState: gameState, to: slot)
                                    refreshSlotMetadata(); refreshStorage()
                                    alertMessage = "Career saved to \(slot.displayName)."
                                    showAlert = true
                                } catch {
                                    alertMessage = "Save failed: \(error.localizedDescription)"
                                    showAlert = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Save to \(slot.displayName)")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if metadata != nil && slot != .autoSave {
                            Button("Delete", role: .destructive) { slotPendingDelete = slot }
                        }
                    }
                }
            }
            
            Section(header: Text("Storage"), footer: Text("Saves are compressed. Older saves shrink the next time they are saved.")) {
                LabeledContent("Saves on this device", value: ByteCountFormatter.string(fromByteCount: Int64(storageUsed), countStyle: .file))
                if backupSize > 0 {
                    Button(role: .destructive) {
                        SaveManager.shared.deleteQuarantinedBackups()
                        refreshStorage()
                    } label: {
                        Text("Delete unreadable save backups (\(ByteCountFormatter.string(fromByteCount: Int64(backupSize), countStyle: .file)))")
                    }
                }
            }

            Section {
                Button(role: .destructive, action: {
                    gameState.currentScreen = .mainMenu
                }) {
                    Text("Exit to Main Menu")
                }
            }
        }
        .navigationTitle("Settings & Saves")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshSlotMetadata()
            refreshStorage()
        }
        .confirmationDialog(
            "Load This Save?",
            isPresented: Binding(
                get: { slotPendingLoad != nil },
                set: { if !$0 { slotPendingLoad = nil } }
            ),
            titleVisibility: .visible,
            presenting: slotPendingLoad
        ) { slot in
            Button("Load \(slot.displayName)", role: .destructive) {
                slotPendingLoad = nil
                load(slot)
            }
            Button("Cancel", role: .cancel) { slotPendingLoad = nil }
        } message: { _ in
            Text("Any unsaved progress in the current career will be lost.")
        }
        .confirmationDialog(
            "Delete This Save?",
            isPresented: Binding(
                get: { slotPendingDelete != nil },
                set: { if !$0 { slotPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: slotPendingDelete
        ) { slot in
            Button("Delete \(slot.displayName)", role: .destructive) {
                slotPendingDelete = nil
                do {
                    try SaveManager.shared.deleteSave(for: slot)
                    refreshSlotMetadata()
                    refreshStorage()
                } catch {
                    alertMessage = "Could not delete \(slot.displayName). \(error.localizedDescription)"
                    showAlert = true
                }
            }
            Button("Cancel", role: .cancel) { slotPendingDelete = nil }
        } message: { _ in
            Text("This cannot be undone.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    if gameState.userClub != nil {
                        gameState.currentScreen = .dashboard
                    } else {
                        gameState.currentScreen = .mainMenu
                    }
                }
                .accessibilityLabel("Close settings")
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Save Manager"), message: Text(alertMessage ?? ""), dismissButton: .default(Text("OK")))
        }
    }
}

// MARK: - Club Finances Screen

public struct FinancesView: View {
    @Environment(GameState.self) private var gameState

    public var body: some View {
        List {
            if let club = gameState.userClub {
                let f = club.finances

                if let flow = gameState.weeklyCashFlow {
                    Section(header: Text("This Week's Money"), footer: Text(flow.advice)) {
                        row("Income", Player.formatCurrency(flow.income) + "/w", spoken: Player.spokenCurrency(flow.income) + " per week")
                        row("Costs", Player.formatCurrency(flow.costs) + "/w", spoken: Player.spokenCurrency(flow.costs) + " per week")
                        row("Net", (flow.net >= 0 ? "+" : "−") + Player.formatCurrency(abs(flow.net)) + "/w",
                            spoken: (flow.net >= 0 ? "profit of " : "loss of ") + Player.spokenCurrency(abs(flow.net)) + " per week")
                        row("Forecast season-end balance", Player.formatCurrency(flow.projectedBalance), spoken: Player.spokenCurrency(flow.projectedBalance))
                    }
                }

                Section(header: Text("Bank")) {
                    row("Balance", Player.formatCurrency(f.balance), spoken: Player.spokenCurrency(f.balance))
                    row("Transfer Budget", Player.formatCurrency(f.transferBudget), spoken: Player.spokenCurrency(f.transferBudget))
                    row("Recommended Wage Budget", Player.formatCurrency(f.wageBudget) + "/w", spoken: Player.spokenCurrency(f.wageBudget) + " per week")
                    row("Current Wage Bill", Player.formatCurrency(f.currentWageBill) + "/w", spoken: Player.spokenCurrency(f.currentWageBill) + " per week")
                    row("Wage Headroom", Player.formatCurrency(f.weeklyWageSurplus) + "/w", spoken: Player.spokenCurrency(f.weeklyWageSurplus) + " per week")
                }

                Section(header: Text("Annual Income")) {
                    row("TV & Broadcast", Player.formatCurrency(f.tvIncome))
                    row("Commercial & Sponsorship", Player.formatCurrency(f.sponsorshipIncome))
                    row("Matchday (est.)", Player.formatCurrency(f.matchdayIncome * 19))
                    row("Merchandise", Player.formatCurrency(f.merchandiseIncome))
                }

                Section(header: Text("Matchday Economics")) {
                    row("Stadium Capacity", "\(club.stadiumCapacity.formatted())")
                    row("Average Ticket Price", Player.formatCurrency(f.averageTicketPrice))
                    row("Typical Attendance", "\(Int(Double(club.stadiumCapacity) * f.averageAttendancePct).formatted()) (\(Int(f.averageAttendancePct * 100))%)")
                    Text("Gate receipts and hospitality are banked after each home match, scaled by the calibre of the visiting side.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("Squad & Facilities")) {
                    row("Squad Size", "\(club.players.count)")
                    row("Academy Level", "\(club.youthAcademyLevel) / 5")
                    row("Training Ground", "\(club.trainingFacilityLevel) / 5")
                }
            } else {
                Text("Take charge of a club to view its finances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Finances")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { gameState.currentScreen = .dashboard }
                    .accessibilityLabel("Close finances")
            }
        }
    }

    private func row(_ label: String, _ value: String, spoken: String? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).fontWeight(.bold)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(spoken ?? value)")
    }
}

// MARK: - Negotiation View

public struct NegotiationView: View {
    @Environment(GameState.self) private var gameState
    /// Set when shown as a sheet over a player's profile; otherwise the
    /// negotiation is a full screen and closing returns to the dashboard.
    var onClose: (() -> Void)? = nil

    private func close() {
        gameState.negotiationTargetPlayerId = nil
        if let onClose { onClose() } else { gameState.currentScreen = .dashboard }
    }

    // The fee, with the selling club.
    @State private var bidFee: Double = 0
    @State private var installments = 1
    @State private var sellOnPercent = 0
    @State private var addOn: Double = 0
    // Personal terms, with the player.
    @State private var wage: Double = 1_000
    @State private var contractYears = 3
    @State private var signingBonus: Double = 0

    /// The other side's latest answer.
    @State private var reply: NegotiationReply?
    @State private var outcomeMessage: String?
    @State private var showOutcome = false

    private var target: (player: Player, club: Club?)? {
        guard let id = gameState.negotiationTargetPlayerId else { return nil }
        return gameState.player(withId: id)
    }

    /// The most recent live talks for the current target.
    private var liveOffer: TransferOffer? {
        guard let id = gameState.negotiationTargetPlayerId else { return nil }
        return gameState.pendingTransferOffers.first { $0.playerId == id && $0.isLive && !$0.isIncoming && !$0.isLoan }
    }

    /// Personal terms are on the table: the fee is agreed, or he is a free agent.
    private func onTerms(club: Club?) -> Bool {
        club == nil || liveOffer?.status == .personalTerms
    }

    public var body: some View {
        Group {
            if let lookup = target {
                form(for: lookup.player, club: lookup.club)
            } else {
                ContentUnavailableView("No Negotiation in Progress", systemImage: "arrow.left.arrow.right")
            }
        }
        .navigationTitle("Negotiate")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Transfer Update", isPresented: $showOutcome) {
            Button("OK") { close() }
        } message: {
            Text(outcomeMessage ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { close() }
                .accessibilityLabel("Cancel negotiation")
            }
        }
        .onAppear(perform: primeFields)
    }

    @State private var negotiationPage = 0

    private func form(for player: Player, club: Club?) -> some View {
        TabView(selection: $negotiationPage) {
            introPage(player: player, club: club).tag(0)
            offerPage(player: player, club: club).tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        .stadiumBackground()
    }

    /// Page one: who you're dealing with.
    private func introPage(player: Player, club: Club?) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(player.fullName.uppercased()).font(.gfDisplay(20)).multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    if let club { CrestView(club: club, size: 18) }
                    Text(club?.name ?? "Free agent").font(.headline)
                }
                FaceView(player: player, size: 110, style: .full)
                    .frame(width: 170, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text(liveOffer == nil ? "TRANSFER OFFER" : "NEGOTIATION IN PROGRESS").font(.gfDisplay(20))
                negotiationChips(player)
                HStack(spacing: 14) {
                    GFValuePill(title: "Market value", value: Player.formatCurrency(player.value))
                    GFValuePill(title: "Salary", value: "\(Player.formatCurrency(player.wage))/w")
                }
                .gfCard(padding: 14)
                Text(club == nil
                     ? "A free agent: agree personal terms with the player."
                     : "Two steps: agree the fee with \(club?.name ?? "the club"), then agree personal terms with the player. Both answer straight away.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Start") { withAnimation { negotiationPage = 1 } }
                    .buttonStyle(.gfOutline)
                    .padding(.horizontal, 70)
                    .padding(.top, 6)
            }
            .padding()
            .padding(.bottom, 30)
        }
    }

    private func negotiationChips(_ player: Player) -> some View {
        HStack(spacing: 18) {
            Text("\(player.overall)")
                .font(.gfLabel(14))
                .foregroundStyle(Color.gfNight)
                .padding(.horizontal, 12).padding(.vertical, 3)
                .background(Capsule().fill(Color.white))
            Text("\(player.age) YEARS").font(.gfLabel(17))
            Text(player.primaryPosition.abbreviation)
                .font(.gfLabel(14))
                .foregroundStyle(Color.gfNight)
                .padding(.horizontal, 12).padding(.vertical, 3)
                .background(Capsule().fill(player.primaryPosition.category.accentColor))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(player.overall), \(player.age) years old, \(player.primaryPosition.displayName)")
    }

    /// What the other side is saying right now.
    private func theirMessage(player: Player, club: Club?) -> String {
        if let reply { return reply.message }
        if let offer = liveOffer {
            switch offer.status {
            case .counterOffer:
                return "\(club?.name ?? "The club") would accept \(Player.formatCurrency(offer.counterFee ?? offer.askingPrice)). Your last offer was \(Player.formatCurrency(offer.fee))."
            case .personalTerms:
                if let demand = offer.demandedWage {
                    return "\(player.lastName)'s agent wants \(Player.formatCurrency(demand)) a week."
                }
                return club == nil
                    ? "My client is a free agent. Make him a fair offer and he will listen."
                    : "The fee is agreed with \(club?.name ?? "the club"). Now offer \(player.lastName) a contract."
            default:
                break
            }
        }
        if club == nil {
            return "My client is a free agent. Make him a fair offer and he will listen."
        }
        if let club, let user = gameState.userClub, gameState.rivalry(between: club.id, and: user.id) != nil {
            return "We will never sell to you. Not at any price."
        }
        return "\(player.lastName) is valued at \(Player.formatCurrency(player.value)). What are you offering?"
    }

    /// Page two: the haggling.
    private func offerPage(player: Player, club: Club?) -> some View {
        let terms = onTerms(club: club)
        return ScrollView {
            VStack(spacing: 14) {
                Text(player.fullName.uppercased())
                    .font(.gfDisplay(18))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.gfNavy))
                    .overlay(Capsule().stroke(Color.white, lineWidth: 2))
                Text(club?.name ?? "Free agent").font(.subheadline)
                negotiationChips(player)

                Text(terms ? "STEP 2 · PERSONAL TERMS" : "STEP 1 · TRANSFER FEE").font(.gfLabel(15))
                Text(theirMessage(player: player, club: club))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.gfSurface))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.gfStroke))
                    .accessibilityAddTraits(.updatesFrequently)

                if terms {
                    termsCard(player: player)
                } else {
                    feeCard(player: player)
                }

                if club != nil && liveOffer == nil && !gameState.isTransferWindowOpen {
                    Text("\(gameState.transferWindowStatus). Players under contract can only be signed in a window; free agents any time.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                // Accept their counter as it stands.
                if let counter = reply?.counter, reply?.kind == .countered || reply?.kind == .rejected {
                    Button(terms ? "Accept \(Player.formatCurrency(counter))/w" : "Accept \(Player.formatCurrency(counter))") {
                        if terms { wage = Double(counter) } else { bidFee = Double(counter) }
                        submit(player: player, club: club)
                    }
                    .buttonStyle(.gfSolid)
                    .padding(.horizontal, 40)
                }

                Button(terms ? "Offer Contract" : "Make Offer") { submit(player: player, club: club) }
                    .buttonStyle(.gfPrimary)
                    .padding(.horizontal, 40)
                    .disabled((club != nil && !gameState.isTransferWindowOpen && liveOffer == nil) || isRivalSeller(club))

                if liveOffer != nil {
                    Button("Walk Away") {
                        gameState.abandonTalks(playerId: player.id)
                        close()
                    }
                    .buttonStyle(.gfDanger)
                    .padding(.horizontal, 60)
                }
            }
            .padding()
            .padding(.bottom, 30)
        }
    }

    /// Step one: the fee and how it is paid.
    private func feeCard(player: Player) -> some View {
        let fee = Int(bidFee)
        let upfront = installments == 1 ? fee : fee - (fee / installments) * (installments - 1)
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                GFValuePill(title: "Market value", value: Player.formatCurrency(player.value))
                GFValuePill(title: "Budget", value: Player.formatCurrency(gameState.userClub?.finances.transferBudget ?? 0), tone: .good)
            }
            Text("FEE").font(.gfLabel(14))
            valueStepper(value: $bidFee, step: feeStep(player), range: 0...feeUpperBound(for: player), label: "Transfer fee") {
                Player.formatCurrency(Int($0))
            }
            Text("PAID IN").font(.gfLabel(14))
            valueStepper(value: Binding(get: { Double(installments) }, set: { installments = Int($0) }),
                         step: 1, range: 1...4, label: "Installments") {
                Int($0) == 1 ? "ONE PAYMENT" : "\(Int($0)) YEARLY PAYMENTS"
            }
            if installments > 1 {
                Text("\(Player.formatCurrency(upfront)) now, then \(Player.formatCurrency(fee / installments)) a year. Clubs value money later a little less.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text("SELL-ON CLAUSE").font(.gfLabel(14))
            valueStepper(value: Binding(get: { Double(sellOnPercent) }, set: { sellOnPercent = Int($0) }),
                         step: 5, range: 0...40, label: "Sell-on clause") {
                Int($0) == 0 ? "NONE" : "\(Int($0))% OF NEXT SALE"
            }
            Text("ADD-ON").font(.gfLabel(14))
            valueStepper(value: $addOn, step: feeStep(player), range: 0...max(feeStep(player), feeUpperBound(for: player) / 2), label: "Add-on") {
                Int($0) == 0 ? "NONE" : Player.formatCurrency(Int($0))
            }
            if addOn > 0 {
                Text("Paid after a year if he is still at the club.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .gfCard(padding: 14)
    }

    /// Step two: wage, length and signing-on bonus.
    private func termsCard(player: Player) -> some View {
        VStack(spacing: 10) {
            if let offer = liveOffer, offer.fee > 0 {
                Text("Agreed fee: " + GameState.dealStructureText(fee: offer.fee, installments: offer.installments,
                                                                 sellOnPercent: offer.sellOnPercent, addOn: offer.addOnAmount))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text("WEEKLY WAGE").font(.gfLabel(14))
            valueStepper(value: $wage, step: max(100, (wage / 20 / 100).rounded() * 100), range: 500...bidWageUpperBound(for: player), label: "Weekly wage") {
                "\(Player.formatCurrency(Int($0)))/w"
            }
            Text("CONTRACT").font(.gfLabel(14))
            valueStepper(value: Binding(get: { Double(contractYears) }, set: { contractYears = Int($0) }),
                         step: 1, range: 1...5, label: "Contract length") {
                "\(Int($0)) YEAR\(Int($0) == 1 ? "" : "S")"
            }
            Text("SIGNING-ON BONUS").font(.gfLabel(14))
            valueStepper(value: $signingBonus, step: max(10_000, (wage * 4 / 10_000).rounded() * 10_000), range: 0...max(100_000, wage * 52), label: "Signing-on bonus") {
                Int($0) == 0 ? "NONE" : Player.formatCurrency(Int($0))
            }
            Text("A bonus is paid now and lets you offer a lower wage.")
                .font(.caption).foregroundStyle(.secondary)
            if let user = gameState.userClub {
                Text("Wage room \(Player.formatCurrency(user.finances.weeklyWageSurplus))/w (the board's recommendation)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .gfCard(padding: 14)
    }

    private func feeStep(_ player: Player) -> Double {
        let raw = Double(max(player.value, 100_000)) / 20
        let magnitude = pow(10, floor(log10(raw)))
        return max(10_000, (raw / magnitude).rounded() * magnitude)
    }

    /// "‹  £50.4K  ›": arrows nudge the value; VoiceOver can swipe it.
    private func valueStepper(value: Binding<Double>, step: Double, range: ClosedRange<Double>, label: String,
                              format: @escaping (Double) -> String) -> some View {
        HStack {
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) } label: {
                Image(systemName: "chevron.left").font(.headline.weight(.bold)).frame(width: 40, height: 36)
            }
            .accessibilityHidden(true)
            Text(format(value.wrappedValue))
                .font(.gfDisplay(20).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.gfNavy))
                .overlay(Capsule().stroke(Color.white.opacity(0.3)))
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) } label: {
                Image(systemName: "chevron.right").font(.headline.weight(.bold)).frame(width: 40, height: 36)
            }
            .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value.wrappedValue))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            case .decrement: value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            @unknown default: break
            }
        }
    }

    private func isRivalSeller(_ club: Club?) -> Bool {
        guard let club, let userClub = gameState.userClub else { return false }
        return gameState.rivalry(between: club.id, and: userClub.id) != nil
    }

    /// Slider ceiling for the fee: always above the club's counter.
    private func feeUpperBound(for player: Player) -> Double {
        var ceiling = max(Double(player.value) * 2.5, 100_000)
        if let counter = reply?.counter ?? liveOffer?.counterFee {
            ceiling = max(ceiling, Double(counter) * 1.25)
        }
        return ceiling.rounded(.up)
    }

    /// Slider ceiling for the weekly wage, always above any stated demand.
    private func bidWageUpperBound(for player: Player) -> Double {
        var ceiling = max(Double(player.wage) * 4, 80_000)
        if let demand = liveOffer?.demandedWage {
            ceiling = max(ceiling, Double(demand) * 1.5)
        }
        return ceiling
    }

    private func primeFields() {
        guard let lookup = target else { return }
        if let offer = liveOffer {
            bidFee = Double(offer.counterFee ?? offer.fee)
            installments = offer.installments
            sellOnPercent = offer.sellOnPercent
            addOn = Double(offer.addOnAmount)
            wage = Double(offer.demandedWage ?? offer.offeredWage ?? max(lookup.player.wage, 1_000))
            contractYears = offer.contractYears ?? 3
        } else {
            bidFee = lookup.club == nil ? 0 : Double(lookup.player.value)
            wage = Double(max(lookup.player.wage, 1_000))
        }
    }

    private func submit(player: Player, club: Club?) {
        let answer: NegotiationReply
        if onTerms(club: club) {
            answer = gameState.negotiatePersonalTerms(playerId: player.id, wage: Int(wage), years: contractYears,
                                                      signingBonus: Int(signingBonus))
        } else {
            answer = gameState.negotiateTransferFee(playerId: player.id, fee: Int(bidFee), installments: installments,
                                                    sellOnPercent: sellOnPercent, addOn: Int(addOn))
            if answer.kind == .feeAgreed {
                // On to personal terms: start from what he earns now.
                wage = Double(max(player.wage, 1_000))
            }
        }
        withAnimation { reply = answer }
        AccessibilityNotification.Announcement(answer.message).post()
        if answer.kind == .completed || answer.kind == .walkedAway {
            outcomeMessage = answer.message
            showOutcome = true
        }
        try? SaveManager.shared.autoSave(gameState: gameState)
    }
}

// MARK: - European Competitions Screen

public struct EuropeanCompetitionsView: View {
    @Environment(GameState.self) private var gameState
    @State private var selectedCompetition: EuropeanCompetition = .championsLeague
    /// The matchweek whose results and fixtures are shown (nil = latest played).
    @State private var selectedMatchweek: Int?

    private var competitionState: EuropeanCompetitionState? {
        gameState.europeanCompetitions.first { $0.competition == selectedCompetition }
    }

    public var body: some View {
        List {
            Section {
                Picker("Competition", selection: $selectedCompetition) {
                    ForEach(EuropeanCompetition.allCases) { comp in
                        Text(comp.displayName).tag(comp)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Select competition")
            }

            if let state = competitionState {
                Section(header: Text(state.competition.displayName)) {
                    if state.stage == .complete, let champ = state.championClubId {
                        HStack {
                            Image(systemName: "trophy.fill").accessibilityHidden(true).foregroundStyle(.yellow)
                            Text("\(gameState.club(withId: champ)?.name ?? "Champion") — Champions")
                                .fontWeight(.semibold)
                        }
                    } else {
                        Text(state.stage == .leaguePhase
                             ? "League Phase — Matchweek \(min(gameState.europeanMatchweek, state.competition.leaguePhaseMatches)) of \(state.competition.leaguePhaseMatches)"
                             : "Knockout Stage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Your club and the clubs around it, as for the domestic table.
                if let uid = gameState.userClubId, state.table().contains(where: { $0.clubId == uid }) {
                    Section {
                        EuropeanTableAround(title: state.competition.displayName, rows: state.table(), userClubId: uid)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section(header: leaguePhaseHeader) {
                    let rows = state.table()
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        let rank = index + 1
                        let club = gameState.club(withId: row.clubId)
                        HStack {
                            Text("\(rank)")
                                .font(.caption)
                                .frame(width: 24, alignment: .leading)
                            Text(club?.name ?? "Club")
                                .font(.subheadline)
                                .fontWeight(club?.isUserClub == true ? .bold : .regular)
                            Spacer()
                            Text("\(row.played)").font(.caption).frame(width: 22, alignment: .trailing)
                            Text("\(row.won)").font(.caption).frame(width: 20, alignment: .trailing)
                            Text("\(row.drawn)").font(.caption).frame(width: 20, alignment: .trailing)
                            Text("\(row.lost)").font(.caption).frame(width: 20, alignment: .trailing)
                            Text("\(row.goalDifference)").font(.caption).frame(width: 28, alignment: .trailing)
                            Text("\(row.points)").font(.subheadline).fontWeight(.bold).frame(width: 30, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(rank). \(club?.name ?? "Club"): played \(row.played), won \(row.won), drawn \(row.drawn), lost \(row.lost), goal difference \(row.goalDifference), \(row.points) points")
                    }
                }

                resultsSection(state)

                if let userClubId = gameState.userClubId {
                    let userFixtures = state.fixtures
                        .filter { $0.homeClubId == userClubId || $0.awayClubId == userClubId }
                        .sorted { $0.matchweek < $1.matchweek }
                    if !userFixtures.isEmpty {
                        Section(header: Text("Your \(state.competition.displayName) Fixtures")) {
                            ForEach(userFixtures) { fx in
                                EuropeanFixtureRow(fixture: fx, competitionState: state)
                            }
                        }
                    }
                }
            } else {
                Text("No European competitions loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("European Competitions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { gameState.currentScreen = .dashboard }
                    .accessibilityLabel("Close European Competitions")
            }
        }
    }

    private var leaguePhaseHeader: some View {
        HStack {
            Text("#").frame(width: 24, alignment: .leading)
            Text("Club")
            Spacer()
            Text("P").frame(width: 22, alignment: .trailing)
            Text("W").frame(width: 20, alignment: .trailing)
            Text("D").frame(width: 20, alignment: .trailing)
            Text("L").frame(width: 20, alignment: .trailing)
            Text("GD").frame(width: 28, alignment: .trailing)
            Text("Pts").frame(width: 30, alignment: .trailing)
        }
        .font(.caption)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    /// Every match in one matchweek of the competition: results, or the
    /// fixtures still to come, as for the domestic leagues.
    @ViewBuilder
    private func resultsSection(_ state: EuropeanCompetitionState) -> some View {
        let weeks = Array(Set(state.fixtures.map(\.matchweek))).sorted()
        if !weeks.isEmpty {
            let latestPlayed = state.fixtures.filter(\.isPlayed).map(\.matchweek).max() ?? weeks[0]
            let week = selectedMatchweek.flatMap { weeks.contains($0) ? $0 : nil } ?? latestPlayed
            let games = state.fixtures.filter { $0.matchweek == week }
            Section(header: Text("Results & Fixtures")) {
                HStack {
                    Button {
                        if let i = weeks.firstIndex(of: week), i > 0 { selectedMatchweek = weeks[i - 1] }
                    } label: { Image(systemName: "chevron.left") }
                    .disabled(weeks.first == week)
                    .accessibilityLabel("Previous matchweek")
                    Spacer()
                    Text("Matchweek \(week)\(games.first.map { " · \($0.stage)" } ?? "")")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        if let i = weeks.firstIndex(of: week), i < weeks.count - 1 { selectedMatchweek = weeks[i + 1] }
                    } label: { Image(systemName: "chevron.right") }
                    .disabled(weeks.last == week)
                    .accessibilityLabel("Next matchweek")
                }
                .buttonStyle(.borderless)
                ForEach(games) { fx in
                    EuropeanFixtureRow(fixture: fx, competitionState: state)
                }
            }
        }
    }
}

private struct EuropeanFixtureRow: View {
    @Environment(GameState.self) private var gameState
    let fixture: EuropeanFixture
    let competitionState: EuropeanCompetitionState

    public var body: some View {
        let home = gameState.club(withId: fixture.homeClubId)?.name ?? "Home"
        let away = gameState.club(withId: fixture.awayClubId)?.name ?? "Away"
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(home) vs \(away)").font(.subheadline)
                Text("\(fixture.stage) • MW \(fixture.matchweek)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if fixture.isPlayed {
                Text("\(fixture.homeGoals)–\(fixture.awayGoals)").font(.subheadline).fontWeight(.bold)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - News Feed Screen

public struct NewsFeedView: View {
    @Environment(GameState.self) private var gameState
    @State private var categoryFilter: NewsCategory?
    @State private var mode: Mode = .news
    @State private var socialKind: SocialPost.Kind = .general

    enum Mode: String, CaseIterable { case news = "News", terrace = "The Terrace" }

    private var items: [NewsItem] {
        if let categoryFilter {
            return gameState.news.filter { $0.category == categoryFilter }
        }
        return gameState.news
    }

    public var body: some View {
        List {
            Section {
                GFTabs(selection: $mode)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if mode == .terrace {
                terraceSections
            } else {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        newsChip("All", active: categoryFilter == nil) { categoryFilter = nil }
                        ForEach(NewsCategory.allCases, id: \.self) { cat in
                            newsChip(cat.displayName, active: categoryFilter == cat) { categoryFilter = cat }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            }

            if items.isEmpty {
                ContentUnavailableView("No News", systemImage: "newspaper",
                                       description: Text("Stories will appear here as your career unfolds."))
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.category.displayName.uppercased())
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Text(item.date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.headline)
                            .font(.headline)
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(item.sender)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            }
        }
        .stadiumBackground()
        .navigationTitle(mode == .terrace ? "The Terrace" : "News")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if gameState.currentScreen == .news {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { gameState.currentScreen = .dashboard }
                        .accessibilityLabel("Close news and return to club home")
                }
            }
        }
    }

    /// Posts from players and clubs about the season's results and deals.
    @ViewBuilder
    private var terraceSections: some View {
        let feed = gameState.socialFeed()
        let shown = feed.filter { socialKind == .myTeam ? $0.involvesUser : $0.kind == socialKind || (socialKind == .general && $0.kind == .myTeam) }
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SocialPost.Kind.allCases) { kind in
                        newsChip(kind.rawValue, active: socialKind == kind) { socialKind = kind }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        }
        if shown.isEmpty {
            ContentUnavailableView("All Quiet", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Posts appear as matches are played and deals are done."))
        }
        ForEach(shown) { post in
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let seed = post.faceSeed {
                        FaceView(seed: seed, size: 52)
                    } else if let id = post.clubId, let club = gameState.club(withId: id) {
                        CrestView(club: club, size: 46)
                    } else {
                        Image(systemName: "person.crop.circle.fill").accessibilityHidden(true).font(.largeTitle)
                    }
                }
                .frame(width: 54)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(post.handle).font(.gfLabel(15)).lineLimit(1)
                        Spacer()
                        Text(DashboardView.shortDate(post.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(post.text).font(.subheadline)
                    if let tag = post.hashtag {
                        Text(tag).font(.gfLabel(13)).foregroundStyle(Color.gfMint).lineLimit(2)
                    }
                    HStack(spacing: 18) {
                        Label(Self.compact(post.likes), systemImage: "heart.fill")
                        Label(Self.compact(post.reposts), systemImage: "arrow.2.squarepath")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.gfSurface)
            .accessibilityElement(children: .combine)
        }
    }

    /// 1234567 → "1.23M".
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.2fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    @ViewBuilder
    private func newsChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(active ? .bold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color.white : Color.gfNavy.opacity(0.85))
                .foregroundStyle(active ? Color.gfNight : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(active ? 0 : 0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - International Management Screen

public struct InternationalHubView: View {
    @Environment(GameState.self) private var gameState
    @State private var selectedTournament: InternationalTournament.Kind = .worldCup

    private var tournamentState: InternationalTournament.State? {
        gameState.currentTournament(of: selectedTournament)
    }

    private func dateText(_ date: String?) -> String {
        guard let date else { return "" }
        return GameState.longDateText(date)
    }

    private var nextEditionText: String {
        guard let next = selectedTournament.nextEdition(fromSeasonStarting: gameState.seasonStartYear) else {
            return "No edition is scheduled."
        }
        return "Next edition: \(next.edition), from \(GameState.longDateText(next.date))."
    }

    public var body: some View {
        List {
            // My national team
            Section(header: Text("My Nation")) {
                if let team = gameState.managedNationalTeam {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name).font(.headline)
                            Text("\(team.confederation.rawValue) • Squad \(team.players.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Resign") { gameState.resignNationalTeam() }
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityHint("Step down as national team manager")
                    }
                } else {
                    Text("You are not managing a national team.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Pick the squad and play the nation's matches.
            if gameState.managedNationalTeam != nil {
                NationalMatchSection()
            }

            // Take over a nation
            Section(header: Text("Nations That Would Appoint You"),
                    footer: Text("You can manage a nation alongside your club or on its own. Bigger nations want a manager with a bigger reputation; federations also approach you through Job Offers.")) {
                ForEach(availablenations) { team in
                    Button {
                        gameState.takeOverNationalTeam(id: team.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(team.name).font(.subheadline).foregroundStyle(.primary)
                                Text(team.fifaRanking.map { "FIFA Rank \($0)" } ?? "Unranked")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Strength \(Int(team.strength))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Take over \(team.name), strength \(Int(team.strength))")
                }
            }

            // Tournaments
            Section {
                Picker("Tournament", selection: $selectedTournament) {
                    ForEach(InternationalTournament.Kind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Select tournament")
            }

            if let state = tournamentState {
                Section(header: Text(state.title)) {
                    if let start = state.startDate, let end = state.endDate {
                        Text("\(dateText(start)) to \(dateText(end))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if state.stage == .complete, let champId = state.championId {
                        HStack {
                            Image(systemName: "trophy.fill").accessibilityHidden(true).foregroundStyle(.yellow)
                            Text("\(gameState.nationalTeam(withId: champId)?.name ?? "Champion") — Champions")
                                .fontWeight(.semibold)
                        }
                    } else {
                        let started = state.fixtures.contains { $0.isPlayed }
                        Text(!started ? "Not started. Matches are played on their dates."
                             : state.stage == .groupStage ? "Group Stage" : "Knockout Stage")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                let upcoming = state.fixtures.filter { !$0.isPlayed }.sorted { ($0.date ?? "") < ($1.date ?? "") }.prefix(6)
                if !upcoming.isEmpty && state.stage != .complete {
                    Section("Coming up") {
                        ForEach(Array(upcoming)) { fx in
                            let home = gameState.nationalTeam(withId: fx.homeTeamId)?.name ?? fx.homeTeamId
                            let away = gameState.nationalTeam(withId: fx.awayTeamId)?.name ?? fx.awayTeamId
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(home) v \(away)").font(.subheadline)
                                    Text(fx.stage).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(fx.date.map { DashboardView.shortDate($0) } ?? "")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if state.stage == .groupStage {
                    ForEach(state.groupNames, id: \.self) { group in
                        Section(header: Text(group)) {
                            let rows = state.table(forGroup: group)
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                HStack {
                                    Text("\(index + 1)").font(.caption).frame(width: 20, alignment: .leading)
                                    Text(gameState.nationalTeam(withId: row.teamId)?.name ?? row.teamId)
                                        .font(.subheadline)
                                        .fontWeight(gameState.managedNationalTeamId == row.teamId ? .bold : .regular)
                                    Spacer()
                                    Text("\(row.played)").font(.caption).frame(width: 22, alignment: .trailing)
                                    Text("\(row.goalDifference)").font(.caption).frame(width: 28, alignment: .trailing)
                                    Text("\(row.points)").font(.subheadline).fontWeight(.bold).frame(width: 30, alignment: .trailing)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                } else {
                    Section(header: Text("Knockout Bracket")) {
                        ForEach(state.fixtures.filter { !$0.stage.hasPrefix("Group ") }) { fx in
                            let home = gameState.nationalTeam(withId: fx.homeTeamId)?.name ?? fx.homeTeamId
                            let away = gameState.nationalTeam(withId: fx.awayTeamId)?.name ?? fx.awayTeamId
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(home) vs \(away)").font(.subheadline)
                                    Text(fx.stage).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(fx.isPlayed ? "\(fx.homeGoals)–\(fx.awayGoals)" : "—")
                                    .font(.subheadline).fontWeight(.bold)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } else {
                Text(nextEditionText)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("International")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { gameState.currentScreen = .dashboard }
                    .accessibilityLabel("Close International")
            }
        }
    }

    /// Nations the user can take over, ordered by ranking.
    /// Nations whose federation would appoint you: none ask for a manager
    /// with a much smaller reputation than their standing.
    private var availablenations: [NationalTeam] {
        let current = gameState.managedNationalTeamId
        let reputation = gameState.manager.reputation
        return gameState.nationalTeams
            .filter { $0.id != current && gameState.nationalTeamReputation($0) <= reputation + 8 }
            .sorted { lhs, rhs in
                switch (lhs.fifaRanking, rhs.fifaRanking) {
                case let (l?, r?): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.name < rhs.name
                }
            }
    }
}

// MARK: - Youth Academy Screen

public struct YouthAcademyView: View {
    @Environment(GameState.self) private var gameState
    @State private var outcomeMessage: String?
    @State private var showOutcome = false

    public var body: some View {
        List {
            if let club = gameState.userClub {
                Section(header: Text("Academy Overview")) {
                    HStack {
                        Text("Academy Level")
                        Spacer()
                        Text("\(club.youthAcademyLevel) / 5")
                            .fontWeight(.bold)
                    }
                    HStack {
                        Text("Prospects")
                        Spacer()
                        Text("\(club.academyProspects.count)")
                            .fontWeight(.bold)
                    }
                    Text("Prospects develop each season and a new intake arrives every summer. Promote promising youngsters to the senior squad.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("Scouting & Facilities")) {
                    if let scout = club.bestScout {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scout.name)
                                    .font(.body)
                                Text("Lead Scout • quality \(scout.quality) of 5")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                releaseScout(scout)
                            } label: {
                                Text("Release")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Release scout \(scout.name)")
                        }
                    } else {
                        Text("No scouts employed. Hiring a scout improves the quality of each academy intake.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        hireScout()
                    } label: {
                        Label("Hire Scout (\(Player.formatCurrency(Club.scoutHiringFee(quality: 4))))", systemImage: "person.badge.plus")
                    }
                    .accessibilityHint("Hires a highly-rated scout using your transfer budget")

                    Button {
                        upgradeAcademy()
                    } label: {
                        Label("Upgrade Academy to Level \(min(5, club.youthAcademyLevel + 1)) (\(club.youthAcademyLevel >= 5 ? "MAX" : Player.formatCurrency(club.academyUpgradeCost)))", systemImage: "graduationcap")
                    }
                    .disabled(club.youthAcademyLevel >= 5)

                    Button {
                        upgradeTraining()
                    } label: {
                        Label("Upgrade Training Ground to Level \(min(5, club.trainingFacilityLevel + 1)) (\(club.trainingFacilityLevel >= 5 ? "MAX" : Player.formatCurrency(club.trainingUpgradeCost)))", systemImage: "figure.run")
                    }
                    .disabled(club.trainingFacilityLevel >= 5)
                }

                if club.academyProspects.isEmpty {
                    Section {
                        Text("No prospects in the academy yet. A new intake arrives at the start of next season.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section(header: Text("Prospects")) {
                        ForEach(club.academyProspects.sorted { $0.potential > $1.potential }) { prospect in
                            prospectRow(prospect, club: club)
                        }
                    }
                }
            } else {
                Text("Take charge of a club to manage its youth academy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Youth Academy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { gameState.currentScreen = .dashboard }
                    .accessibilityLabel("Close Youth Academy")
            }
        }
        .alert("Academy", isPresented: $showOutcome) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(outcomeMessage ?? "")
        }
    }

    private func prospectRow(_ prospect: Player, club: Club) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                FaceView(player: prospect, size: 40)
                Text(prospect.primaryPosition.abbreviation)
                    .font(.caption)
                    .fontWeight(.bold)
                    .frame(width: 38, height: 26)
                    .background(prospect.primaryPosition.category.accentColor.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(prospect.fullName)
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Age \(prospect.age) • \(prospect.nationality)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(prospect.overall)")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("Pot \(prospect.potential)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    promote(prospect)
                } label: {
                    Label("Promote", systemImage: "arrow.up.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    release(prospect)
                } label: {
                    Label("Release", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.leading, 52)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(prospect.fullName), \(prospect.primaryPosition.displayName), age \(prospect.age), overall \(prospect.overall), potential \(prospect.potential)")
    }

    private func promote(_ prospect: Player) {
        guard let clubIdx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
        if let promoted = gameState.clubs[clubIdx].promoteProspect(withId: prospect.id) {
            gameState.addNews(
                headline: "\(promoted.fullName) Promoted to First Team",
                body: "Academy graduate \(promoted.fullName) (age \(promoted.age), \(promoted.primaryPosition.displayName)) has been promoted to the senior squad.",
                category: .board,
                sender: "Head of Youth Development"
            )
            outcomeMessage = "\(promoted.fullName) has joined the senior squad."
        } else {
            outcomeMessage = "Could not promote that prospect."
        }
        showOutcome = true
        try? SaveManager.shared.autoSave(gameState: gameState)
    }

    private func release(_ prospect: Player) {
        guard let clubIdx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
        if gameState.clubs[clubIdx].releaseProspect(withId: prospect.id) != nil {
            outcomeMessage = "\(prospect.fullName) has been released from the academy."
        }
        showOutcome = true
        try? SaveManager.shared.autoSave(gameState: gameState)
    }

    private func hireScout() {
        guard let clubIdx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
        if let scout = gameState.clubs[clubIdx].hireScout(quality: 4) {
            outcomeMessage = "\(scout.name) has joined as a scout. Academy intakes will improve."
            gameState.addNews(
                headline: "New Scout Appointed",
                body: "\(scout.name) has joined the club as a scout. Expect stronger academy intakes.",
                category: .board,
                sender: "The Board"
            )
        } else {
            outcomeMessage = "You cannot afford a new scout right now."
        }
        showOutcome = true
        try? SaveManager.shared.autoSave(gameState: gameState)
    }

    private func releaseScout(_ scout: StaffMember) {
        guard let clubIdx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
        if gameState.clubs[clubIdx].releaseStaff(withId: scout.id) {
            outcomeMessage = "\(scout.name) has left the club."
        }
        showOutcome = true
        try? SaveManager.shared.autoSave(gameState: gameState)
    }

    private func upgradeAcademy() {
        guard let clubIdx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
        if gameState.clubs[clubIdx].upgradeYouthAcademy() {
            outcomeMessage = "The youth academy is now Level \(gameState.clubs[clubIdx].youthAcademyLevel)."
        } else {
            outcomeMessage = "You cannot afford that upgrade right now."
        }
        showOutcome = true
        try? SaveManager.shared.autoSave(gameState: gameState)
    }

    private func upgradeTraining() {
        guard let clubIdx = gameState.clubs.firstIndex(where: { $0.isUserClub }) else { return }
        if gameState.clubs[clubIdx].upgradeTrainingGround() {
            outcomeMessage = "The training ground is now Level \(gameState.clubs[clubIdx].trainingFacilityLevel)."
        } else {
            outcomeMessage = "You cannot afford that upgrade right now."
        }
        showOutcome = true
        try? SaveManager.shared.autoSave(gameState: gameState)
    }
}

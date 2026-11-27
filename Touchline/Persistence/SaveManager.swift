//
//  SaveManager.swift
//  Touchline
//
//  Created for Touchline - iOS Football Manager Game.
//  Persistence controller managing Codable JSON serialization to the app's
//  Documents directory, supporting multiple manual slots and automatic saving.
//

import Foundation

// MARK: - Save Slot Identifier

public enum SaveSlot: String, CaseIterable, Identifiable, Codable {
    case slot1 = "save_slot_1.json"
    case slot2 = "save_slot_2.json"
    case slot3 = "save_slot_3.json"
    case autoSave = "autosave.json"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .slot1: return "Slot 1"
        case .slot2: return "Slot 2"
        case .slot3: return "Slot 3"
        case .autoSave: return "Autosave"
        }
    }
}

// MARK: - Save Slot Metadata Header

public struct SaveSlotMetadata: Codable, Hashable {
    public let slot: SaveSlot
    public let clubName: String
    public let managerName: String
    public let seasonYear: String
    public let inGameDate: String
    public let savedAt: Date
    public let gameMode: GameMode
    
    public init(
        slot: SaveSlot,
        clubName: String,
        managerName: String,
        seasonYear: String,
        inGameDate: String,
        savedAt: Date = Date(),
        gameMode: GameMode
    ) {
        self.slot = slot
        self.clubName = clubName
        self.managerName = managerName
        self.seasonYear = seasonYear
        self.inGameDate = inGameDate
        self.savedAt = savedAt
        self.gameMode = gameMode
    }
    
    public var formattedRealDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: savedAt)
    }
}

// MARK: - Save Envelope

private struct SaveEnvelope: Codable {
    let metadata: SaveSlotMetadata
    let state: GameState
}

// MARK: - Save Manager Errors

public enum SaveManagerError: LocalizedError {
    case documentDirectoryUnavailable
    case fileNotFound(SaveSlot)
    case decodingFailed(String)
    case encodingFailed(String)
    case writeFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .documentDirectoryUnavailable:
            return "Unable to access the application documents directory."
        case .fileNotFound(let slot):
            return "No saved career found for \(slot.displayName)."
        case .decodingFailed(let reason):
            return "Failed to parse save file data: \(reason)"
        case .encodingFailed(let reason):
            return "Failed to serialize save state: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write save file to disk: \(reason)"
        }
    }
}

// MARK: - Save Manager

public final class SaveManager {
    
    public static let shared = SaveManager()
    
    private let fileManager = FileManager.default
    public init() {}

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - File URL Helpers
    
    private func documentsDirectory() throws -> URL {
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SaveManagerError.documentDirectoryUnavailable
        }
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    public func fileURL(for slot: SaveSlot) throws -> URL {
        return try documentsDirectory().appendingPathComponent(slot.rawValue)
    }
    
    // MARK: - Save Operations
    
    /// Persists current GameState to a designated manual or autosave slot.
    public func save(gameState: GameState, to slot: SaveSlot) throws {
        let snapshot = gameState.makeSnapshot()
        var thrown: Error?
        writeQueue.sync {
            do { try self.write(snapshot, to: slot) } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }

    /// Encodes and writes a state that no other thread is mutating. Uses its
    /// own encoder because `JSONEncoder` is not safe to share across threads.
    private func write(_ gameState: GameState, to slot: SaveSlot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadata = SaveSlotMetadata(
            slot: slot,
            clubName: gameState.userClub?.name ?? "Created Club",
            managerName: gameState.userClub?.manager ?? "Manager",
            seasonYear: gameState.season.year,
            inGameDate: gameState.season.currentDate,
            savedAt: Date(),
            gameMode: gameState.gameMode
        )
        
        let envelope = SaveEnvelope(metadata: metadata, state: gameState)
        
        let data: Data
        do {
            data = try encoder.encode(envelope)
        } catch {
            throw SaveManagerError.encodingFailed(error.localizedDescription)
        }
        
        let targetUrl = try fileURL(for: slot)
        let packed = SaveManager.pack(data)
        do {
            // "Until first unlock" so a background save still succeeds if the
            // device locks while the app is being suspended.
            try packed.write(to: targetUrl, options: [.atomicWrite, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw SaveManagerError.writeFailed(error.localizedDescription)
        }
        // A tiny sidecar header lets the save list show slot details without
        // parsing a multi-megabyte save.
        if let header = try? encoder.encode(metadata) {
            try? header.write(to: metadataURL(for: targetUrl), options: [.atomicWrite, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: - Compression

    /// Saves are JSON compressed with LZFSE (Apple's fast built-in codec),
    /// prefixed with a short marker. A career save shrinks roughly tenfold.
    /// Files without the marker are older, plain-JSON saves and load as-is.
    private static let compressedMarker = Data("GFCZ1".utf8)

    static func pack(_ json: Data) -> Data {
        #if canImport(Darwin)
        if let compressed = try? (json as NSData).compressed(using: .lzfse) as Data {
            return compressedMarker + compressed
        }
        #endif
        return json
    }

    static func unpack(_ stored: Data) throws -> Data {
        guard stored.starts(with: compressedMarker) else { return stored }
        #if canImport(Darwin)
        let body = Data(stored.dropFirst(compressedMarker.count))
        return try (body as NSData).decompressed(using: .lzfse) as Data
        #else
        throw SaveManagerError.decodingFailed("Compressed saves are not supported on this platform.")
        #endif
    }

    /// Total bytes used by saves, sidecars and quarantined backups.
    public func storageUsed() -> Int {
        guard let dir = try? documentsDirectory(),
              let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Bytes held by quarantined (unreadable) save backups.
    public func quarantinedBackupSize() -> Int {
        SaveSlot.allCases.reduce(0) { total, slot in
            guard let url = try? fileURL(for: slot).appendingPathExtension("corrupt") else { return total }
            return total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Deletes quarantined save backups to free space.
    public func deleteQuarantinedBackups() {
        for slot in SaveSlot.allCases {
            if let url = try? fileURL(for: slot).appendingPathExtension("corrupt") {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func metadataURL(for saveURL: URL) -> URL {
        saveURL.appendingPathExtension("meta")
    }
    
    /// Shortcut to trigger an autosave.
    /// Serial queue for all writes, so saves land on disk in the order they
    /// were requested and never interleave.
    private let writeQueue = DispatchQueue(label: "com.touchline.save", qos: .utility)

    /// A world with no career attached is skipped, so backing out of a new
    /// career never replaces the previous career's autosave.
    ///
    /// Encoding the whole world takes a couple of seconds, so the state is
    /// snapshotted (cheap, copy-on-write) on the caller's thread and encoded
    /// and written in the background. Use `autoSaveNow` when the write must
    /// finish before returning, e.g. when the app is being backgrounded.
    public func autoSave(gameState: GameState) throws {
        guard gameState.hasStartedCareer else { return }
        let snapshot = gameState.makeSnapshot()
        // Coalesce: only the newest pending snapshot is kept. Queuing every
        // request let snapshots pile up faster than they could be written
        // (a week simulates in a fraction of the time an encode takes); each
        // one became a full copy of the world and memory grew without bound.
        pendingLock.lock()
        pendingAutoSave = snapshot
        let startDrain = !isDrainingAutoSaves
        if startDrain { isDrainingAutoSaves = true }
        pendingLock.unlock()
        if startDrain {
            writeQueue.async { self.drainAutoSaves() }
        }
    }

    private let pendingLock = NSLock()
    private var pendingAutoSave: GameState?
    private var isDrainingAutoSaves = false

    /// Writes the latest pending autosave until none is left.
    private func drainAutoSaves() {
        while true {
            pendingLock.lock()
            guard let next = pendingAutoSave else {
                isDrainingAutoSaves = false
                pendingLock.unlock()
                return
            }
            pendingAutoSave = nil
            pendingLock.unlock()
            try? write(next, to: .autoSave)
        }
    }

    /// Synchronous autosave of the current state. Any older pending background
    /// save is discarded so it cannot overwrite this one afterwards.
    public func autoSaveNow(gameState: GameState) throws {
        guard gameState.hasStartedCareer else { return }
        let snapshot = gameState.makeSnapshot()
        pendingLock.lock()
        pendingAutoSave = nil
        pendingLock.unlock()
        var thrown: Error?
        writeQueue.sync {
            do { try self.write(snapshot, to: .autoSave) } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }
    
    // MARK: - Load Operations
    
    /// Loads the GameState stored in the designated save slot.
    public func load(from slot: SaveSlot) throws -> GameState {
        let targetUrl = try fileURL(for: slot)
        guard fileManager.fileExists(atPath: targetUrl.path) else {
            throw SaveManagerError.fileNotFound(slot)
        }
        
        do {
            let data = try SaveManager.unpack(Data(contentsOf: targetUrl))
            let envelope = try makeDecoder().decode(SaveEnvelope.self, from: data)
            return envelope.state
        } catch {
            throw SaveManagerError.decodingFailed(error.localizedDescription)
        }
    }
    
    public func loadAutoSave() throws -> GameState {
        return try load(from: .autoSave)
    }
    
    // MARK: - Metadata & Inspection
    
    /// Reads only the save metadata header without retaining the full world state.
    public func getMetadata(for slot: SaveSlot) -> SaveSlotMetadata? {
        guard let targetUrl = try? fileURL(for: slot),
              fileManager.fileExists(atPath: targetUrl.path) else {
            return nil
        }
        let decoder = makeDecoder()
        if let sidecar = try? Data(contentsOf: metadataURL(for: targetUrl)),
           let meta = try? decoder.decode(SaveSlotMetadata.self, from: sidecar) {
            return meta
        }
        // Saves from older builds have no sidecar; fall back to the full file.
        guard let stored = try? Data(contentsOf: targetUrl),
              let data = try? SaveManager.unpack(stored) else { return nil }
        
        struct HeaderOnly: Codable {
            let metadata: SaveSlotMetadata
        }
        
        let header = try? decoder.decode(HeaderOnly.self, from: data)
        return header?.metadata
    }
    
    public func doesSaveExist(for slot: SaveSlot) -> Bool {
        guard let url = try? fileURL(for: slot) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// Renames an unreadable save file to `<name>.corrupt` (replacing any older
    /// quarantined copy) so it is no longer loaded or overwritten, while keeping
    /// the bytes around for recovery.
    public func quarantineUnreadableSave(_ slot: SaveSlot) {
        guard let url = try? fileURL(for: slot),
              fileManager.fileExists(atPath: url.path) else { return }
        let backup = url.appendingPathExtension("corrupt")
        try? fileManager.removeItem(at: backup)
        try? fileManager.moveItem(at: url, to: backup)
        try? fileManager.removeItem(at: metadataURL(for: url))
    }

    public func deleteSave(for slot: SaveSlot) throws {
        if slot == .autoSave {
            pendingLock.lock()
            pendingAutoSave = nil
            pendingLock.unlock()
        }
        // An autosave already being encoded must finish before the file is removed.
        try writeQueue.sync {
            let url = try fileURL(for: slot)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try? fileManager.removeItem(at: metadataURL(for: url))
        }
    }
}

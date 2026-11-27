//
//  DatapackStore.swift
//  Touchline
//
//  Datapacks: complete, editable copies of the game's leagues, clubs and
//  players, kept as JSON files in the app's Documents folder. One pack can
//  be active; a new career is then built from it instead of the bundled
//  data. Packs can be exported to a file and imported from one.
//

import Foundation

public struct Datapack: Codable {
    public var name: String
    public var leagues: [RawLeagueData]

    public var clubCount: Int { leagues.reduce(0) { $0 + $1.clubs.count } }
    public var playerCount: Int { leagues.reduce(0) { $0 + $1.clubs.reduce(0) { $0 + $1.players.count } } }
}

public final class DatapackStore {
    public static let shared = DatapackStore()
    private static let activeKey = "gfActiveDatapack"
    private static let fileSuffix = ".gfpack.json"
    private let creationLock = NSLock()
    private var cache: (name: String, pack: Datapack)?

    private var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = docs.appendingPathComponent("Datapacks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func fileURL(for name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent(safe + Self.fileSuffix)
    }

    /// Names of the saved packs, alphabetically.
    public func list() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasSuffix(Self.fileSuffix) }
            .map { String($0.lastPathComponent.dropLast(Self.fileSuffix.count)) }
            .sorted()
    }

    public func load(_ name: String) -> Datapack? {
        if let cache, cache.name == name { return cache.pack }
        guard let data = try? Data(contentsOf: fileURL(for: name)),
              var pack = try? JSONDecoder().decode(Datapack.self, from: data) else { return nil }
        // Older builds stored the original name in JSON, even if the filename was sanitized.
        pack.name = name
        return pack
    }

    @discardableResult
    public func save(_ pack: Datapack) -> Bool {
        guard write(pack) else { return false }
        if cache?.name == pack.name { cache = (pack.name, pack) }
        return true
    }

    private func write(_ pack: Datapack) -> Bool {
        guard let data = try? JSONEncoder().encode(pack) else { return false }
        do {
            try data.write(to: fileURL(for: pack.name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func delete(_ name: String) {
        try? FileManager.default.removeItem(at: fileURL(for: name))
        if activeName == name { activeName = nil }
        if cache?.name == name { cache = nil }
    }

    /// The pack new careers are built from, or nil for the game's own data.
    public var activeName: String? {
        get {
            guard let name = UserDefaults.standard.string(forKey: Self.activeKey),
                  FileManager.default.fileExists(atPath: fileURL(for: name).path) else { return nil }
            return name
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.activeKey)
            cache = nil
        }
    }

    public var activePack: Datapack? {
        guard let name = activeName else { return nil }
        if let cache, cache.name == name { return cache.pack }
        guard let pack = load(name), !pack.leagues.isEmpty else { return nil }
        cache = (name, pack)
        return pack
    }

    /// A new pack holding the game's current data, ready to edit.
    public func createFromBundled(named name: String) -> Datapack? {
        let leagues = LeagueTier.allCases.compactMap { DataLoader.bundledLeague(for: $0) }
        guard !leagues.isEmpty else { return nil }
        return storeNew(Datapack(name: name, leagues: leagues))
    }

    /// A copy of an existing pack under a new name.
    public func duplicate(_ name: String) -> Datapack? {
        guard var pack = load(name) else { return nil }
        pack.name = name + " copy"
        return storeNew(pack)
    }

    /// Reads a pack from a file chosen by the user and stores it.
    public func importPack(from url: URL) -> Datapack? {
        #if canImport(UIKit)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        guard let data = try? Data(contentsOf: url),
              var pack = try? JSONDecoder().decode(Datapack.self, from: data),
              !pack.leagues.isEmpty else { return nil }
        if pack.name.isEmpty { pack.name = "Imported" }
        return storeNew(pack)
    }

    private func storeNew(_ source: Datapack) -> Datapack? {
        creationLock.lock()
        defer { creationLock.unlock() }
        var pack = source
        pack.name = uniqueName(source.name)
        return write(pack) ? pack : nil
    }

    private func uniqueName(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let root = trimmed.isEmpty ? "My Datapack" : trimmed
        let existing = Set(list().map { $0.lowercased() })
        if !existing.contains(root.lowercased()) { return root }
        var n = 2
        while existing.contains("\(root) \(n)".lowercased()) { n += 1 }
        return "\(root) \(n)"
    }
}

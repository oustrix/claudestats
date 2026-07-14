import Foundation

/// A working directory the user ran Claude Code in.
///
/// Identity is the full path, taken from the session's earliest message. The encoded directory name
/// under `~/.claude/projects/` is not used: `-Users-me--claude-code-router` stands for
/// `/Users/me/.claude-code-router`, and the encoding cannot be inverted — a dash in the decoded
/// path is indistinguishable from an encoded separator.
public struct Project: Hashable, Sendable {
    public let fullPath: String
    private let home: String

    public init(cwd: String, home: String) {
        fullPath = cwd
        self.home = home
    }

    /// The last path component, or `~` for the home directory itself.
    public var displayName: String {
        guard fullPath != home else { return "~" }
        return URL(filePath: fullPath).lastPathComponent
    }

    /// The full path with the home directory written as `~`. Compares whole path components, so
    /// `/Users/median` is not mistaken for a child of `/Users/me`.
    public var abbreviatedPath: String {
        guard fullPath != home else { return "~" }
        let homeComponents = home.split(separator: "/")
        let pathComponents = fullPath.split(separator: "/")
        guard pathComponents.starts(with: homeComponents) else { return fullPath }
        return "~/" + pathComponents.dropFirst(homeComponents.count).joined(separator: "/")
    }

    public static func == (lhs: Project, rhs: Project) -> Bool { lhs.fullPath == rhs.fullPath }
    public func hash(into hasher: inout Hasher) { hasher.combine(fullPath) }
}

/// One run of Claude Code, attributed to the working directory and day of its earliest message.
public struct Session: Identifiable, Equatable, Sendable {
    public let id: String
    public let project: Project
    public let start: Date
    public let end: Date
    public let messageCount: Int
    public let usage: TokenUsage
    /// The estimated dollar cost, summed per the model of each of the session's messages. Present
    /// only when `Aggregation.sessions` was given a pricing; nil otherwise.
    public let estimatedCost: Double?

    public init(
        id: String, project: Project, start: Date, end: Date, messageCount: Int,
        usage: TokenUsage, estimatedCost: Double? = nil
    ) {
        self.id = id
        self.project = project
        self.start = start
        self.end = end
        self.messageCount = messageCount
        self.usage = usage
        self.estimatedCost = estimatedCost
    }
}

import Foundation

/// The person a file belongs to when Resolute runs as root because of `sudo`, so that what
/// `sudo resolute …` creates in their support folder stays writable by the app.
struct FileOwner: Hashable, Sendable {
    var uid: uid_t
    var gid: gid_t

    /// The person who ran `sudo`; nil unless this process runs as root because of it.
    static func sudoPerson(
        environment: [String: String] = ProcessInfo.processInfo.environment, isRoot: Bool = geteuid() == 0
    ) -> FileOwner? {
        guard isRoot, let uid = environment["SUDO_UID"].flatMap(uid_t.init), uid != 0,
              let gid = environment["SUDO_GID"].flatMap(gid_t.init)
        else { return nil }
        return FileOwner(uid: uid, gid: gid)
    }
}

/// An open folder whose files are reached by name through it, so a file can't be swapped
/// for a link between a check and its use. As root, the folder must be inside the person's
/// home, no link below the home is followed on the way (the person could point one at a
/// system file), and what root creates there is given to `owner`.
final class SupportFolder {
    let descriptor: Int32
    let path: String
    let owner: FileOwner?

    private init(descriptor: Int32, path: String, owner: FileOwner?) {
        self.descriptor = descriptor
        self.path = path
        self.owner = owner
    }

    deinit {
        close(descriptor)
    }

    /// Opens `url`, creating missing folders when `creating`. Nil when the folder does not
    /// exist and `creating` is false.
    static func open(
        _ url: URL, creating: Bool, owner: FileOwner?,
        home: URL = SupportLocations.personHome, isRoot: Bool = geteuid() == 0
    ) throws -> SupportFolder? {
        let components = url.standardizedFileURL.pathComponents
        let homeComponents = home.standardizedFileURL.pathComponents
        let path = "/" + components.dropFirst().joined(separator: "/")
        let isInsideHome = components.count > homeComponents.count
            && Array(components.prefix(homeComponents.count)) == homeComponents
        guard !isRoot || isInsideHome else {
            throw HistoryError.unusable(
                path: path, reason: "as root, Resolute keeps its files only inside the home folder of the person using sudo"
            )
        }
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw HistoryError.unusable(path: "/", reason: describe(errno)) }
        var reached = ""
        for (index, name) in components.enumerated().dropFirst() {
            reached += "/" + name
            // The folders that make up the home itself may be links an administrator set up.
            let followsLinks = !isRoot || index < homeComponents.count
            let flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | (followsLinks ? 0 : O_NOFOLLOW)
            var next = openat(current, name, flags)
            var created = false
            if next < 0, errno == ENOENT {
                guard creating else {
                    close(current)
                    return nil
                }
                if mkdirat(current, name, 0o755) == 0 {
                    created = true
                } else if errno != EEXIST {
                    let reason = describe(errno)
                    close(current)
                    throw HistoryError.unusable(path: reached, reason: reason)
                }
                next = openat(current, name, flags)
            }
            let openError = errno
            close(current)
            guard next >= 0 else {
                throw HistoryError.unusable(path: reached, reason: openError == ELOOP ? "it is a link" : describe(openError))
            }
            current = next
            if created, let owner, fchown(current, owner.uid, owner.gid) != 0 {
                let reason = describe(errno)
                close(current)
                throw HistoryError.unusable(path: reached, reason: reason)
            }
        }
        let folder = SupportFolder(descriptor: current, path: path, owner: owner)
        // A support folder that root made earlier, without handing it over, is handed over now.
        try folder.handOver(current, at: path)
        return folder
    }

    /// Opens the regular file `name` in this folder, never through a link. Refuses a file
    /// with more than one link: writing to it would change a file elsewhere too.
    func openFile(_ name: String, flags: Int32, mode: mode_t = 0o644) throws -> Int32 {
        let filePath = path + "/" + name
        let file = openat(descriptor, name, flags | O_NOFOLLOW | O_CLOEXEC, mode)
        guard file >= 0 else {
            let code = errno
            if code == ENOENT { throw HistoryError.missing(path: filePath) }
            throw HistoryError.unusable(path: filePath, reason: code == ELOOP ? "it is a link" : Self.describe(code))
        }
        do {
            var info = stat()
            guard fstat(file, &info) == 0 else { throw HistoryError.unusable(path: filePath, reason: Self.describe(errno)) }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
                throw HistoryError.unusable(path: filePath, reason: "it is not a regular file with a single link")
            }
            try handOver(file, at: filePath)
        } catch {
            close(file)
            throw error
        }
        return file
    }

    /// Replaces `destination` with `source`, both in this folder.
    func rename(_ source: String, to destination: String) throws {
        guard renameat(descriptor, source, descriptor, destination) == 0 else {
            throw HistoryError.unusable(path: path + "/" + destination, reason: Self.describe(errno))
        }
    }

    func remove(_ name: String) {
        unlinkat(descriptor, name, 0)
    }

    /// Gives `file` to the owner when root owns it: root made it, now or on an earlier run.
    private func handOver(_ file: Int32, at path: String) throws {
        guard let owner else { return }
        var info = stat()
        guard fstat(file, &info) == 0 else { throw HistoryError.unusable(path: path, reason: Self.describe(errno)) }
        guard info.st_uid == 0 else { return }
        guard fchown(file, owner.uid, owner.gid) == 0 else {
            throw HistoryError.unusable(path: path, reason: Self.describe(errno))
        }
    }

    static func describe(_ code: Int32) -> String {
        String(cString: strerror(code)).lowercased()
    }
}

/// Why History could not be read or written.
public enum HistoryError: Error, Equatable, Sendable {
    /// Another Resolute process held the history file for longer than the store waits.
    case busy(path: String)
    /// A file or folder could not be used.
    case unusable(path: String, reason: String)
    /// A file that should be there is not.
    case missing(path: String)
}

extension HistoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .busy(let path):
            "Another Resolute process kept \(path) busy. Try again in a moment."
        case .unusable(let path, let reason):
            "Could not use \(path): \(reason)."
        case .missing(let path):
            "\(path) is missing."
        }
    }
}

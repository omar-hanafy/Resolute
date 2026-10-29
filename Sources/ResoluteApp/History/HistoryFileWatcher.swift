import Foundation

/// Calls `onChange` when History's file changes, as it does when `resolute` or an agent
/// switches a display while the History page is open. It watches the file for writes and
/// its folder for the file being created or replaced (pruning writes a new file in its
/// place), and opens the file again when it is.
@MainActor
final class HistoryFileWatcher {
    private let file: URL
    private let onChange: @MainActor () -> Void
    private var folderSource: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?

    init(file: URL, onChange: @escaping @MainActor () -> Void) {
        self.file = file
        self.onChange = onChange
    }

    var isWatching: Bool { folderSource != nil }

    func start() {
        guard folderSource == nil else { return }
        folderSource = source(for: file.deletingLastPathComponent(), events: .write) { [weak self] in
            self?.watchFile()
            self?.onChange()
        }
        watchFile()
    }

    func stop() {
        folderSource?.cancel()
        folderSource = nil
        fileSource?.cancel()
        fileSource = nil
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = source(for: file, events: [.write, .extend, .delete, .rename]) { [weak self] in
            guard let self else { return }
            if let source = fileSource, !source.data.isDisjoint(with: [.delete, .rename]) {
                watchFile()
            }
            onChange()
        }
    }

    /// A source on the main queue for `url`; nil when it can't be opened, as before the
    /// support folder or the file exists.
    private func source(
        for url: URL, events: DispatchSource.FileSystemEvent, handler: @escaping @MainActor () -> Void
    ) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { handler() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }
}

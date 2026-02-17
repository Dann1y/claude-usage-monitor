import Foundation

final class FileWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let path: String
    private let onChange: () -> Void

    init(path: String = NSHomeDirectory() + "/.claude/projects", onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        watchDirectory(path)
        watchSubdirectories()
    }

    func stop() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
    }

    private func watchDirectory(_ dirPath: String) {
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptors.append(fd)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources.append(source)
    }

    private func watchSubdirectories() {
        let fm = FileManager.default
        guard let subdirs = try? fm.contentsOfDirectory(atPath: path) else { return }

        for subdir in subdirs {
            let subdirPath = (path as NSString).appendingPathComponent(subdir)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: subdirPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let fd = open(subdirPath, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend],
                queue: .global(qos: .utility)
            )

            source.setEventHandler { [weak self] in
                self?.handleChange()
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            sources.append(source)
        }
    }

    private func handleChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onChange()
        }
    }

    deinit {
        stop()
    }
}

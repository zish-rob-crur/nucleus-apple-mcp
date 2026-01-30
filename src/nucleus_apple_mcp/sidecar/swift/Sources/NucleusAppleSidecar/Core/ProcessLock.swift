import Darwin
import Foundation

func withProcessLock<T>(name: String, _ body: () throws -> T) throws -> T {
    let fm = FileManager.default
    let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let lockDir = cacheDir.appendingPathComponent("nucleus-apple-mcp", isDirectory: true)
    try fm.createDirectory(at: lockDir, withIntermediateDirectories: true)
    let lockPath = lockDir.appendingPathComponent("\(name).lock").path

    let fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    if fd == -1 {
        throw SimpleSidecarError(
            code: "INTERNAL",
            message: "Failed to open lock file: \(lockPath)"
        )
    }

    defer { close(fd) }

    if flock(fd, LOCK_EX) != 0 {
        throw SimpleSidecarError(code: "INTERNAL", message: "Failed to acquire lock: \(lockPath)")
    }
    defer { flock(fd, LOCK_UN) }

    return try body()
}


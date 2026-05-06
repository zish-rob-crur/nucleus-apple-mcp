import Foundation
import Network

enum NetworkSyncStatus: Equatable, Sendable {
    case unknown
    case unavailable
    case wifi
    case cellular
    case other

    func allowsSync(allowCellular: Bool) -> Bool {
        switch self {
        case .wifi, .other:
            true
        case .cellular:
            allowCellular
        case .unknown, .unavailable:
            false
        }
    }

    var label: String {
        switch self {
        case .unknown:
            "Checking"
        case .unavailable:
            "Offline"
        case .wifi:
            "Wi-Fi"
        case .cellular:
            "Cellular"
        case .other:
            "Network"
        }
    }

    func detail(allowCellular: Bool) -> String {
        switch self {
        case .unknown:
            "Sync will start after the connection is confirmed."
        case .unavailable:
            "Sync is paused until a permitted network is available."
        case .wifi:
            "Sync can run now."
        case .cellular:
            allowCellular ? "Sync can run on mobile data." : "Sync is paused on mobile data."
        case .other:
            "Sync can run on this connection."
        }
    }

    static func from(_ path: NWPath) -> Self {
        guard path.status == .satisfied else { return .unavailable }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .other
    }
}

final class NetworkStatusMonitor: @unchecked Sendable {
    var onStatusChange: (@MainActor (NetworkSyncStatus) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.zhiwenwang.nucleus.network-status")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = NetworkSyncStatus.from(path)
            Task { @MainActor [weak self] in
                self?.onStatusChange?(status)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

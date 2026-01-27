import Foundation

protocol SidecarError: Error {
    var code: String { get }
    var message: String { get }
}

struct SimpleSidecarError: SidecarError {
    let code: String
    let message: String
}


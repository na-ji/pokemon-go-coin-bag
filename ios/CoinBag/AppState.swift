import Foundation

enum AppState: Equatable {
    case idle
    case scanning
    case connecting
    case readingDevice
    case pairing
    case exchanging
    case successPair(String)
    case successExchange(String)
    case failure(String)
}

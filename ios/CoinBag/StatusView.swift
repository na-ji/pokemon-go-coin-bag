import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

private func stateLabel(_ state: AppState) -> String {
    switch state {
    case .idle: return "waiting…"
    case .scanning: return "scanning…"
    case .connecting: return "connecting…"
    case .readingDevice: return "checking device…"
    case .pairing: return "pairing Switch…"
    case .exchanging: return "receiving postcard…"
    case .successPair: return "Switch paired!"
    case .successExchange: return "postcard received!"
    case .failure: return "failed"
    }
}

private func stateDetail(_ state: AppState) -> String? {
    switch state {
    case .failure(let message): return message
    case .successPair(let name): return "Paired with \(name)"
    case .successExchange(let name): return "Postcard received from \(name)"
    default: return nil
    }
}

private func stateColor(_ state: AppState) -> Color {
    switch state {
    case .successPair, .successExchange: return Color(hex: 0x69D391)
    case .failure: return Color(hex: 0xFF7C8C)
    case .idle: return Color(hex: 0x8B79FF)
    default: return Color(hex: 0xD2A63D)
    }
}

struct StatusView: View {
    @ObservedObject var client: BleClient
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(hex: 0x11131A).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if client.permissionDenied {
                        StatusCard(
                            label: "permission needed",
                            detail: "Grant Bluetooth permission in Settings to continue",
                            color: Color(hex: 0x4A4D5C)
                        )
                    } else {
                        StatusCard(
                            label: stateLabel(client.state),
                            detail: stateDetail(client.state),
                            color: stateColor(client.state)
                        )
                    }

                    HistoryCard(log: client.log)
                    InstructionsCard()
                }
                .padding(24)
            }
        }
        .onAppear { client.start() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: client.start()
            case .background: client.stop()
            default: break
            }
        }
    }
}

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

private func logIcon(_ type: LogEventType) -> String {
    switch type {
    case .paired: return "🔗"
    case .exchanged: return "📮"
    case .failed: return "⚠️"
    }
}

private func logSummary(_ entry: LogEntry) -> String {
    switch entry.type {
    case .paired: return "Paired with \(entry.playerName ?? "?")"
    case .exchanged: return "Postcard received from \(entry.playerName ?? "?")"
    case .failed: return entry.message ?? "Failed"
    }
}

private struct StatusCard: View {
    let label: String
    let detail: String?
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 36, weight: .black))
                .foregroundColor(Color(hex: 0x0D0D14))
            if let detail {
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x0D0D14))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct HistoryCard: View {
    let log: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)
                .foregroundColor(.white)

            if log.isEmpty {
                Text("No activity yet.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(log.reversed())) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(logIcon(entry.type))
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(logSummary(entry))
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Text(timeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
    }
}

private struct InstructionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step 1 · Pair Switch")
                .font(.headline)
                .foregroundColor(.white)
            Text("In Pokémon GO: Poké Ball menu → Settings → Connected devices and Services → Nintendo Switch → Connect to Nintendo Switch → pick your game.")
                .foregroundColor(.white.opacity(0.85))
            Text("This app connects automatically while open.")
                .foregroundColor(.white.opacity(0.85))

            Spacer().frame(height: 8)

            Text("Step 2 · Send postcard")
                .font(.headline)
                .foregroundColor(.white)
            Text("In Pokémon GO: Items → Postcard Book → pick a postcard → SEND TO NINTENDO SWITCH.")
                .foregroundColor(.white.opacity(0.85))
            Text("This app receives it automatically while open.")
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

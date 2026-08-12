package io.github.naji.pokemongo.coin.bag

import java.time.Instant

enum class LogEventType {
    PAIRED,
    EXCHANGED,
    FAILED,
}

data class LogEntry(
    val timestamp: Instant,
    val type: LogEventType,
    val playerName: String? = null,
    val message: String? = null,
)

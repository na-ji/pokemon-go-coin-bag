package io.github.naji.pokemongo.coin.bag

sealed interface AppState {
    data object Idle : AppState
    data object Scanning : AppState
    data object Connecting : AppState
    data object ReadingDevice : AppState
    data object Pairing : AppState
    data object Exchanging : AppState
    data object SuccessPair : AppState
    data object SuccessExchange : AppState
    data class Failure(val message: String) : AppState
}

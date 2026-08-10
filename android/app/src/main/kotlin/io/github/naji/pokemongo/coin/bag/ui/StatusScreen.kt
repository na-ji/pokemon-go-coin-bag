package io.github.naji.pokemongo.coin.bag.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.naji.pokemongo.coin.bag.AppState

private fun stateLabel(state: AppState): String = when (state) {
    AppState.Idle -> "waiting…"
    AppState.Scanning -> "scanning…"
    AppState.Connecting -> "connecting…"
    AppState.ReadingDevice -> "checking device…"
    AppState.Pairing -> "pairing Switch…"
    AppState.Exchanging -> "receiving postcard…"
    AppState.SuccessPair -> "Switch paired!"
    AppState.SuccessExchange -> "postcard received!"
    is AppState.Failure -> "failed"
}

private fun stateColor(state: AppState): Color = when (state) {
    AppState.SuccessPair, AppState.SuccessExchange -> Color(0xFF69D391)
    is AppState.Failure -> Color(0xFFFF7C8C)
    AppState.Idle -> Color(0xFF8B79FF)
    else -> Color(0xFFD2A63D)
}

@Composable
fun StatusScreen(state: AppState, permissionDenied: Boolean) {
    Surface(color = Color(0xFF11131A)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (permissionDenied) {
                StatusCard(
                    label = "permission needed",
                    detail = "Grant Bluetooth permission to continue",
                    color = Color(0xFF4A4D5C),
                )
            } else {
                StatusCard(
                    label = stateLabel(state),
                    detail = (state as? AppState.Failure)?.message,
                    color = stateColor(state),
                )
            }

            Spacer(modifier = Modifier.height(24.dp))
            InstructionsCard()
        }
    }
}

@Composable
private fun StatusCard(label: String, detail: String?, color: Color) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(color, RoundedCornerShape(24.dp))
            .padding(32.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text = label, color = Color(0xFF0D0D14), fontSize = 36.sp, fontWeight = FontWeight.Black)
            if (detail != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(text = detail, color = Color(0xFF0D0D14), fontSize = 14.sp)
            }
        }
    }
}

@Composable
private fun InstructionsCard() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0x0AFFFFFF), RoundedCornerShape(24.dp))
            .padding(20.dp),
    ) {
        Text("Step 1 · Pair Switch", color = Color.White, fontWeight = FontWeight.Bold)
        Text(
            "In Pokémon GO: Poké Ball menu → Settings → Connected devices and Services → " +
                "Nintendo Switch → Connect to Nintendo Switch → pick your game.",
            color = Color.White.copy(alpha = 0.85f),
        )
        Text("This app connects automatically while open.", color = Color.White.copy(alpha = 0.85f))
        Spacer(modifier = Modifier.height(16.dp))
        Text("Step 2 · Send postcard", color = Color.White, fontWeight = FontWeight.Bold)
        Text(
            "In Pokémon GO: Items → Postcard Book → pick a postcard → SEND TO NINTENDO SWITCH.",
            color = Color.White.copy(alpha = 0.85f),
        )
        Text("This app receives it automatically while open.", color = Color.White.copy(alpha = 0.85f))
    }
}

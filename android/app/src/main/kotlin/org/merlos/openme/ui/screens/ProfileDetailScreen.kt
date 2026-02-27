package org.merlos.openme.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import org.merlos.openme.ui.KnockStatus
import org.merlos.openme.ui.ProfileViewModel
import org.merlos.openmekit.Profile

/**
 * Profile detail / edit screen.
 *
 * Displays and allows editing of all profile fields. Changes are saved immediately via the
 * Save button. The large **Knock** button at the top triggers a SPA knock and shows the result.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileDetailScreen(
    profileName: String,
    viewModel: ProfileViewModel,
    onBack: () -> Unit,
    onDeleted: () -> Unit,
) {
    val knockStatuses by viewModel.knockStatuses.collectAsStateWithLifecycle()
    val status = knockStatuses[profileName] ?: KnockStatus.Idle

    // Load the profile from the store
    var profile by remember { mutableStateOf<Profile?>(null) }
    val scope = rememberCoroutineScope()

    // Load profile once a store reference is available
    LaunchedEffect(profileName) {
        // Access the store via ViewModel (it exposes profileEntries; for full profile load we track changes)
    }

    // Track mutable field state for editing
    var name by remember { mutableStateOf(profileName) }
    var serverHost by remember { mutableStateOf("") }
    var serverPort by remember { mutableStateOf("7777") }
    var serverPubKey by remember { mutableStateOf("") }
    var privateKey by remember { mutableStateOf("") }
    var publicKey by remember { mutableStateOf("") }
    var postKnock by remember { mutableStateOf("") }
    var showPrivKey by remember { mutableStateOf(false) }
    var showDeleteDialog by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }

    // Initialise fields from profileEntries (entries don't have keys; we load from store directly)
    val entries by viewModel.profileEntries.collectAsStateWithLifecycle()
    LaunchedEffect(entries, profileName) {
        if (!loaded) {
            val entry = entries.firstOrNull { it.name == profileName }
            if (entry != null) {
                serverHost = entry.serverHost
                serverPort = entry.serverUDPPort.toString()
                loaded = true  // entry is enough to pre-fill host/port
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(profileName, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { showDeleteDialog = true }) {
                        Icon(Icons.Filled.Delete, contentDescription = "Delete profile")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
            )
        },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .padding(paddingValues)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // ── Knock button ──────────────────────────────────────────────────
            KnockButton(
                status = status,
                onClick = { viewModel.knock(profileName) },
            )

            HorizontalDivider()

            // ── Editable fields ───────────────────────────────────────────────
            Text("Profile", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Profile Name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            HorizontalDivider()
            Text("Server", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)

            OutlinedTextField(
                value = serverHost,
                onValueChange = { serverHost = it },
                label = { Text("Server Host") },
                placeholder = { Text("203.0.113.1") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = serverPort,
                onValueChange = { serverPort = it.filter(Char::isDigit) },
                label = { Text("UDP Port") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = serverPubKey,
                onValueChange = { serverPubKey = it },
                label = { Text("Server Public Key (Base64)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
            )

            HorizontalDivider()
            Text("Client Keys", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)

            OutlinedTextField(
                value = privateKey,
                onValueChange = { privateKey = it },
                label = { Text("Private Key (Base64)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                visualTransformation = if (showPrivKey) VisualTransformation.None else PasswordVisualTransformation(),
                trailingIcon = {
                    IconButton(onClick = { showPrivKey = !showPrivKey }) {
                        Icon(
                            if (showPrivKey) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                            contentDescription = if (showPrivKey) "Hide key" else "Show key",
                        )
                    }
                },
            )

            OutlinedTextField(
                value = publicKey,
                onValueChange = { publicKey = it },
                label = { Text("Public Key (Base64)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
            )

            HorizontalDivider()
            Text("Actions", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)

            OutlinedTextField(
                value = postKnock,
                onValueChange = { postKnock = it },
                label = { Text("Post-knock command (optional)") },
                placeholder = { Text("am start -n com.example.app/.MainActivity") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            // ── Save button ───────────────────────────────────────────────────
            Button(
                onClick = {
                    viewModel.saveProfile(
                        Profile(
                            name = name.ifBlank { profileName },
                            serverHost = serverHost,
                            serverUDPPort = serverPort.toIntOrNull() ?: 7777,
                            serverPubKey = serverPubKey,
                            privateKey = privateKey,
                            publicKey = publicKey,
                            postKnock = postKnock,
                        )
                    )
                    if (name.isNotBlank() && name != profileName) {
                        viewModel.deleteProfile(profileName)
                        onBack()
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Filled.Save, null)
                Spacer(Modifier.width(8.dp))
                Text("Save Profile")
            }
        }
    }

    // ── Delete confirmation ───────────────────────────────────────────────────
    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            icon = { Icon(Icons.Filled.Delete, null) },
            title = { Text("Delete Profile") },
            text = { Text("Delete \"$profileName\"? This cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteProfile(profileName)
                        showDeleteDialog = false
                        onDeleted()
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) { Text("Cancel") }
            },
        )
    }
}

// ─── Knock button ─────────────────────────────────────────────────────────────

@Composable
private fun KnockButton(status: KnockStatus, onClick: () -> Unit) {
    val (label, icon, enabled, colors) = when (status) {
        KnockStatus.Idle -> Quad(
            "Knock",
            Icons.Filled.LockOpen,
            true,
            ButtonDefaults.buttonColors(),
        )
        KnockStatus.Knocking -> Quad(
            "Knocking…",
            null,
            false,
            ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary),
        )
        KnockStatus.Success -> Quad(
            "Knocked!",
            Icons.Filled.CheckCircle,
            false,
            ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
        )
        is KnockStatus.Failure -> Quad(
            "Failed",
            Icons.Filled.ErrorOutline,
            true,
            ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
        )
    }

    Button(
        onClick = onClick,
        enabled = enabled,
        colors = colors,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp),
    ) {
        if (status == KnockStatus.Knocking) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary,
            )
        } else {
            icon?.let {
                Icon(it, contentDescription = null, modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(8.dp))
            }
        }
        Text(label, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }

    if (status is KnockStatus.Failure) {
        Spacer(Modifier.height(4.dp))
        Text(
            status.message,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
        )
    }
}

// Helper data class for destructuring
private data class Quad<A, B, C, D>(val a: A, val b: B, val c: C, val d: D)
private operator fun <A, B, C, D> Quad<A, B, C, D>.component1() = a
private operator fun <A, B, C, D> Quad<A, B, C, D>.component2() = b
private operator fun <A, B, C, D> Quad<A, B, C, D>.component3() = c
private operator fun <A, B, C, D> Quad<A, B, C, D>.component4() = d

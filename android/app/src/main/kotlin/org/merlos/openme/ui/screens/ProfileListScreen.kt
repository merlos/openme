package org.merlos.openme.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.SwipeToDismissBoxValue.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.merlos.openme.ui.KnockStatus
import org.merlos.openme.ui.ProfileViewModel
import org.merlos.openmekit.ProfileEntry

/**
 * Profile list screen — the app's home screen.
 *
 * Displays all saved profiles in a [LazyColumn]. Each row shows the profile name,
 * server host : port, and a colour-coded knock status indicator.
 *
 * ### Gestures
 * - **Swipe left** → Delete profile (with confirmation snackbar undo).
 * - **Swipe right** → Knock immediately.
 *
 * ### Toolbar
 * - **+** FAB / menu → Add profile (via QR scan or YAML paste).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileListScreen(
    viewModel: ProfileViewModel,
    onProfileClick: (String) -> Unit,
    onImportClick: (startOnQr: Boolean) -> Unit,
) {
    val profiles by viewModel.profileEntries.collectAsStateWithLifecycle()
    val knockStatuses by viewModel.knockStatuses.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var showAddMenu by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("openme", fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
            )
        },
        floatingActionButton = {
            Box {
                FloatingActionButton(
                    onClick = { showAddMenu = true },
                    containerColor = MaterialTheme.colorScheme.primary,
                ) {
                    Icon(Icons.Filled.Add, contentDescription = "Add profile")
                }
                DropdownMenu(
                    expanded = showAddMenu,
                    onDismissRequest = { showAddMenu = false },
                ) {
                    DropdownMenuItem(
                        text = { Text("Scan QR Code") },
                        leadingIcon = { Icon(Icons.Outlined.QrCodeScanner, null) },
                        onClick = {
                            showAddMenu = false
                            onImportClick(true)
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("Paste YAML Config") },
                        leadingIcon = { Icon(Icons.Outlined.Description, null) },
                        onClick = {
                            showAddMenu = false
                            onImportClick(false)
                        },
                    )
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { paddingValues ->
        if (profiles.isEmpty()) {
            EmptyState(
                modifier = Modifier.padding(paddingValues),
                onScanQr = { onImportClick(true) },
                onPasteYaml = { onImportClick(false) },
            )
        } else {
            LazyColumn(
                contentPadding = paddingValues,
                modifier = Modifier.fillMaxSize(),
            ) {
                items(profiles, key = { it.id }) { entry ->
                    val status = knockStatuses[entry.name] ?: KnockStatus.Idle
                    SwipeableProfileRow(
                        entry = entry,
                        status = status,
                        onClick = { onProfileClick(entry.name) },
                        onKnock = { viewModel.knock(entry.name) },
                        onDelete = {
                            viewModel.deleteProfile(entry.name)
                        },
                    )
                    HorizontalDivider(thickness = 0.5.dp)
                }
            }
        }
    }
}

// ─── Row ─────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeableProfileRow(
    entry: ProfileEntry,
    status: KnockStatus,
    onClick: () -> Unit,
    onKnock: () -> Unit,
    onDelete: () -> Unit,
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                EndToStart -> { onDelete(); true }
                StartToEnd -> { onKnock(); false } // reset after knock
                Settled -> false
            }
        },
        positionalThreshold = { it * 0.4f },
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = { SwipeBackground(dismissState.targetValue) },
        content = {
            ProfileRow(entry = entry, status = status, onClick = onClick)
        },
    )
}

@Composable
private fun ProfileRow(
    entry: ProfileEntry,
    status: KnockStatus,
    onClick: () -> Unit,
) {
    ListItem(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .clickable { onClick() },
        headlineContent = {
            Text(
                entry.name,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        },
        supportingContent = {
            Text(
                "${entry.serverHost}:${entry.serverUDPPort}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        trailingContent = { KnockStatusChip(status) },
        tonalElevation = 0.dp,
    )
}

@Composable
private fun KnockStatusChip(status: KnockStatus) {
    AnimatedVisibility(
        visible = status != KnockStatus.Idle,
        enter = fadeIn(tween(150)),
        exit = fadeOut(tween(600)),
    ) {
        when (status) {
            KnockStatus.Knocking -> CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
            )
            KnockStatus.Success -> Icon(
                Icons.Filled.CheckCircle,
                contentDescription = "Knock succeeded",
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp),
            )
            is KnockStatus.Failure -> Icon(
                Icons.Filled.ErrorOutline,
                contentDescription = "Knock failed: ${status.message}",
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(20.dp),
            )
            else -> Unit
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeBackground(direction: SwipeToDismissBoxValue) {
    val (color, icon, align) = when (direction) {
        StartToEnd -> Triple(
            MaterialTheme.colorScheme.primaryContainer,
            Icons.Filled.LockOpen,
            Alignment.CenterStart,
        )
        EndToStart -> Triple(
            MaterialTheme.colorScheme.errorContainer,
            Icons.Filled.Delete,
            Alignment.CenterEnd,
        )
        Settled -> Triple(Color.Transparent, null, Alignment.Center)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(color)
            .padding(horizontal = 24.dp),
        contentAlignment = align,
    ) {
        icon?.let {
            Icon(
                it,
                contentDescription = null,
                tint = if (direction == EndToStart)
                    MaterialTheme.colorScheme.onErrorContainer
                else MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
    }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

@Composable
private fun EmptyState(
    modifier: Modifier = Modifier,
    onScanQr: () -> Unit,
    onPasteYaml: () -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Outlined.LockOpen,
            contentDescription = null,
            modifier = Modifier.size(72.dp),
            tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f),
        )
        Spacer(Modifier.height(16.dp))
        Text(
            "No profiles yet",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "Import a profile to start knocking.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(32.dp))
        Button(onClick = onScanQr) {
            Icon(Icons.Outlined.QrCodeScanner, null)
            Spacer(Modifier.width(8.dp))
            Text("Scan QR Code")
        }
        Spacer(Modifier.height(12.dp))
        OutlinedButton(onClick = onPasteYaml) {
            Icon(Icons.Outlined.Description, null)
            Spacer(Modifier.width(8.dp))
            Text("Paste YAML Config")
        }
    }
}

package org.merlos.openme.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.merlos.openmekit.ClientConfigParser
import org.merlos.openmekit.KnockManager
import org.merlos.openmekit.KnockResult
import org.merlos.openmekit.Profile
import org.merlos.openmekit.ProfileEntry
import org.merlos.openmekit.ProfileStore

/**
 * Status of an in-progress or recently completed knock attempt for a profile row.
 */
sealed class KnockStatus {
    object Idle : KnockStatus()
    object Knocking : KnockStatus()
    object Success : KnockStatus()
    data class Failure(val message: String) : KnockStatus()
}

/**
 * Shared ViewModel for all profile-related screens.
 *
 * Exposes:
 * - [profileEntries] — reactive list of lightweight profile summaries.
 * - [knockStatuses] — per-profile knock status (idle / in-progress / success / failure).
 * - CRUD methods: [saveProfile], [deleteProfile], [importYaml], [importQr].
 * - [knock] — triggers a SPA knock for a named profile.
 */
class ProfileViewModel(application: Application) : AndroidViewModel(application) {

    private val store = ProfileStore(application)
    private val knockManager = KnockManager(application)

    /** Ordered list of profile summaries, updated whenever the store changes. */
    val profileEntries: StateFlow<List<ProfileEntry>> = store.profileEntries
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** Per-profile knock status map (name → status). */
    private val _knockStatuses = MutableStateFlow<Map<String, KnockStatus>>(emptyMap())
    val knockStatuses: StateFlow<Map<String, KnockStatus>> = _knockStatuses

    /** Error message for import operations (null when no error). */
    private val _importError = MutableStateFlow<String?>(null)
    val importError: StateFlow<String?> = _importError

    // ─── Knock ────────────────────────────────────────────────────────────────

    /**
     * Sends a SPA knock for the named profile, updating [knockStatuses] reactively.
     * Status resets to [KnockStatus.Idle] after [clearAfterMs] milliseconds.
     */
    fun knock(profileName: String, clearAfterMs: Long = 3_000L) {
        viewModelScope.launch {
            setStatus(profileName, KnockStatus.Knocking)
            val result = knockManager.knock(profileName)
            val newStatus = when (result) {
                is KnockResult.Success -> KnockStatus.Success
                is KnockResult.Failure -> KnockStatus.Failure(result.error.message ?: "Unknown error")
            }
            setStatus(profileName, newStatus)
            kotlinx.coroutines.delay(clearAfterMs)
            setStatus(profileName, KnockStatus.Idle)
        }
    }

    // ─── CRUD ─────────────────────────────────────────────────────────────────

    /** Saves or replaces a profile in the store. */
    fun saveProfile(profile: Profile) {
        viewModelScope.launch { store.save(profile) }
    }

    /** Deletes the profile with the given name. */
    fun deleteProfile(name: String) {
        viewModelScope.launch { store.delete(name) }
    }

    // ─── Import ───────────────────────────────────────────────────────────────

    /** Parses a YAML config string and bulk-imports all valid profiles. */
    fun importYaml(yaml: String, onSuccess: () -> Unit) {
        _importError.value = null
        viewModelScope.launch {
            try {
                val profiles = ClientConfigParser.parseYaml(yaml)
                store.saveAll(profiles)
                onSuccess()
            } catch (e: Exception) {
                _importError.value = e.message ?: "Failed to parse YAML."
            }
        }
    }

    /** Parses a QR JSON string and imports the encoded profile. */
    fun importQr(json: String, onSuccess: () -> Unit) {
        _importError.value = null
        viewModelScope.launch {
            try {
                val profile = ClientConfigParser.parseQRPayload(json)
                store.save(profile)
                onSuccess()
            } catch (e: Exception) {
                _importError.value = e.message ?: "Invalid QR code."
            }
        }
    }

    /** Clears the current import error. */
    fun clearImportError() { _importError.value = null }

    // ─── Internal ─────────────────────────────────────────────────────────────

    private fun setStatus(name: String, status: KnockStatus) {
        _knockStatuses.update { it + (name to status) }
    }
}

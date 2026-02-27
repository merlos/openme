package org.merlos.openmekit

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import org.json.JSONArray
import org.json.JSONObject

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "openme_profiles")

private val KEY_PROFILE_NAMES = stringPreferencesKey("profile_names")
private fun profileKey(name: String) = stringPreferencesKey("profile_$name")

/**
 * Persistent store for openme [Profile] objects, backed by Jetpack DataStore Preferences.
 *
 * Profiles are serialised as JSON and stored individually under per-profile preference keys.
 * An index entry (`profile_names`) keeps an ordered JSON array of names so that the list
 * order is preserved across restarts.
 *
 * ### Security note
 * DataStore Preferences is **not** encrypted by default. On devices running Android 6.0+
 * the backing file resides in app-private storage (`/data/data/<package>/files/datastore/`),
 * which is inaccessible to other apps on non-rooted devices. For additional protection on
 * Android 6+ you can wrap DataStore with the
 * [Jetpack Security EncryptedFile API](https://developer.android.com/topic/security/data).
 *
 * ### Usage
 * ```kotlin
 * val store = ProfileStore(context)
 *
 * // Add or update a profile
 * store.save(profile)
 *
 * // Observe profile list reactively
 * store.profileEntries.collect { entries -> updateUI(entries) }
 *
 * // Load a full profile for a knock
 * val profile = store.profile("my-server")
 * ```
 *
 * @param context Android [Context] — only the application context is retained internally.
 */
class ProfileStore(context: Context) {

    private val ctx = context.applicationContext

    // ─── Read ────────────────────────────────────────────────────────────────────

    /**
     * A cold [Flow] that emits an ordered list of [ProfileEntry] summaries whenever the store
     * is modified. Suitable for driving a profile list UI.
     *
     * Profile entries omit key material so they can be displayed safely.
     */
    val profileEntries: Flow<List<ProfileEntry>> = ctx.dataStore.data.map { prefs ->
        val names = parseName(prefs[KEY_PROFILE_NAMES])
        names.mapNotNull { name ->
            val json = prefs[profileKey(name)] ?: return@mapNotNull null
            deserialiseEntry(json)
        }
    }

    /**
     * Loads the full [Profile] for [name], including key material.
     *
     * @param name Profile name.
     * @return The [Profile], or `null` if not found.
     */
    suspend fun profile(name: String): Profile? {
        val prefs = ctx.dataStore.data.first()
        val json = prefs[profileKey(name)] ?: return null
        return deserialise(json)
    }

    /**
     * Returns a snapshot list of all [ProfileEntry] summaries (no key material).
     *
     * Prefer [profileEntries] for reactive UI; use this for one-shot reads.
     */
    suspend fun allEntries(): List<ProfileEntry> = profileEntries.first()

    // ─── Write ───────────────────────────────────────────────────────────────────

    /**
     * Saves or updates a [Profile] in the store.
     *
     * If a profile with the same [name][Profile.name] already exists it is silently replaced.
     * New profiles are appended to the end of the ordered list.
     *
     * @param profile The [Profile] to persist.
     */
    suspend fun save(profile: Profile) {
        ctx.dataStore.edit { prefs ->
            val names = parseName(prefs[KEY_PROFILE_NAMES]).toMutableList()
            if (!names.contains(profile.name)) names.add(profile.name)
            prefs[KEY_PROFILE_NAMES] = serialiseNames(names)
            prefs[profileKey(profile.name)] = serialise(profile)
        }
    }

    /**
     * Saves all profiles in [profiles], replacing any existing entries with the same name.
     *
     * Useful for bulk imports (e.g. loading a `config.yaml`).
     *
     * @param profiles Map of profile name → [Profile].
     */
    suspend fun saveAll(profiles: Map<String, Profile>) {
        ctx.dataStore.edit { prefs ->
            val names = parseName(prefs[KEY_PROFILE_NAMES]).toMutableList()
            for ((_, p) in profiles) {
                if (!names.contains(p.name)) names.add(p.name)
                prefs[profileKey(p.name)] = serialise(p)
            }
            prefs[KEY_PROFILE_NAMES] = serialiseNames(names)
        }
    }

    /**
     * Removes the profile with the given [name] from the store.
     *
     * No-ops silently if the profile does not exist.
     *
     * @param name Name of the profile to delete.
     */
    suspend fun delete(name: String) {
        ctx.dataStore.edit { prefs ->
            val names = parseName(prefs[KEY_PROFILE_NAMES]).toMutableList()
            names.remove(name)
            prefs[KEY_PROFILE_NAMES] = serialiseNames(names)
            prefs.remove(profileKey(name))
        }
    }

    /**
     * Renames a profile, preserving all other fields and maintaining list position.
     *
     * @param oldName Current profile name.
     * @param newName New profile name.
     */
    suspend fun rename(oldName: String, newName: String) {
        if (oldName == newName) return
        val existing = profile(oldName) ?: return
        val updated = existing.copy(name = newName)
        ctx.dataStore.edit { prefs ->
            val names = parseName(prefs[KEY_PROFILE_NAMES]).toMutableList()
            val idx = names.indexOf(oldName)
            if (idx >= 0) names[idx] = newName else names.add(newName)
            prefs.remove(profileKey(oldName))
            prefs[profileKey(newName)] = serialise(updated)
            prefs[KEY_PROFILE_NAMES] = serialiseNames(names)
        }
    }

    // ─── Serialisation ───────────────────────────────────────────────────────────

    private fun serialise(p: Profile): String = JSONObject().apply {
        put("name", p.name)
        put("serverHost", p.serverHost)
        put("serverUDPPort", p.serverUDPPort)
        put("serverPubKey", p.serverPubKey)
        put("privateKey", p.privateKey)
        put("publicKey", p.publicKey)
        put("postKnock", p.postKnock)
    }.toString()

    private fun deserialise(json: String): Profile? = try {
        val obj = JSONObject(json)
        Profile(
            name = obj.getString("name"),
            serverHost = obj.optString("serverHost"),
            serverUDPPort = obj.optInt("serverUDPPort", 54154),
            serverPubKey = obj.optString("serverPubKey"),
            privateKey = obj.optString("privateKey"),
            publicKey = obj.optString("publicKey"),
            postKnock = obj.optString("postKnock"),
        )
    } catch (_: Exception) { null }

    private fun deserialiseEntry(json: String): ProfileEntry? = try {
        val obj = JSONObject(json)
        ProfileEntry(
            name = obj.getString("name"),
            serverHost = obj.optString("serverHost"),
            serverUDPPort = obj.optInt("serverUDPPort", 54154),
        )
    } catch (_: Exception) { null }

    private fun parseName(raw: String?): List<String> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(raw)
            List(arr.length()) { arr.getString(it) }
        } catch (_: Exception) { emptyList() }
    }

    private fun serialiseNames(names: List<String>): String =
        JSONArray(names).toString()
}

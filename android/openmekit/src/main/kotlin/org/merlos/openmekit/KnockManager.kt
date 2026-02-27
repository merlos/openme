package org.merlos.openmekit

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Represents the outcome of a SPA knock attempt.
 */
sealed class KnockResult {
    /** The knock UDP datagram was dispatched successfully. */
    object Success : KnockResult()

    /** The knock failed. [error] describes the cause. */
    data class Failure(val error: KnockError) : KnockResult()
}

/**
 * High-level manager that orchestrates loading a [Profile] from [ProfileStore]
 * and invoking [KnockService] to send a SPA knock packet.
 *
 * [KnockManager] is the recommended entry point for knock operations in app code.
 * It handles coroutine dispatch, profile lookup, and error wrapping so that UI
 * layers only need to call [knock] and react to [KnockResult].
 *
 * ### Usage
 * ```kotlin
 * val manager = KnockManager(context)
 * viewModelScope.launch {
 *     val result = manager.knock("my-server")
 *     when (result) {
 *         is KnockResult.Success -> showSuccess()
 *         is KnockResult.Failure -> showError(result.error)
 *     }
 * }
 * ```
 *
 * @param context Android [Context] used to initialise the underlying [ProfileStore].
 */
class KnockManager(context: Context) {

    private val store = ProfileStore(context)

    /**
     * Loads the named profile from [ProfileStore] and sends a SPA knock packet.
     *
     * The network operation runs on [Dispatchers.IO] so this function is safe
     * to call from a coroutine on any dispatcher.
     *
     * @param profileName Name of the profile to knock with.
     * @return [KnockResult.Success] when the UDP datagram was dispatched,
     *   or [KnockResult.Failure] with a descriptive [KnockError].
     */
    suspend fun knock(profileName: String): KnockResult = withContext(Dispatchers.IO) {
        val profile = store.profile(profileName)
            ?: return@withContext KnockResult.Failure(
                KnockError.InvalidClientKey // profile not found — closest semantic error
            )
        return@withContext knock(profile)
    }

    /**
     * Sends a SPA knock for the given [Profile] directly.
     *
     * Prefer passing a profile name to [knock] for typical app use.
     * This overload is useful when you already have a loaded [Profile] instance,
     * e.g. in the profile detail screen.
     *
     * @param profile Fully populated [Profile] containing key material.
     * @return [KnockResult.Success] or [KnockResult.Failure].
     */
    suspend fun knock(profile: Profile): KnockResult = withContext(Dispatchers.IO) {
        return@withContext try {
            KnockService.knock(
                serverHost = profile.serverHost,
                serverPort = profile.serverUDPPort,
                serverPubKeyBase64 = profile.serverPubKey,
                clientPrivKeyBase64 = profile.privateKey,
            )
            KnockResult.Success
        } catch (e: KnockError) {
            KnockResult.Failure(e)
        }
    }
}

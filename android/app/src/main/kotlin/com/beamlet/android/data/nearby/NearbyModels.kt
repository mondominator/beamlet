package com.beamlet.android.data.nearby

import java.time.Instant

data class NearbyUser(
    val id: String,
    val name: String,
    val isContact: Boolean,
    val lastSeen: Instant = Instant.now(),
)

enum class DiscoverabilityMode {
    OFF,
    CONTACTS_ONLY,
    EVERYONE;

    val displayName: String
        get() = when (this) {
            OFF -> "Receiving Off"
            CONTACTS_ONLY -> "Contacts Only"
            EVERYONE -> "Everyone"
        }

    val description: String
        get() = when (this) {
            OFF -> "You won't be visible to nearby users"
            CONTACTS_ONLY -> "Only your contacts can see you nearby"
            EVERYONE -> "Anyone with Beamlet nearby can see you"
        }
}

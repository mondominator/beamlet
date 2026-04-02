package com.beamlet.android.util

import java.time.Duration
import java.time.Instant

fun formatRelativeTime(instant: Instant): String {
    val now = Instant.now()
    val duration = Duration.between(instant, now)
    val seconds = duration.seconds
    return when {
        seconds < 60 -> "just now"
        seconds < 3600 -> "${seconds / 60}m ago"
        seconds < 86400 -> "${seconds / 3600}h ago"
        seconds < 604800 -> "${seconds / 86400}d ago"
        else -> "${seconds / 604800}w ago"
    }
}

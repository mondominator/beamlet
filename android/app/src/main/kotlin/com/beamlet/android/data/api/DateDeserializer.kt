package com.beamlet.android.data.api

import com.google.gson.JsonDeserializationContext
import com.google.gson.JsonDeserializer
import com.google.gson.JsonElement
import com.google.gson.JsonPrimitive
import com.google.gson.JsonSerializationContext
import com.google.gson.JsonSerializer
import java.lang.reflect.Type
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

/**
 * Gson adapter for java.time.Instant that handles the various date formats
 * emitted by Go's time package:
 *
 * - ISO 8601 with fractional seconds: 2024-01-15T10:30:00.000Z
 * - ISO 8601 without fractional seconds: 2024-01-15T10:30:00Z
 * - Go nanosecond format: 2024-01-15T10:30:00.000000000+0000
 * - Go space-separated format: 2024-01-15 10:30:00.000000000 +0000
 * - Zero time: 0001-01-01T00:00:00Z
 */
class InstantTypeAdapter : JsonDeserializer<Instant>, JsonSerializer<Instant> {

    companion object {
        // Go's nanosecond format with timezone offset (no colon)
        private val GO_NANO_FORMATTER: DateTimeFormatter = DateTimeFormatter.ofPattern(
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSZ"
        )

        // Go's space-separated format
        private val GO_SPACE_FORMATTER: DateTimeFormatter = DateTimeFormatter.ofPattern(
            "yyyy-MM-dd HH:mm:ss.SSSSSSSSS Z"
        )
    }

    override fun deserialize(
        json: JsonElement,
        typeOfT: Type,
        context: JsonDeserializationContext,
    ): Instant? {
        val dateString = json.asString
        if (dateString.isNullOrBlank()) return null

        // Go zero time
        if (dateString.startsWith("0001-01-01")) return null

        // Try standard ISO 8601 first (handles both with and without fractional seconds)
        try {
            return Instant.parse(dateString)
        } catch (_: DateTimeParseException) {
            // Continue to next format
        }

        // Try Go nanosecond format
        try {
            val temporal = GO_NANO_FORMATTER.parse(dateString)
            return LocalDateTime.from(temporal).toInstant(ZoneOffset.UTC)
        } catch (_: DateTimeParseException) {
            // Continue to next format
        }

        // Try Go space-separated format
        try {
            val temporal = GO_SPACE_FORMATTER.parse(dateString)
            return LocalDateTime.from(temporal).toInstant(ZoneOffset.UTC)
        } catch (_: DateTimeParseException) {
            // Continue to next format
        }

        // Last resort: try trimming and re-parsing
        try {
            val trimmed = dateString.trim()
            return Instant.parse(trimmed)
        } catch (_: DateTimeParseException) {
            return null
        }
    }

    override fun serialize(
        src: Instant?,
        typeOfSrc: Type,
        context: JsonSerializationContext,
    ): JsonElement? {
        return src?.let { JsonPrimitive(it.toString()) }
    }
}

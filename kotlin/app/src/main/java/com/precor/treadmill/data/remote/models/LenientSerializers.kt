package com.precor.treadmill.data.remote.models

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.nullable
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

/**
 * Deserializes booleans leniently: accepts true/false, 0/1, "true"/"false", "0"/"1".
 * Postel's Law: be liberal in what you accept.
 */
object LenientBoolSerializer : KSerializer<Boolean> {
    override val descriptor = PrimitiveSerialDescriptor("LenientBool", PrimitiveKind.BOOLEAN)

    override fun deserialize(decoder: Decoder): Boolean {
        if (decoder is JsonDecoder) {
            val element = decoder.decodeJsonElement()
            if (element is JsonPrimitive) {
                element.booleanOrNull?.let { return it }
                element.intOrNull?.let { return it != 0 }
                element.content.let { s ->
                    return s.equals("true", ignoreCase = true) || s == "1"
                }
            }
        }
        return decoder.decodeBoolean()
    }

    override fun serialize(encoder: Encoder, value: Boolean) = encoder.encodeBoolean(value)
}

/**
 * Nullable variant of [LenientBoolSerializer] for Boolean? fields.
 * Returns null for JSON null, otherwise delegates to the same lenient logic.
 */
object LenientNullableBoolSerializer : KSerializer<Boolean?> {
    override val descriptor = PrimitiveSerialDescriptor("LenientNullableBool", PrimitiveKind.BOOLEAN).nullable

    override fun deserialize(decoder: Decoder): Boolean? {
        if (decoder is JsonDecoder) {
            val element = decoder.decodeJsonElement()
            if (element is kotlinx.serialization.json.JsonNull) return null
            if (element is JsonPrimitive) {
                element.booleanOrNull?.let { return it }
                element.intOrNull?.let { return it != 0 }
                element.content.let { s ->
                    return s.equals("true", ignoreCase = true) || s == "1"
                }
            }
        }
        return decoder.decodeBoolean()
    }

    @OptIn(ExperimentalSerializationApi::class)
    override fun serialize(encoder: Encoder, value: Boolean?) {
        if (value == null) encoder.encodeNull() else encoder.encodeBoolean(value)
    }
}

/**
 * Deserializes Int leniently: accepts 1, 1.0, "1".
 * Handles the case where the server sends a float for what should be an int.
 */
object LenientIntSerializer : KSerializer<Int> {
    override val descriptor = PrimitiveSerialDescriptor("LenientInt", PrimitiveKind.INT)

    override fun deserialize(decoder: Decoder): Int {
        if (decoder is JsonDecoder) {
            val element = decoder.decodeJsonElement()
            if (element is JsonPrimitive) {
                element.intOrNull?.let { return it }
                element.content.toDoubleOrNull()?.let { return it.toInt() }
            }
        }
        return decoder.decodeInt()
    }

    override fun serialize(encoder: Encoder, value: Int) = encoder.encodeInt(value)
}

/**
 * Deserializes String leniently: accepts "foo", 123, 1.5, true, null → "".
 * Handles IDs that come as integers, booleans serialized as strings, etc.
 */
object LenientStringSerializer : KSerializer<String> {
    override val descriptor = PrimitiveSerialDescriptor("LenientString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        if (decoder is JsonDecoder) {
            val element = decoder.decodeJsonElement()
            if (element is kotlinx.serialization.json.JsonNull) return ""
            if (element is JsonPrimitive) return element.content
        }
        return decoder.decodeString()
    }

    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
}

/**
 * Deserializes Double leniently: accepts 1.5, 1, "1.5".
 * Handles the case where the server sends an int for what should be a double.
 */
object LenientDoubleSerializer : KSerializer<Double> {
    override val descriptor = PrimitiveSerialDescriptor("LenientDouble", PrimitiveKind.DOUBLE)

    override fun deserialize(decoder: Decoder): Double {
        if (decoder is JsonDecoder) {
            val element = decoder.decodeJsonElement()
            if (element is JsonPrimitive) {
                element.content.toDoubleOrNull()?.let { return it }
            }
        }
        return decoder.decodeDouble()
    }

    override fun serialize(encoder: Encoder, value: Double) = encoder.encodeDouble(value)
}

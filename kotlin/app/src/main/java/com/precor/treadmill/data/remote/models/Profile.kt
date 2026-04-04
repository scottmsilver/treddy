package com.precor.treadmill.data.remote.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Profile(
    val id: String = "",
    val name: String = "",
    val color: String = "#d4c4a8",
    val initials: String = "?",
    @SerialName("weight_lbs") val weightLbs: Double = 154.0,
    @SerialName("vest_lbs") val vestLbs: Double = 0.0,
    @SerialName("has_avatar") val hasAvatar: Boolean = false,
)

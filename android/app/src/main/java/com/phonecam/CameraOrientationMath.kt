package com.phonecam

internal object CameraOrientationMath {
    fun relativeRotation(
        sensorOrientationDegrees: Int,
        displayRotationDegrees: Int,
        isFrontFacing: Boolean
    ): Int {
        val sign = if (isFrontFacing) 1 else -1
        return normalizeDegrees(sensorOrientationDegrees - displayRotationDegrees * sign)
    }

    fun normalizeDegrees(degrees: Int): Int {
        return ((degrees % 360) + 360) % 360
    }
}

package com.phonecam

import org.junit.Assert.assertEquals
import org.junit.Test

class CameraOrientationMathTest {
    @Test
    fun relativeRotationUsesCamera2FormulaForFrontFacingCameras() {
        assertEquals(270, CameraOrientationMath.relativeRotation(270, 0, isFrontFacing = true))
        assertEquals(180, CameraOrientationMath.relativeRotation(270, 90, isFrontFacing = true))
        assertEquals(90, CameraOrientationMath.relativeRotation(270, 180, isFrontFacing = true))
        assertEquals(0, CameraOrientationMath.relativeRotation(270, 270, isFrontFacing = true))
    }

    @Test
    fun relativeRotationReversesDisplayRotationForBackFacingCameras() {
        assertEquals(90, CameraOrientationMath.relativeRotation(90, 0, isFrontFacing = false))
        assertEquals(180, CameraOrientationMath.relativeRotation(90, 90, isFrontFacing = false))
        assertEquals(270, CameraOrientationMath.relativeRotation(90, 180, isFrontFacing = false))
        assertEquals(0, CameraOrientationMath.relativeRotation(90, 270, isFrontFacing = false))
    }

    @Test
    fun normalizeDegreesWrapsNegativeAndLargeValues() {
        assertEquals(270, CameraOrientationMath.normalizeDegrees(-90))
        assertEquals(90, CameraOrientationMath.normalizeDegrees(450))
        assertEquals(0, CameraOrientationMath.normalizeDegrees(720))
    }
}

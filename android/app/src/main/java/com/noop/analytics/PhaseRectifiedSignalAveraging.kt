package com.noop.analytics

/*
 * PhaseRectifiedSignalAveraging.kt - experimental PRSA DC/AC over cleaned NN intervals.
 * Behavioral twin of StrandAnalytics/PhaseRectifiedSignalAveraging.swift.
 *
 * EXPERIMENTAL / RESEARCH METRIC ONLY. No risk tier, diagnosis, or score input.
 * PPG-derived RR/PRV is not assumed equivalent to clinical ECG NN intervals.
 */
object PhaseRectifiedSignalAveraging {

    enum class Kind { DECELERATION, ACCELERATION }

    const val DEFAULT_ANCHOR_RATIO_CAP: Double = 0.05
    const val MINIMUM_RADIUS: Int = 2

    data class Result(
        val capacityMs: Double,
        val profileMs: List<Double>,
        val anchorCount: Int,
        val kind: Kind,
        val radius: Int,
        val anchorRatioCap: Double,
        val rejectedLargeChangeAnchors: Int,
    )

    fun decelerationCapacity(
        cleanedNNMs: List<Double>,
        radius: Int = MINIMUM_RADIUS,
        anchorRatioCap: Double = DEFAULT_ANCHOR_RATIO_CAP,
        minimumAnchors: Int = 1,
    ): Result? = evaluate(
        cleanedNNMs, Kind.DECELERATION, radius, anchorRatioCap, minimumAnchors
    )

    fun accelerationCapacity(
        cleanedNNMs: List<Double>,
        radius: Int = MINIMUM_RADIUS,
        anchorRatioCap: Double = DEFAULT_ANCHOR_RATIO_CAP,
        minimumAnchors: Int = 1,
    ): Result? = evaluate(
        cleanedNNMs, Kind.ACCELERATION, radius, anchorRatioCap, minimumAnchors
    )

    fun evaluate(
        cleanedNNMs: List<Double>,
        kind: Kind,
        radius: Int = MINIMUM_RADIUS,
        anchorRatioCap: Double = DEFAULT_ANCHOR_RATIO_CAP,
        minimumAnchors: Int = 1,
    ): Result? {
        if (radius < MINIMUM_RADIUS ||
            !anchorRatioCap.isFinite() ||
            anchorRatioCap < 0.0 ||
            minimumAnchors <= 0 ||
            cleanedNNMs.size < 2 * radius + 1 ||
            cleanedNNMs.any { !it.isFinite() || it <= 0.0 }
        ) return null

        val anchors = ArrayList<Int>()
        var rejectedLarge = 0
        for (i in radius until cleanedNNMs.size - radius) {
            val previous = cleanedNNMs[i - 1]
            val current = cleanedNNMs[i]
            val delta = current - previous
            val directional = if (kind == Kind.DECELERATION) delta > 0.0 else delta < 0.0
            if (!directional) continue

            val ratio = kotlin.math.abs(current / previous - 1.0)
            if (ratio > anchorRatioCap) {
                rejectedLarge++
                continue
            }
            anchors.add(i)
        }
        if (anchors.size < minimumAnchors) return null

        val profile = DoubleArray(2 * radius)
        for (anchor in anchors) {
            for (k in -radius until radius) {
                profile[k + radius] += cleanedNNMs[anchor + k]
            }
        }
        val anchorDenominator = anchors.size.toDouble()
        for (i in profile.indices) profile[i] /= anchorDenominator

        val x0 = profile[radius]
        val x1 = profile[radius + 1]
        val xm1 = profile[radius - 1]
        val xm2 = profile[radius - 2]
        val capacity = (x0 + x1 - xm1 - xm2) / 4.0
        if (!capacity.isFinite()) return null

        return Result(
            capacityMs = capacity,
            profileMs = profile.toList(),
            anchorCount = anchors.size,
            kind = kind,
            radius = radius,
            anchorRatioCap = anchorRatioCap,
            rejectedLargeChangeAnchors = rejectedLarge,
        )
    }
}

package com.noop.analytics

/**
 * Keeps the R-R audit's stable cross-platform wire mapping readable while the native Android coverage
 * verdict remains nested under HrvAnalyzer. No new semantics: this is exactly the upstream analyzer enum.
 */
internal typealias RrCoverageVerdict = HrvAnalyzer.RrCoverageVerdict

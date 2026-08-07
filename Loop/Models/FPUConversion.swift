//
//  FPUConversion.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

/// Converts the fat and protein content of a meal into a delayed carb-equivalent entry,
/// following the Warsaw method (Pańkowska equation): 1 fat-protein unit (FPU) is 100 kcal
/// of fat and protein, dosed like 10 g of carbohydrate.
///
/// The equivalent entry starts one hour after the meal, so it adds nothing to the meal's
/// bolus recommendation. It does enter Loop's forecast as soon as it is saved, so
/// automatic dosing (temp basal or partial automatic boluses) begins working toward the
/// predicted rise ahead of absorption, and dynamic carb absorption stretches or trims the
/// remainder to match the observed glucose response. No insulin is scheduled or bolused
/// up front, but delivery is anticipatory — unlike Trio, whose algorithm cannot see a
/// future-dated entry until its timestamp arrives.
enum FPUConversion {
    static let kilocaloriesPerGramOfFat: Double = 9
    static let kilocaloriesPerGramOfProtein: Double = 4
    static let kilocaloriesPerFPU: Double = 100
    static let carbGramsPerFPU: Double = 10

    /// Equivalents smaller than this are dropped: meals this small need no extra insulin,
    /// and dosing them increases hypoglycemia risk.
    static let minimumEquivalentGrams: Double = 10

    /// Upper bound on the size of an equivalent entry.
    static let maximumEquivalentGrams: Double = 99

    /// How long after the meal the equivalent entry starts. Matches Trio's default FPU
    /// delay and the farthest future date the carb entry UI itself allows. A meal itself
    /// dated up to 1 h ahead yields an equivalent up to 2 h ahead; the store and the
    /// algorithm accept that (the +1 h limit is UI/remote validation only), but the entry
    /// stays outside the carb status list until it comes within an hour of now.
    static let equivalentEntryDelay: TimeInterval = LoopConstants.maxCarbEntryFutureTime

    /// Fraction of the full Warsaw insulin equivalence to apply. Full-strength dosing
    /// (1.0) produced hypoglycemia in roughly half of study subjects; half strength is the
    /// widely used correction.
    static let defaultAdjustmentFactor: Double = 0.5
    static let adjustmentFactorRange: ClosedRange<Double> = 0.1...1.0

    /// Food type that marks an equivalent entry, so it is recognizable in the carb entry
    /// list and can be cleaned up when its meal entry is deleted.
    static let equivalentFoodType = "FPU 🍽️"

    static func fatProteinKilocalories(fatGrams: Double, proteinGrams: Double) -> Double {
        return max(0, fatGrams) * kilocaloriesPerGramOfFat + max(0, proteinGrams) * kilocaloriesPerGramOfProtein
    }

    static func fpuCount(fatGrams: Double, proteinGrams: Double) -> Double {
        return fatProteinKilocalories(fatGrams: fatGrams, proteinGrams: proteinGrams) / kilocaloriesPerFPU
    }

    /// The whole-gram carb equivalent before the minimum and maximum are applied,
    /// truncated toward zero. Used for display, so the calculation can be shown even
    /// when it lands below the minimum.
    static func rawCarbEquivalentGrams(fatGrams: Double, proteinGrams: Double, adjustmentFactor: Double) -> Double {
        let kilocalories = fatProteinKilocalories(fatGrams: fatGrams, proteinGrams: proteinGrams)
        return (kilocalories / kilocaloriesPerFPU * carbGramsPerFPU * adjustmentFactor).rounded(.down)
    }

    /// The whole-gram carb equivalent of a meal's fat and protein, truncated toward zero,
    /// or nil when it falls below the minimum worth dosing.
    static func carbEquivalentGrams(fatGrams: Double, proteinGrams: Double, adjustmentFactor: Double) -> Double? {
        let grams = rawCarbEquivalentGrams(fatGrams: fatGrams, proteinGrams: proteinGrams, adjustmentFactor: adjustmentFactor)
        guard grams >= minimumEquivalentGrams else {
            return nil
        }
        return min(grams, maximumEquivalentGrams)
    }

    /// Absorption time to enter for the equivalent entry: the Warsaw extended-bolus
    /// duration for the FPU count (1 FPU → 3 h, 2 → 4 h, 3 → 5 h, above 3 → 8 h), divided
    /// by the algorithm's absorption time overrun so that the modeled absorption window
    /// matches the Warsaw duration.
    static func absorptionTime(fpuCount: Double) -> TimeInterval {
        let warsawDuration: TimeInterval
        switch fpuCount {
        case ..<1.5:
            warsawDuration = .hours(3)
        case ..<2.5:
            warsawDuration = .hours(4)
        case ..<3.5:
            warsawDuration = .hours(5)
        default:
            warsawDuration = .hours(8)
        }
        let enteredDuration = warsawDuration / CarbMath.defaultAbsorptionTimeOverrun
        return enteredDuration.clamped(to: LoopConstants.minCarbAbsorptionTime...LoopConstants.maxCarbAbsorptionTime)
    }

    /// Builds the delayed carb-equivalent entry for a meal, or nil when its fat and
    /// protein don't amount to enough to dose.
    static func carbEquivalentEntry(
        fatGrams: Double?,
        proteinGrams: Double?,
        adjustmentFactor: Double,
        mealStartDate: Date,
        date: Date = Date()
    ) -> NewCarbEntry? {
        let fat = fatGrams ?? 0
        let protein = proteinGrams ?? 0
        guard let grams = carbEquivalentGrams(fatGrams: fat, proteinGrams: protein, adjustmentFactor: adjustmentFactor) else {
            return nil
        }
        return NewCarbEntry(
            date: date,
            quantity: HKQuantity(unit: .gram(), doubleValue: grams),
            startDate: mealStartDate.addingTimeInterval(equivalentEntryDelay),
            foodType: equivalentFoodType,
            absorptionTime: absorptionTime(fpuCount: fpuCount(fatGrams: fat, proteinGrams: protein))
        )
    }
}

extension TimeInterval {
    fileprivate func clamped(to range: ClosedRange<TimeInterval>) -> TimeInterval {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

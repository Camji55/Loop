//
//  MacroAbsorptionModel.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Derives a carb absorption time from a meal's macronutrients using Fat-Protein Units (the "Warsaw method").
///
/// 1 FPU = 100 kcal from fat + protein (fat 9 kcal/g, protein 4 kcal/g). The more fat/protein in a meal, the longer
/// carbs tend to take to absorb, so absorption starts at the configured *medium* default and extends by
/// `hoursPerFatProteinUnit` per FPU, clamped to Loop's supported absorption range.
///
/// This is a transparent, tunable heuristic — adjust the constants below.
enum MacroAbsorptionModel {
    static let caloriesPerFatProteinUnit: Double = 100
    static let caloriesPerGramFat: Double = 9
    static let caloriesPerGramProtein: Double = 4

    /// Additional carb absorption time per Fat-Protein Unit.
    static let hoursPerFatProteinUnit: Double = 1.0

    /// The number of Fat-Protein Units in a meal.
    static func fatProteinUnits(fatGrams: Double, proteinGrams: Double) -> Double {
        let calories = max(0, fatGrams) * caloriesPerGramFat + max(0, proteinGrams) * caloriesPerGramProtein
        return calories / caloriesPerFatProteinUnit
    }

    /// The derived carb absorption time for a meal, clamped to Loop's supported range.
    ///
    /// - Parameters:
    ///   - fatGrams: Total fat in the meal, in grams.
    ///   - proteinGrams: Total protein in the meal, in grams.
    ///   - defaultAbsorptionTimes: The user's configured fast/medium/slow defaults; `medium` is used as the base.
    static func absorptionTime(
        fatGrams: Double,
        proteinGrams: Double,
        defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes,
        minAbsorptionTime: TimeInterval = LoopConstants.minCarbAbsorptionTime,
        maxAbsorptionTime: TimeInterval = LoopConstants.maxCarbAbsorptionTime
    ) -> TimeInterval {
        let fpu = fatProteinUnits(fatGrams: fatGrams, proteinGrams: proteinGrams)
        let derived = defaultAbsorptionTimes.medium + fpu * .hours(hoursPerFatProteinUnit)
        return min(max(derived, minAbsorptionTime), maxAbsorptionTime)
    }
}

//
//  FPUConversionTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit

@testable import Loop

class FPUConversionTests: XCTestCase {

    // MARK: - Kilocalories and FPU count

    func testFatProteinKilocalories() {
        XCTAssertEqual(FPUConversion.fatProteinKilocalories(fatGrams: 30, proteinGrams: 25), 370)
        XCTAssertEqual(FPUConversion.fatProteinKilocalories(fatGrams: 0, proteinGrams: 0), 0)
        XCTAssertEqual(FPUConversion.fatProteinKilocalories(fatGrams: 10, proteinGrams: 0), 90)
        XCTAssertEqual(FPUConversion.fatProteinKilocalories(fatGrams: 0, proteinGrams: 10), 40)
    }

    func testNegativeInputsAreTreatedAsZero() {
        XCTAssertEqual(FPUConversion.fatProteinKilocalories(fatGrams: -10, proteinGrams: 25), 100)
        XCTAssertNil(FPUConversion.carbEquivalentGrams(fatGrams: -50, proteinGrams: -50, adjustmentFactor: 1.0))
    }

    func testFPUCount() {
        XCTAssertEqual(FPUConversion.fpuCount(fatGrams: 30, proteinGrams: 25), 3.7, accuracy: 0.0001)
        XCTAssertEqual(FPUConversion.fpuCount(fatGrams: 11.1, proteinGrams: 0), 0.999, accuracy: 0.0001)
    }

    // MARK: - Carb equivalent grams (Trio formula parity)

    func testWorkedPizzaExample() {
        // 50 g carb / 30 g fat / 25 g protein pizza: 370 kcal = 3.7 FPU.
        // At the 50% default factor: floor(37 × 0.5) = 18 g — matching Trio's output.
        XCTAssertEqual(FPUConversion.carbEquivalentGrams(fatGrams: 30, proteinGrams: 25, adjustmentFactor: 0.5), 18)
    }

    func testTruncationTowardZero() {
        // 390 kcal → 39 g at 100%; × 0.5 = 19.5 → truncates to 19, not rounds to 20
        XCTAssertEqual(FPUConversion.carbEquivalentGrams(fatGrams: 30, proteinGrams: 30, adjustmentFactor: 0.5), 19)
    }

    func testMinimumEquivalentIsDropped() {
        // 199 kcal at 50% → floor(9.95) = 9 g, below the 10 g minimum → nil
        XCTAssertNil(FPUConversion.carbEquivalentGrams(fatGrams: 19, proteinGrams: 7, adjustmentFactor: 0.5))

        // 200 kcal at 50% → exactly 10 g → kept
        XCTAssertEqual(FPUConversion.carbEquivalentGrams(fatGrams: 20, proteinGrams: 5, adjustmentFactor: 0.5), 10)
    }

    func testMaximumEquivalentIsCapped() {
        // 250 g fat = 2250 kcal → 225 g at 100%, capped at 99 g
        XCTAssertEqual(FPUConversion.carbEquivalentGrams(fatGrams: 250, proteinGrams: 0, adjustmentFactor: 1.0), 99)
    }

    func testRawEquivalentIsUnfloored() {
        // The display value shows the truncated equivalent even below the minimum and above the cap
        XCTAssertEqual(FPUConversion.rawCarbEquivalentGrams(fatGrams: 10, proteinGrams: 0, adjustmentFactor: 0.5), 4)
        XCTAssertEqual(FPUConversion.rawCarbEquivalentGrams(fatGrams: 250, proteinGrams: 0, adjustmentFactor: 1.0), 225)
        XCTAssertEqual(FPUConversion.rawCarbEquivalentGrams(fatGrams: 0, proteinGrams: 0, adjustmentFactor: 0.5), 0)
    }

    // MARK: - Absorption time (Warsaw durations, adjusted for the modeling overrun)

    func testAbsorptionTimeMapping() {
        let overrun = 1.5

        // 1 FPU → 3 h Warsaw duration
        XCTAssertEqual(FPUConversion.absorptionTime(fpuCount: 1.0), .hours(3) / overrun, accuracy: 1)
        // 2 FPU → 4 h
        XCTAssertEqual(FPUConversion.absorptionTime(fpuCount: 2.0), .hours(4) / overrun, accuracy: 1)
        // 3 FPU → 5 h
        XCTAssertEqual(FPUConversion.absorptionTime(fpuCount: 3.0), .hours(5) / overrun, accuracy: 1)
        // Above 3 FPU → 8 h
        XCTAssertEqual(FPUConversion.absorptionTime(fpuCount: 3.7), .hours(8) / overrun, accuracy: 1)
        XCTAssertEqual(FPUConversion.absorptionTime(fpuCount: 10), .hours(8) / overrun, accuracy: 1)
    }

    func testAbsorptionTimeBoundaries() {
        // Fractional counts round to the nearest whole FPU tier
        XCTAssertEqual(FPUConversion.absorptionTime(fpuCount: 1.4), .hours(3) / 1.5, accuracy: 1)
        XCTAssertEqual(FPUConversion.absorptionTime(fpuCount: 1.5), .hours(4) / 1.5, accuracy: 1)
        XCTAssertEqual(FPUConversion.absorptionTime(fpuCount: 3.4), .hours(5) / 1.5, accuracy: 1)
        XCTAssertEqual(FPUConversion.absorptionTime(fpuCount: 3.5), .hours(8) / 1.5, accuracy: 1)
    }

    func testAbsorptionTimeStaysWithinLoopLimits() {
        for fpuCount in stride(from: 0.0, through: 20.0, by: 0.5) {
            let time = FPUConversion.absorptionTime(fpuCount: fpuCount)
            XCTAssertGreaterThanOrEqual(time, LoopConstants.minCarbAbsorptionTime)
            XCTAssertLessThanOrEqual(time, LoopConstants.maxCarbAbsorptionTime)
        }
    }

    // MARK: - Equivalent entry construction

    func testCarbEquivalentEntry() {
        let mealDate = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = FPUConversion.carbEquivalentEntry(
            fatGrams: 30,
            proteinGrams: 25,
            adjustmentFactor: 0.5,
            mealStartDate: mealDate
        )

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.quantity.doubleValue(for: .gram()), 18)
        XCTAssertEqual(entry?.startDate, mealDate.addingTimeInterval(.hours(1)))
        XCTAssertEqual(entry?.foodType, FPUConversion.equivalentFoodType)
        XCTAssertEqual(entry!.absorptionTime!, .hours(8) / 1.5, accuracy: 1)
    }

    func testCarbEquivalentEntryDating() {
        // The equivalent is dated relative to the MEAL time, not to now. A meal itself
        // future-dated to the picker's +1 h limit therefore yields an equivalent at +2 h
        // from now — accepted by the store and algorithm by design (the +1 h limit is
        // UI/remote validation only). The delay itself must not exceed the future-dating
        // limit so that a now-dated meal produces a UI-valid equivalent.
        XCTAssertLessThanOrEqual(FPUConversion.equivalentEntryDelay, LoopConstants.maxCarbEntryFutureTime)

        let futureMealDate = Date().addingTimeInterval(LoopConstants.maxCarbEntryFutureTime)
        let entry = FPUConversion.carbEquivalentEntry(fatGrams: 30, proteinGrams: 25, adjustmentFactor: 0.5, mealStartDate: futureMealDate)
        XCTAssertEqual(entry?.startDate, futureMealDate.addingTimeInterval(FPUConversion.equivalentEntryDelay))
    }

    func testNoEntryForSmallMeals() {
        XCTAssertNil(FPUConversion.carbEquivalentEntry(fatGrams: 5, proteinGrams: 5, adjustmentFactor: 0.5, mealStartDate: Date()))
        XCTAssertNil(FPUConversion.carbEquivalentEntry(fatGrams: nil, proteinGrams: nil, adjustmentFactor: 0.5, mealStartDate: Date()))
        XCTAssertNil(FPUConversion.carbEquivalentEntry(fatGrams: 0, proteinGrams: 0, adjustmentFactor: 0.5, mealStartDate: Date()))
    }

    // MARK: - Favorite foods carrying macros

    func testStoredFavoriteFoodDecodesLegacyPayloadWithoutMacros() throws {
        // Favorites saved before fat/protein existed must keep decoding, with nil macros.
        let legacyJSON = """
        {"id":"ABC","name":"Pizza","carbsQuantity":50,"foodType":"🍕","absorptionTime":18000}
        """.data(using: .utf8)!

        let food = try JSONDecoder().decode(StoredFavoriteFood.self, from: legacyJSON)
        XCTAssertEqual(food.name, "Pizza")
        XCTAssertEqual(food.carbsQuantity.doubleValue(for: .gram()), 50)
        XCTAssertNil(food.fatQuantity)
        XCTAssertNil(food.proteinQuantity)
    }

    func testStoredFavoriteFoodMacroRoundTrip() throws {
        let food = StoredFavoriteFood(
            name: "Pizza",
            carbsQuantity: HKQuantity(unit: .gram(), doubleValue: 50),
            foodType: "🍕",
            absorptionTime: .hours(3),
            fatQuantity: HKQuantity(unit: .gram(), doubleValue: 30),
            proteinQuantity: HKQuantity(unit: .gram(), doubleValue: 25)
        )

        let decoded = try JSONDecoder().decode(StoredFavoriteFood.self, from: JSONEncoder().encode(food))
        XCTAssertEqual(decoded.fatQuantity?.doubleValue(for: .gram()), 30)
        XCTAssertEqual(decoded.proteinQuantity?.doubleValue(for: .gram()), 25)
        XCTAssertEqual(decoded.carbsQuantity.doubleValue(for: .gram()), 50)
    }
}

//
//  AddEditFavoriteFoodViewModel.swift
//  Loop
//
//  Created by Noah Brauner on 7/31/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit

final class AddEditFavoriteFoodViewModel: ObservableObject {
    enum Alert: Identifiable {
        var id: Self {
            return self
        }
        
        case maxQuantityExceded
        case warningQuantityValidation
    }
    
    @Published var name = ""
    
    @Published var carbsQuantity: Double? = nil
    var preferredCarbUnit = HKUnit.gram()
    var maxCarbEntryQuantity = LoopConstants.maxCarbEntryQuantity
    var warningCarbEntryQuantity = LoopConstants.warningCarbEntryQuantity
    
    @Published var foodType = ""

    // Fat & Protein Entries experiment: favorites can carry macros. When the experiment
    // is off the fields are hidden and left untouched (existing values are preserved).
    let fpuConversionEnabled = UserDefaults.standard.fpuConversionEnabled
    @Published var fatQuantity: Double? = nil
    @Published var proteinQuantity: Double? = nil

    @Published var absorptionTime: TimeInterval
    let minAbsorptionTime = LoopConstants.minCarbAbsorptionTime
    let maxAbsorptionTime = LoopConstants.maxCarbAbsorptionTime
    var absorptionRimesRange: ClosedRange<TimeInterval> {
        return minAbsorptionTime...maxAbsorptionTime
    }
    
    @Published var alert: AddEditFavoriteFoodViewModel.Alert?
    
    private let onSave: (NewFavoriteFood) -> ()
    
    init(originalFavoriteFood: StoredFavoriteFood?, onSave: @escaping (NewFavoriteFood) -> ()) {
        self.onSave = onSave
        if let food = originalFavoriteFood {
            self.originalFavoriteFood = food
            self.name = food.name
            self.carbsQuantity = food.carbsQuantity.doubleValue(for: preferredCarbUnit)
            self.foodType = food.foodType
            self.absorptionTime = food.absorptionTime
            self.fatQuantity = food.fatQuantity?.doubleValue(for: preferredCarbUnit)
            self.proteinQuantity = food.proteinQuantity?.doubleValue(for: preferredCarbUnit)
        }
        else {
            self.absorptionTime = .hours(3)
        }
    }

    init(carbsQuantity: Double?, foodType: String, absorptionTime: TimeInterval, fatQuantity: Double? = nil, proteinQuantity: Double? = nil, onSave: @escaping (NewFavoriteFood) -> ()) {
        self.onSave = onSave
        self.carbsQuantity = carbsQuantity
        self.foodType = foodType
        self.absorptionTime = absorptionTime
        self.fatQuantity = fatQuantity
        self.proteinQuantity = proteinQuantity
    }
    
    var originalFavoriteFood: StoredFavoriteFood?

    /// Entered macros as quantities; zero and empty both mean "none".
    private var fatQuantityValue: HKQuantity? {
        guard let fatQuantity, fatQuantity > 0 else { return nil }
        return HKQuantity(unit: preferredCarbUnit, doubleValue: fatQuantity)
    }

    private var proteinQuantityValue: HKQuantity? {
        guard let proteinQuantity, proteinQuantity > 0 else { return nil }
        return HKQuantity(unit: preferredCarbUnit, doubleValue: proteinQuantity)
    }

    var updatedFavoriteFood: NewFavoriteFood? {
        if let quantity = carbsQuantity, quantity != 0, name != "", foodType != "" {
            if let o = originalFavoriteFood, o.name == name, o.carbsQuantity.doubleValue(for: preferredCarbUnit) == carbsQuantity && o.foodType == foodType && o.absorptionTime == absorptionTime && o.fatQuantity == fatQuantityValue && o.proteinQuantity == proteinQuantityValue {
                return nil  // No changes were made
            }

            return NewFavoriteFood(
                name: name,
                carbsQuantity: HKQuantity(unit: preferredCarbUnit, doubleValue: quantity),
                foodType: foodType,
                absorptionTime: absorptionTime,
                fatQuantity: fatQuantityValue,
                proteinQuantity: proteinQuantityValue
            )
        }
        else {
            return nil
        }
    }

    func save() {
        guard let updatedFavoriteFood, absorptionTime <= maxAbsorptionTime else { return }

        guard let carbsQuantity, carbsQuantity > 0 else { return }
        let maxGrams = maxCarbEntryQuantity.doubleValue(for: preferredCarbUnit)
        if fatQuantity ?? 0 > maxGrams || proteinQuantity ?? 0 > maxGrams {
            self.alert = .maxQuantityExceded
            return
        }
        let quantity = HKQuantity(unit: preferredCarbUnit, doubleValue: carbsQuantity)
        if quantity.compare(maxCarbEntryQuantity) == .orderedDescending {
            self.alert = .maxQuantityExceded
            return
        }
        else if quantity.compare(warningCarbEntryQuantity) == .orderedDescending {
            self.alert = .warningQuantityValidation
            return
        }
        
        onSave(updatedFavoriteFood)
    }
    
    func clearAlertAndSave() {
        guard let updatedFavoriteFood else { return }
        self.alert = nil
        onSave(updatedFavoriteFood)
    }
    
    func clearAlert() {
        self.alert = nil
    }
}

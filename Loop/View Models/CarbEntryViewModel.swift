//
//  CarbEntryViewModel.swift
//  Loop
//
//  Created by Noah Brauner on 7/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit
import Combine

protocol CarbEntryViewModelDelegate: AnyObject, BolusEntryViewModelDelegate {
    var analyticsServicesManager: AnalyticsServicesManager { get }
    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes { get }
}

final class CarbEntryViewModel: ObservableObject {
    enum Alert: Identifiable {
        var id: Self {
            return self
        }
        
        case maxQuantityExceded
        case warningQuantityValidation
    }
    
    enum Warning: Identifiable {
        var id: Self {
            return self
        }
        
        var priority: Int {
            switch self {
            case .entryIsMissedMeal:
                return 1
            case .overrideInProgress:
                return 2
            }
        }
        
        case entryIsMissedMeal
        case overrideInProgress
    }
    
    @Published var alert: CarbEntryViewModel.Alert?
    @Published var warnings: Set<Warning> = []

    /// Called when the user has finished entering a meal. The host (meal-entry plugin) is responsible for acting on the
    /// resulting entry (e.g. reporting a `MealNutrition` and continuing to bolus). Set by the plugin that vends this view.
    var onComplete: ((NewCarbEntry) -> Void)?

    let shouldBeginEditingQuantity: Bool

    /// The entry mode: emoji food-type picker, or macro (fat/protein) entry with a derived absorption time.
    /// Mutable so the user can swap methods from the navigation-title menu; the choice is persisted.
    @Published var mode: MealEntryMode

    /// Switches the entry method (and persists it as the default). Re-derives the absorption time when switching to
    /// macro entry, unless the user has manually adjusted it.
    func selectMode(_ newMode: MealEntryMode) {
        guard newMode != mode else { return }
        mode = newMode
        UserDefaults.standard.mealEntryMode = newMode
        if newMode == .macro, !absorptionTimeWasEdited {
            absorptionEditIsProgrammatic = true
            absorptionTime = derivedAbsorptionTime
        }
    }

    @Published var carbsQuantity: Double? = nil

    // Macro entry (used when `mode == .macro`). Grams.
    @Published var fatQuantity: Double? = nil
    @Published var proteinQuantity: Double? = nil
    var preferredCarbUnit = HKUnit.gram()
    var maxCarbEntryQuantity = LoopConstants.maxCarbEntryQuantity
    var warningCarbEntryQuantity = LoopConstants.warningCarbEntryQuantity
    
    @Published var time = Date()
    private var date = Date()
    var minimumDate: Date {
        get { date.addingTimeInterval(LoopConstants.maxCarbEntryPastTime) }
    }
    var maximumDate: Date {
        get { date.addingTimeInterval(LoopConstants.maxCarbEntryFutureTime) }
    }
    
    @Published var foodType = ""
    @Published var selectedDefaultAbsorptionTimeEmoji: String = ""
    @Published var usesCustomFoodType = false
    @Published var absorptionTimeWasEdited = false // if true, selecting an emoji will not alter the absorption time
    private var absorptionEditIsProgrammatic = false // needed for when absorption time is changed due to favorite food selection, so that absorptionTimeWasEdited does not get set to true

    @Published var absorptionTime: TimeInterval
    let defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes
    let minAbsorptionTime = LoopConstants.minCarbAbsorptionTime
    let maxAbsorptionTime = LoopConstants.maxCarbAbsorptionTime
    var absorptionRimesRange: ClosedRange<TimeInterval> {
        return minAbsorptionTime...maxAbsorptionTime
    }
    
    @Published var favoriteFoods = UserDefaults.standard.favoriteFoods
    @Published var selectedFavoriteFoodIndex = -1
    
    weak var delegate: CarbEntryViewModelDelegate?
    
    private lazy var cancellables = Set<AnyCancellable>()
    
    /// Initalizer for when`CarbEntryView` is presented from the home screen
    init(delegate: CarbEntryViewModelDelegate, mode: MealEntryMode = .emoji) {
        self.delegate = delegate
        self.mode = mode
        self.absorptionTime = delegate.defaultAbsorptionTimes.medium
        self.defaultAbsorptionTimes = delegate.defaultAbsorptionTimes
        self.shouldBeginEditingQuantity = true

        observeAbsorptionTimeChange()
        observeFavoriteFoodChange()
        observeFavoriteFoodIndexChange()
        observeMacroChanges()
        observeLoopUpdates()
    }

    /// Initalizer for when`CarbEntryView` has an entry to edit
    init(delegate: CarbEntryViewModelDelegate, originalCarbEntry: StoredCarbEntry) {
        self.delegate = delegate
        self.mode = .emoji
        self.originalCarbEntry = originalCarbEntry
        self.defaultAbsorptionTimes = delegate.defaultAbsorptionTimes

        self.carbsQuantity = originalCarbEntry.quantity.doubleValue(for: preferredCarbUnit)
        self.time = originalCarbEntry.startDate
        self.foodType = originalCarbEntry.foodType ?? ""
        self.absorptionTime = originalCarbEntry.absorptionTime ?? .hours(3)
        self.absorptionTimeWasEdited = true
        self.usesCustomFoodType = true
        self.shouldBeginEditingQuantity = false
        
        observeLoopUpdates()
    }
    
    var originalCarbEntry: StoredCarbEntry? = nil
    private var favoriteFood: FavoriteFood? = nil
    
    private var updatedCarbEntry: NewCarbEntry? {
        if let quantity = carbsQuantity, quantity != 0 {
            if let o = originalCarbEntry, o.quantity.doubleValue(for: preferredCarbUnit) == quantity && o.startDate == time && o.foodType == foodType && o.absorptionTime == absorptionTime {
                return nil  // No changes were made
            }
            
            return NewCarbEntry(
                date: date,
                quantity: HKQuantity(unit: preferredCarbUnit, doubleValue: quantity),
                startDate: time,
                foodType: resolvedFoodType,
                absorptionTime: absorptionTime
            )
        }
        else {
            return nil
        }
    }

    private var resolvedFoodType: String {
        switch mode {
        case .macro:
            return "🍽️"
        case .emoji:
            return usesCustomFoodType ? foodType : selectedDefaultAbsorptionTimeEmoji
        }
    }

    // MARK: - Macro-derived absorption (macro mode)

    /// The Fat-Protein Units for the currently-entered macros.
    var fatProteinUnits: Double {
        MacroAbsorptionModel.fatProteinUnits(fatGrams: fatQuantity ?? 0, proteinGrams: proteinQuantity ?? 0)
    }

    /// The carb absorption time derived from the currently-entered macros.
    var derivedAbsorptionTime: TimeInterval {
        MacroAbsorptionModel.absorptionTime(
            fatGrams: fatQuantity ?? 0,
            proteinGrams: proteinQuantity ?? 0,
            defaultAbsorptionTimes: defaultAbsorptionTimes
        )
    }

    /// Total fat as an `HKQuantity`, if entered.
    var fatHKQuantity: HKQuantity? {
        fatQuantity.map { HKQuantity(unit: preferredCarbUnit, doubleValue: $0) }
    }

    /// Total protein as an `HKQuantity`, if entered.
    var proteinHKQuantity: HKQuantity? {
        proteinQuantity.map { HKQuantity(unit: preferredCarbUnit, doubleValue: $0) }
    }
    
    var saveFavoriteFoodButtonDisabled: Bool {
        get {
            if let carbsQuantity, 0...maxCarbEntryQuantity.doubleValue(for: preferredCarbUnit) ~= carbsQuantity, selectedFavoriteFoodIndex == -1 {
                return false
            }
            return true
        }
    }
    
    var continueButtonDisabled: Bool {
        get { updatedCarbEntry == nil }
    }
    
    // MARK: - Continue to Bolus and Carb Quantity Warnings
    func continueToBolus() {
        guard updatedCarbEntry != nil else {
            return
        }
        
        validateInputAndContinue()
    }
    
    private func validateInputAndContinue() {
        guard absorptionTime <= maxAbsorptionTime else {
            return
        }
        
        guard let carbsQuantity, carbsQuantity > 0 else { return }
        let quantity = HKQuantity(unit: preferredCarbUnit, doubleValue: carbsQuantity)
        if quantity.compare(maxCarbEntryQuantity) == .orderedDescending {
            self.alert = .maxQuantityExceded
            return
        }
        else if quantity.compare(warningCarbEntryQuantity) == .orderedDescending, selectedFavoriteFoodIndex == -1 {
            self.alert = .warningQuantityValidation
            return
        }
        
        Task { @MainActor in
            completeMeal()
        }
    }

    /// Hands the finished carb entry back to the host via `onComplete`. The host owns the bolus/save flow.
    @MainActor private func completeMeal() {
        guard let entry = updatedCarbEntry else { return }
        onComplete?(entry)
    }

    func clearAlert() {
        self.alert = nil
    }

    func clearAlertAndContinueToBolus() {
        self.alert = nil
        Task { @MainActor in
            completeMeal()
        }
    }
    
    // MARK: - Favorite Foods
    func onFavoriteFoodSave(_ food: NewFavoriteFood) {
        let newStoredFood = StoredFavoriteFood(name: food.name, carbsQuantity: food.carbsQuantity, foodType: food.foodType, absorptionTime: food.absorptionTime, fatQuantity: food.fatQuantity, proteinQuantity: food.proteinQuantity)
        favoriteFoods.append(newStoredFood)
        selectedFavoriteFoodIndex = favoriteFoods.count - 1
    }
    
    private func observeFavoriteFoodIndexChange() {
        $selectedFavoriteFoodIndex
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] index in
                self?.favoriteFoodSelected(at: index)
            }
            .store(in: &cancellables)
    }
    
    private func observeFavoriteFoodChange() {
        $favoriteFoods
            .dropFirst()
            .removeDuplicates()
            .sink { newValue in
                UserDefaults.standard.favoriteFoods = newValue
            }
            .store(in: &cancellables)
    }

    private func favoriteFoodSelected(at index: Int) {
        self.absorptionEditIsProgrammatic = true
        if index == -1 {
            self.carbsQuantity = 0
            self.foodType = ""
            self.absorptionTime = defaultAbsorptionTimes.medium
            self.absorptionTimeWasEdited = false
            self.usesCustomFoodType = false
            self.fatQuantity = nil
            self.proteinQuantity = nil
        }
        else {
            let food = favoriteFoods[index]
            self.carbsQuantity = food.carbsQuantity.doubleValue(for: preferredCarbUnit)
            self.foodType = food.foodType
            self.absorptionTime = food.absorptionTime
            self.absorptionTimeWasEdited = true
            self.usesCustomFoodType = true
            // One combined list: fill macros only when this favorite carries them and we're in macro mode.
            // The favorite's stored absorption is kept (absorptionTimeWasEdited == true prevents re-derivation).
            if mode == .macro {
                self.fatQuantity = food.fatQuantity?.doubleValue(for: preferredCarbUnit)
                self.proteinQuantity = food.proteinQuantity?.doubleValue(for: preferredCarbUnit)
            }
        }
    }

    /// In macro mode, re-derive the absorption time from the macros whenever they change — unless the user has
    /// manually adjusted the absorption time (mirrors the emoji-selection behavior).
    private func observeMacroChanges() {
        Publishers.CombineLatest($fatQuantity, $proteinQuantity)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self, self.mode == .macro, !self.absorptionTimeWasEdited else { return }
                self.absorptionEditIsProgrammatic = true
                self.absorptionTime = self.derivedAbsorptionTime
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Utility
    func restoreUserActivityState(_ activity: NSUserActivity) {
        if let entry = activity.newCarbEntry {
            time = entry.date
            carbsQuantity = entry.quantity.doubleValue(for: preferredCarbUnit)

            if let foodType = entry.foodType {
                self.foodType = foodType
                usesCustomFoodType = true
            }

            if let absorptionTime = entry.absorptionTime {
                self.absorptionTime = absorptionTime
                absorptionTimeWasEdited = true
            }
            
            if activity.entryisMissedMeal {
                warnings.insert(.entryIsMissedMeal)
            }
        }
    }
    
    private func observeLoopUpdates() {
        self.checkIfOverrideEnabled()
        NotificationCenter.default
            .publisher(for: .LoopDataUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkIfOverrideEnabled()
            }
            .store(in: &cancellables)
    }
    
    private func checkIfOverrideEnabled() {
        if let managerSettings = delegate?.settings,
           managerSettings.scheduleOverrideEnabled(at: Date()),
           let overrideSettings = managerSettings.scheduleOverride?.settings,
           overrideSettings.effectiveInsulinNeedsScaleFactor != 1.0 {
            self.warnings.insert(.overrideInProgress)
        }
        else {
            self.warnings.remove(.overrideInProgress)
        }
    }
    
    private func observeAbsorptionTimeChange() {
        $absorptionTime
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in
                if self?.absorptionEditIsProgrammatic == true {
                    self?.absorptionEditIsProgrammatic = false
                }
                else {
                    self?.absorptionTimeWasEdited = true
                }
            }
            .store(in: &cancellables)
    }
}

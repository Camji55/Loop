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
        case maxFatProteinExceded
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
            case .customAbsorptionTimeWithFPU:
                return 3
            }
        }

        case entryIsMissedMeal
        case overrideInProgress
        case customAbsorptionTimeWithFPU
    }
    
    @Published var alert: CarbEntryViewModel.Alert?
    @Published var warnings: Set<Warning> = []

    @Published var bolusViewModel: BolusEntryViewModel?
    
    let shouldBeginEditingQuantity: Bool
    
    @Published var carbsQuantity: Double? = nil
    var preferredCarbUnit = HKUnit.gram()
    var maxCarbEntryQuantity = LoopConstants.maxCarbEntryQuantity
    var warningCarbEntryQuantity = LoopConstants.warningCarbEntryQuantity

    // Fat & Protein Entries experiment. Fat and protein are only editable on new entries;
    // when the experiment is off, the carb entry flow is unchanged.
    let fpuConversionEnabled: Bool
    @Published var fatQuantity: Double? = nil
    @Published var proteinQuantity: Double? = nil

    var hasEnteredMacros: Bool {
        (fatQuantity ?? 0) > 0 || (proteinQuantity ?? 0) > 0
    }

    // Tracks whether the current absorption time came from a food-type emoji, so it can
    // be reverted when fat/protein are entered (the FPU entry covers the slow tail; the
    // meal keeps a carb-honest absorption). Explicit picker edits are never reverted.
    private var pendingEmojiAbsorptionWrite = false
    private var absorptionTimeSetByEmoji = false
    
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
    init(delegate: CarbEntryViewModelDelegate) {
        self.delegate = delegate
        self.absorptionTime = delegate.defaultAbsorptionTimes.medium
        self.defaultAbsorptionTimes = delegate.defaultAbsorptionTimes
        self.shouldBeginEditingQuantity = true
        self.fpuConversionEnabled = UserDefaults.standard.fpuConversionEnabled

        observeAbsorptionTimeChange()
        observeFavoriteFoodChange()
        observeFavoriteFoodIndexChange()
        observeLoopUpdates()
    }

    /// Initalizer for when`CarbEntryView` has an entry to edit
    init(delegate: CarbEntryViewModelDelegate, originalCarbEntry: StoredCarbEntry) {
        self.delegate = delegate
        self.originalCarbEntry = originalCarbEntry
        self.defaultAbsorptionTimes = delegate.defaultAbsorptionTimes
        self.fpuConversionEnabled = false

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
                foodType: usesCustomFoodType ? foodType : selectedDefaultAbsorptionTimeEmoji,
                absorptionTime: absorptionTime
            )
        }
        else {
            return nil
        }
    }
    
    /// The delayed carb-equivalent entry for the meal's fat and protein, saved alongside
    /// the meal entry when the user confirms the bolus. Nil when the experiment is off,
    /// when editing an existing entry, or when fat and protein are too small to dose.
    var fpuCarbEntry: NewCarbEntry? {
        guard fpuConversionEnabled, originalCarbEntry == nil else {
            return nil
        }
        return FPUConversion.carbEquivalentEntry(
            fatGrams: fatQuantity,
            proteinGrams: proteinQuantity,
            adjustmentFactor: UserDefaults.standard.fpuAdjustmentFactor,
            mealStartDate: time
        )
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

        let maxGrams = maxCarbEntryQuantity.doubleValue(for: preferredCarbUnit)
        if fatQuantity ?? 0 > maxGrams || proteinQuantity ?? 0 > maxGrams {
            self.alert = .maxFatProteinExceded
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
            setBolusViewModel()
        }
    }
        
    @MainActor private func setBolusViewModel() {
        let viewModel = BolusEntryViewModel(
            delegate: delegate,
            screenWidth: UIScreen.main.bounds.width,
            originalCarbEntry: originalCarbEntry,
            potentialCarbEntry: updatedCarbEntry,
            selectedCarbAbsorptionTimeEmoji: selectedDefaultAbsorptionTimeEmoji,
            fpuCarbEntry: fpuCarbEntry
        )
        Task {
            await viewModel.generateRecommendationAndStartObserving()
        }
        
        viewModel.analyticsServicesManager = delegate?.analyticsServicesManager
        bolusViewModel = viewModel
        
        delegate?.analyticsServicesManager.didDisplayBolusScreen()
    }
    
    func clearAlert() {
        self.alert = nil
    }
    
    func clearAlertAndContinueToBolus() {
        self.alert = nil
        Task { @MainActor in
            setBolusViewModel()
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
        // Replace any macros typed for a different meal with the favorite's own (or
        // clear them), so they cannot silently attach an FPU entry to this one.
        if index == -1 {
            self.fatQuantity = nil
            self.proteinQuantity = nil
            self.carbsQuantity = 0
            self.foodType = ""
            self.absorptionTime = defaultAbsorptionTimes.medium
            self.absorptionTimeWasEdited = false
            self.usesCustomFoodType = false
        }
        else {
            let food = favoriteFoods[index]
            self.fatQuantity = fpuConversionEnabled ? food.fatQuantity?.doubleValue(for: preferredCarbUnit) : nil
            self.proteinQuantity = fpuConversionEnabled ? food.proteinQuantity?.doubleValue(for: preferredCarbUnit) : nil
            self.carbsQuantity = food.carbsQuantity.doubleValue(for: preferredCarbUnit)
            self.foodType = food.foodType
            self.absorptionTime = food.absorptionTime
            self.absorptionTimeWasEdited = true
            self.usesCustomFoodType = true
        }
        updateCustomAbsorptionWarning()
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
                guard let self else { return }
                if self.absorptionEditIsProgrammatic {
                    self.absorptionEditIsProgrammatic = false
                    self.absorptionTimeSetByEmoji = false
                }
                else {
                    self.absorptionTimeWasEdited = true
                    self.absorptionTimeSetByEmoji = self.pendingEmojiAbsorptionWrite
                }
                self.pendingEmojiAbsorptionWrite = false
                self.updateCustomAbsorptionWarning()
            }
            .store(in: &cancellables)
    }

    // MARK: - Fat & Protein Entries

    /// Absorption-time writes coming from the food-type emoji shortcuts. While the FPU
    /// experiment is active and fat/protein have been entered, the emoji only tags the
    /// food type — the meal keeps its carb absorption and the FPU entry covers the tail.
    /// With no macros entered (e.g. 🍭 glucose tabs), stock behavior is unchanged.
    func setAbsorptionTimeFromEmoji(_ time: TimeInterval) {
        guard !(fpuConversionEnabled && hasEnteredMacros) else {
            return
        }
        pendingEmojiAbsorptionWrite = true
        absorptionTime = time
    }

    /// Fat/protein edits from the entry screen. When macros first appear, an
    /// emoji-driven absorption reverts to the carb default; explicit edits are kept.
    func userEnteredFatQuantity(_ value: Double?) {
        fatQuantity = value
        revertEmojiAbsorptionIfNeeded()
        updateCustomAbsorptionWarning()
    }

    func userEnteredProteinQuantity(_ value: Double?) {
        proteinQuantity = value
        revertEmojiAbsorptionIfNeeded()
        updateCustomAbsorptionWarning()
    }

    private func revertEmojiAbsorptionIfNeeded() {
        guard fpuConversionEnabled, hasEnteredMacros, absorptionTimeSetByEmoji else {
            return
        }
        absorptionEditIsProgrammatic = true
        absorptionTime = defaultAbsorptionTimes.medium
        absorptionTimeWasEdited = false
        absorptionTimeSetByEmoji = false
    }

    /// Warns while the absorption time differs from the default although fat/protein are
    /// generating a carb equivalent entry: the equivalent already covers the slow tail,
    /// so stretching the meal's own absorption usually double-covers the fat. Comparing
    /// values (not edit flags) lets the warning clear when the time is set back.
    /// With macros entered, a non-default time can only come from an explicit edit or a
    /// favorite food — emoji-driven times are blocked and auto-reverted in that state.
    private func updateCustomAbsorptionWarning() {
        if fpuConversionEnabled, fpuCarbEntry != nil, absorptionTime != defaultAbsorptionTimes.medium {
            warnings.insert(.customAbsorptionTimeWithFPU)
        }
        else {
            warnings.remove(.customAbsorptionTimeWithFPU)
        }
    }
}

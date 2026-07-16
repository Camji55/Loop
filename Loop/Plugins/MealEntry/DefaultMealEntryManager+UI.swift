//
//  DefaultMealEntryManager+UI.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

/// A navigation controller that conforms to `CompletionNotifying` so the meal-entry flow can signal dismissal to its host.
final class MealEntryNavigationController: UINavigationController, CompletionNotifying {
    weak var completionDelegate: CompletionDelegate?
}

extension DefaultMealEntryManager: MealEntryManagerUI {
    static var image: UIImage? { nil }

    static func setupViewController(colorPalette: LoopUIColorPalette, pluginHost: PluginHost) -> SetupUIResult<MealEntryViewController, MealEntryManagerUI> {
        // The default plugin needs no setup; it is created and onboarded by the host.
        return .createdAndOnboarded(DefaultMealEntryManager())
    }

    func mealEntryViewController(colorPalette: LoopUIColorPalette) -> MealEntryViewController {
        guard let host else {
            // Should never happen for the built-in plugin; return an empty controller to fail safe.
            return MealEntryNavigationController(rootViewController: UIViewController())
        }

        if host.prefersSimpleMealEntry {
            return simpleMealCalculatorViewController(host: host)
        } else {
            return carbEntryViewController(host: host)
        }
    }

    // MARK: - Full carb/meal entry

    private func carbEntryViewController(host: DefaultMealEntryManagerHost) -> MealEntryViewController {
        let viewModel = CarbEntryViewModel(delegate: host.carbEntryViewModelDelegate, mode: UserDefaults.standard.mealEntryMode)
        if let pendingUserActivity {
            viewModel.restoreUserActivityState(pendingUserActivity)
            self.pendingUserActivity = nil
        }
        viewModel.onComplete = { [weak self, weak viewModel] entry in
            guard let self, let viewModel else { return }
            self.mealEntryManagerDelegate?.mealEntryManager(self, didCompleteWith: self.nutrition(from: entry, viewModel: viewModel))
        }

        let view = CarbEntryView(viewModel: viewModel)
            .environmentObject(host.displayGlucosePreference)
        let hostingController = DismissibleHostingController(rootView: view, isModalInPresentation: false)
        let navigationController = MealEntryNavigationController(rootViewController: hostingController)
        return navigationController
    }

    // MARK: - Simple meal calculator

    private func simpleMealCalculatorViewController(host: DefaultMealEntryManagerHost) -> MealEntryViewController {
        let viewModel = SimpleBolusViewModel(delegate: host.simpleBolusViewModelDelegate, displayMealEntry: true)
        let view = SimpleBolusView(viewModel: viewModel)
            .environmentObject(DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter))
        let hostingController = DismissibleHostingController(rootView: view, isModalInPresentation: false)
        let navigationController = MealEntryNavigationController(rootViewController: hostingController)
        hostingController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: navigationController, action: #selector(UIViewController.dismissWithAnimation))
        return navigationController
    }

    // MARK: - Nutrition mapping

    private func nutrition(from entry: NewCarbEntry, viewModel: CarbEntryViewModel) -> MealNutrition {
        MealNutrition(
            carbohydrates: entry.quantity,
            carbAbsorptionTime: entry.absorptionTime ?? .hours(3),
            foodType: entry.foodType,
            startDate: entry.startDate,
            protein: viewModel.proteinHKQuantity,
            fat: viewModel.fatHKQuantity
        )
    }
}

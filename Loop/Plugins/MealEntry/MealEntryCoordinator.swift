//
//  MealEntryCoordinator.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import UIKit
import SwiftUI
import LoopKit
import LoopKitUI

/// Drives presentation of the active meal-entry plugin and owns the app-side bolus/save continuation once the plugin
/// produces a meal. Shared by the status screen and the carb absorption screen so the plugin boundary lives in one place.
///
/// Retained by the presenting view controller (the plugin holds the delegate weakly).
final class MealEntryCoordinator: NSObject {
    private let deviceManager: DeviceDataManager
    private weak var mealEntryViewController: MealEntryViewController?

    init(deviceManager: DeviceDataManager) {
        self.deviceManager = deviceManager
    }

    func presentMealEntry(from viewController: UIViewController, userActivity: NSUserActivity? = nil) {
        guard let manager = deviceManager.mealEntryManager as? MealEntryManagerUI else {
            return
        }
        // The built-in default plugin needs a reference to the host to vend its UI. Injected here because
        // DeviceDataManager sets `mealEntryManager` inside its own init, where `didSet` (which would set the host)
        // does not fire.
        if let defaultManager = manager as? DefaultMealEntryManager {
            defaultManager.host = deviceManager
        }
        manager.mealEntryManagerDelegate = self
        if let userActivity {
            manager.restoreUserActivityState(userActivity)
        }
        var mealViewController = manager.mealEntryViewController(colorPalette: .default)
        mealViewController.completionDelegate = self
        mealEntryViewController = mealViewController
        viewController.present(mealViewController, animated: true)
        deviceManager.analyticsServicesManager.didDisplayCarbEntryScreen()
    }
}

// MARK: - MealEntryManagerDelegate
extension MealEntryCoordinator: MealEntryManagerDelegate {
    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes {
        deviceManager.defaultAbsorptionTimes
    }

    func mealEntryManager(_ manager: MealEntryManager, didCompleteWith nutrition: MealNutrition) {
        // The plugin produced the meal total; the app now owns building the entry and driving bolus/save.
        let entry = NewCarbEntry(
            quantity: nutrition.carbohydrates,
            startDate: nutrition.startDate,
            foodType: nutrition.foodType,
            absorptionTime: nutrition.carbAbsorptionTime
        )

        Task { @MainActor in
            let bolusViewModel = BolusEntryViewModel(
                delegate: deviceManager,
                screenWidth: UIScreen.main.bounds.width,
                originalCarbEntry: nil,
                potentialCarbEntry: entry,
                selectedCarbAbsorptionTimeEmoji: nutrition.foodType ?? ""
            )
            await bolusViewModel.generateRecommendationAndStartObserving()
            bolusViewModel.analyticsServicesManager = deviceManager.analyticsServicesManager
            deviceManager.analyticsServicesManager.didDisplayBolusScreen()

            let bolusView = BolusEntryView(viewModel: bolusViewModel)
                .environmentObject(deviceManager.displayGlucosePreference)
                .environment(\.dismissAction, { [self] in
                    mealEntryViewController?.dismiss(animated: true)
                })
            let hostingController = UIHostingController(rootView: bolusView)

            if let navigationController = mealEntryViewController as? UINavigationController {
                // Push bolus onto the plugin's navigation stack so the user can go back to edit the meal.
                navigationController.pushViewController(hostingController, animated: true)
            } else {
                mealEntryViewController?.present(hostingController, animated: true)
            }
        }
    }

    func mealEntryManagerDidCancel(_ manager: MealEntryManager) {
        mealEntryViewController?.dismiss(animated: true)
    }

    func mealEntryManagerDidUpdateState(_ manager: MealEntryManager) {}
}

// MARK: - CompletionDelegate
extension MealEntryCoordinator: CompletionDelegate {
    func completionNotifyingDidComplete(_ object: CompletionNotifying) {
        (object as? UIViewController)?.dismiss(animated: true)
    }
}

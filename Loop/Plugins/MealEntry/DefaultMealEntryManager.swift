//
//  DefaultMealEntryManager.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI

/// The context the built-in meal-entry plugin needs from the host app to vend its UI.
///
/// This is app-internal glue: the default plugin is compiled into the app, so it may depend on app types.
/// A third-party meal-entry plugin ships as a framework and does not use this.
protocol DefaultMealEntryManagerHost: AnyObject {
    /// Delegate used to build the full carb/meal entry view model.
    var carbEntryViewModelDelegate: CarbEntryViewModelDelegate { get }

    /// Delegate used to build the simple meal calculator view model.
    var simpleBolusViewModelDelegate: SimpleBolusViewModelDelegate { get }

    /// Glucose display preference for the vended UI.
    var displayGlucosePreference: DisplayGlucosePreference { get }

    /// Whether the simple meal calculator should be shown instead of the full carb entry flow.
    var prefersSimpleMealEntry: Bool { get }
}

/// The built-in, default meal-entry plugin. Vends Loop's carb entry flow and simple meal calculator, and reports the
/// resulting meal (total carbs + carb absorption time) back to the host as a `MealNutrition`.
final class DefaultMealEntryManager: MealEntryManager {
    static let pluginIdentifier = "DefaultMealEntry"

    static var localizedTitle: String {
        NSLocalizedString("Loop Meal Entry", comment: "The title of the built-in meal entry plugin")
    }

    weak var mealEntryManagerDelegate: MealEntryManagerDelegate?
    weak var stateDelegate: StatefulPluggableDelegate?

    /// The host providing app context. Injected by the host after instantiation (the default plugin is built-in).
    weak var host: DefaultMealEntryManagerHost?

    /// A user activity to apply to the next vended carb entry view (Siri shortcut / missed-meal notification).
    var pendingUserActivity: NSUserActivity?

    var isOnboarded: Bool { true }

    init() {}

    init?(rawState: RawStateValue) {
        // The default plugin is stateless.
    }

    var rawState: RawStateValue { [:] }

    func restoreUserActivityState(_ activity: NSUserActivity) {
        pendingUserActivity = activity
    }
}

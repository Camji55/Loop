//
//  MealEntryMode.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// How the built-in meal-entry plugin collects a meal.
enum MealEntryMode: String, CaseIterable, Identifiable {
    /// Carbs + emoji food type (🍭/🌮/🍕), absorption chosen via the emoji or adjusted manually.
    case emoji
    /// Carbs + fat/protein macros, with the carb absorption time derived from the macros (Fat-Protein Units).
    case macro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emoji:
            return NSLocalizedString("Basic", comment: "Title for the basic meal entry mode")
        case .macro:
            return NSLocalizedString("Macros", comment: "Title for the macro meal entry mode")
        }
    }
}

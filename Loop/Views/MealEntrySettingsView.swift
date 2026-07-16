//
//  MealEntrySettingsView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

/// Settings for the built-in meal-entry plugin.
///
/// On iOS 16+, the entry style (emoji vs. macros) is swapped from the meal-entry screen's title menu and remembered as
/// the default. On iOS 15, that title-menu API is unavailable, so this screen offers the entry-style toggle instead.
struct MealEntrySettingsView: View {
    @State private var mode: MealEntryMode = UserDefaults.standard.mealEntryMode
    @State private var showFavoriteFoods = false

    private var modeBinding: Binding<MealEntryMode> {
        Binding(
            get: { mode },
            set: { newValue in
                mode = newValue
                UserDefaults.standard.mealEntryMode = newValue
            }
        )
    }

    var body: some View {
        List {
            if #unavailable(iOS 16.0) {
                Section(footer: Text("Choose how you enter meals. Macro entry estimates the carb absorption time from the fat and protein you enter.", comment: "Footer describing the meal entry style setting")) {
                    Picker(selection: modeBinding) {
                        ForEach(MealEntryMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        Text("Entry Style", comment: "Label for the meal entry style picker")
                    }
                }
            }

            Section {
                Button(action: { showFavoriteFoods = true }) {
                    HStack {
                        Text("Favorite Foods", comment: "Label for the favorite foods row in meal entry settings")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
                .foregroundColor(.primary)
            }
        }
        .insetGroupedListStyle()
        .navigationBarTitle(Text(NSLocalizedString("Meal Entry", comment: "Title of the meal entry settings screen")), displayMode: .inline)
        .sheet(isPresented: $showFavoriteFoods) {
            FavoriteFoodsView()
        }
    }
}

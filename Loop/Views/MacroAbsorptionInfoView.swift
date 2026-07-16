//
//  MacroAbsorptionInfoView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit

/// Explains how the carb absorption time is estimated from macros (Fat-Protein Units / "Warsaw method"), and shows the
/// calculation using the values the user has currently entered.
struct MacroAbsorptionInfoView: View {
    @Environment(\.dismiss) private var dismiss

    let fatGrams: Double
    let proteinGrams: Double
    let defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    // MARK: - Derived values

    private var fatCalories: Double { fatGrams * MacroAbsorptionModel.caloriesPerGramFat }
    private var proteinCalories: Double { proteinGrams * MacroAbsorptionModel.caloriesPerGramProtein }
    private var totalCalories: Double { fatCalories + proteinCalories }
    private var fatProteinUnits: Double {
        MacroAbsorptionModel.fatProteinUnits(fatGrams: fatGrams, proteinGrams: proteinGrams)
    }
    private var addedHours: Double { fatProteinUnits * MacroAbsorptionModel.hoursPerFatProteinUnit }
    private var baseTime: TimeInterval { defaultAbsorptionTimes.medium }
    private var derivedTime: TimeInterval {
        MacroAbsorptionModel.absorptionTime(fatGrams: fatGrams, proteinGrams: proteinGrams, defaultAbsorptionTimes: defaultAbsorptionTimes)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Fat and protein slow how quickly a meal's carbohydrates absorb, so higher-fat or higher-protein meals are given a longer absorption time.", comment: "Macro absorption explanation intro")
                    Text("This uses Fat-Protein Units (FPU), from the Warsaw method: every 100 calories from fat and protein counts as one FPU. Fat provides 9 calories per gram and protein 4 calories per gram. Each FPU adds about an hour of absorption time on top of the base, kept within Loop's allowed range.", comment: "Macro absorption explanation of the Warsaw method")
                }

                Section(header: Text("Your Calculation", comment: "Header for the macro absorption calculation section"),
                        footer: Text(String(format: NSLocalizedString("Absorption time is kept between %1$@ and %2$@.", comment: "Footer noting the clamp range (1: min, 2: max)"), durationString(LoopConstants.minCarbAbsorptionTime), durationString(LoopConstants.maxCarbAbsorptionTime)))) {
                    calculationRow(label: String(format: NSLocalizedString("Fat: %1$@ g × 9", comment: "Fat calories calculation (1: grams of fat)"), number(fatGrams)),
                                   value: String(format: NSLocalizedString("%1$@ cal", comment: "Calorie value (1: number of calories)"), number(fatCalories)))
                    calculationRow(label: String(format: NSLocalizedString("Protein: %1$@ g × 4", comment: "Protein calories calculation (1: grams of protein)"), number(proteinGrams)),
                                   value: String(format: NSLocalizedString("%1$@ cal", comment: "Calorie value (1: number of calories)"), number(proteinCalories)))
                    calculationRow(label: Text("Fat + Protein Energy", comment: "Label for total fat and protein calories"),
                                   value: Text(String(format: NSLocalizedString("%1$@ cal", comment: "Calorie value (1: number of calories)"), number(totalCalories))))
                    calculationRow(label: String(format: NSLocalizedString("Fat-Protein Units: %1$@ cal ÷ 100", comment: "FPU calculation (1: total calories)"), number(totalCalories)),
                                   value: String(format: NSLocalizedString("%1$@ FPU", comment: "Fat-protein unit value (1: number of units)"), number(fatProteinUnits)))
                    calculationRow(label: Text(String(format: NSLocalizedString("Absorption: %1$@ + (%2$@ FPU × 1 hr)", comment: "Absorption calculation (1: base time, 2: FPU count)"), durationString(baseTime), number(fatProteinUnits))).font(.subheadline).bold(),
                                   value: Text(durationString(derivedTime)).font(.subheadline).bold())
                }
            }
            .navigationTitle(Text("Absorption Time", comment: "Title of the macro absorption info screen"))
            .toolbar {
                Button(action: dismiss.callAsFunction) {
                    Text("Close", comment: "Button to dismiss the macro absorption info screen")
                }
            }
        }
    }

    // MARK: - Row helpers

    private func calculationRow(label: String, value: String) -> some View {
        calculationRow(label: Text(label), value: Text(value))
    }

    private func calculationRow<L: View, V: View>(label: L, value: V) -> some View {
        HStack {
            label
                .foregroundColor(.primary)
            Spacer()
            value
                .foregroundColor(.secondary)
        }
    }

    private func number(_ value: Double) -> String {
        Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func durationString(_ time: TimeInterval) -> String {
        Self.durationFormatter.string(from: time) ?? ""
    }
}

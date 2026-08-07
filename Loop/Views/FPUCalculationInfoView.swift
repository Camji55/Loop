//
//  FPUCalculationInfoView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit

/// Shows the two carb entries a fat/protein meal produces — the meal's own entry and the
/// delayed carb-equivalent entry — with their amounts, start times, and absorption times,
/// followed by the Fat-Protein Unit (Warsaw method) calculation behind the equivalent.
struct FPUCalculationInfoView: View {
    @Environment(\.dismiss) private var dismiss

    let carbsGrams: Double
    let fatGrams: Double
    let proteinGrams: Double
    let adjustmentFactor: Double
    let mealStartDate: Date
    let mealAbsorptionTime: TimeInterval

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

    private var fatCalories: Double { fatGrams * FPUConversion.kilocaloriesPerGramOfFat }
    private var proteinCalories: Double { proteinGrams * FPUConversion.kilocaloriesPerGramOfProtein }
    private var totalCalories: Double { FPUConversion.fatProteinKilocalories(fatGrams: fatGrams, proteinGrams: proteinGrams) }
    private var fatProteinUnits: Double { FPUConversion.fpuCount(fatGrams: fatGrams, proteinGrams: proteinGrams) }
    private var rawGrams: Double { FPUConversion.rawCarbEquivalentGrams(fatGrams: fatGrams, proteinGrams: proteinGrams, adjustmentFactor: adjustmentFactor) }
    private var equivalentEntry: NewCarbEntry? {
        FPUConversion.carbEquivalentEntry(fatGrams: fatGrams, proteinGrams: proteinGrams, adjustmentFactor: adjustmentFactor, mealStartDate: mealStartDate)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("This meal is saved as two carb entries: the carbohydrates you entered, and a smaller delayed entry covering the late glucose rise from fat and protein. The meal's bolus recommendation covers only the first — Loop delivers insulin for the second gradually as it absorbs.", comment: "FPU info intro describing the two carb entries")
                }

                Section(header: Text("Meal Entry", comment: "Header for the meal entry section of the FPU info screen")) {
                    infoRow(label: Text("Amount", comment: "Label for the amount row"),
                            value: Text(gramsString(carbsGrams)))
                    infoRow(label: Text("Starts", comment: "Label for the start time row"),
                            value: Text(timeString(mealStartDate)))
                    infoRow(label: Text("Absorption Time", comment: "Label for the absorption time row"),
                            value: Text(durationString(mealAbsorptionTime)))
                }

                Section(header: Text("Carb Equivalent Entry", comment: "Header for the carb equivalent entry section of the FPU info screen")) {
                    if let equivalentEntry = equivalentEntry {
                        infoRow(label: Text("Amount", comment: "Label for the amount row"),
                                value: Text(gramsString(equivalentEntry.quantity.doubleValue(for: .gram()))))
                        infoRow(label: Text("Starts", comment: "Label for the start time row"),
                                value: Text(String(format: NSLocalizedString("%1$@", comment: "Start time of the carb equivalent entry (1: time)"), timeString(equivalentEntry.startDate))))
                        if let absorptionTime = equivalentEntry.absorptionTime {
                            infoRow(label: Text("Absorption Time", comment: "Label for the absorption time row"),
                                    value: Text(durationString(absorptionTime)))
                        }
                    }
                    else {
                        infoRow(label: Text("Amount", comment: "Label for the amount row"),
                                value: Text(String(format: NSLocalizedString("None — %1$@ g is below the %2$@ g minimum", comment: "Value when the carb equivalent is below the minimum (1: equivalent grams)(2: minimum grams)"), number(rawGrams), number(FPUConversion.minimumEquivalentGrams))))
                    }
                }

                Section(header: Text("Your Calculation", comment: "Header for the FPU calculation section"),
                        footer: footerText) {
                    calculationRow(label: String(format: NSLocalizedString("Fat: %1$@ g × 9", comment: "Fat calories calculation (1: grams of fat)"), number(fatGrams)),
                                   value: String(format: NSLocalizedString("%1$@ cal", comment: "Calorie value (1: number of calories)"), number(fatCalories)))
                    calculationRow(label: String(format: NSLocalizedString("Protein: %1$@ g × 4", comment: "Protein calories calculation (1: grams of protein)"), number(proteinGrams)),
                                   value: String(format: NSLocalizedString("%1$@ cal", comment: "Calorie value (1: number of calories)"), number(proteinCalories)))
                    calculationRow(label: String(format: NSLocalizedString("Fat-Protein Units: %1$@ cal ÷ 100", comment: "FPU calculation (1: total calories)"), number(totalCalories)),
                                   value: String(format: NSLocalizedString("%1$@ FPU", comment: "Fat-protein unit value (1: number of units)"), number(fatProteinUnits)))
                    calculationRow(label: String(format: NSLocalizedString("Carb Equivalent: %1$@ FPU × 10 g × %2$@%%", comment: "Carb equivalent calculation (1: FPU count)(2: adjustment factor percent)"), number(fatProteinUnits), number(adjustmentFactor * 100)),
                                   value: String(format: NSLocalizedString("%1$@ g", comment: "Gram value (1: number of grams)"), number(rawGrams)))
                }
            }
            .navigationTitle(Text("Calculation Info", comment: "Title of the FPU info screen"))
            .toolbar {
                Button(action: dismiss.callAsFunction) {
                    Text("Close", comment: "Button to dismiss the FPU calculation info screen")
                }
            }
        }
    }

    private var footerText: Text {
        Text(String(format: NSLocalizedString("One FPU is 100 calories of fat and protein, dosed like 10 g of carbohydrate and scaled by your Fat & Protein Percentage. Equivalents below %1$@ g are skipped and larger ones are capped at %2$@ g. The equivalent entry's absorption time comes from the Warsaw duration for the FPU count (3–8 hours), adjusted so Loop's modeled absorption window matches it.", comment: "Footer for the FPU calculation section (1: minimum grams)(2: maximum grams)"), number(FPUConversion.minimumEquivalentGrams), number(FPUConversion.maximumEquivalentGrams)))
    }

    // MARK: - Row helpers

    private func infoRow(label: Text, value: Text) -> some View {
        HStack {
            label
                .foregroundColor(.primary)
            Spacer()
            value
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func calculationRow(label: String, value: String) -> some View {
        infoRow(label: Text(label), value: Text(value))
    }

    private func number(_ value: Double) -> String {
        Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func gramsString(_ value: Double) -> String {
        String(format: NSLocalizedString("%1$@ g", comment: "Gram value (1: number of grams)"), number(value))
    }

    private func timeString(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private func durationString(_ time: TimeInterval) -> String {
        Self.durationFormatter.string(from: time) ?? ""
    }
}

struct FPUCalculationInfoView_Previews: PreviewProvider {
    static var previews: some View {
        FPUCalculationInfoView(carbsGrams: 50, fatGrams: 30, proteinGrams: 25, adjustmentFactor: 0.5, mealStartDate: Date(), mealAbsorptionTime: .hours(3))
    }
}

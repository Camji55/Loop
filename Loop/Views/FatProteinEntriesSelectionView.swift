//
//  FatProteinEntriesSelectionView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

extension UserDefaults {
    static let fpuConversionEnabledKey = "com.loopkit.algorithmExperiments.fpuConversionEnabled"
    static let fpuAdjustmentFactorKey = "com.loopkit.algorithmExperiments.fpuAdjustmentFactor"

    var fpuConversionEnabled: Bool {
        get {
            bool(forKey: UserDefaults.fpuConversionEnabledKey)
        }
        set {
            set(newValue, forKey: UserDefaults.fpuConversionEnabledKey)
        }
    }

    var fpuAdjustmentFactor: Double {
        get {
            guard object(forKey: UserDefaults.fpuAdjustmentFactorKey) != nil else {
                return FPUConversion.defaultAdjustmentFactor
            }
            let factor = double(forKey: UserDefaults.fpuAdjustmentFactorKey)
            return factor.clamped(to: FPUConversion.adjustmentFactorRange)
        }
        set {
            set(newValue.clamped(to: FPUConversion.adjustmentFactorRange), forKey: UserDefaults.fpuAdjustmentFactorKey)
        }
    }
}

public struct FatProteinEntriesSelectionView: View {
    @Binding var isFPUConversionEnabled: Bool
    @AppStorage(UserDefaults.fpuAdjustmentFactorKey) private var adjustmentFactor = FPUConversion.defaultAdjustmentFactor

    private let factorChoices = stride(from: 10, through: 100, by: 5).map { Double($0) / 100 }

    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Fat & Protein Entries", comment: "Title for fat and protein entries experiment description"))
                    .font(.headline)
                    .padding(.bottom, 20)

                Divider()

                Text(NSLocalizedString("When enabled, the carb entry screen gains fat and protein fields. Loop converts their calories into a separate, smaller carb entry that starts one hour after the meal, using the Warsaw method: 100 kcal of fat and protein counts like 10 g of carbohydrate, scaled by the percentage below.\n\nThe delayed entry does not change the meal's bolus recommendation, and no insulin for it is bolused up front. It does join Loop's forecast right away, so automatic dosing begins working toward the predicted late rise on top of your meal bolus — another reason to start with a low percentage.\n\nWhen disabled, the carb entry screen and Loop's behavior are completely unchanged.\n\n⚠️ It's recommended to start at 50% or less.", comment: "Description of fat and protein entries experiment."))
                    .foregroundColor(.secondary)

                Divider()

                HStack {
                    Toggle(NSLocalizedString("Enable Fat & Protein Entries", comment: "Title for fat and protein entries toggle"), isOn: $isFPUConversionEnabled)
                    Spacer()
                }
                .padding(.top, 20)

                if isFPUConversionEnabled {
                    Divider()

                    HStack {
                        Text(NSLocalizedString("Fat & Protein Percentage", comment: "Label for the FPU adjustment factor picker"))
                        Spacer()
                        Picker(String(""), selection: $adjustmentFactor) {
                            ForEach(factorChoices, id: \.self) { factor in
                                Text("\(Int((factor * 100).rounded()))%")
                                    .tag(factor)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel(NSLocalizedString("Fat & Protein Percentage", comment: "Label for the FPU adjustment factor picker"))
                    }
                    .padding(.top, 8)

                    Text(NSLocalizedString("The fraction of the full Warsaw insulin equivalence to apply. 50% is the widely used starting point.", comment: "Footer describing the FPU adjustment factor"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

struct FatProteinEntriesSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FatProteinEntriesSelectionView(isFPUConversionEnabled: .constant(true))
        }
    }
}

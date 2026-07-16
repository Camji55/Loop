//
//  MealEntryManager.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI

let staticMealEntryManagersByIdentifier: [String: MealEntryManager.Type] = [
    DefaultMealEntryManager.pluginIdentifier: DefaultMealEntryManager.self
]

var availableStaticMealEntryManagers: [MealEntryManagerDescriptor] {
    [
        MealEntryManagerDescriptor(identifier: DefaultMealEntryManager.pluginIdentifier, localizedTitle: DefaultMealEntryManager.localizedTitle)
    ]
}

func MealEntryManagerFromRawValue(_ rawValue: [String: Any]) -> MealEntryManager? {
    guard let managerIdentifier = rawValue["managerIdentifier"] as? String,
          let rawState = rawValue["state"] as? MealEntryManager.RawStateValue,
          let Manager = staticMealEntryManagersByIdentifier[managerIdentifier]
    else {
        return nil
    }

    return Manager.init(rawState: rawState)
}

extension MealEntryManager {
    typealias RawValue = [String: Any]

    var rawValue: [String: Any] {
        return [
            "managerIdentifier": pluginIdentifier,
            "state": self.rawState
        ]
    }
}

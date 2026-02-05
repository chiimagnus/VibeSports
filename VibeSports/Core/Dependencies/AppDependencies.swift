//
//  AppDependencies.swift
//  VibeSports
//
//  Created by chii_magnus on 2026/2/5.
//

import Foundation

struct AppDependencies {
    var clock: Clock

    static func live() -> AppDependencies {
        AppDependencies(clock: SystemClock())
    }
}


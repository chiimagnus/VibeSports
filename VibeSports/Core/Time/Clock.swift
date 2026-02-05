//
//  Clock.swift
//  VibeSports
//
//  Created by chii_magnus on 2026/2/5.
//

import Foundation

protocol Clock {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}


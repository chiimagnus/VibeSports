//
//  ContentView.swift
//  VibeSports
//
//  Created by chii_magnus on 2026/1/28.
//

import SwiftUI

struct ContentView: View {
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live()) {
        self.dependencies = dependencies
    }

    var body: some View {
        RunnerGameHomeView(dependencies: dependencies)
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  BLEBackground
//
//  Created by Importants on 1/9/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Central") {
                    CentralView()
                }
                NavigationLink("Peripheral") {
                    PeripheralView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

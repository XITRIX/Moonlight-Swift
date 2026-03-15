//
//  AddHostView.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 15.03.2026.
//

import SwiftUI

struct AddHostView: View {

    @State private var addingManualIP: Bool = false
    @State private var addingManualIPHost: String = ""
    
    var body: some View {
        Button {
            addingManualIP = true
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderedProminent)
        .alert("Add Host Address", isPresented: $addingManualIP) {
            TextField("Host", text: $addingManualIPHost)

            Button("Cancel", role: .cancel) {}
            Button("OK") {
                Task {
                    let pin = PairManager.generatePin()
                    let res = await ConnectionHelper.pairHost(addingManualIPHost, with: pin)
                    print(res)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

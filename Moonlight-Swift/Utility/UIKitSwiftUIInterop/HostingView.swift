//
//  HostingView.swift
//  PJCore
//
//  Created by Даниил Виноградов on 05.11.2025.
//

import SwiftUI
import UIKit

public final class HostingView<Content: View>: UIView {
    public init(@ViewBuilder content: () -> Content) {
        super.init(frame: .zero)

        let contentView = UIHostingConfiguration(content: content)
            .margins(.all, 0)
            .makeContentView()

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

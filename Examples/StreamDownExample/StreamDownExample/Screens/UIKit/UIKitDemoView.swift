// UIKitDemoView.swift
// SwiftUI wrapper that hosts the UIKit demo view controller.

import SwiftUI

struct UIKitDemoView: View {
    var body: some View {
        UIKitDemoRepresentable()
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("UIKit")
    }
}

struct UIKitDemoRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIKitDemoViewController {
        UIKitDemoViewController()
    }

    func updateUIViewController(_ uiViewController: UIKitDemoViewController, context: Context) {}
}

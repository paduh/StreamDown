// CustomThemeEditorView.swift
// Form-based editor for customising Theme properties.

import SwiftUI
import StreamDownCore

struct CustomThemeEditorView: View {

    @Binding var theme: Theme

    var body: some View {
        Form {
            Section("Typography") {
                stepperRow(
                    label: "Body size",
                    value: Binding(get: { theme.typography.bodySize },
                                   set: { theme.typography.bodySize = $0 }),
                    range: 12...24,
                    unit: "pt"
                )
                stepperRow(
                    label: "Code size",
                    value: Binding(get: { theme.typography.codeSize },
                                   set: { theme.typography.codeSize = $0 }),
                    range: 10...20,
                    unit: "pt"
                )
            }

            Section("Code Blocks") {
                Picker("Syntax theme", selection: Binding(
                    get: { theme.codeBlock.syntaxTheme },
                    set: { theme.codeBlock.syntaxTheme = $0 }
                )) {
                    ForEach(SyntaxThemeName.allCases, id: \.self) { name in
                        Text(name.rawValue).tag(name)
                    }
                }

                Toggle("Line numbers", isOn: Binding(
                    get: { theme.codeBlock.showLineNumbers },
                    set: { theme.codeBlock.showLineNumbers = $0 }
                ))
            }

            Section("Spacing") {
                stepperRow(
                    label: "Block spacing",
                    value: Binding(get: { theme.spacing.blockSpacing },
                                   set: { theme.spacing.blockSpacing = $0 }),
                    range: 4...32,
                    unit: "pt"
                )
                stepperRow(
                    label: "Content padding",
                    value: Binding(get: { theme.spacing.contentPadding },
                                   set: { theme.spacing.contentPadding = $0 }),
                    range: 0...40,
                    unit: "pt"
                )
            }

            Section {
                Button("Reset to Default") {
                    theme = .default
                }
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func stepperRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        Stepper(
            value: value,
            in: range,
            step: 1
        ) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)")
                    .foregroundStyle(.secondary)
                    .font(.callout.monospacedDigit())
            }
        }
    }
}

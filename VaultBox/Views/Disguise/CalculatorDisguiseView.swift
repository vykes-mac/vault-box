import Foundation
import SwiftUI

enum CalculatorOperation: String {
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"
}

struct CalculatorEngine {
    private(set) var display = "0"
    private(set) var pendingOperation: CalculatorOperation?
    private var accumulator: Double?
    private var startsNewEntry = true

    mutating func inputDigit(_ digit: String) {
        guard digit.count == 1, digit.allSatisfy(\.isNumber) else { return }
        if startsNewEntry || display == "0" {
            display = digit
            startsNewEntry = false
        } else if display.count < 12 {
            display += digit
        }
    }

    mutating func inputDecimal() {
        if startsNewEntry {
            display = "0."
            startsNewEntry = false
        } else if !display.contains(".") {
            display += "."
        }
    }

    mutating func clear() {
        display = "0"
        accumulator = nil
        pendingOperation = nil
        startsNewEntry = true
    }

    mutating func toggleSign() {
        guard let value = Double(display), value != 0 else { return }
        display = formatted(-value)
    }

    mutating func percent() {
        guard let value = Double(display) else { return }
        display = formatted(value / 100)
        startsNewEntry = true
    }

    mutating func select(_ operation: CalculatorOperation) {
        if let pendingOperation, !startsNewEntry {
            evaluate(pendingOperation)
        } else if accumulator == nil {
            accumulator = Double(display)
        }
        pendingOperation = operation
        startsNewEntry = true
    }

    mutating func equals() {
        guard let pendingOperation else { return }
        evaluate(pendingOperation)
        self.pendingOperation = nil
        accumulator = nil
        startsNewEntry = true
    }

    private mutating func evaluate(_ operation: CalculatorOperation) {
        guard let left = accumulator, let right = Double(display) else { return }
        let result: Double
        switch operation {
        case .add: result = left + right
        case .subtract: result = left - right
        case .multiply: result = left * right
        case .divide:
            guard right != 0 else {
                display = "Error"
                accumulator = nil
                startsNewEntry = true
                return
            }
            result = left / right
        }
        display = formatted(result)
        accumulator = result
        startsNewEntry = true
    }

    private func formatted(_ value: Double) -> String {
        guard value.isFinite else { return "Error" }
        if value.rounded() == value, abs(value) < 1_000_000_000_000 {
            return String(Int64(value))
        }
        return String(format: "%.8g", value)
    }
}

struct CalculatorDisguiseView: View {
    @State private var engine = CalculatorEngine()

    private let rows = [
        ["AC", "+/−", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "="],
    ]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            let buttonSize = min((proxy.size.width - 52 - spacing * 3) / 4, 84)

            VStack(spacing: spacing) {
                Spacer(minLength: 12)

                Text(engine.display)
                    .font(.system(size: min(proxy.size.width * 0.18, 72), weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 26)
                    .accessibilityLabel("Calculator result")
                    .accessibilityValue(engine.display)

                ForEach(rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: \.self) { label in
                            calculatorButton(label, size: buttonSize)
                                .frame(
                                    width: label == "0" ? buttonSize * 2 + spacing : buttonSize,
                                    height: buttonSize
                                )
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
    }

    private func calculatorButton(_ label: String, size: CGFloat) -> some View {
        Button {
            handle(label)
        } label: {
            Text(label)
                .font(.system(size: size * 0.34, weight: .medium, design: .rounded))
                .foregroundStyle(buttonForeground(label))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(buttonBackground(label), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(label))
    }

    private func handle(_ label: String) {
        switch label {
        case "0"..."9": engine.inputDigit(label)
        case ".": engine.inputDecimal()
        case "AC": engine.clear()
        case "+/−": engine.toggleSign()
        case "%": engine.percent()
        case "=": engine.equals()
        case "+": engine.select(.add)
        case "−": engine.select(.subtract)
        case "×": engine.select(.multiply)
        case "÷": engine.select(.divide)
        default: break
        }
    }

    private func buttonBackground(_ label: String) -> Color {
        if ["÷", "×", "−", "+", "="].contains(label) {
            return .orange
        }
        if ["AC", "+/−", "%"].contains(label) {
            return Color(white: 0.72)
        }
        return Color(white: 0.19)
    }

    private func buttonForeground(_ label: String) -> Color {
        ["AC", "+/−", "%"].contains(label) ? .black : .white
    }

    private func accessibilityLabel(_ label: String) -> String {
        switch label {
        case "AC": "Clear"
        case "+/−": "Toggle sign"
        case "%": "Percent"
        case "÷": "Divide"
        case "×": "Multiply"
        case "−": "Subtract"
        case "+": "Add"
        case "=": "Equals"
        case ".": "Decimal"
        default: label
        }
    }
}

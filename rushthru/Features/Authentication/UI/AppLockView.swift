import SwiftUI

struct AppLockView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject var viewModel: LockViewModel
    @State private var lastInteraction = Date()

    private let keypad: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("ShelfTrack")
                    .font(.largeTitle.bold())
                Text("Enter store PIN to unlock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ForEach(0..<6) { index in
                    Circle()
                        .fill(index < viewModel.enteredPIN.count ? Color.accentColor : Color.gray.opacity(0.2))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 8)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            } else if viewModel.attemptsRemaining < 5 {
                Text("Attempts remaining: \(viewModel.attemptsRemaining)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(keypad, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { symbol in
                            Button(action: { tap(symbol) }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.secondarySystemBackground))
                                    if symbol == "⌫" {
                                        Image(systemName: "delete.left")
                                            .font(.title2)
                                    } else if symbol.isEmpty {
                                        Color.clear
                                    } else {
                                        Text(symbol)
                                            .font(.title2)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 56)
                            }
                            .disabled(symbol.isEmpty)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Button(action: submit) {
                Text(viewModel.isProcessing ? "Checking…" : "Unlock")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(Color.white)
            }
            .disabled(viewModel.enteredPIN.count < 4 || viewModel.isProcessing)
            .padding(.horizontal, 48)

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .onAppear {
            lastInteraction = Date()
        }
    }

    private func tap(_ symbol: String) {
        lastInteraction = Date()
        switch symbol {
        case "⌫":
            guard !viewModel.enteredPIN.isEmpty else { return }
            viewModel.enteredPIN.removeLast()
        case "":
            break
        default:
            guard viewModel.enteredPIN.count < 6 else { return }
            viewModel.enteredPIN.append(contentsOf: symbol)
        }
    }

    private func submit() {
        lastInteraction = Date()
        viewModel.submit(using: authService)
    }
}

#Preview {
    AppLockView(viewModel: LockViewModel())
        .environmentObject(AuthService())
}

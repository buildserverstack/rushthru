import Foundation
import Combine

@MainActor
final class LockViewModel: ObservableObject {
    enum State {
        case locked
        case unlocked
    }

    @Published private(set) var state: State = .locked
    @Published var enteredPIN: String = ""
    @Published var errorMessage: String?
    @Published var isProcessing: Bool = false
    @Published var attemptsRemaining: Int = 5

    private var cancellables = Set<AnyCancellable>()

    func bind(to authService: AuthService) {
        cancellables.removeAll()
        authService.$state
            .map { $0 == .unlocked ? State.unlocked : .locked }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.state = newValue
                if newValue == .locked {
                    self?.enteredPIN = ""
                }
            }
            .store(in: &cancellables)

        authService.$failedAttempts
            .map { max(0, 5 - $0) }
            .receive(on: DispatchQueue.main)
            .assign(to: &$attemptsRemaining)
    }

    func submit(using authService: AuthService) {
        guard !enteredPIN.isEmpty else { return }
        isProcessing = true
        Task {
            do {
                try await authService.verify(pin: enteredPIN)
                await MainActor.run {
                    self.errorMessage = nil
                    self.enteredPIN = ""
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.enteredPIN = ""
                    self.isProcessing = false
                }
            }
        }
    }

    func lock() {
        state = .locked
        enteredPIN = ""
    }

    func unlock() {
        state = .unlocked
    }
}

import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class HapticsManager {
    static let shared = HapticsManager()

    #if canImport(UIKit)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    #endif

    private init() {}

    func playSuccess() {
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(.success)
        #endif
    }

    func playWarning() {
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(.warning)
        #endif
    }

    func playError() {
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(.error)
        #endif
    }

    func playSelectionChanged() {
        #if canImport(UIKit)
        impactGenerator.impactOccurred()
        #endif
    }
}

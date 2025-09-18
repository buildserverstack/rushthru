import SwiftUI

enum DesignTokens {
    enum Colors {
        static let background = Color(.systemBackground)
        static let surface = Color(.secondarySystemBackground)
        static let primary = Color(red: 139/255, green: 92/255, blue: 246/255)
        static let primaryGradientEnd = Color(red: 236/255, green: 72/255, blue: 153/255)
        static let success = Color(red: 16/255, green: 185/255, blue: 129/255)
        static let warning = Color(red: 245/255, green: 158/255, blue: 11/255)
        static let error = Color(red: 239/255, green: 68/255, blue: 68/255)
    }

    enum Typography {
        static let title = Font.system(size: 28, weight: .semibold)
        static let subtitle = Font.system(size: 18, weight: .medium)
        static let body = Font.system(size: 16)
        static let label = Font.system(size: 14, weight: .medium)
        static let footnote = Font.system(size: 12)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

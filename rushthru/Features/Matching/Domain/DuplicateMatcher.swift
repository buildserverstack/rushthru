import Foundation

struct DuplicateMatcher {
    static func similarity(between lhs: ItemIdentity, and rhs: ItemIdentity) -> Double {
        let nameScore = stringSimilarity(lhs.normalizedName, rhs.normalizedName)
        let typeScore = lhs.normalizedType == rhs.normalizedType ? 1.0 : 0.0
        let sizeScore = lhs.normalizedSizeML == rhs.normalizedSizeML ? 1.0 : 0.0
        return (nameScore * 0.6) + (typeScore * 0.2) + (sizeScore * 0.2)
    }

    static func shouldMerge(lhs: ItemIdentity, rhs: ItemIdentity, threshold: Double = 0.88) -> Bool {
        similarity(between: lhs, and: rhs) >= threshold
    }

    private static func stringSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let distance = levenshtein(lhs, rhs)
        let maxLen = max(lhs.count, rhs.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        var matrix = Array(repeating: Array(repeating: 0, count: rhsChars.count + 1), count: lhsChars.count + 1)
        for i in 0...lhsChars.count { matrix[i][0] = i }
        for j in 0...rhsChars.count { matrix[0][j] = j }
        for i in 1...lhsChars.count {
            for j in 1...rhsChars.count {
                let cost = lhsChars[i - 1] == rhsChars[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        return matrix[lhsChars.count][rhsChars.count]
    }
}

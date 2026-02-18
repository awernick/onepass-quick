import Foundation

/// Fuzzy string matcher inspired by the fzy algorithm.
///
/// Matches query characters as a subsequence of the candidate string,
/// scoring based on character proximity, word boundaries, and
/// consecutive matches. Higher scores indicate better matches.
enum FuzzyMatcher {

    /// Result of a successful fuzzy match.
    struct Match {
        /// Overall match score. Higher is better.
        let score: Double

        /// Indices in the candidate where query characters matched.
        /// Useful for highlighting matched characters in the UI.
        let positions: [Int]
    }

    // MARK: - Scoring Constants

    private static let scoreGapLeading: Double = -0.005
    private static let scoreGapTrailing: Double = -0.005
    private static let scoreGapInner: Double = -0.01
    private static let scoreMatchConsecutive: Double = 1.0
    private static let scoreMatchSlash: Double = 0.9
    private static let scoreMatchWord: Double = 0.8
    private static let scoreMatchCapital: Double = 0.7
    private static let scoreMatchDot: Double = 0.6

    // MARK: - Public API

    /// Attempt to fuzzy-match `query` against `candidate`.
    ///
    /// Returns `nil` if the query characters don't appear as a
    /// subsequence in the candidate. Otherwise returns a `Match`
    /// with a score and the matched character positions.
    ///
    /// - Parameters:
    ///   - query: The search string (typically user input).
    ///   - candidate: The string to match against.
    /// - Returns: A `Match` if successful, `nil` otherwise.
    static func match(query: String, candidate: String) -> Match? {
        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate.lowercased())
        let originalChars = Array(candidate)
        let n = queryChars.count
        let m = candidateChars.count

        guard n > 0, m > 0, n <= m else { return nil }

        // Quick check: is query a subsequence of candidate?
        var qi = 0
        for ci in 0..<m where qi < n {
            if candidateChars[ci] == queryChars[qi] {
                qi += 1
            }
        }
        guard qi == n else { return nil }

        // Perfect length match — compute score directly without DP
        if n == m {
            let bonus = computeBonus(originalChars)
            let score = bonus[0]
                + Double(n - 1) * scoreMatchConsecutive
            return Match(score: score, positions: Array(0..<n))
        }

        // Precompute word-boundary bonuses
        let bonus = computeBonus(originalChars)

        // DP tables
        // D[i][j] = best score when query[i] matches candidate[j]
        // M[i][j] = best score for query[0..i] against candidate[0..j]
        let negInf = -Double.infinity
        var D = Array(
            repeating: Array(repeating: negInf, count: m),
            count: n
        )
        var M = Array(
            repeating: Array(repeating: negInf, count: m),
            count: n
        )

        for i in 0..<n {
            var prevScore = negInf
            let gapScore = (i == n - 1)
                ? scoreGapTrailing : scoreGapInner

            for j in 0..<m {
                if queryChars[i] == candidateChars[j] {
                    var score = negInf
                    if i == 0 {
                        score = Double(j) * scoreGapLeading + bonus[j]
                    } else if j > 0 {
                        score = max(
                            M[i - 1][j - 1] + bonus[j],
                            D[i - 1][j - 1] + scoreMatchConsecutive
                        )
                    }
                    D[i][j] = score
                    M[i][j] = max(score, prevScore + gapScore)
                    prevScore = M[i][j]
                } else {
                    D[i][j] = negInf
                    M[i][j] = prevScore + gapScore
                    prevScore = M[i][j]
                }
            }
        }

        // Backtrace to find optimal match positions
        let positions = backtrace(D: D, M: M, n: n, m: m)

        return Match(score: M[n - 1][m - 1], positions: positions)
    }

    // MARK: - Private Helpers

    /// Compute word-boundary bonus for each position in the candidate.
    private static func computeBonus(_ chars: [Character]) -> [Double] {
        var result = [Double](repeating: 0, count: chars.count)
        // Treat start of string as after a separator
        var lastChar: Character = "/"

        for i in 0..<chars.count {
            let ch = chars[i]
            if lastChar == "/" || lastChar == "\\" {
                result[i] = scoreMatchSlash
            } else if lastChar == "-" || lastChar == "_"
                || lastChar == " "
            {
                result[i] = scoreMatchWord
            } else if lastChar == "." {
                result[i] = scoreMatchDot
            } else if lastChar.isLowercase && ch.isUppercase {
                result[i] = scoreMatchCapital
            }
            lastChar = ch
        }

        return result
    }

    /// Walk the DP tables backward to find the positions that produced
    /// the optimal score.
    private static func backtrace(
        D: [[Double]], M: [[Double]], n: Int, m: Int
    ) -> [Int] {
        var positions = [Int](repeating: 0, count: n)
        var matchRequired = false
        var col = m - 1

        for i in stride(from: n - 1, through: 0, by: -1) {
            while col >= 0 {
                if D[i][col] != -Double.infinity
                    && (matchRequired || D[i][col] == M[i][col])
                {
                    matchRequired = i > 0 && col > 0
                        && M[i][col] == D[i - 1][col - 1]
                            + scoreMatchConsecutive
                    positions[i] = col
                    col -= 1
                    break
                }
                col -= 1
            }
        }

        return positions
    }
}

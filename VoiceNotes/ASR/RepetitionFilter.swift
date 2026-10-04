import Foundation

/// Collapses runaway repetition loops that Whisper sometimes emits, e.g.
/// "to operate on the defense to operate on the defense ..." repeated dozens
/// of times. Applied as a safety net on top of the decoder's temperature
/// fallback, which is the primary defense against this failure mode.
///
/// The filter is conservative: it only collapses a unit that repeats
/// consecutively at least `minRepeats` times, and short (single-word) units
/// need more repeats because emphatic repeats ("no no no") are legitimate.
enum RepetitionFilter {
    /// - Parameters:
    ///   - maxUnitWords: longest repeated phrase (in words) to look for.
    ///   - minRepeats: minimum consecutive repetitions of a multi-word unit
    ///     before collapsing it to a single occurrence.
    static func removeRepetition(
        _ text: String,
        maxUnitWords: Int = 20,
        minRepeats: Int = 3
    ) -> String {
        guard !text.isEmpty else { return text }

        let units = tokenize(text)
        guard units.count >= minRepeats else { return text }

        let words = units.map { normalize($0.word) }
        var drop = [Bool](repeating: false, count: units.count)

        let maxUnit = min(maxUnitWords, max(1, units.count / minRepeats))
        if maxUnit >= 1 {
            for n in 1...maxUnit {
                // A single repeated word is more likely to be emphasis, so it
                // must repeat more often before we consider it a loop.
                let requiredRepeats = n == 1 ? max(minRepeats, 4) : minRepeats
                if n * requiredRepeats > units.count { continue }

                var i = 0
                while i + n <= units.count {
                    var repeats = 1
                    while i + (repeats + 1) * n <= units.count {
                        if Array(words[i..<i + n]) == Array(words[i + repeats * n..<i + (repeats + 1) * n]) {
                            repeats += 1
                        } else {
                            break
                        }
                    }

                    if repeats >= requiredRepeats {
                        for repeatIndex in 1..<repeats {
                            for offset in 0..<n {
                                drop[i + repeatIndex * n + offset] = true
                            }
                        }
                        i += n
                    } else {
                        i += 1
                    }
                }
            }
        }

        guard drop.contains(true) else { return text }

        var result = ""
        for (index, unit) in units.enumerated() where !drop[index] {
            result += unit.raw
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Unit {
        let word: String
        let raw: String
    }

    /// Splits `text` into words plus the trailing whitespace that follows each,
    /// so reconstruction preserves the original spacing and line breaks of the
    /// words that are kept.
    private static func tokenize(_ text: String) -> [Unit] {
        var units: [Unit] = []
        var word = ""
        var trailing = ""
        var inWord = false

        for character in text {
            if character.isWhitespace {
                if inWord {
                    trailing.append(character)
                    inWord = false
                } else {
                    trailing.append(character)
                }
            } else {
                if !inWord {
                    if !word.isEmpty {
                        units.append(Unit(word: word, raw: word + trailing))
                        word = ""
                        trailing = ""
                    }
                    inWord = true
                }
                word.append(character)
            }
        }
        if !word.isEmpty {
            units.append(Unit(word: word, raw: word + trailing))
        } else if !trailing.isEmpty, var last = units.popLast() {
            units.append(Unit(word: last.word, raw: last.raw + trailing))
        }
        return units
    }

    /// Case-insensitive comparison key with surrounding punctuation removed, so
    /// "Defense." and "defense" are treated as the same token.
    private static func normalize(_ word: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        let trimmed = word.trimmingCharacters(in: punctuation).lowercased()
        return trimmed.isEmpty ? word.lowercased() : trimmed
    }
}

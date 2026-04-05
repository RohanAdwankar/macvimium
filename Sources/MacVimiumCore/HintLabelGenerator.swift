public enum HintLabelGenerator {
    private static let alphabet = Array("ASDFGHJKLQWERTYUIOPZXCVBNM")

    public static func labels(count: Int) -> [String] {
        guard count > 0 else {
            return []
        }

        var result: [String] = []
        var width = 1

        while result.count < count {
            build(width: width, prefix: "", into: &result, limit: count)
            width += 1
        }

        return result
    }

    private static func build(width: Int, prefix: String, into result: inout [String], limit: Int) {
        guard result.count < limit else {
            return
        }

        if prefix.count == width {
            result.append(prefix)
            return
        }

        for character in alphabet {
            build(width: width, prefix: prefix + String(character), into: &result, limit: limit)
            if result.count >= limit {
                return
            }
        }
    }
}

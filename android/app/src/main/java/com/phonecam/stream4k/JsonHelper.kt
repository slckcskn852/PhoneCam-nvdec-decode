package com.phonecam.stream4k

object JsonHelper {
    fun parse(jsonStr: String): Map<String, Any> {
        val result = mutableMapOf<String, Any>()
        val trimmed = jsonStr.trim()
        if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return result
        val content = trimmed.removeSurrounding("{", "}")
        val pairs = splitIgnoringBrackets(content)
        for (pair in pairs) {
            val parts = pair.split(":", limit = 2)
            if (parts.size != 2) continue
            val key = parts[0].trim().removeSurrounding("\"")
            val valStr = parts[1].trim()
            if (valStr.startsWith("{")) {
                result[key] = parse(valStr)
            } else if (valStr.startsWith("[")) {
                result[key] = parseList(valStr)
            } else {
                result[key] = parsePrimitive(valStr)
            }
        }
        return result
    }

    private fun splitIgnoringBrackets(s: String): List<String> {
        val result = mutableListOf<String>()
        var bracketCount = 0
        var braceCount = 0
        var inQuotes = false
        var current = StringBuilder()
        for (c in s) {
            if (c == '"') inQuotes = !inQuotes
            if (!inQuotes) {
                if (c == '[') bracketCount++
                if (c == ']') bracketCount--
                if (c == '{') braceCount++
                if (c == '}') braceCount--
                if (c == ',' && bracketCount == 0 && braceCount == 0) {
                    result.add(current.toString())
                    current = StringBuilder()
                    continue
                }
            }
            current.append(c)
        }
        if (current.isNotEmpty()) {
            result.add(current.toString())
        }
        return result
    }

    private fun parseList(s: String): List<Any> {
        val trimmed = s.trim().removeSurrounding("[", "]")
        if (trimmed.isEmpty()) return emptyList()
        val parts = trimmed.split(",")
        return parts.map { parsePrimitive(it.trim()) }
    }

    private fun parsePrimitive(s: String): Any {
        val trimmed = s.trim()
        if (trimmed.startsWith("\"") && trimmed.endsWith("\"")) {
            return trimmed.removeSurrounding("\"")
        }
        if (trimmed == "true") return true
        if (trimmed == "false") return false
        if (trimmed == "null") return Unit
        val intVal = trimmed.toIntOrNull()
        if (intVal != null) return intVal
        val doubleVal = trimmed.toDoubleOrNull()
        if (doubleVal != null) return doubleVal
        return trimmed
    }
}

import Testing
@testable import AgendaCore

struct SearchTextTests {
    @Test func ignoresCaseAndAccents() {
        #expect(SearchText.matches("Matemáticas Discretas", "matematicas"))
        #expect(SearchText.matches("Taller de BD", "taller"))
        #expect(!SearchText.matches("Taller", "parcial"))
        #expect(!SearchText.matches("Taller", "  "))
    }

    @Test func snippetIsTheMatchingLine() {
        let text = "# Clase 3\n\nNormalización hasta 3FN.\n- Dependencias funcionales"
        #expect(SearchText.snippet(text, "normalizacion") == "Normalización hasta 3FN.")
        #expect(SearchText.snippet(text, "dependencias") == "Dependencias funcionales")
        #expect(SearchText.snippet(text, "clase") == "Clase 3")
        #expect(SearchText.snippet(text, "árbol") == nil)
    }

    @Test func longLinesAreTrimmedAroundTheMatch() {
        let text = String(repeating: "a", count: 200) + " objetivo " + String(repeating: "b", count: 200)
        let snippet = SearchText.snippet(text, "objetivo", width: 60)!
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.contains("objetivo"))
        #expect(snippet.count <= 62)
    }
}

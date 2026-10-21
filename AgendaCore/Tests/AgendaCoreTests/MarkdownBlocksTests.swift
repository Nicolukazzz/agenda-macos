import Testing
@testable import AgendaCore

struct MarkdownBlocksTests {
    @Test func parsesCommonBlocks() {
        let source = """
        # Normalización
        Texto con **negrita**
        que sigue.

        - uno
          - anidado
        1. primero
        - [x] hecho
        - [ ] pendiente
        > cita
        ---
        ```sql
        SELECT *
          FROM t;
        ```
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        #expect(MarkdownBlocks.parse(source) == [
            .heading(level: 1, text: "Normalización"),
            .paragraph("Texto con **negrita** que sigue."),
            .bullet(indent: 0, text: "uno"),
            .bullet(indent: 1, text: "anidado"),
            .numbered(indent: 0, number: 1, text: "primero"),
            .checkbox(indent: 0, checked: true, text: "hecho"),
            .checkbox(indent: 0, checked: false, text: "pendiente"),
            .quote("cita"),
            .rule,
            .code(language: "sql", text: "SELECT *\n  FROM t;"),
            .table(rows: [["A", "B"], ["1", "2"]]),
        ])
    }

    @Test func unclosedCodeBlockKeepsText() {
        #expect(MarkdownBlocks.parse("```\nlet x = 1") == [.code(language: "", text: "let x = 1")])
    }
}

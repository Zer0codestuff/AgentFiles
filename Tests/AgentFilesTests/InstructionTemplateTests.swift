import Foundation
import Testing

@testable import AgentFiles

@Suite("Instruction template")
struct InstructionTemplateTests {
  private let codex = """
    # Personal Codex defaults

    ## Language
    - Keep artifacts in English.
    - Use Codex's question tool.

    ## Interests
    - I enjoy ASCII art.

    """

  private let factory = """
    # Personal Droid defaults

    ## Language
    - Keep artifacts in English.
    - Use Droid's question tool.

    """

  @Test
  func importingReproducesEveryFileExactly() {
    let template = InstructionTemplate.importing(
      base: codex,
      others: [(key: "factory", content: factory), (key: "claude", content: "")]
    )

    #expect(template.render(for: "codex") == codex)
    #expect(template.render(for: "factory") == factory)
    #expect(template.render(for: "claude") == "")
  }

  @Test
  func textRoundTripsThroughMarkers() {
    let template = InstructionTemplate.importing(
      base: codex,
      others: [(key: "factory", content: factory)]
    )

    let reparsed = InstructionTemplate(parsing: template.text)

    #expect(reparsed == template)
    #expect(template.text.contains("<!-- except: factory -->"))
    #expect(template.text.contains("<!-- only: factory -->"))
    #expect(!template.render(for: "codex").contains("<!--"))
  }

  @Test
  func sharedEditReachesEveryFileThatHasTheLine() {
    let template = InstructionTemplate.importing(
      base: codex,
      others: [(key: "factory", content: factory)]
    )
    let edited = codex.replacingOccurrences(
      of: "- Keep artifacts in English.",
      with: "- Keep every artifact in English."
    )

    let updated = template.applying(edited: edited, from: "codex", scope: .shared)

    #expect(updated.render(for: "codex") == edited)
    #expect(updated.render(for: "factory").contains("- Keep every artifact in English."))
    #expect(updated.render(for: "factory").contains("# Personal Droid defaults"))
  }

  @Test
  func privateEditOnlyChangesOneFile() {
    let template = InstructionTemplate(shared: codex)
    let edited = codex + "- Codex only.\n"

    let updated = template.applying(edited: edited, from: "codex", scope: .only("codex"))

    #expect(updated.render(for: "codex") == edited)
    #expect(updated.render(for: "factory") == codex)
    #expect(updated.specificLineCount(for: "codex") == 1)
  }

  @Test
  func sharedEditOfAgentSpecificLineKeepsItsAudience() {
    let template = InstructionTemplate.importing(
      base: codex,
      others: [(key: "factory", content: factory)]
    )
    let edited = factory.replacingOccurrences(of: "Droid's", with: "the Droid")

    let updated = template.applying(edited: edited, from: "factory", scope: .shared)

    #expect(updated.render(for: "factory") == edited)
    #expect(updated.render(for: "codex") == codex)
  }

  @Test
  func variationsGroupFilesBySharedText() throws {
    let template = InstructionTemplate.importing(
      base: codex,
      others: [(key: "factory", content: factory), (key: "grok", content: codex)]
    )

    let variations = template.variations(keys: ["codex", "factory", "grok"])

    // The tool line and the Interests section sit next to each other, so they form
    // one difference.
    try #require(variations.count == 2)
    #expect(variations[0].section == nil)
    #expect(variations[0].alternatives.map(\.keys) == [["codex", "grok"], ["factory"]])
    #expect(variations[1].section == "## Language")
    #expect(variations[1].alternatives.last?.lines == ["- Use Droid's question tool."])
  }

  @Test
  func resolvingAVariationSharesTheChosenText() {
    let template = InstructionTemplate.importing(
      base: codex,
      others: [(key: "factory", content: factory)]
    )
    let title = template.variations(keys: ["codex", "factory"])[0]

    let updated = template.resolving(title, with: ["# Personal defaults"])
      .pruned(keys: ["codex", "factory"])

    #expect(updated.render(for: "codex").hasPrefix("# Personal defaults\n"))
    #expect(updated.render(for: "factory").hasPrefix("# Personal defaults\n"))
    #expect(updated.variations(keys: ["codex", "factory"]).count == 1)
  }

  @Test
  func pruningSimplifiesAudiences() {
    let template = InstructionTemplate(lines: [
      TemplateLine(text: "a", audience: .only(["codex", "factory"])),
      TemplateLine(text: "b", audience: .except(["gone"])),
      TemplateLine(text: "c", audience: .except(["codex", "factory"])),
    ])

    let pruned = template.pruned(keys: ["codex", "factory"])

    #expect(pruned.lines.map(\.audience) == [.everyone, .everyone])
    #expect(pruned.lines.map(\.text) == ["a", "b"])
  }
}

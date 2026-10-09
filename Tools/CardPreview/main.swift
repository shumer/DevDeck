import AppKit
import DevDeckCore
import DevDeckEngine
import DevDeckLocalization
import DevDeckUI
import SwiftUI

// Renders every card of a protocol transcript the way the Mac draws it, one PNG per state, so a
// card on Windows can be put next to the same card on the Mac on the same data. The transcripts
// in Tests/EngineTests/Golden are neutral by construction, which is what a screenshot for the
// repository has to be.
//
//   swift run CardPreview Tests/EngineTests/Golden/session-en.expected.jsonl /tmp/cards
//
// Each file is `<card id>-<n>.png`, `n` counting the card's distinct states in the order the
// transcript sent them.

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2 else {
    print("usage: CardPreview <transcript.jsonl> <output directory>")
    exit(1)
}
let transcript = URL(fileURLWithPath: arguments.first!)
let output = URL(fileURLWithPath: arguments.last!, isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// The models carry their words already; the tables are only for the few labels a view says
// itself, in the transcript's language.
Strings.use(transcript.lastPathComponent.contains("-ru") ? .russian : .english, lookingIn: LocalizationResources.root)

/// One line of the transcript, as much of it as this needs.
struct Line: Decodable {
    let event: String
    let card: CardID?
    let model: DeckCardModel?
}

/// A card's size as the Mac sizes it, and the view the Mac draws.
@MainActor
func render(_ model: DeckCardModel) -> (size: CGSize, view: AnyView) {
    switch model {
    case .reviewList(let model): return (ReviewListCard.size(for: model), AnyView(ReviewListCard(model: model)))
    case .inbox(let model): return (InboxCard.size(for: model), AnyView(InboxCard(model: model)))
    case .actions(let model): return (ActionsCard.size(isCollapsed: model.isCollapsed), AnyView(ActionsCard(model: model)))
    case .workInFlight(let model): return (WorkInFlightCard.size(for: model), AnyView(WorkInFlightCard(model: model)))
    case .project(let model): return (ProjectCard.size(for: model), AnyView(ProjectCard(model: model)))
    }
}

/// Whether the model is the folded row, which has the smaller radius.
func isCollapsed(_ model: DeckCardModel) -> Bool {
    switch model {
    case .reviewList(let model): return model.isCollapsed
    case .inbox(let model): return model.isCollapsed
    case .actions(let model): return model.isCollapsed
    case .workInFlight(let model): return model.isCollapsed
    case .project(let model): return model.isCollapsed
    }
}

/// The panel as the window draws it: a dark veil with a hairline, on a bit of desktop.
struct Panel: View {
    let size: CGSize
    let radius: CGFloat
    let content: AnyView

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.04, green: 0.05, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(white: 0.17))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black.opacity(0.30))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                content
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width + 48, height: size.height + 48)
        .preferredColorScheme(.dark)
    }
}

@MainActor
func write(_ model: DeckCardModel, to file: URL) throws {
    let (size, view) = render(model)
    let radius = isCollapsed(model) ? CGFloat(CollapsedCardMetrics.cornerRadius) : DeckTheme.cornerRadius
    let renderer = ImageRenderer(content: Panel(size: size, radius: radius, content: view))
    renderer.scale = 2
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: file)
}

let decoder = JSONDecoder()
var seen: [CardID: [DeckCardModel]] = [:]
var written = 0
for line in try String(contentsOf: transcript, encoding: .utf8).split(separator: "\n") {
    guard let parsed = try? decoder.decode(Line.self, from: Data(line.utf8)),
          parsed.event == "card.changed", let card = parsed.card, let model = parsed.model
    else { continue }
    // Only a state the card has not been in: a model sent again because its menu changed is
    // the same picture.
    if seen[card, default: []].contains(model) { continue }
    seen[card, default: []].append(model)
    let file = output.appendingPathComponent("\(card.rawValue)-\(seen[card]!.count).png")
    try MainActor.assumeIsolated { try write(model, to: file) }
    written += 1
}
print("\(written) cards written to \(output.path)")

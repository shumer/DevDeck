import AppKit
import DevDeckCore
import DevDeckUI
import SwiftUI

/// Everything the application layer knows about one kind of card.
///
/// Adding a kind used to mean an `if` in `CardHostView`, a case in its size switch, a group
/// in the menu, a branch in the catalog and a form in the settings window: five files, none
/// of which said "this is a kind of card". A module says it. The deck asks every module which
/// cards it owns and takes the view, the size and the dashboard from the one that says yes.
@MainActor
protocol CardModule: AnyObject {
    /// The group a project card of this kind goes under in the menu, with the count in the
    /// title. Nil for a built-in card, which sits at the top level.
    var menuGroup: String? { get }

    /// The descriptors this module adds beyond `CardCatalog.all`: one per configured project,
    /// in the order the deck lays them out. Built-in cards return nothing, since the catalog
    /// already has them.
    func descriptors() -> [CardDescriptor]

    func owns(_ card: CardID) -> Bool

    /// The card's view. Built fresh each time the host redraws, which is how it tracks the
    /// controller.
    func view(for card: CardID) -> AnyView

    /// The panel size for the card as it is right now.
    func size(for card: CardID) -> NSSize

    /// Where a double-click on the panel goes: the same data, on the web. Nil for a card that
    /// has no web page.
    func dashboardURL(for card: CardID) -> URL?
}

extension CardModule {
    var menuGroup: String? { nil }
    func descriptors() -> [CardDescriptor] { [] }
    func dashboardURL(for card: CardID) -> URL? { nil }
}

/// What every module is built with: the controller, and the few things a card does that are
/// not the controller's business, such as which browser a link opens in.
@MainActor
struct ModuleContext {
    let controller: DeckController

    /// Rows open in the browser of the account they belong to - one signed-in identity per
    /// browser profile is the whole reason accounts exist.
    func openGitHub(_ url: URL, account: String) {
        LinkOpener.open(url, using: controller.browser(for: account))
    }

    /// GitLab rows open in the browser of the instance they came from, for the same reason.
    func openGitLab(_ url: URL, account: String) {
        LinkOpener.open(url, using: controller.gitlabBrowser(for: account))
    }

    /// Nil on a machine whose runtime has no application to open, which is how the cards know
    /// to show a disabled Start rather than a button that would do nothing.
    var startDocker: (() -> Void)? {
        controller.canStartDocker ? { controller.startDockerRuntime() } : nil
    }
}

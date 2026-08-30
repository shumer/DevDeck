import DevDeckCore
import SwiftUI

/// The Docker precondition, said the same way on every card that has one.
///
/// A card whose project cannot start without Docker has to answer a different question when
/// Docker is down: not "is this project running" - obviously not - but "why is the button
/// there at all". Pressing Start with no daemon produces a wall of shell output the card has
/// nowhere to put, so the card says what is wrong instead and offers the thing that fixes it.
public enum DockerGate {
    /// Whether the card should talk about Docker rather than about the project.
    ///
    /// A running project is never gated: something is clearly serving it, and no amount of
    /// probing beats that.
    public static func blocks(_ status: DockerStatus, isRunning: Bool, requiresDocker: Bool) -> Bool {
        guard requiresDocker, !isRunning else { return false }
        return !status.allowsStart
    }

    public static func pillText(_ status: DockerStatus) -> String {
        switch status.state {
        case .notInstalled: return "no docker"
        case .starting: return "docker starting…"
        default: return "docker off"
        }
    }

    /// What goes on the state line.
    public static func text(_ status: DockerStatus) -> String {
        switch status.state {
        case .notInstalled: return "Docker is not installed, nothing here can run"
        case .starting: return "starting Docker…"
        default: return "Docker is not running, start it first"
        }
    }

    public static func color(_ status: DockerStatus) -> Color {
        status.state == .notInstalled ? DeckTheme.red : DeckTheme.amber
    }

    public static func pill(_ status: DockerStatus) -> (text: String, color: Color) {
        (pillText(status), color(status))
    }

    /// The action that replaces Start while Docker is in the way.
    ///
    /// `onStart` is nil when there is no runtime to launch - a machine on Colima has a CLI and
    /// no app to open - and then there is nothing to offer but the disabled Start.
    public static func startAction(_ status: DockerStatus, onStart: (() -> Void)?) -> CardAction {
        guard let onStart else {
            return CardAction("Start", systemImage: "play.fill", tint: DeckTheme.green, isEnabled: false)
        }
        return CardAction(
            "Start Docker",
            systemImage: "shippingbox.fill",
            tint: DeckTheme.amber,
            isEnabled: status.state == .notRunning,
            isProminent: true,
            action: onStart
        )
    }
}

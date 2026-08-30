import AppKit
import DevDeckCore
import SwiftUI

/// The local site, addressed so a phone on the same network can ask for it.
///
/// The cheapest of the three ways to get a running site onto a phone, and the only one that
/// needs no account, no tunnel and nothing published to the internet: the site is already being
/// served, it is only being asked for by a name that means "this device". Swapping `localhost`
/// for the machine's address on the wifi is the whole trick.
public struct PhoneSheet: View {
    private let url: URL
    private let onCopy: (String) -> Void

    public init(url: URL, onCopy: @escaping (String) -> Void = { _ in }) {
        self.url = url
        self.onCopy = onCopy
    }

    public nonisolated static let codeSize: CGFloat = 148

    public var body: some View {
        VStack(spacing: 10) {
            Text("Open on your phone")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(DeckTheme.value.opacity(0.55))

            if let image = QRCodeImage.make(from: url.absoluteString, size: Self.codeSize) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Self.codeSize, height: Self.codeSize)
                    // On white, always. A QR code inverted or tinted is one a phone thinks about
                    // for a second longer than it should.
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text(url.absoluteString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DeckTheme.value.opacity(0.75))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Same wifi as this Mac. A dev server bound to localhost only will not answer.")
                .font(.system(size: 10))
                .foregroundStyle(DeckTheme.value.opacity(0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            CardActionButton("Copy the link", systemImage: "doc.on.doc", isProminent: true) {
                onCopy(url.absoluteString)
            }
            .frame(width: 148)
        }
        .padding(16)
        .frame(width: 200)
    }
}

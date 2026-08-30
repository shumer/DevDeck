import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// A URL as a square somebody can point a phone at.
///
/// CoreImage's generator rather than an encoder of our own. A QR encoder is four hundred lines of
/// Reed-Solomon, mask selection and format bits, all of it a solved problem that ships with the
/// system, and none of it something this app should be maintaining to draw one square.
public enum QRCodeImage {
    /// Nil only if CoreImage refuses, which for a short ASCII URL it does not.
    public static func make(from text: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // The lowest correction level: this code is read from a screen a foot away, not off a
        // parcel, and lower correction means fewer modules and fatter, more scannable ones.
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }

        // Scaled up before rasterising, and with nearest-neighbour sampling, because a QR code
        // resampled smoothly is a QR code with grey edges that a phone hesitates over.
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

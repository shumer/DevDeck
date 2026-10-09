import Foundation

public enum LocalizationResources {
    public static var root: URL { Bundle.module.resourceURL ?? Bundle.module.bundleURL }
}

import DevDeckCore
import Foundation

#if os(Windows)
let arguments = Array(CommandLine.arguments.dropFirst())
do {
    if arguments == ["--supervise"] {
        try WindowsProjectHost.supervise()
    } else if arguments.count == 2, arguments[0] == "--interrupt", let pid = UInt32(arguments[1]) {
        exit(WindowsProjectHost.interrupt(pid: pid) ? 0 : 1)
    } else {
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("Project process host failed.\n".utf8))
    exit(1)
}
#endif

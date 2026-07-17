import Foundation
import OpenMusicEventReleaseTools

#if os(Linux)
import Glibc
#elseif os(Windows)
import CRT
#else
import Darwin
#endif

@main
struct OpenMusicEventReleaseCheck {
    static func main() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let issues = try ReleaseMetadataGate().validate(rootURL: rootURL)
        let report = ReleaseMetadataGateReport(issues: issues)

        print(report.render())

        if !report.didPass {
            exit(1)
        }
    }
}

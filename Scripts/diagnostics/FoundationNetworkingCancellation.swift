// Native Android regression reproducer. Compile with the same Swift SDK as OME.
// Stock 6.3.3 deadlocks; PR 5417 alone can trap in TaskRegistry.
// Run with a process timeout; every request must reach completion.
import Foundation
import FoundationNetworking
import Android

@main
struct CancellationProbe {
    static func main() async {
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "http://127.0.0.1:19999/")!
        for iteration in 1...3000 {
            let request = Task { try? await session.data(from: url) }
            try? await Task.sleep(nanoseconds: 100_000)
            request.cancel()
            _ = await request.value
            if iteration % 100 == 0 {
                print("completed", iteration)
                fflush(nil)
            }
        }
        print("PASS: 3000 cancellation/completion races")
        fflush(nil)
    }
}

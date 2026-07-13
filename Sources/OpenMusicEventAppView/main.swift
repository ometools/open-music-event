import OpenMusicEventAppViewServer

let configuration = AppViewConfiguration.fromEnvironment()
let app = try OpenMusicEventAppViewServer.application(configuration: configuration)
try await app.runService()

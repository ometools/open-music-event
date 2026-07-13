import AWSLambdaEvents
import HummingbirdLambda
import OpenMusicEventAppViewServer

let configuration = AppViewConfiguration.lambda()
let router = OpenMusicEventAppViewServer.router(
    context: BasicLambdaRequestContext<APIGatewayV2Request>.self,
    configuration: configuration
)
let lambda = APIGatewayV2LambdaFunction(router: router)

try await lambda.runService()

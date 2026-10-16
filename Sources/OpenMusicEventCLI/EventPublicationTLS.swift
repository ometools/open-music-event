import Foundation
import HTTPTypesFoundation
import Security
import struct ArgumentParser.ValidationError

/// Trust an explicitly supplied private PDS CA for this invocation only.
final class EventPublicationTLS: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let certificate: Data
    let host: String

    init(certificateURL: URL, host: String) throws {
        let bytes = try Data(contentsOf: certificateURL)
        if let pem = String(data: bytes, encoding: .utf8), pem.contains("-----BEGIN CERTIFICATE-----") {
            let encoded = pem.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
                .filter { !$0.isWhitespace }
            guard let der = Data(base64Encoded: encoded) else { throw ValidationError("Invalid CA certificate.") }
            certificate = der
        } else {
            certificate = bytes
        }
        guard SecCertificateCreateWithData(nil, certificate as CFData) != nil else {
            throw ValidationError("Invalid CA certificate.")
        }
        self.host = host
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust,
              let anchor = SecCertificateCreateWithData(nil, certificate as CFData),
              SecTrustSetAnchorCertificates(trust, [anchor] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

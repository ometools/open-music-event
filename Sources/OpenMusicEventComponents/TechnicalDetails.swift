import Foundation

public enum TechnicalDetails {
    public static let environmentVariable = "OME_SHOW_TECHNICAL_DETAILS"
    public static let userDefaultsKey = "showTechnicalDetails"

    public static func environmentOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool? {
        guard let value = environment[environmentVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return nil }

        switch value {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    public static func isVisible(
        userPreference: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environmentOverride(environment: environment) ?? userPreference
    }

    public static func identityTitle(
        displayName: String?,
        handle: String?,
        technicalID: String,
        isVisible: Bool
    ) -> String {
        displayName?.technicalDetailsDisplayValue
            ?? handle?.technicalDetailsHandle
            ?? (isVisible ? technicalID.technicalDetailsDisplayValue : nil)
            ?? "Account"
    }

    public static func identitySubtitle(
        displayName: String?,
        handle: String?,
        technicalID: String,
        isVisible: Bool
    ) -> String? {
        let displayName = displayName?.technicalDetailsDisplayValue
        let handle = handle?.technicalDetailsHandle
        let technicalID = technicalID.technicalDetailsDisplayValue

        guard isVisible else {
            return displayName == nil ? nil : handle
        }
        guard let technicalID else {
            return displayName == nil ? nil : handle
        }
        guard let handle else { return technicalID }
        return displayName == nil
            ? technicalID
            : "\(handle) - \(technicalID)"
    }
}

private extension String {
    var technicalDetailsDisplayValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var technicalDetailsHandle: String? {
        guard let value = technicalDetailsDisplayValue else { return nil }
        return value.hasPrefix("@") ? value : "@\(value)"
    }
}

#if os(Android) || canImport(SwiftUI)
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#else
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

enum TechnicalDetailsEnvironmentKey: EnvironmentKey {
    static let defaultValue = TechnicalDetails.isVisible(userPreference: false)
}

public extension EnvironmentValues {
    var showsTechnicalDetails: Bool {
        get { self[TechnicalDetailsEnvironmentKey.self] }
        set { self[TechnicalDetailsEnvironmentKey.self] = newValue }
    }
}

public struct WorkspaceTechnicalValueView: View {
    let label: String
    let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .monospaced()
                #if !os(Android) && !SKIP_BRIDGE
                .textSelection(.enabled)
                #endif
        }
    }
}

public struct TechnicalDetailsSettingsSection: View {
    @AppStorage(TechnicalDetails.userDefaultsKey) var userPreference = false

    public init() {}

    public var body: some View {
        Section {
            if let environmentOverride {
                Toggle("Show Technical Details", isOn: .constant(environmentOverride))
                    .disabled(true)
            } else {
                Toggle("Show Technical Details", isOn: $userPreference)
            }
        } header: {
            Text("Privacy")
        } footer: {
            if let environmentOverride {
                Text(
                    environmentOverride
                        ? "Enabled by OME_SHOW_TECHNICAL_DETAILS."
                        : "Disabled by OME_SHOW_TECHNICAL_DETAILS."
                )
            } else {
                Text("Shows raw account identifiers, source locations, diagnostics, and advanced authoring fields.")
            }
        }
    }

    var environmentOverride: Bool? {
        TechnicalDetails.environmentOverride()
    }
}
#endif

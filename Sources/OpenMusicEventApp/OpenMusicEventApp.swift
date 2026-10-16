import Foundation
import SkipFuse
import SwiftUI
import ATProto
import ATProtoOAuth
import Bluesky
import ComposableCalendarEvents
import ComposableNotifications
import ComposableNotificationsHTTP
import Dependencies
import ErrorHandling
import SQLiteData
import ComposableArchitecture2
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventAppRouting
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventWhiteLabel
import ComposableAtmosphere
#if canImport(UIKit)
import UIKit
#endif

/// A logger for the OpenMusicEventApp module.
let logger: Logger = Logger(subsystem: "fm.woody.openmusicevent", category: "OpenMusicEventApp")

enum APNSEnvironmentConfigurationError: Error, Equatable {
    case missing
    case invalid(String)
    case invalidProfile
}

enum APNSEnvironmentConfiguration {
#if !SKIP
    static func resolve(
        isSimulator: Bool,
        embeddedProfileData: Data?
    ) throws -> Push.APNS.Environment {
        if isSimulator {
            return .development
        }
        guard let embeddedProfileData else {
            return .production
        }
        guard
            let openingTag = embeddedProfileData.range(of: Data("<plist".utf8))?.lowerBound,
            let closingTag = embeddedProfileData.range(
                of: Data("</plist>".utf8),
                options: .backwards
            )?.upperBound
        else {
            throw APNSEnvironmentConfigurationError.invalidProfile
        }
        let propertyListData = embeddedProfileData[openingTag..<closingTag]
        guard
            let profile = try? PropertyListSerialization.propertyList(
                from: propertyListData,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            throw APNSEnvironmentConfigurationError.invalidProfile
        }
        guard
            let entitlements = profile["Entitlements"] as? [String: Any],
            let rawValue = entitlements["aps-environment"] as? String
        else {
            throw APNSEnvironmentConfigurationError.missing
        }
        guard let environment = Push.APNS.Environment(rawValue: rawValue) else {
            throw APNSEnvironmentConfigurationError.invalid(rawValue)
        }
        return environment
    }
#endif

    static func current() throws -> Push.APNS.Environment {
#if SKIP
        throw APNSEnvironmentConfigurationError.missing
#elseif targetEnvironment(simulator)
        return .development
#else
        let profileURL = Bundle.main.bundleURL.appendingPathComponent(
            "embedded.mobileprovision"
        )
        guard FileManager.default.fileExists(atPath: profileURL.path) else {
            return .production
        }
        guard let profileData = try? Data(contentsOf: profileURL, options: .mappedIfSafe) else {
            throw APNSEnvironmentConfigurationError.invalidProfile
        }
        return try resolve(isSimulator: false, embeddedProfileData: profileData)
#endif
    }
}

public struct OpenMusicEventWhiteLabelAppVariant: Equatable, Sendable {
    public struct Environment: Equatable, Sendable {
        public var configuration: WhiteLabelAppConfiguration

        public init(
            configuration: WhiteLabelAppConfiguration
        ) {
            self.configuration = configuration
        }
    }

    public var production: Environment
    public var staging: Environment

    public init(
        production: Environment,
        staging: Environment
    ) {
        self.production = production
        self.staging = staging
    }

    func configuration(
        for environment: OpenMusicEventServiceEnvironment
    ) -> Environment {
        switch environment {
        case .production:
            production
        case .staging:
            staging
        }
    }
}

public enum OpenMusicEventAppVariant: Equatable, Sendable {
    case generic
    case whiteLabel(WhiteLabelAppConfiguration)
    case whiteLabelEnvironments(OpenMusicEventWhiteLabelAppVariant)

    public static func whiteLabel(
        production: OpenMusicEventWhiteLabelAppVariant.Environment,
        staging: OpenMusicEventWhiteLabelAppVariant.Environment
    ) -> Self {
        .whiteLabelEnvironments(
            OpenMusicEventWhiteLabelAppVariant(
                production: production,
                staging: staging
            )
        )
    }
}

extension OpenMusicEventAppVariant {
    var appConfiguration: OpenMusicEventAppConfiguration {
        switch self {
        case .generic:
            .openMusicEvent
        case let .whiteLabel(configuration)
            where configuration.handle == WickedWoodsWhiteLabel.handle:
            .wickedWoods
        case let .whiteLabelEnvironments(variant)
            where variant.production.configuration.handle == WickedWoodsWhiteLabel.handle:
            .wickedWoods
        case .whiteLabel, .whiteLabelEnvironments:
            .openMusicEvent
        }
    }

    var persistsSelectedEvent: Bool {
        switch self {
        case .generic:
            true
        case .whiteLabel, .whiteLabelEnvironments:
            true
        }
    }

    func whiteLabelConfiguration(
        for environment: OpenMusicEventServiceEnvironment
    ) -> WhiteLabelAppConfiguration? {
        switch self {
        case .generic:
            nil
        case let .whiteLabel(configuration):
            configuration
        case let .whiteLabelEnvironments(variant):
            variant.configuration(for: environment).configuration
        }
    }

}

public enum OpenMusicEventAppDependencyProfile: Sendable {
    case generic
    case whiteLabel
}

extension OpenMusicEventServiceEnvironment {
    var appViewHost: ATProto.PDSHost {
        switch self {
        case .production:
            "openmusicevent.app"
        case .staging:
            "stg.openmusicevent.app"
        }
    }
}

extension OME {
    public static func prepareDependencies(
        _ dependencies: inout DependencyValues,
        environment: OpenMusicEventServiceEnvironment = .production,
        uiAutomation: OpenMusicEventUIAutomation = .normal
    ) throws {
        try dependencies.bootstrapDatabase(environment: environment)

        prepareDependencies(
            &dependencies,
            database: dependencies.defaultDatabase,
            environment: environment,
            uiAutomation: uiAutomation
        )
    }

    public static func preparePersistedServiceEnvironmentDependencies(
        _ dependencies: inout DependencyValues,
        uiAutomation: OpenMusicEventUIAutomation = .normal
    ) throws {
        try prepareDependencies(
            &dependencies,
            environment: OpenMusicEventServiceEnvironment.persisted(),
            uiAutomation: uiAutomation
        )
    }

    public static func prepareDependencies(
        _ dependencies: inout DependencyValues,
        database: any DatabaseWriter,
        environment: OpenMusicEventServiceEnvironment = .production,
        uiAutomation: OpenMusicEventUIAutomation = .normal
    ) {
        dependencies.defaultDatabase = database
        dependencies.openMusicEventServiceEnvironment = environment
        dependencies.openMusicEventUIAutomation = uiAutomation
        if uiAutomation == .attendee || uiAutomation == .workspace {
            dependencies.date = .constant(OpenMusicEventUIAutomationFixture.now)
        }
        dependencies.calendarEvents = uiAutomation != .normal && uiAutomation != .publication
            ? .uiAutomation(database: database)
            : .openMusicEventAndAtmo(
                appViewHost: uiAutomation == .publication ? "metadata.ome-auth.test" : environment.appViewHost
            )
        if uiAutomation == .normal || uiAutomation == .publication {
            let host: ATProto.PDSHost = uiAutomation == .publication ? "metadata.ome-auth.test" : environment.appViewHost
            dependencies.eventRecords = .appView(host: host)
        } else if uiAutomation == .attendee || uiAutomation == .workspace {
            dependencies.eventRecords = EventRecordClient(latestEvent: { id in
                try await database.read { db in
                    guard let event = try OpenMusicEventLexicon.Event.find(id).fetchOne(db) else {
                        throw ValidationError("The fixture event is unavailable")
                    }
                    return event
                }
            }, load: { id in
                try await database.read { db in
                    guard let graph = try EventRecordGraph.fetch(eventID: id, from: db) else {
                        throw ValidationError("The fixture event graph is unavailable")
                    }
                    return graph
                }
            })
        }
        if uiAutomation == .authentication || uiAutomation == .workspace || uiAutomation == .publication {
            OpenMusicEventAuthenticationAutomation.prepareSignUp(&dependencies)
        }
        OpenMusicEventOAuth.prepareDependencies(&dependencies)
        OpenMusicEventNotificationAuthorization.prepareDependencies(
            &dependencies,
            environment: environment
        )
        dependencies.notificationsClient = uiAutomation == .workspace
            ? .testValue
            : .http(baseURL: environment.serverURL)
        OpenMusicEventActorTypeahead.prepareDependencies(&dependencies)
        BlueskyActorCacheDependencies.prepareDependencies(&dependencies)
        if uiAutomation == .authentication || uiAutomation == .workspace || uiAutomation == .publication {
            OpenMusicEventAuthenticationAutomation.prepareDependencies(&dependencies)
        }
        if uiAutomation == .workspace {
            dependencies.openMusicEventAccountSessionValidationClient = .init { _ in
                .accepted()
            }
        }
    }

}

public typealias OpenMusicEventApplicationContent = OpenMusicEventAppRoot

/// The application's single authentication boundary. Its entire root receives the authenticated
/// OAuth session, authorization requests, and authorization broker from `OAuthAuthorization`.
public struct OpenMusicEventApplication: FeatureProtocol {
    public typealias State = OAuthAuthorization<OpenMusicEventApplicationContent>.State
    public typealias Action = OAuthAuthorization<OpenMusicEventApplicationContent>.Action

    private let makeContent: @Sendable () -> OpenMusicEventApplicationContent
    private let requestCenter: AuthorizationRequestCenter
    private let storage: OAuthSessionStorage

    public init(
        storage: OAuthSessionStorage,
        requestCenter: AuthorizationRequestCenter = AuthorizationRequestCenter(),
        makeContent: @escaping @Sendable () -> OpenMusicEventApplicationContent
    ) {
        self.makeContent = makeContent
        self.requestCenter = requestCenter
        self.storage = storage
    }

    public var body: some FeatureProtocol<State, Action> {
        OAuthAuthorization(
            storage: storage,
            requestCenter: requestCenter,
            makeContent: makeContent
        )
        .presentAuthorizationFailures()
        .deliverAuthoringAuthorizationChanges()
    }
}

/// The concrete application-delegate boundary around the authenticated application tree.
///
/// Keeping this root concrete avoids a TCA26 remount issue in which a generic outer feature can
/// lose an optional descendant's mount observer while the rest of the root initializes.
@Feature
public struct OpenMusicEventApp {
    private let eventTrigger:
        KeyPath<OpenMusicEventApplication.State, Trigger<AppDelegateEvent>>
    private let notificationDestinationTrigger:
        KeyPath<OpenMusicEventApplication.State, Trigger<Push.Destination>>
    private let notificationEventTrigger:
        KeyPath<OpenMusicEventApplication.State, Trigger<NotificationEvent>>
    private let makeContent: @Sendable () -> OpenMusicEventApplication

    public init(
        eventTrigger:
            KeyPath<OpenMusicEventApplication.State, Trigger<AppDelegateEvent>>,
        notificationDestinationTrigger:
            KeyPath<OpenMusicEventApplication.State, Trigger<Push.Destination>>,
        notificationEventTrigger:
            KeyPath<OpenMusicEventApplication.State, Trigger<NotificationEvent>>,
        content makeContent: @escaping @Sendable () -> OpenMusicEventApplication
    ) {
        self.eventTrigger = eventTrigger
        self.notificationDestinationTrigger = notificationDestinationTrigger
        self.notificationEventTrigger = notificationEventTrigger
        self.makeContent = makeContent
    }

    public struct State {
        public init(content: OpenMusicEventApplication.State) {
            self.content = content
        }

        public var content: OpenMusicEventApplication.State
    }

    public enum Action {
        case content(OpenMusicEventApplication.Action)
        case lifecycle(AppDelegateEvent)
        case notification(NotificationEvent)
        case notificationDestination(Push.Destination)
    }

    public var body: some FeatureProtocol<State, Action> {
        Features {
            Update { state, action in
                switch action {
                case .content:
                    break

                case let .lifecycle(event):
                    let trigger = state.content[keyPath: eventTrigger]
                    store.addTask {
                        let reaction = try trigger(event)
                        await reaction?.value
                    }

                case let .notification(event):
                    let trigger = state.content[keyPath: notificationEventTrigger]
                    store.addTask {
                        let reaction = try trigger(event)
                        await reaction?.value
                    }

                case let .notificationDestination(destination):
                    let trigger = state.content[keyPath: notificationDestinationTrigger]
                    store.addTask {
                        let reaction = try trigger(destination)
                        await reaction?.value
                    }
                }
            }
            Scope(\.content) {
                makeContent()
            }
        }
    }
}

struct SelectedEventRestoration {
    var eventID: Event.ID?
    var error: (any Error)?

    init(
        eventID: Event.ID? = nil,
        error: (any Error)? = nil
    ) {
        self.eventID = eventID
        self.error = error
    }
}

struct OpenMusicEventApplicationRuntime {
    let notificationsClient: NotificationsClient
    let store: StoreOf<OpenMusicEventApp>
}

/* SKIP @bridge */public struct OpenMusicEventApplicationRootView : View {
    let appDelegate: OpenMusicEventAppDelegate?
    @AppStorage(TechnicalDetails.userDefaultsKey) var technicalDetailsUserPreference = false
    @AppStorage(OpenMusicEventServiceEnvironment.userDefaultsKey)
    var serviceEnvironmentRawValue = OpenMusicEventServiceEnvironment.production.rawValue
    @State var activeServiceEnvironment: OpenMusicEventServiceEnvironment
    @State var isServiceEnvironmentSwitchErrorPresented = false
    @State var isServiceEnvironmentSwitching = false
    @State var serviceEnvironmentSwitchErrorMessage = ""
    @State var store: StoreOf<OpenMusicEventApp>

    /* SKIP @bridge */@MainActor public init() {
        self.init(appDelegate: OpenMusicEventAppDelegate.shared)
    }

    @MainActor
    public init(appDelegate: OpenMusicEventAppDelegate) {
        self.appDelegate = appDelegate
        self._activeServiceEnvironment = State(initialValue: appDelegate.serviceEnvironment)
        self._store = State(initialValue: appDelegate.store)
    }

    @MainActor
    public init(store: StoreOf<OpenMusicEventApp>) {
        self.appDelegate = nil
        self._activeServiceEnvironment = State(
            initialValue: OpenMusicEventServiceEnvironment.persisted()
        )
        self._store = State(initialValue: store)
    }

    @MainActor
    public init(variant: OpenMusicEventAppVariant) {
        self.init(appDelegate: .persisted(variant: variant))
    }

    public var body: some View {
        let applicationStore = store.scope(\.content)
#if os(Android)
        let authenticationStore = applicationStore.scope(\.authentication)
        let applicationContentStore = applicationStore.scope(\.content)

        OpenMusicEventAppRootView(
            store: applicationContentStore,
            serviceEnvironment: activeServiceEnvironment,
            isServiceEnvironmentSelectionEnabled: appDelegate != nil,
            isServiceEnvironmentSwitching: isServiceEnvironmentSwitching,
            serviceEnvironmentSelected: serviceEnvironmentSelected
        )
            .background {
                if let presentationStore: StoreOf<OAuthAuthenticationPresentation> =
                    authenticationStore.scope(
                        \.authorization
                    ),
                    case let .direct(authorizationStore) = presentationStore.enumeration
                {
                    OpenMusicEventImmediateAuthorizationMount(store: authorizationStore)
                }
            }
            .sheet(item: authorizationSheetStore(authenticationStore)) { authorizationStore in
                OpenMusicEventAuthorizationFlowSheetView(store: authorizationStore)
                    .modifier(OAuthBrowserSessionModifier(store: authorizationStore))
            }
            .onOpenURL { url in
                guard OpenMusicEventOAuth.isCallbackURL(url) else { return }
                applicationStore.send(.authentication(.handleOpenURL(.init(url))))
            }
            .environment(
                \.showsTechnicalDetails,
                TechnicalDetails.isVisible(userPreference: technicalDetailsUserPreference)
            )
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
            .id(activeServiceEnvironment)
            .alert(
                "Unable to Switch Environment",
                isPresented: $isServiceEnvironmentSwitchErrorPresented
            ) {
                Button("OK") {}
            } message: {
                Text(serviceEnvironmentSwitchErrorMessage)
            }
#else
        OpenMusicEventAuthorizationView(store: applicationStore) { rootStore in
            OpenMusicEventAppRootView(
                store: rootStore,
                serviceEnvironment: activeServiceEnvironment,
                isServiceEnvironmentSelectionEnabled: appDelegate != nil,
                isServiceEnvironmentSwitching: isServiceEnvironmentSwitching,
                serviceEnvironmentSelected: serviceEnvironmentSelected
            )
        }
            .environment(
                \.showsTechnicalDetails,
                TechnicalDetails.isVisible(userPreference: technicalDetailsUserPreference)
            )
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
            .id(activeServiceEnvironment)
            .alert(
                String(
                    localized: "Unable to Switch Environment",
                    bundle: .module,
                    comment: "title for an alert shown when changing the OME service environment fails"
                ),
                isPresented: $isServiceEnvironmentSwitchErrorPresented
            ) {
                Button(
                    String(
                        localized: "OK",
                        bundle: .module,
                        comment: "dismiss button for an environment switch failure alert"
                    )
                ) {}
            } message: {
                Text(serviceEnvironmentSwitchErrorMessage)
            }
#endif
    }

#if os(Android)
    private func authorizationSheetStore(
        _ authenticationStore: StoreOf<AuthenticationCoordinator>
    ) -> Binding<StoreOf<AuthorizationFlow>?> {
        Binding {
            guard let presentationStore: StoreOf<OAuthAuthenticationPresentation> =
                authenticationStore.scope(
                    \.authorization
                ),
                case let .sheet(authorizationStore) = presentationStore.enumeration
            else { return nil }
            return authorizationStore
        } set: { authorizationStore in
            if authorizationStore == nil {
                authenticationStore.send(.authorizationSheetDismissed)
            }
        }
    }
#endif

    func serviceEnvironmentSelected(_ environment: OpenMusicEventServiceEnvironment) {
        guard environment != activeServiceEnvironment,
              !isServiceEnvironmentSwitching,
              let appDelegate
        else { return }

        isServiceEnvironmentSwitching = true
        Task {
            defer { isServiceEnvironmentSwitching = false }
            do {
                let replacementStore = try await appDelegate.switchServiceEnvironment(
                    to: environment
                )
                store = replacementStore
                activeServiceEnvironment = environment
                serviceEnvironmentRawValue = environment.rawValue
            } catch {
                serviceEnvironmentSwitchErrorMessage = String(describing: error)
                isServiceEnvironmentSwitchErrorPresented = true
            }
        }
    }

    @MainActor
    public static func makeStore(
        variant: OpenMusicEventAppVariant,
        environment: OpenMusicEventServiceEnvironment = .production
    ) -> StoreOf<OpenMusicEventApp> {
        try! makeRuntime(
            variant: variant,
            environment: environment,
            bootstrapsDatabase: false,
            restoresSelectedEvent: true
        ).store
    }

    @MainActor
    static func makeRuntime(
        variant: OpenMusicEventAppVariant,
        environment: OpenMusicEventServiceEnvironment,
        bootstrapsDatabase: Bool,
        restoresSelectedEvent: Bool
    ) throws -> OpenMusicEventApplicationRuntime {
        return try withDependencies {
            let uiAutomation = $0.openMusicEventUIAutomation
            if bootstrapsDatabase {
                try OME.prepareDependencies(
                    &$0,
                    environment: environment,
                    uiAutomation: uiAutomation
                )
            } else {
                let database = $0.defaultDatabase
                OME.prepareDependencies(
                    &$0,
                    database: database,
                    environment: environment,
                    uiAutomation: uiAutomation
                )
            }
            let appConfiguration = variant.appConfiguration
            $0.openMusicEventAppConfiguration = appConfiguration
            $0.deviceSupportsCriticalAlerts = appConfiguration.supportsCriticalAlerts
        } operation: {
            @Dependency(\.notificationsClient) var notificationsClient
            let selectedEventRestoration = restoresSelectedEvent
                ? selectedEventRestoration(for: variant)
                : SelectedEventRestoration()
            return OpenMusicEventApplicationRuntime(
                notificationsClient: notificationsClient,
                store: StoreOf<OpenMusicEventApp>(
                    initialState: .init(
                        content: OpenMusicEventApplication.State(
                            storage: OpenMusicEventOAuth.storage
                        ) {
                            OpenMusicEventAppRoot.State(
                                variant: variant,
                                serviceEnvironment: environment,
                                selectedEventIDAtLaunch: selectedEventRestoration.eventID,
                                workspaceRestorationErrorAtLaunch: selectedEventRestoration.error
                            )
                        }
                    )
                ) {
                    OpenMusicEventApp(
                        eventTrigger: \OpenMusicEventApplication.State.content.appDelegateEvent,
                        notificationDestinationTrigger:
                            \OpenMusicEventApplication.State.content.notificationDestination,
                        notificationEventTrigger:
                            \OpenMusicEventApplication.State.content.notificationEvent
                    ) {
                        OpenMusicEventApplication(storage: OpenMusicEventOAuth.storage) {
                            OpenMusicEventAppRoot()
                        }
                    }
                }
            )
        }
    }

    static func selectedEventRestoration(
        for variant: OpenMusicEventAppVariant
    ) -> SelectedEventRestoration {
        guard variant.persistsSelectedEvent else { return .init() }
        @Dependency(\.defaultDatabase) var database
        do {
            return SelectedEventRestoration(
                eventID: try database.read { db in
                    try AppState.find(1).fetchOne(db)?.selectedEventID
                }
            )
        } catch {
            return SelectedEventRestoration(error: error)
        }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */@MainActor public final class OpenMusicEventAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = OpenMusicEventAppDelegate()

    var latestNotificationDestination: Push.Destination?
    var runtime: OpenMusicEventApplicationRuntime
    let variant: OpenMusicEventAppVariant
    public private(set) var serviceEnvironment: OpenMusicEventServiceEnvironment

    public var store: StoreOf<OpenMusicEventApp> {
        runtime.store
    }

    /* SKIP @bridge */public convenience init() {
        self.init(
            variant: OpenMusicEventAppVariant.generic,
            environment: OpenMusicEventServiceEnvironment.persisted()
        )
    }

    public init(
        variant: OpenMusicEventAppVariant,
        environment: OpenMusicEventServiceEnvironment = .production
    ) {
        @Dependency(\.openMusicEventUIAutomation) var uiAutomation
        self.variant = variant
        self.serviceEnvironment = environment
        self.runtime = try! OpenMusicEventApplicationRootView.makeRuntime(
            variant: variant,
            environment: environment,
            bootstrapsDatabase: false,
            restoresSelectedEvent: uiAutomation != .authentication
        )
    }

    #if os(Android)
    public static func persisted(
        variant: OpenMusicEventAppVariant
    ) -> OpenMusicEventAppDelegate {
        OpenMusicEventAppDelegate(
            variant: variant,
            environment: OpenMusicEventServiceEnvironment.persisted()
        )
    }
    #else
    public static func persisted(
        variant: OpenMusicEventAppVariant,
        userDefaults: UserDefaults = .standard
    ) -> OpenMusicEventAppDelegate {
        OpenMusicEventAppDelegate(
            variant: variant,
            environment: OpenMusicEventServiceEnvironment.persisted(
                userDefaults: userDefaults
            )
        )
    }
    #endif

    init(
        variant: OpenMusicEventAppVariant,
        environment: OpenMusicEventServiceEnvironment,
        runtime: OpenMusicEventApplicationRuntime
    ) {
        self.variant = variant
        self.serviceEnvironment = environment
        self.runtime = runtime
    }

    public func switchServiceEnvironment(
        to environment: OpenMusicEventServiceEnvironment
    ) async throws -> StoreOf<OpenMusicEventApp> {
        guard environment != serviceEnvironment else { return store }

        let replacementRuntime = try OpenMusicEventApplicationRootView.makeRuntime(
            variant: variant,
            environment: environment,
            bootstrapsDatabase: true,
            restoresSelectedEvent: false
        )
        return try await activateServiceEnvironment(
            environment,
            replacementRuntime: replacementRuntime
        )
    }

    func activateServiceEnvironment(
        _ environment: OpenMusicEventServiceEnvironment,
        replacementRuntime: OpenMusicEventApplicationRuntime
    ) async throws -> StoreOf<OpenMusicEventApp> {
        try await withDependencies {
            $0.openMusicEventServiceEnvironment = serviceEnvironment
            OpenMusicEventNotificationAuthorization.prepareDependencies(
                &$0,
                environment: serviceEnvironment
            )
        } operation: {
            try await runtime.notificationsClient.replaceSubscriptions(
                Set<NotificationSubscription>()
            )
        }
        runtime = replacementRuntime
        serviceEnvironment = environment

        send(.initialized)
        send(.launched)
        send(.resumed)
        if let latestNotificationDestination {
            let registration = store.send(
                .notificationDestination(latestNotificationDestination)
            )
            await registration?.value
        }
        return store
    }

    /* SKIP @bridge */public func onInit() {
//        OME.bootstrapIfNeeded()
        send(.initialized)
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        send(.launched)
        logger.debug("onLaunch")
#if canImport(UIKit)
        let wasRegistered = UIApplication.shared.isRegisteredForRemoteNotifications
        logger.info(
            "Requesting remote notification registration; already registered: \(wasRegistered, privacy: .public)"
        )
        UIApplication.shared.registerForRemoteNotifications()
        let isRegisteredAfterRequest = UIApplication.shared.isRegisteredForRemoteNotifications
        logger.info(
            "Submitted remote notification registration request; registered after submission: \(isRegisteredAfterRequest, privacy: .public)"
        )
#endif
        enforceStoredAuthenticationFreshness()
    }

    /* SKIP @bridge */public func onRegisteredForRemoteNotifications(deviceToken: Data) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            logger.error("Remote notification registration has no application bundle identifier")
            return
        }
        let environment: Push.APNS.Environment
        do {
            environment = try APNSEnvironmentConfiguration.current()
        } catch APNSEnvironmentConfigurationError.missing {
            logger.error(
                "Remote notification registration has no APNs environment configuration"
            )
            return
        } catch APNSEnvironmentConfigurationError.invalid {
            logger.error(
                "Remote notification registration has an invalid APNs environment configuration"
            )
            return
        } catch APNSEnvironmentConfigurationError.invalidProfile {
            logger.error(
                "Remote notification registration has an invalid embedded provisioning profile"
            )
            return
        } catch {
            logger.error("Remote notification registration could not read its APNs environment")
            return
        }
#if SKIP || os(Android)
        logger.info(
            "Remote notification destination available for \(bundleIdentifier) in \(environment.rawValue)"
        )
#else
        logger.info(
            "Remote notification destination available for \(bundleIdentifier, privacy: .public) in \(environment.rawValue, privacy: .public)"
        )
#endif
        let value = deviceToken.map { String(format: "%02x", $0) }.joined()
        let destination = Push.Destination.apns(
            Push.APNS(
                applicationID: .init(rawValue: bundleIdentifier),
                environment: environment,
                deviceToken: .init(rawValue: value)
            )
        )
        latestNotificationDestination = destination
        store.send(
            .notificationDestination(destination)
        )
    }

#if os(Android)
    /* SKIP @bridge */public func onFirebaseMessagingRegistration(
        applicationID: String,
        registrationToken: String
    ) {
        logger.info("Firebase Messaging destination available for \(applicationID)")
        let destination = Push.Destination.fcm(
            Push.FCM(
                applicationID: .init(rawValue: applicationID),
                registrationToken: .init(rawValue: registrationToken)
            )
        )
        latestNotificationDestination = destination
        store.send(
            .notificationDestination(destination)
        )
    }
#endif

    /* SKIP @bridge */public func onRemoteNotificationRegistrationFailed(
        errorDescription: String
    ) {
#if SKIP || os(Android)
        logger.error("Remote notification registration failed: \(errorDescription)")
#else
        logger.error(
            "Remote notification registration failed: \(errorDescription, privacy: .public)"
        )
#endif
    }

    /// Preserves provider JSON until the notifications feature transforms it into an app signal.
    /* SKIP @bridge */public func onRemoteNotification(json: String) {
        sendNotification(
            NotificationEvent(json: json, delivery: .contentAvailable)
        )
    }

    /// Preserves a notification delivered while the application is in the foreground.
    /* SKIP @bridge */public func onForegroundNotification(json: String) {
        sendNotification(
            NotificationEvent(json: json, delivery: .foreground)
        )
    }

    /// Preserves the notification and action that brought the user into the application.
    /* SKIP @bridge */public func onNotificationInteraction(
        json: String,
        actionIdentifier: String?
    ) {
        sendNotification(
            NotificationEvent(
                json: json,
                delivery: .userInteraction(actionIdentifier: actionIdentifier)
            )
        )
    }

#if canImport(UIKit)
    @MainActor
    public func onRemoteNotificationAndWait(json: String) async -> Bool {
        await handleNotification(
            NotificationEvent(json: json, delivery: .contentAvailable)
        )
    }

    @MainActor
    public func onNotificationInteractionAndWait(
        json: String,
        actionIdentifier: String?
    ) async {
        await handleNotification(
            NotificationEvent(
                json: json,
                delivery: .userInteraction(actionIdentifier: actionIdentifier)
            )
        )
    }
#endif

    /* SKIP @bridge */public func onResume() {
        send(.resumed)
        logger.debug("onResume")
        enforceStoredAuthenticationFreshness()
    }

    /* SKIP @bridge */public func onPause() {
        send(.paused)
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        send(.stopped)
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        send(.destroyed)
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        send(.lowMemory)
        logger.debug("onLowMemory")
    }

    private func send(_ event: AppDelegateEvent) {
        store.send(.lifecycle(event))
    }

    private func sendNotification(_ event: NotificationEvent) {
        Task {
            await handleNotification(event)
        }
    }

    @MainActor
    @discardableResult
    private func handleNotification(_ event: NotificationEvent) async -> Bool {
        let reaction = store.send(.notification(event))
        await reaction?.value
        return true
    }

    private func enforceStoredAuthenticationFreshness() {
        @Dependency(\.openMusicEventAutomaticallyRefreshesStoredAuthentication)
        var automaticallyRefreshesStoredAuthentication

        guard automaticallyRefreshesStoredAuthentication else { return }
        Task {
            try? await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()
        }
    }
}

#if os(Android)
struct OpenMusicEventImmediateAuthorizationMount: View {
    let store: StoreOf<AuthorizationFlow>

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .modifier(OAuthBrowserSessionModifier(store: store))
    }
}
#endif

#if os(Android)
/// Prepares process-wide dependencies before Android initializes the shared app delegate.
/* SKIP @bridge */public final class OpenMusicEventAndroidApplication : Sendable {
    private init() {}

    /* SKIP @bridge */public static func prepareDependencies() {
        prepareDependencies(uiAutomation: false, profile: "")
    }

    /* SKIP @bridge */public static func prepareDependencies(uiAutomation: Bool, profile: String) {
        try! Dependencies.prepareDependencies {
            try OME.preparePersistedServiceEnvironmentDependencies(
                &$0,
                uiAutomation: .buildProfile(profile, legacyAttendee: uiAutomation)
            )
        }
    }
}
#endif

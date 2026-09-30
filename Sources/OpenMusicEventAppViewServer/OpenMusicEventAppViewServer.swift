import ComposableNotifications
import ComposableNotificationsServer
import Dependencies
import Hummingbird
import ATProtoStreams
import OpenMusicEventRouting
import ServiceLifecycle

public enum OpenMusicEventAppViewServer {
    public static func application(
        configuration: AppViewConfiguration = .init(),
        store providedStore: OpenMusicEventAppViewStore? = nil,
        hydrantClient: HydrantClient? = nil,
        commsPostSubmission: CommsPostSubmission? = nil,
        notificationRegistration: NotificationRegistrationServer? = nil,
        notificationProvider: NotificationProviderClient? = nil,
        sourceArtifactPublisher providedSourceArtifactPublisher: SourceArtifactPublisher? = nil,
        tangledSourceUpdateProcessor providedTangledSourceUpdateProcessor:
            TangledSourceUpdateProcessor? = nil
    ) throws -> some ApplicationProtocol {
        let store: OpenMusicEventAppViewStore?
        if let providedStore {
            store = providedStore
        } else if let databaseURL = configuration.databaseURL {
            store = try OpenMusicEventAppViewStore(
                databaseURL: databaseURL,
                webhookSecretProtection: configuration.webhookSecretProtection,
                initiallyReady: configuration.ingestion == nil
            )
        } else {
            store = nil
        }
        if configuration.tangledWebhook != nil, store == nil {
            throw OpenMusicEventAppViewServerError.tangledWebhookRequiresDatabase
        }

        var services: [any Service] = []
        if let ingestion = configuration.ingestion {
            guard let store else {
                throw OpenMusicEventAppViewServerError.ingestionRequiresDatabase
            }
            services.append(
                OpenMusicEventAppViewIngestion(
                    store: store,
                    configuration: ingestion,
                    tangledWebhookConfiguration: configuration.tangledWebhook,
                    client: hydrantClient ?? .hummingbird()
                )
            )
        }
        if let tangledWebhook = configuration.tangledWebhook, let store {
            services.append(
                TangledWorkspaceProposalService(
                    processor: TangledWorkspaceProposalProcessor(
                        configuration: tangledWebhook,
                        store: store
                    )
                )
            )
        }

        let notificationRegistration = try notificationRegistration
            ?? withNotificationDependencies(configuration: configuration, store: store) {
                try configuredNotificationRegistration(
                    configuration: configuration,
                    store: store
                )
            }
        let tangledSourceUpdateProcessor: TangledSourceUpdateProcessor?
        if let providedTangledSourceUpdateProcessor {
            tangledSourceUpdateProcessor = providedTangledSourceUpdateProcessor
        } else if configuration.tangledWebhook != nil, let store {
            let sourceArtifactPublisher: SourceArtifactPublisher
            if let providedSourceArtifactPublisher {
                sourceArtifactPublisher = providedSourceArtifactPublisher
            } else {
                guard let sourceArtifactConfiguration = configuration.sourceArtifacts else {
                    throw OpenMusicEventAppViewServerError
                        .tangledWebhookRequiresSourceArtifactConfiguration
                }
                sourceArtifactPublisher = .s3(configuration: sourceArtifactConfiguration)
            }
            tangledSourceUpdateProcessor = withNotificationDependencies(
                configuration: configuration,
                store: store
            ) {
                .publishSourceAndNotifyChannels(
                    store: store,
                    artifactPublisher: sourceArtifactPublisher
                )
            }
        } else {
            tangledSourceUpdateProcessor = nil
        }
        if let notificationProvider {
            guard let store else {
                throw OpenMusicEventAppViewServerError.notificationDeliveryRequiresDatabase
            }
            guard let destinationProtection = configuration.notificationDestinationProtection else {
                throw OpenMusicEventAppViewServerError
                    .notificationDeliveryRequiresDestinationProtection
            }
            services.append(
                NotificationOutboxService(
                    database: store.database,
                    destinationProtection: destinationProtection,
                    legacyAPNSEnvironments: configuration.legacyAPNSEnvironments,
                    provider: notificationProvider
                )
            )
        }

        return Application(
            router: router(
                configuration: configuration,
                store: store,
                commsPostSubmission: commsPostSubmission,
                notificationRegistration: notificationRegistration,
                tangledSourceUpdateProcessor: tangledSourceUpdateProcessor
            ),
            configuration: configuration.hummingbirdConfiguration,
            services: services
        )
    }

    public static func router(
        configuration: AppViewConfiguration = .init(),
        store: OpenMusicEventAppViewStore? = nil,
        commsPostSubmission: CommsPostSubmission? = nil,
        notificationRegistration: NotificationRegistrationServer? = nil,
        tangledSourceUpdateProcessor: TangledSourceUpdateProcessor? = nil
    ) -> Router<BasicRequestContext> {
        router(
            context: BasicRequestContext.self,
            configuration: configuration,
            store: store,
            commsPostSubmission: commsPostSubmission,
            notificationRegistration: notificationRegistration,
            tangledSourceUpdateProcessor: tangledSourceUpdateProcessor
        )
    }

    public static func router<Context: RequestContext>(
        context: Context.Type,
        configuration: AppViewConfiguration = .init(),
        store: OpenMusicEventAppViewStore? = nil,
        commsPostSubmission: CommsPostSubmission? = nil,
        notificationRegistration: NotificationRegistrationServer? = nil,
        tangledSourceUpdateProcessor: TangledSourceUpdateProcessor? = nil
    ) -> Router<Context> {
        let router = Router(context: context, options: [.autoGenerateHeadEndpoints])
        let openMusicEventCatalog = OpenMusicEventCalendarCatalog(
            appViewHost: configuration.publicAppViewHost,
            tangledWebhook: configuration.tangledWebhook,
            store: store
        )

        installCommsPostRoutes(
            on: router,
            submission: commsPostSubmission
        )
        installCalendarEventRoutes(
            on: router,
            store: store,
            openMusicEventCatalog: openMusicEventCatalog
        )
        installWorkspaceProposalRoutes(
            on: router,
            store: store,
            tangledWebhookConfiguration: configuration.tangledWebhook
        )
        installNotificationRegistrationRoutes(
            on: router,
            registration: notificationRegistration
        )
        installTangledWebhookRoute(
            on: router,
            configuration: configuration.tangledWebhook,
            store: store,
            sourceUpdateProcessor: tangledSourceUpdateProcessor
        )
        installWebRoutes(
            on: router,
            oauthClient: configuration.oauthClient,
            routeResolver: OpenMusicEventRouter(
                configuration: OpenMusicEventRoutingConfiguration(
                    brandedEventRouteClaims: configuration.brandedEventRouteClaims
                )
            ),
            staticSiteFiles: StaticSiteFiles(rootDirectory: configuration.siteRoot),
            wellKnownFiles: WellKnownFiles(rootDirectory: configuration.wellKnownRoot),
            openMusicEventCatalog: openMusicEventCatalog,
            store: store
        )

        return router
    }

    static func configuredNotificationRegistration(
        configuration: AppViewConfiguration,
        store: OpenMusicEventAppViewStore?
    ) throws -> NotificationRegistrationServer? {
        guard let notificationConfiguration = configuration.notificationRegistration else {
            return nil
        }
        guard store != nil else {
            throw OpenMusicEventAppViewServerError.notificationRegistrationRequiresDatabase
        }
        guard configuration.notificationDestinationProtection != nil else {
            throw OpenMusicEventAppViewServerError
                .notificationRegistrationRequiresDestinationProtection
        }
        let providerApplications = configuration.notificationProviders.map { providers in
            NotificationRegistrationPolicy.ProviderApplications(
                apns: providers.apns?.applications.mapValues {
                    .init(
                        environment: $0.environment,
                        allowedEnvironments: $0.allowedEnvironments
                    )
                } ?? [:],
                fcm: providers.fcm.map { Set($0.applications.keys) } ?? []
            )
        }

        switch notificationConfiguration.authorization {
        case .anonymous:
            let notificationDatabase = NotificationDatabase()
            return NotificationRegistrationServer(
                database: notificationDatabase,
                installationAuthorizer: .anonymous(database: notificationDatabase),
                policy: NotificationRegistrationPolicy(
                    allowedApplicationIDs: notificationConfiguration.allowedApplicationIDs,
                    providerApplications: providerApplications
                )
            )
        }
    }

    static func withNotificationDependencies<Value>(
        configuration: AppViewConfiguration,
        store: OpenMusicEventAppViewStore?,
        operation: () throws -> Value
    ) rethrows -> Value {
        try withDependencies {
            if let store {
                $0.defaultDatabase = store.database
            }
            if let protection = configuration.notificationDestinationProtection {
                $0.notificationDestinationProtectionClient = protection.client(
                    legacyAPNSEnvironments: configuration.legacyAPNSEnvironments
                )
            }
        } operation: {
            try operation()
        }
    }
}

public enum OpenMusicEventAppViewServerError: Error, Equatable, Sendable {
    case ingestionRequiresDatabase
    case notificationDeliveryRequiresDatabase
    case notificationDeliveryRequiresDestinationProtection
    case notificationRegistrationRequiresDatabase
    case notificationRegistrationRequiresDestinationProtection
    case tangledWebhookRequiresDatabase
    case tangledWebhookRequiresSourceArtifactConfiguration
}

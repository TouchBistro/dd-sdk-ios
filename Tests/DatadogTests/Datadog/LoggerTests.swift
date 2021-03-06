/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class LoggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        temporaryDirectory.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(LoggingFeature.instance)
        temporaryDirectory.delete()
        super.tearDown()
    }

    // MARK: - Customizing Logger

    func testSendingLogWithDefaultLogger() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            configuration: .mockWith(
                applicationVersion: "1.0.0",
                applicationBundleIdentifier: "com.datadoghq.ios-sdk",
                serviceName: "default-service-name",
                environment: "tests"
            ),
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")

        let logMatcher = try server.waitAndReturnLogMatchers(count: 1)[0]
        try logMatcher.assertItFullyMatches(jsonString: """
        {
          "status" : "debug",
          "message" : "message",
          "service" : "default-service-name",
          "logger.name" : "com.datadoghq.ios-sdk",
          "logger.version": "\(sdkVersion)",
          "logger.thread_name" : "main",
          "date" : "2019-12-15T10:00:00.000Z",
          "version": "1.0.0",
          "ddtags": "env:tests"
        }
        """)
    }

    func testSendingLogWithCustomizedLogger() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder
            .set(serviceName: "custom-service-name")
            .set(loggerName: "custom-logger-name")
            .sendNetworkInfo(true)
            .build()
        logger.debug("message")

        let logMatcher = try server.waitAndReturnLogMatchers(count: 1)[0]

        logMatcher.assertServiceName(equals: "custom-service-name")
        logMatcher.assertLoggerName(equals: "custom-logger-name")
        logMatcher.assertValue(forKeyPath: "network.client.sim_carrier.name", isTypeOf: String.self)
        logMatcher.assertValue(forKeyPath: "network.client.sim_carrier.iso_country", isTypeOf: String.self)
        logMatcher.assertValue(forKeyPath: "network.client.sim_carrier.technology", isTypeOf: String.self)
        logMatcher.assertValue(forKeyPath: "network.client.sim_carrier.allows_voip", isTypeOf: Bool.self)
        logMatcher.assertValue(forKeyPath: "network.client.available_interfaces", isTypeOf: [String].self)
        logMatcher.assertValue(forKeyPath: "network.client.reachability", isTypeOf: String.self)
        logMatcher.assertValue(forKeyPath: "network.client.is_expensive", isTypeOf: Bool.self)
        logMatcher.assertValue(forKeyPath: "network.client.supports_ipv4", isTypeOf: Bool.self)
        logMatcher.assertValue(forKeyPath: "network.client.supports_ipv6", isTypeOf: Bool.self)
        if #available(iOS 13.0, *) {
            logMatcher.assertValue(forKeyPath: "network.client.is_constrained", isTypeOf: Bool.self)
        }
    }

    // MARK: - Sending Customized Logs

    func testSendingLogsWithDifferentDates() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            dateProvider: RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC(), advancingBySeconds: 1)
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.info("message 1")
        logger.info("message 2")
        logger.info("message 3")

        let logMatchers = try server.waitAndReturnLogMatchers(count: 3)
        // swiftlint:disable trailing_closure
        logMatchers[0].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC() })
        logMatchers[1].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 1) })
        logMatchers[2].assertDate(matches: { $0 == Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 2) })
        // swiftlint:enable trailing_closure
    }

    func testSendingLogsWithDifferentLevels() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")
        logger.info("message")
        logger.notice("message")
        logger.warn("message")
        logger.error("message")
        logger.critical("message")

        let logMatchers = try server.waitAndReturnLogMatchers(count: 6)
        logMatchers[0].assertStatus(equals: "debug")
        logMatchers[1].assertStatus(equals: "info")
        logMatchers[2].assertStatus(equals: "notice")
        logMatchers[3].assertStatus(equals: "warn")
        logMatchers[4].assertStatus(equals: "error")
        logMatchers[5].assertStatus(equals: "critical")
    }

    // MARK: - Sending user info

    func testSendingUserInfo() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        Datadog.instance = Datadog(
            userInfoProvider: UserInfoProvider()
        )
        defer { Datadog.instance = nil }
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            userInfoProvider: Datadog.instance!.userInfoProvider
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message with no user info")

        Datadog.setUserInfo(id: "abc-123", name: "Foo")
        logger.debug("message with user `id` and `name`")

        Datadog.setUserInfo(id: "abc-123", name: "Foo", email: "foo@example.com")
        logger.debug("message with user `id`, `name` and `email`")

        Datadog.setUserInfo(id: nil, name: nil, email: nil)
        logger.debug("message with no user info")

        let logMatchers = try server.waitAndReturnLogMatchers(count: 4)
        logMatchers[0].assertUserInfo(equals: nil)
        logMatchers[1].assertUserInfo(equals: (id: "abc-123", name: "Foo", email: nil))
        logMatchers[2].assertUserInfo(equals: (id: "abc-123", name: "Foo", email: "foo@example.com"))
        logMatchers[3].assertUserInfo(equals: nil)
    }

    // MARK: - Sending carrier info

    func testSendingCarrierInfoWhenEnteringAndLeavingCellularServiceRange() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let carrierInfoProvider = CarrierInfoProviderMock(carrierInfo: nil)
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            carrierInfoProvider: carrierInfoProvider
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder
            .sendNetworkInfo(true)
            .build()

        // simulate entering cellular service range
        carrierInfoProvider.set(
            current: .mockWith(
                carrierName: "Carrier",
                carrierISOCountryCode: "US",
                carrierAllowsVOIP: true,
                radioAccessTechnology: .LTE
            )
        )

        logger.debug("message")

        // simulate leaving cellular service range
        carrierInfoProvider.set(current: nil)

        logger.debug("message")

        let logMatchers = try server.waitAndReturnLogMatchers(count: 2)
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.name", equals: "Carrier")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.iso_country", equals: "US")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.technology", equals: "LTE")
        logMatchers[0].assertValue(forKeyPath: "network.client.sim_carrier.allows_voip", equals: true)
        logMatchers[1].assertNoValue(forKeyPath: "network.client.sim_carrier")
    }

    // MARK: - Sending network info

    func testSendingNetworkConnectionInfoWhenReachabilityChanges() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let networkConnectionInfoProvider = NetworkConnectionInfoProviderMock.mockAny()
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            networkConnectionInfoProvider: networkConnectionInfoProvider
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder
            .sendNetworkInfo(true)
            .build()

        // simulate reachable network
        networkConnectionInfoProvider.set(
            current: .mockWith(
                reachability: .yes,
                availableInterfaces: [.wifi, .cellular],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: false,
                isConstrained: false
            )
        )

        logger.debug("message")

        // simulate unreachable network
        networkConnectionInfoProvider.set(
            current: .mockWith(
                reachability: .no,
                availableInterfaces: [],
                supportsIPv4: false,
                supportsIPv6: false,
                isExpensive: false,
                isConstrained: false
            )
        )

        logger.debug("message")

        // put the network back online so last log can be send
        networkConnectionInfoProvider.set(current: .mockWith(reachability: .yes))

        let logMatchers = try server.waitAndReturnLogMatchers(count: 2)
        logMatchers[0].assertValue(forKeyPath: "network.client.reachability", equals: "yes")
        logMatchers[0].assertValue(forKeyPath: "network.client.available_interfaces", equals: ["wifi", "cellular"])
        logMatchers[0].assertValue(forKeyPath: "network.client.is_constrained", equals: false)
        logMatchers[0].assertValue(forKeyPath: "network.client.is_expensive", equals: false)
        logMatchers[0].assertValue(forKeyPath: "network.client.supports_ipv4", equals: true)
        logMatchers[0].assertValue(forKeyPath: "network.client.supports_ipv6", equals: true)

        logMatchers[1].assertValue(forKeyPath: "network.client.reachability", equals: "no")
        logMatchers[1].assertValue(forKeyPath: "network.client.available_interfaces", equals: [String]())
        logMatchers[1].assertValue(forKeyPath: "network.client.is_constrained", equals: false)
        logMatchers[1].assertValue(forKeyPath: "network.client.is_expensive", equals: false)
        logMatchers[1].assertValue(forKeyPath: "network.client.supports_ipv4", equals: false)
        logMatchers[1].assertValue(forKeyPath: "network.client.supports_ipv6", equals: false)
    }

    // MARK: - Sending attributes

    func testSendingLoggerAttributesOfDifferentEncodableValues() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()

        // string literal
        logger.addAttribute(forKey: "string", value: "hello")

        // boolean literal
        logger.addAttribute(forKey: "bool", value: true)

        // integer literal
        logger.addAttribute(forKey: "int", value: 10)

        // Typed 8-bit unsigned Integer
        logger.addAttribute(forKey: "uint-8", value: UInt8(10))

        // double-precision, floating-point value
        logger.addAttribute(forKey: "double", value: 10.5)

        // array of `Encodable` integer
        logger.addAttribute(forKey: "array-of-int", value: [1, 2, 3])

        // dictionary of `Encodable` date types
        logger.addAttribute(forKey: "dictionary-of-date", value: [
            "date1": Date.mockDecember15th2019At10AMUTC(),
            "date2": Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 60 * 60)
        ])

        struct Person: Codable {
            let name: String
            let age: Int
            let nationality: String
        }

        // custom `Encodable` structure
        logger.addAttribute(forKey: "person", value: Person(name: "Adam", age: 30, nationality: "Polish"))

        // nested string literal
        logger.addAttribute(forKey: "nested.string", value: "hello")

        // URL
        logger.addAttribute(forKey: "url", value: URL(string: "https://example.com/image.png")!)

        logger.info("message")

        let logMatcher = try server.waitAndReturnLogMatchers(count: 1)[0]
        logMatcher.assertValue(forKey: "string", equals: "hello")
        logMatcher.assertValue(forKey: "bool", equals: true)
        logMatcher.assertValue(forKey: "int", equals: 10)
        logMatcher.assertValue(forKey: "uint-8", equals: UInt8(10))
        logMatcher.assertValue(forKey: "double", equals: 10.5)
        logMatcher.assertValue(forKey: "array-of-int", equals: [1, 2, 3])
        logMatcher.assertValue(forKeyPath: "dictionary-of-date.date1", equals: "2019-12-15T10:00:00.000Z")
        logMatcher.assertValue(forKeyPath: "dictionary-of-date.date2", equals: "2019-12-15T11:00:00.000Z")
        logMatcher.assertValue(forKeyPath: "person.name", equals: "Adam")
        logMatcher.assertValue(forKeyPath: "person.age", equals: 30)
        logMatcher.assertValue(forKeyPath: "person.nationality", equals: "Polish")
        logMatcher.assertValue(forKeyPath: "nested.string", equals: "hello")
        /// URLs are encoded explicitly as `String` - see the comment in `EncodableValue`
        logMatcher.assertValue(forKeyPath: "url", equals: "https://example.com/image.png")
    }

    func testSendingMessageAttributes() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()

        // add logger attribute
        logger.addAttribute(forKey: "attribute", value: "logger's value")

        // send message with no attributes
        logger.info("info message 1")

        // send message with attribute overriding logger's attribute
        logger.info("info message 2", attributes: ["attribute": "message's value"])

        // remove logger attribute
        logger.removeAttribute(forKey: "attribute")

        // send message
        logger.info("info message 3")

        let logMatchers = try server.waitAndReturnLogMatchers(count: 3)
        logMatchers[0].assertValue(forKey: "attribute", equals: "logger's value")
        logMatchers[1].assertValue(forKey: "attribute", equals: "message's value")
        logMatchers[2].assertNoValue(forKey: "attribute")
    }

    // MARK: - Sending tags

    func testSendingTags() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            configuration: .mockWith(environment: "tests")
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()

        // add tag
        logger.add(tag: "tag1")

        // send message
        logger.info("info message 1")

        // add tag with key
        logger.addTag(withKey: "tag2", value: "abcd")

        // send message
        logger.info("info message 2")

        // remove tag with key
        logger.removeTag(withKey: "tag2")

        // remove tag
        logger.remove(tag: "tag1")

        // send message
        logger.info("info message 3")

        let logMatchers = try server.waitAndReturnLogMatchers(count: 3)
        logMatchers[0].assertTags(equal: ["tag1", "env:tests"])
        logMatchers[1].assertTags(equal: ["tag1", "tag2:abcd", "env:tests"])
        logMatchers[2].assertTags(equal: ["env:tests"])
    }

    // MARK: - Sending logs with different network and battery conditions

    func testGivenBadBatteryConditions_itDoesNotTryToSendLogs() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            mobileDevice: .mockWith(
                currentBatteryStatus: { () -> MobileDevice.BatteryStatus in
                    .mockWith(state: .charging, level: 0.05, isLowPowerModeEnabled: true)
                }
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")

        server.waitAndAssertNoRequestsSent()
    }

    func testGivenNoNetworkConnection_itDoesNotTryToSendLogs() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
                networkConnectionInfo: .mockWith(reachability: .no)
            )
        )
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder.build()
        logger.debug("message")

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        LoggingFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        defer { LoggingFeature.instance = nil }

        let logger = Logger.builder
            .sendLogsToDatadog(false)
            .printLogsToConsole(false)
            .build()

        DispatchQueue.concurrentPerform(iterations: 900) { iteration in
            let modulo = iteration % 3

            switch modulo {
            case 0:
                logger.debug("message")
                logger.debug("message", attributes: ["attribute": "value"])
            case 1:
                logger.addAttribute(forKey: "att\(modulo)", value: "value")
                logger.addTag(withKey: "t\(modulo)", value: "value")
            case 2:
                logger.removeAttribute(forKey: "att\(modulo)")
                logger.removeTag(withKey: "att\(modulo)")
            default:
                break
            }
        }

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Usage

    func testGivenDatadogNotInitialized_whenInitializingLogger_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        XCTAssertNil(Datadog.instance)

        // when
        let logger = Logger.builder.build()

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Logger.builder.build()`."
        )
        XCTAssertTrue(logger.logOutput is NoOpLogOutput)
    }

    func testGivenLoggingFeatureDisabled_whenInitializingLogger_itPrintsError() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        Datadog.initialize(
            appContext: .mockAny(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abc.def", environment: "tests")
                .enableLogging(false)
                .build()
        )

        // when
        let logger = Logger.builder.build()

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Logger.builder.build()` produces a non-functional logger, as the logging feature is disabled."
        )
        XCTAssertTrue(logger.logOutput is NoOpLogOutput)

        try Datadog.deinitializeOrThrow()
    }

    func testDDLoggerIsLoggerTypealias() {
        XCTAssertTrue(DDLogger.self == Logger.self)
    }
}
// swiftlint:enable multiline_arguments_brackets

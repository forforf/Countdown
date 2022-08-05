//

import XCTest
import Combine
import TimerPublisher

@testable import Countdown

// Allows for cleaner func signatures
typealias Closure<ARG, RET> = (ARG) -> RET

@available(iOS 14.0, *)
class CountdownTests: XCTestCase {
        
    private var countdownComplete: Countdown!
    
    private var cancellables: Set<AnyCancellable> = []
    
    override func setUpWithError() throws {
        super.setUp()
        
        // Setup a countdown instance that can complete a full countdown
        let countdownListBasic = makeCountdownList(interval: MockDefaults.interval, countdownFrom: MockDefaults.countdownFrom)
        let mockCompleteCountdown = MockFactory.addEndMarker(countdownListBasic)
        let countdownDependenciesComplete = makeDependencies(mockCompleteCountdown)
        countdownComplete = Countdown(countdownDependenciesComplete)
    }
    
    override func tearDownWithError() throws {
        cancellables = []
    }
    
    // Instantiation Tests
    func test_init_stateIsReady() throws {
        XCTAssertEqual(Countdown().state, .ready) // Test default initialization
        XCTAssertEqual(countdownComplete.state, .ready)
    }
    
    func test_init_timeIsInitialized() throws {
        XCTAssertEqual(Countdown().time, Countdown.initialCountdownTime) // Test default initialization
        XCTAssertEqual(countdownComplete.time, Countdown.initialCountdownTime)
    }
        
    // countdown behavior tests
    func test_reset_countdownNeverSubscribed() throws {
        countdownComplete.reset()
        XCTAssertEqual(countdownComplete.state, .ready)
        XCTAssertEqual(countdownComplete.time, Countdown.initialCountdownTime)
    }
    
    func test_reset_countdownCompleted() throws {
        let expectation = XCTestExpectation(description: "Wait for last countdown value")
        
        // Fulfills expecation
        timeSubscriberWithExpectation(countdownComplete, expectation: expectation)
        
        countdownComplete.start()
        wait(for: [expectation], timeout: 0.1)
        countdownComplete.reset()
        
        XCTAssertEqual(countdownComplete.state, .ready)
        XCTAssertEqual(countdownComplete.time, Countdown.initialCountdownTime)
    }
    
    func test_reset_countdownStateUndefined() throws {
        let deps = makeDependencies([])
        let countdownWithStateUndefined = Countdown(deps, initialState: .undefined)
        XCTAssertEqual(CountdownState.undefined, countdownWithStateUndefined.state)
        countdownWithStateUndefined.reset()
        XCTAssertEqual(countdownWithStateUndefined.state, .ready)
    }
    
    func test_reset_countdownStateValidToReset() throws {
        let validStates: [CountdownState] = [.inProgress, .triggering, .stopped, .complete]
        validStates.forEach { state in
            let deps = makeDependencies([])
            let countdownWithState = Countdown(deps, initialState: state)
            XCTAssertEqual(state, countdownWithState.state)
            countdownWithState.reset()
            XCTAssertEqual(countdownWithState.state, .ready)
        }
    }
    
    func test_start_timeIsUpdated() throws {
        self.continueAfterFailure = false
        let expectation = XCTestExpectation(description: "Wait for last countdown value")

        // We need access to countdownList to verify publishing countdown time is working
        let countdownList = makeCountdownList(interval: MockDefaults.interval, countdownFrom: MockDefaults.countdownFrom)
        let mockCompleteCountdown = MockFactory.addEndMarker(countdownList)
        let countdownDependencies = makeDependencies(mockCompleteCountdown)
        let countdownComplete = Countdown(countdownDependencies)
        
        var expectedCountdownTimes = expectedCountdownComplete(countdownList,
                                                               initVal: Countdown.initialCountdownTime,
                                                               endMarker: CountdownTests.markEndOfCountdown)
        
        timeSubscriberWithExpectation(countdownComplete, expectation: expectation) { time in
            // remove elements from the expected array and compare to actual published value
            let expectedCountdownTime = expectedCountdownTimes.isEmpty ? nil : expectedCountdownTimes.removeFirst()
            XCTAssertNotNil(expectedCountdownTime)
            XCTAssertEqual(expectedCountdownTime!, time, accuracy: 0.01) // compare to published value
        }
        
        countdownComplete.start()
        wait(for: [expectation], timeout: 0.1)
    }
    
    func test_start_stateInProgress() throws {
        let countdownList = [MockDefaults.countdownFrom]
        let countdownDependencies = makeDependencies(countdownList)
        let countdown = Countdown(countdownDependencies)
        
        var receivedStates: [CountdownState] = []
        let expectation = XCTestExpectation(description: "Get first countdown event")
        // TODO: This test is failing, because Countdown behavior needs to change
        let expectedCountdownStates: [CountdownState] = [.ready, .inProgress]
  
        // Fulfills expecation
        timeSubscriber(countdown) { time in
            print("Countdown time: \(time)")
            if time == MockDefaults.countdownFrom {
                expectation.fulfill()
            }
        }
        
        countdown.$state
            .removeDuplicates() // Remove duplicates to get unique state changes
            .sink { state in receivedStates.append(state) }
            .store(in: &cancellables)
        
        countdown.start()
        wait(for: [expectation], timeout: 0.1)
        
        XCTAssertEqual(expectedCountdownStates, receivedStates)
    }
    
    func test_start_stateTriggering() throws {
        let triggerValue = 0.0 // must be <= 0
        let countdownList = [MockDefaults.countdownFrom, triggerValue]
        let countdownDependencies = makeDependencies(countdownList)
        let countdown = Countdown(countdownDependencies)
        
        var receivedStates: [CountdownState] = []
        let expectation = XCTestExpectation(description: "Wait until triggering")
        // TODO: This test is failing, because Countdown behavior needs to change
        let expectedCountdownStates: [CountdownState] = [.ready, .inProgress, .triggering]
  
        // Fulfills expecation
        timeSubscriber(countdown) { time in
            print("Countdown time: \(time)")
            if time == triggerValue {
                expectation.fulfill()
            }
        }
        
        countdown.$state
            .removeDuplicates() // Remove duplicates to get unique state changes
            .sink { state in receivedStates.append(state) }
            .store(in: &cancellables)
        
        countdown.start()
        wait(for: [expectation], timeout: 0.1)
        
        XCTAssertEqual(expectedCountdownStates, receivedStates)
    }
    
    func test_start_stateIsUpdatedOnCompleteCountdown() throws {
        let expectation = XCTestExpectation(description: "Wait for last countdown value")
        
        var receivedStates: [CountdownState] = []
        
        // TODO: This test is failing, because Countdown behavior needs to change
        let expectedCountdownStates: [CountdownState] = [.ready, .inProgress, .triggering, .complete]
  
        // Fulfills expecation
        timeSubscriberWithExpectation(countdownComplete, expectation: expectation)
        
        countdownComplete.$state
            .removeDuplicates() // Remove duplicates to get unique states chnages
            .sink { state in
            receivedStates.append(state)
        }
        .store(in: &cancellables)
        
        countdownComplete.start()
        wait(for: [expectation], timeout: 0.1)
        
        XCTAssertEqual(expectedCountdownStates, receivedStates)
        
        print("Expected: \(String(describing: expectedCountdownStates))")
        print("Received: \(String(describing: receivedStates))")
    }
    
    func test_stop() throws {
        countdownComplete.stop()
        XCTAssertEqual(countdownComplete.state, .stopped)
    }

    func test_complete() throws {
        countdownComplete.complete()
        XCTAssertEqual(countdownComplete.state, .complete)
    }
}

// Helpers for setting up a Subscriber to exercise the observable
@available(iOS 14.0, *)
extension CountdownTests {
    private func timeSubscriber(_ countdown: Countdown, perform: Closure<Double, Void>? = nil) {
        countdown.$time.sink { time in
            perform?(time)
        }
        .store(in: &cancellables)
    }
    
    private func timeSubscriberWithExpectation(_ countdown: Countdown, expectation: XCTestExpectation, perform: Closure<Double, Void>? = nil ) {
        timeSubscriber(countdown) { time in
            perform?(time)
            if time == Self.markEndOfCountdown {
                expectation.fulfill()
            }
        }
    }
}

// Test Helpers for setting up mocks
@available(iOS 14.0, *)
extension CountdownTests {
    private static let markEndOfCountdown = -999.0
    
    func makeCountdownList(interval: TimeInterval, countdownFrom: Double) -> [Double] {
        let step = -interval
        return Array(stride(from: countdownFrom, through: step, by: step))
    }
    
    func makeDependencies(_ countdownList: [Double]) -> CountdownDependenciesProtocol {
        let countdownPublisherClosure = MockFactory.countdownClosure(countdownList)
        return MockFactory.getCountdownDependencies(countdownPublisherClosure)
    }
    
    func expectedCountdownComplete(_ countdownList: [Double], initVal: Double, endMarker: Double) -> [Double] {
        var wrappedList = countdownList
        wrappedList.insert(initVal, at: 0)
        wrappedList.append(endMarker)
        return wrappedList
    }
        
    struct MockDefaults {
        static let referenceTimeClosure = { Date(timeIntervalSinceReferenceDate: 0.0).timeIntervalSince1970}
        static let countdownFrom = 5.5
        static let interval = 0.7
    }

    struct MockCountdownDependencies: CountdownDependenciesProtocol {
        let referenceTimeProvider: ReferenceTimeProvider
        let countdownFrom: Double
        let interval: TimeInterval
        let countdownPublisherClosure: CountdownPublisherClosure
    }

    struct MockFactory {
        
        // Appends a magic number to the countdown, it signals that we've finished all countdown related work
        // I would MUCH rather use a combine completion handler, but haven't figured out how to do that for a published property
        // in an ObservableObject.
        static func addEndMarker(_ countdownList: [Double]) -> [Double] {
            return countdownList + [CountdownTests.markEndOfCountdown]
        }

        static func getCountdownDependencies(_ countdownPublisherClosure: @escaping CountdownPublisherClosure,
                                             referenceTimeProvider: @escaping ReferenceTimeProvider = MockDefaults.referenceTimeClosure,
                                             countdownFrom: Double = MockDefaults.countdownFrom,
                                             interval: TimeInterval = MockDefaults.interval
        ) -> CountdownDependenciesProtocol {

            return MockCountdownDependencies(
                referenceTimeProvider: referenceTimeProvider,
                countdownFrom: countdownFrom,
                interval: interval,
                countdownPublisherClosure: countdownPublisherClosure
            )
        }

        static func getCountdownPublisherArgs(_ deps: CountdownDependenciesProtocol) -> CountdownPublisherArgsProtocol {
            return CountdownPublisherArgs(
                countdownFrom: deps.countdownFrom,
                referenceTime: deps.referenceTimeProvider(),
                interval: deps.interval
            )
        }

        static func countdownClosure(_ countdownList: [Double]) -> CountdownPublisherClosure {
            return { _ in countdownList.publisher.eraseToAnyPublisher() }
        }
    }
}


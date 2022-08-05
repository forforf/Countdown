//

import Combine
import AVFoundation
import TimerPublisher
import FLog

typealias ReferenceTimeProvider = () -> TimeInterval
@available(iOS 13.0, *)
typealias CountdownPublisherClosure = (CountdownPublisherArgsProtocol) -> AnyPublisher<Double, Never>

enum CountdownState: CaseIterable {
    case ready
    case inProgress
    case triggering
    case complete
    case stopped
    case undefined
}

@available(iOS 13.0, *)
protocol CountdownDependenciesProtocol {
    var referenceTimeProvider: ReferenceTimeProvider { get }
    var countdownFrom: Double { get }
    var interval: TimeInterval { get }
    var countdownPublisherClosure: CountdownPublisherClosure { get }
}

// In most cases the client should be providing the defaults, but
// these fallbacks can provide a starting point and guide.
@available(iOS 13.0, *)
struct CountdownDependencies: CountdownDependenciesProtocol {
    let referenceTimeProvider = { Date().timeIntervalSince1970 }
    let countdownFrom = 5.0
    let interval = 0.5
    let countdownPublisherClosure = TimerPublisher().countdownPublisher
}

struct CountdownPublisherArgs: CountdownPublisherArgsProtocol {
    let countdownFrom: Double
    let referenceTime: TimeInterval
    let interval: TimeInterval? // fall back to default if not provided
}

// referenceTime is the absolute time when the countdown starts. In most cases this will be the current time.
// but for testing (and added feature flexibility) it is useful to specify a specific time.
@available(iOS 14.0, *)
class Countdown: ObservableObject {
    static let log = FLog<Countdown>.make()
    
    // The initial value of the time property before any updates have been published by the underlying publisher
    static let initialCountdownTime = 0.0
    
    @Published private(set) var time = Countdown.initialCountdownTime
    @Published private(set) var state: CountdownState
    
    private var cancellable: AnyCancellable?
    private var dependencies: CountdownDependenciesProtocol
    
    private var countdownPublisher: CountdownPublisherClosure
    
    init(_ deps: CountdownDependenciesProtocol = CountdownDependencies(), initialState: CountdownState = .ready) {
        self.dependencies = deps
        self.state = initialState
        self.countdownPublisher = deps.countdownPublisherClosure // syntactic sugar
        Self.log.debug("Countdown Initialized")
    }
    
    func reset() {
        cancellable?.cancel()
        switch state {
        case .ready:
            break
        case .inProgress, .triggering, .stopped, .complete:
            updateState(.ready)
        case .undefined:
            Self.log.warning("Resetting from an undefined state")
            updateState(.ready)
        }
        time = Countdown.initialCountdownTime
    }
    
    func start(_ countdownFrom: Double? = nil,
               interval: TimeInterval? = nil,
               referenceTime: TimeInterval? = nil) {
        let interval = interval ?? dependencies.interval
        let referenceTime = referenceTime ?? dependencies.referenceTimeProvider()
        let countdownFrom = countdownFrom ?? dependencies.countdownFrom
        Self.log.debug("Countdown attempting to start from state: \(String(describing: self.state))")
        cancellable?.cancel() // just in case
        switch state {
        case .ready, .stopped, .complete:
            Self.log.debug("Starting Countdown from \(countdownFrom)")
            let countdownArgs = CountdownPublisherArgs(countdownFrom: countdownFrom, referenceTime: referenceTime, interval: interval)
            cancellable = countdownPublisher(countdownArgs)
                .sink { [weak self] time in
                    self?.time = time
                    self?.updateStateFromTimer(countdownTimer: time, countdownFrom: countdownFrom)
                }
        default:
            Self.log.notice("Invalid starting state: \(String(describing: self.state))")
        }
    }
    
    // Basically start, but with a cleaner type signature
    // instead of (TimeInterval, TimeInterval, Double) -> Void, it is () -> Void
    func restart() {
        start()
    }
    
    func stop() {
        Self.log.debug("stopping countdown")
        updateState(.stopped)
        cancellable?.cancel()
    }
    
    func complete() {
        Self.log.debug("Countdown complete")
        self.cancellable?.cancel()
        updateState(.complete)
    }
    
    // Centralize state updates
    private func updateState(_ newState: CountdownState) {
        Self.log.debug("State changing: \(state) -> \(newState)")
        state = newState
    }
    
    private func updateStateFromTimer(countdownTimer: TimeInterval, countdownFrom: Double) {
        if countdownTimer <= 0.0 {
            switch state {
            case .inProgress:
                updateState(.triggering)
            case .triggering:
                complete()
            case .complete, .stopped, .undefined:
                Self.log.warning("Countdown still running in state \(state)")
            case .ready:
                Self.log.warning("Countdown ended without ever being .inProgress")
            }
        } else if countdownTimer <= countdownFrom {
            updateState(.inProgress)
        } else {
            // countdownTimer > countdownFrom (not sure how we got here)
            updateState(.undefined)
        }
    }
}


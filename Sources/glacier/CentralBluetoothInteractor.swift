import Foundation
import Combine
import CoreBluetooth

public protocol CentralBluetoothInteractable: AnyObject {
    var interactorOptions: CentralBluetoothInteractorConfigurable { get }

    var authorizationState: AuthorizationState { get }
    var serverState: AnyPublisher<ServerState, Never> { get }
    var isScanning: AnyPublisher<Bool, Never> { get }
    var advertisingPeripherals: AnyPublisher<[PeripheralProtocol], Never> { get }
    var readyToControlPeripherals: AnyPublisher<[PeripheralProtocol], Never> { get }
    var autoReconnectionPipeline: AnyPublisher<AutoReconnectionStatus, Never> { get }
    // Besides advertising and readyToControl peripherals. There's a convenience to observe all peripherals with given states
    var allPeripherals: AnyPublisher<[UUID: (peripheral: PeripheralProtocol, peripheralState: PeripheralConnectionState)], Never> { get }

    // Following permission methods are convenience only, designed to show a specific system pop-up. Consuming the interactor streams without calling these will work as expected
    func triggerPermissionAlert()
    func triggerPowerOnAlert()

    func scanForPeripherals()
    func stopScan()

    /// Starts connection process for a specific peripheral. The result is a one time emission that specific peripheral. This method is intended for convenience if the consumer is interested in success or failure of the intended peripheral pairing. On top of this, `advertisingPeripherals` and `readyToControlPeripherals` are already updated to be subscribed.
    ///
    /// - Parameter peripheral: `Peripheral` to be connected
    /// - Parameter options: Connection options
    /// - Returns: A publisher of a `<Peripheral, Error>` which completes immediately after any given output.
    func connect(_ peripheral: PeripheralProtocol, options: [String : Any]?) -> AnyPublisher<PeripheralProtocol, GlacierError>
}

private let BluetoothExecutionQueueLabel = "glacier.execution"

public class CentralBluetoothInteractor: NSObject, CentralBluetoothInteractable {
    private let executionQueue: DispatchQueue
    private let peripheralInitialCommunication: PeripheralInitialCommunicationProtocol?
    public let interactorOptions: CentralBluetoothInteractorConfigurable

    private lazy var cbCentralManager: CBCentralManagerAbstraction? = {
        let cbCentralManager = CBCentralManager(delegate: self,
                                                queue: self.executionQueue,
                                                options: interactorOptions.centralManagerInitializationOptions)
        return cbCentralManager
    }()

    private var subscriptions = Set<AnyCancellable>()
    private var autoReconnectCancellables = [UUID: AnyCancellable]()

    // MARK: Initialization
    public convenience override init() {
        self.init(queue: DispatchQueue(label: BluetoothExecutionQueueLabel, qos: .background, attributes: .concurrent),
                  peripheralCommunication: nil,
                  interactorOptions: DefaultBluetoothInteractorOptions())
    }

    public convenience init(peripheralCommunication: PeripheralInitialCommunicationProtocol? = nil,
                            interactorOptions: CentralBluetoothInteractorConfigurable = DefaultBluetoothInteractorOptions()) {

        self.init(queue: DispatchQueue(label: BluetoothExecutionQueueLabel, qos: .background, attributes: .concurrent),
                  peripheralCommunication: peripheralCommunication,
                  interactorOptions: interactorOptions)
    }

    init(queue: DispatchQueue,
         peripheralCommunication: PeripheralInitialCommunicationProtocol?,
         interactorOptions: CentralBluetoothInteractorConfigurable) {

        self.executionQueue = queue
        self.peripheralInitialCommunication = peripheralCommunication
        self.interactorOptions = interactorOptions

        super.init()
    }

    init(centralManager: CBCentralManagerAbstraction,
         peripheralCommunication: PeripheralInitialCommunicationProtocol?,
         options: CentralBluetoothInteractorConfigurable = DefaultBluetoothInteractorOptions()) {
        self.executionQueue = DispatchQueue(label: BluetoothExecutionQueueLabel, qos: .background, attributes: .concurrent)
        interactorOptions = options
        peripheralInitialCommunication = peripheralCommunication

        super.init()
        cbCentralManager = centralManager
    }

    // MARK: CentralBluetoothInteractable
    public var authorizationState: AuthorizationState { CBManager.authorizationState }

    public var serverState: AnyPublisher<ServerState, Never> { serverStateSubject.eraseToAnyPublisher() }
    private lazy var serverStateSubject: CurrentValueSubject<ServerState, Never> = { .init(cbCentralManager?.serverState ?? .unknown) }()

    public var isScanning: AnyPublisher<Bool, Never> {
        isScanningSubject.eraseToAnyPublisher()
    }
    private lazy var isScanningSubject: CurrentValueSubject<Bool, Never> = { .init(cbCentralManager?.isScanning ?? false) }()

    public func triggerPermissionAlert() {
        refreshCentralManager(with: interactorOptions.centralManagerInitializationOptions)
    }

    public func triggerPowerOnAlert() {
        refreshCentralManager(
            with: (interactorOptions.centralManagerInitializationOptions ?? [:])
                .merging([CBCentralManagerOptionShowPowerAlertKey: true],
                         uniquingKeysWith: { (current, _) in current })
        )
    }

    private func refreshCentralManager(with options: [String: Any]?) {
        cbCentralManager = CBCentralManager(delegate: self,
                                            queue: executionQueue,
                                            options: options)
    }

    public var advertisingPeripherals: AnyPublisher<[PeripheralProtocol], Never> {
        internalPeripheralStorage
            .map { $0.values
                .filter { $1 == .advertising }
                .map { $0.peripheral }
            }
            .removeDuplicates(by: { $0.map { $0.cbPeripheral.identifier } == $1.map { $0.cbPeripheral.identifier } })
            .share()
            .eraseToAnyPublisher()
    }
    public var readyToControlPeripherals: AnyPublisher<[PeripheralProtocol], Never> {
        internalPeripheralStorage
            .map { $0.values
                .filter { $1 == .readyToControl }
                .map { $0.peripheral }
            }
            .removeDuplicates(by: { $0.map { $0.cbPeripheral.identifier } == $1.map { $0.cbPeripheral.identifier } })
            .share()
            .eraseToAnyPublisher()
    }
    public var allPeripherals: AnyPublisher<[UUID: (peripheral: PeripheralProtocol, peripheralState: PeripheralConnectionState)], Never> {
        internalPeripheralStorage
            .share()
        .eraseToAnyPublisher() }
    private var internalPeripheralStorage: CurrentValueSubject<[UUID: (peripheral: PeripheralProtocol, peripheralState: PeripheralConnectionState)], Never> = .init([:])

    public var autoReconnectionPipeline: AnyPublisher<AutoReconnectionStatus, Never> { autoReconnectionPipelineSubject.eraseToAnyPublisher() }
    private let autoReconnectionPipelineSubject = PassthroughSubject<AutoReconnectionStatus, Never>()

    public func scanForPeripherals() {
        guard
            let cbCentralManager = cbCentralManager,
            serverStateSubject.value == .poweredOn,
            !cbCentralManager.isScanning
        else { return }

        cbCentralManager.scanForPeripherals(withServices: interactorOptions.peripheralScanningRequiredServices,
                                            options: interactorOptions.peripheralScanningOptions)

        if isScanningSubject.value == false { isScanningSubject.send(true) }
    }

    public func stopScan() {
        if isScanningSubject.value == true { isScanningSubject.send(false) }
        guard let cbCentralManager = cbCentralManager, cbCentralManager.isScanning else { return }

        cbCentralManager.stopScan()

        executionQueue.async(flags: .barrier) { [internalPeripheralStorage] in
            for (key, value) in internalPeripheralStorage.value {
                if value.peripheralState == .advertising {
                    internalPeripheralStorage.value.removeValue(forKey: key)
                }
            }
        }
    }

    private var peripheralPairingValidationStream = PassthroughSubject<(peripheralIdentifier: UUID, error: Error?), Never>()
    /**
     As explained in the protocol declaration above, this method is emitting based on a succesful/failed connection followed by pairing validation. Any successful or failed emission will complete the returned AnyPublisher due to the underlying Future. This requires resubscription on-demand.

     */
    public func connect(_ peripheral: PeripheralProtocol, options: [String : Any]?) -> AnyPublisher<PeripheralProtocol, GlacierError> {
        guard let cbCentralManager = cbCentralManager, case .unpaired = peripheral.pairingState else {
            internalPeripheralStorage.value[peripheral.cbPeripheral.identifier] = (peripheral, .readyToControl)
            return Just(peripheral).setFailureType(to: GlacierError.self).eraseToAnyPublisher()
        }

        cbCentralManager.connect(peripheral, options: options)

        return peripheralPairingValidationStream
            .filter { peripheral.cbPeripheral.identifier == $0.peripheralIdentifier }
            .flatMap { [weak self] validationResult in
                Future { promise in
                    guard let self = self else {
                        promise(.failure(GlacierError.unknown(nil)))
                        return
                    }

                    if let error = validationResult.error {
                        self.cbCentralManager?.cancelConnection(peripheral: peripheral)
                        peripheral.resetPairingState()

                        if let error = error as? GlacierError {
                            promise(.failure(error))
                        } else {
                            promise(.failure(GlacierError.unknown(error)))
                        }
                    } else {
                        promise(.success(peripheral))
                    }
                }
            }
            .timeout(interactorOptions.initialDiscoveryTimeout, scheduler: DispatchQueue.global()) { [internalPeripheralStorage] in
                internalPeripheralStorage.value.removeValue(forKey: peripheral.cbPeripheral.identifier)
                return GlacierError.peripheralInitialDiscoveryTimeout
            }
            .first()
            .eraseToAnyPublisher()
    }

    // MARK: CBCentralManagerDelegate Redirections

    func updateServerState(state: ServerState) {
        executionQueue.async(flags: .barrier) { [serverStateSubject, internalPeripheralStorage] in
            serverStateSubject.send(state)
            guard state == .poweredOn else {
                internalPeripheralStorage.value = [:]
                return
            }
        }
    }

    func reactPeripheralDiscovery(peripheral: PeripheralProtocol) {
        guard peripheral.cbPeripheral.name != nil else { return }
        executionQueue.async(flags: .barrier) { [weak internalPeripheralStorage] in
            internalPeripheralStorage?.value[peripheral.cbPeripheral.identifier] = (peripheral, .advertising)
        }
    }

    /**
     After initiating connection to a peripheral with `connect` method, `didConnect` delegate callback redirects to this method.

     After the check, specific peripheral goes under pairing validation with ping data (this part is handled within the `Peripheral` logic). Subscribing to that validation process will ping the internal `peripheralPairingValidationStream` in this class to inform the result back to the `connect` method defined above.
     */
    func reactPeripheralConnection(peripheral: CBPeripheralAbstraction) {
        func advertisingAndReconnectingPeripherals() -> AnyPublisher<[PeripheralProtocol], Never> {
            internalPeripheralStorage
                .map { $0.values
                        .filter { ($1 == .advertising) || ($1 == .reconnecting) }
                        .map { $0.peripheral }
                }
                .removeDuplicates(by: { $0.map { $0.cbPeripheral.identifier } == $1.map { $0.cbPeripheral.identifier } })
                .eraseToAnyPublisher()
        }

        return advertisingAndReconnectingPeripherals()
            .subscribe(on: executionQueue)
            .tryMap { advertisingAndReconnectingPeripherals -> PeripheralProtocol in
                guard let matchingPeripheral = advertisingAndReconnectingPeripherals
                        .first(where: { $0.cbPeripheral.identifier == peripheral.identifier }) else {
                            throw GlacierError.peripheralStoppedAdvertising
                        }
                return matchingPeripheral
            }
            .flatMap {
                $0.validatePairing()
            }
            .first()
            .sink(receiveCompletion: { [weak self] in
                if case let .failure(error) = $0 {
                    self?.peripheralPairingValidationStream.send((peripheralIdentifier: peripheral.identifier, error: error))
                }
            }, receiveValue: { [weak executionQueue, internalPeripheralStorage, peripheralPairingValidationStream] readyToControlPeripheral in
                executionQueue?.async(flags: .barrier) {
                    internalPeripheralStorage.value[peripheral.identifier] = (readyToControlPeripheral, .readyToControl)

                    peripheralPairingValidationStream.send((peripheralIdentifier: peripheral.identifier, error: nil))
                }
            }).store(in: &subscriptions)
    }

    func reactPeripheralFailedConnection(peripheral: CBPeripheralAbstraction, error: Error?) {
        peripheralPairingValidationStream.send(
            (peripheralIdentifier: peripheral.identifier,
             error: GlacierError.unknown(error))
        )
    }

    func reactPeripheralDisconnection(peripheral: CBPeripheralAbstraction, error: Error?) {
        func attemptReconnection(to disconnectingPeripheral: PeripheralProtocol) {
            executionQueue.async(flags: .barrier) { [weak self] in
                self?.internalPeripheralStorage.value[peripheral.identifier] = (disconnectingPeripheral, .reconnecting)
            }
            disconnectingPeripheral.resetPairingState()

            func reconnect() -> AnyPublisher<PeripheralProtocol, GlacierError> {
                connect(disconnectingPeripheral, options: [:])
                    .catch({ _ in reconnect() })
                    .eraseToAnyPublisher()
            }

            autoReconnectCancellables[disconnectingPeripheral.cbPeripheral.identifier] =
            reconnect()
                .subscribe(on: executionQueue)
                .timeout(interactorOptions.autoReconnectTimeout, scheduler: DispatchQueue.global()) {
                    return GlacierError.peripheralAutoReconnectTimeout
                }
                .first()
                .handleEvents(receiveSubscription: { [weak self] _ in
                    self?.autoReconnectionPipelineSubject.send(.init(
                        identifier: disconnectingPeripheral.cbPeripheral.identifier,
                        state: .reconnecting))
                })
                .sink(receiveCompletion: { [weak self] in
                    if case .failure = $0 {
                        // Failed to reconnect within given timeout range
                        self?.executionQueue.async(flags: .barrier) {
                            self?.internalPeripheralStorage.value.removeValue(forKey: disconnectingPeripheral.cbPeripheral.identifier)
                            self?.autoReconnectCancellables.removeValue(forKey: disconnectingPeripheral.cbPeripheral.identifier)
                        }
                        self?.cbCentralManager?.cancelConnection(peripheral: disconnectingPeripheral)

                        self?.autoReconnectionPipelineSubject.send(.init(
                            identifier: disconnectingPeripheral.cbPeripheral.identifier,
                            state: .failed))
                    }
                }, receiveValue: { [weak self] peripheral in
                    // Successful reconnection
                    self?.executionQueue.async(flags: .barrier) {
                        self?.autoReconnectCancellables.removeValue(forKey: peripheral.cbPeripheral.identifier)
                        self?.autoReconnectionPipelineSubject.send(
                            .init(identifier: disconnectingPeripheral.cbPeripheral.identifier,
                                  state: .reconnected)
                        )
                    }
                })
        }

        // Only try to receonnect if the error is a `connectionTimeout` or `encryptionTimedOut`.
        // Those errors treated as an accidental/unconscious disconnect.

        if let error = error as? CBError,
           (CBError.connectionTimeout == error.code || CBError.encryptionTimedOut == error.code),
           let disconnectingPeripheral = internalPeripheralStorage.value[peripheral.identifier]?.peripheral,
           disconnectingPeripheral.cbPeripheral.peripheralState == .disconnected ||
            disconnectingPeripheral.cbPeripheral.peripheralState == .disconnecting {

            attemptReconnection(to: disconnectingPeripheral)
        } else {
            executionQueue.async(flags: .barrier) { [weak self] in
                self?.internalPeripheralStorage.value.removeValue(forKey: peripheral.identifier)
            }
        }
    }
}

extension CentralBluetoothInteractor: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateServerState(state: central.serverState)
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any], rssi RSSI: NSNumber) {

        guard let peripheralCommunication = peripheralInitialCommunication else { return }

        let peripheral = Peripheral(cbPeripheral: peripheral,
                                    advertisementData: advertisementData,
                                    rssi: RSSI,
                                    peripheralCommunication: peripheralCommunication)

        reactPeripheralDiscovery(peripheral: peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        reactPeripheralConnection(peripheral: peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        reactPeripheralFailedConnection(peripheral: peripheral, error: error)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        reactPeripheralDisconnection(peripheral: peripheral, error: error)
    }
}

public enum PeripheralConnectionState: Hashable {
    /*
     `readyToControl` means either connected - bonded - paired OR connected - bonded peripheral.
     This is based on the BT stack of a specific peripheral.
     */
    case advertising
    case readyToControl
    case reconnecting
}

public enum AutoReconnectionState: Equatable {
    case reconnecting
    case reconnected
    case failed
}

public struct AutoReconnectionStatus: Equatable {
    public let identifier: UUID
    public let state: AutoReconnectionState

    public init(identifier: UUID, state: AutoReconnectionState) {
        self.identifier = identifier
        self.state = state
    }
}

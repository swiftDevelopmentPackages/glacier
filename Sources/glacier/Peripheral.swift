import Foundation
import CoreBluetooth
import Combine

public protocol PeripheralProtocol {
  var cbPeripheral: CBPeripheralAbstraction { get }
  var pairingState: PeripheralPairingState { get set }
  func discoverServices()
  func validatePairing() -> AnyPublisher<PeripheralProtocol, Error>
  func resetPairingState()
  
  func writeWithoutResponse(data: Data)
  func writeWithResponse(data: Data) -> AnyPublisher<Void, Error>
  
  func read() -> AnyPublisher<Result<Data, Error>, Never>
  var readValueStream: AnyPublisher<Result<Data, Error>, Never> { get }
}

public enum PeripheralPairingState {
  case unpaired(dialogueShown: Bool)
  case paired
}

public class Peripheral: NSObject, PeripheralProtocol {
  
  public let cbPeripheral: CBPeripheralAbstraction
  public let advertisementData: [String : Any]
  public let rssi: NSNumber
  
  private var peripheralValidationFlow = PassthroughSubject<Result<PeripheralProtocol, GlacierError>, Never>()
  public var pairingState: PeripheralPairingState = .unpaired(dialogueShown: false)
  
  private var readCharacteristic: CBCharacteristicAbstraction?
  private var writeCharacteristic: CBCharacteristicAbstraction?
  private var peripheralCommunication: PeripheralInitialCommunicationProtocol
  
  private let writeQueue = DispatchQueue(label: "peripheralWriteQueue", qos: .background)
  private let writeSemaphore = DispatchSemaphore(value: 1)
  private let writeResponseStream = CurrentValueSubject<Result<Void, Error>?, Never>(nil)
  
  private let readValueSubject = CurrentValueSubject<Result<Data, Error>?, Never>(nil)
  
  private var subscriptions = Set<AnyCancellable>()
  
  init(cbPeripheral: CBPeripheralAbstraction,
       advertisementData: [String : Any],
       rssi: NSNumber,
       peripheralCommunication: PeripheralInitialCommunicationProtocol) {
    
    self.cbPeripheral = cbPeripheral
    self.advertisementData = advertisementData
    self.rssi = rssi
    self.peripheralCommunication = peripheralCommunication
    
    super.init()
    
    self.cbPeripheral.delegate = self
  }
  
  public func discoverServices() {
    if cbPeripheral.peripheralState == .disconnected || cbPeripheral.peripheralState == .disconnecting {
      peripheralValidationFlow.send(.failure(GlacierError.peripheralConnectionLossDuringPairing))
    } else {
      cbPeripheral.discoverServices(peripheralCommunication.servicesToDiscover)
    }
  }
  
  public func validatePairing() -> AnyPublisher<PeripheralProtocol, Error> {
    return peripheralValidationFlow
      .handleEvents(receiveSubscription: { [weak self] _ in
        self?.discoverServices()
      })
      .flatMap { result in
        Deferred {
          Future { promise in
            if case let .success(peripheral) = result {
              promise(.success(peripheral))
            } else if case let .failure(error) = result {
              promise(.failure(error))
            }
          }
        }
      }
    // This is the non-configurable pairing system pop-up presence timeout
      .timeout(30, scheduler: DispatchQueue.global()) {
        GlacierError.peripheralInitialDiscoveryTimeout
      }
      .eraseToAnyPublisher()
  }
  
  public func resetPairingState() {
    pairingState = .unpaired(dialogueShown: false)
  }
  
  func reactServicesDiscovery(peripheral: CBPeripheralAbstraction) {
    for service in peripheral.getServices() {
      peripheral.discoverCharacteristics(peripheralCommunication.characteristicsToDiscover, forService: service)
    }
  }
  
  func reactCharacteristicsDiscovery(peripheral: CBPeripheralAbstraction, service: CBServiceAbstraction) {
    let characteristics = service.getCharacteristics()
    
    func initializeWriteCharacteristic() {
      if writeCharacteristic == nil {
        writeCharacteristic = characteristics.first {
          $0.uuid.uuidString
            .contains(peripheralCommunication.writeCharacteristicIdentifier.uuidString) &&
          $0.properties
            .contains(.write)
        }
      }
      
      guard let writeCharacteristic = writeCharacteristic else { return }
      cbPeripheral.setNotifyValue(true, forCharacteristic: writeCharacteristic)
    }
    
    func initializeReadCharacteristic() {
      if readCharacteristic == nil {
        readCharacteristic = characteristics.first {
          $0.uuid.uuidString
            .contains(peripheralCommunication.readCharacteristicIdentifier.uuidString) &&
          ($0.properties.contains(.read) || $0.properties.contains(.notify))
        }
      }
    }
    
    guard case .unpaired = pairingState else { return }
    
    initializeWriteCharacteristic()
    initializeReadCharacteristic()
    requestPairing()
  }
  
  private func requestPairing() {
    guard let writeCharacteristic = writeCharacteristic else { return }
    
    cbPeripheral.writeValue(peripheralCommunication.pairingRequestPayload,
                            forCharacteristic: writeCharacteristic,
                            type: .withResponse)
  }
  
  private func confirmPairing() {
    func configureReadCharacteristicNotification() {
      // if the peripheral has notify channel
      if let readCharacteristic = readCharacteristic,
         readCharacteristic.properties.contains(.notify) {
        cbPeripheral.setNotifyValue(true, forCharacteristic: readCharacteristic)
      }
    }
    
    if let writeCharacteristic = writeCharacteristic {
      cbPeripheral.writeValue(peripheralCommunication.pairingConfirmationPayload,
                              forCharacteristic: writeCharacteristic,
                              type: .withResponse)
    }
    
    configureReadCharacteristicNotification()
  }
  
  func reactPairingValueWrite(error: Error?) {
    if case let .unpaired(dialogueShown) = pairingState,
       !dialogueShown,
       error != nil {
      // Retry because the first one will always fail for pairing required toys
      pairingState = .unpaired(dialogueShown: true)
      requestPairing()
    } else if let error = error as? CBATTError,
              case .insufficientEncryption = error.code {
      peripheralValidationFlow.send(.failure(GlacierError.peripheralPairingPermissonFailure))
    } else if let error = error {
      peripheralValidationFlow.send(.failure(GlacierError.unknown(error)))
    } else {
      peripheralValidationFlow.send(.success(self))
      pairingState = .paired
      confirmPairing()
    }
  }
  
  func reactValueWrite(error: Error?) {
    if let error = error {
      writeResponseStream.send(.failure(error))
    } else {
      writeResponseStream.send(.success(()))
    }
    
    writeSemaphore.signal()
  }
  
  func reactValueUpdate(characteristic: CBCharacteristicAbstraction, error: Error?) {
    if let error = error {
      readValueSubject.send(.failure(error))
    } else if let value = characteristic.value {
      readValueSubject.send(.success(value))
    }
  }
  
  //MARK: READ/WRITE OPERATIONS
  
  public func read() -> AnyPublisher<Result<Data, Error>, Never> {
    guard let readCharacteristic = readCharacteristic else { return Empty().eraseToAnyPublisher() }
    cbPeripheral.readValueForCharacteristic(readCharacteristic)
    
    return readValueSubject
      .compactMap { $0 }
      .first()
      .receive(on: DispatchQueue.main)
      .eraseToAnyPublisher()
  }
  
  public var readValueStream: AnyPublisher<Result<Data, Error>, Never> {
    // some peripherals fail to notify even if they have `.notify` channel
    // A timeout force-reads the characteristic and refreshes the value manually
    func repeatableRead() -> AnyPublisher<Result<Data, Error>, Error> {
      readValueSubject
        .setFailureType(to: Error.self)
        .compactMap { $0 }
        .timeout(peripheralCommunication.readCharacteristicPollingInterval,
                 scheduler: DispatchQueue.main) {
          PeripheralError.readNotifyTimeout
        }
                 .catch({ [weak self] _ -> AnyPublisher<Result<Data, Error>, Error> in
                   guard let readCharacteristic = self?.readCharacteristic else {
                     return Empty().eraseToAnyPublisher()
                   }
                   // force read manually
                   self?.cbPeripheral.readValueForCharacteristic(readCharacteristic)
                   
                   return repeatableRead()
                 })
                 .eraseToAnyPublisher()
    }
    
    return repeatableRead()
      .handleEvents(receiveSubscription: { [weak self] _ in
        guard let readCharacteristic = self?.readCharacteristic else { return }
        self?.cbPeripheral.readValueForCharacteristic(readCharacteristic)
      })
      .assertNoFailure()
      .receive(on: DispatchQueue.main)
      .eraseToAnyPublisher()
  }
  
  public func writeWithoutResponse(data: Data) {
    guard let writeCharacteristic = writeCharacteristic else { return }
    
    cbPeripheral.writeValue(data,
                            forCharacteristic: writeCharacteristic,
                            type: .withResponse)
  }
  
  public func writeWithResponse(data: Data) -> AnyPublisher<Void, Error> {
    Deferred {
      Future { [weak self] promise in
        self?.writeQueue.async { [weak self] in
          guard let self = self,
                let writeCharacteristic = self.writeCharacteristic else { return }
          
          self.writeSemaphore.wait()
          
          self.cbPeripheral.writeValue(data,
                                       forCharacteristic: writeCharacteristic,
                                       type: .withResponse)
          
          self.writeResponseStream
            .compactMap { $0 }
            .sink(receiveCompletion: { _ in },
                  receiveValue: {
              if case .success = $0 {
                promise(.success(()))
              } else if case let .failure(error) = $0 {
                promise(.failure(error))
              }})
            .store(in: &self.subscriptions)
        }
      }
    }
    .eraseToAnyPublisher()
  }
  
  deinit {
    // Deallocation during a semaphore lock causes a crash, freeing the pool
    writeSemaphore.signal()
  }
}

//MARK: CBPeripheralDelegate

extension Peripheral: CBPeripheralDelegate {
  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    reactServicesDiscovery(peripheral: peripheral)
  }
  
  public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    reactCharacteristicsDiscovery(peripheral: peripheral, service: service)
  }
  
  public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    if case .unpaired = pairingState {
      reactPairingValueWrite(error: error)
    } else {
      reactValueWrite(error: error)
    }
  }
  
  public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    reactValueUpdate(characteristic: characteristic, error: error)
  }
}

private enum PeripheralError: Error {
  case readNotifyTimeout
}

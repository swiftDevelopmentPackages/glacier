import CoreBluetooth
@testable import glacier
import Combine

class MockPeripheral: MockBase, PeripheralProtocol {
  static func dummyPeripheral(identifier: String) -> MockPeripheral {
    let cbPeripheral = MockCBPeripheral.dummyCBPeripheral(identifier: identifier)
    let peripheral = MockPeripheral()
    peripheral.cbPeripheral = cbPeripheral
    return peripheral
  }
  
  static func dummyPeripheral() -> PeripheralProtocol {
    let cbPeripheral = MockCBPeripheral.dummyCBPeripheral(identifier: "00000000-0000-0000-0000-000000000000")
    let peripheral = MockPeripheral()
    peripheral.cbPeripheral = cbPeripheral
    return peripheral
  }
  
  var cbPeripheral: CBPeripheralAbstraction = MockCBPeripheral()
  var pairingState: PeripheralPairingState = .unpaired(dialogueShown: false)
  
  var pairingValidationStream = CurrentValueSubject<PeripheralProtocol?, Error>(nil)
  
  func writeWithoutResponse(data: Data) { track() }
  func writeWithResponse(data: Data) -> AnyPublisher<Void, Error> {
    track()
    return writeMock
  }
  
  func read() -> AnyPublisher<Result<Data, Error>, Never> {
    track()
    return Just(.success(Data())).eraseToAnyPublisher()
  }
  
  var readValueStream: AnyPublisher<Result<Data, Error>, Never> { readMock }
  
  func discoverServices() {
    track()
  }
  
  func validatePairing() -> AnyPublisher<PeripheralProtocol, Error> {
    track()
    return pairingValidationStream.compactMap { $0 }.eraseToAnyPublisher()
  }
  
  func resetPairingState() {
    track()
  }
  
  var readMock: AnyPublisher<Result<Data, Error>, Never> = CurrentValueSubject(.success(Data())).eraseToAnyPublisher()
  var writeMock: AnyPublisher<Void, Error> = Empty().eraseToAnyPublisher()
}

import CoreBluetooth
@testable import glacier
import Combine

class MockCBPeripheral: MockBase, CBPeripheralAbstraction {
  static func dummyCBPeripheral(identifier: String) -> MockCBPeripheral {
    let identifier: UUID = UUID(uuidString: identifier)!
    let cbPeripheral = MockCBPeripheral()
    cbPeripheral.identifier = identifier
    cbPeripheral.name = "name"
    return cbPeripheral
  }

  var peripheralState: PeripheralState = .disconnected
  var services = [CBServiceAbstraction]()

  var peripheralStatePublisher: AnyPublisher<PeripheralState, Never> {
    Just<PeripheralState>(peripheralState).eraseToAnyPublisher()
  }

  var name: String?
  var identifier: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
  var delegate: CBPeripheralDelegate?

  func discoverServices(_ services: [CBUUID]?) {
    track()
  }

  func discoverCharacteristics(_ characteristics: [CBUUID]?, forService service: CBServiceAbstraction) {
    track()
  }

  func setNotifyValue(_ enabled: Bool, forCharacteristic characteristic: CBCharacteristicAbstraction) {
    track()
  }

  func readValueForCharacteristic(_ characteristic: CBCharacteristicAbstraction) {
    track()
  }

  func writeValue(_ data: Data, forCharacteristic characteristic: CBCharacteristicAbstraction, type: CBCharacteristicWriteType) {
    track()
  }

  func getServices() -> [CBServiceAbstraction] {
    track()
    return services
  }
}

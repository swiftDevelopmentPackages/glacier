import CoreBluetooth
@testable import glacier
import Combine

class MockCBCharacteristic: MockBase, CBCharacteristicAbstraction {
  var uuid = CBUUID(string: "00000000-0000-0000-0000-000000000000")
  var value: Data?
  var properties: CBCharacteristicProperties = .notify
  var isNotifying: Bool = true
}

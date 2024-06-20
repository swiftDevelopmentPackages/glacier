import CoreBluetooth
@testable import glacier
import Combine

class MockCBService: MockBase, CBServiceAbstraction {
  var uuid = CBUUID(string: "00000000-0000-0000-0000-000000000000")
  var characteristics = [CBCharacteristicAbstraction]()
  
  func getCharacteristics() -> [CBCharacteristicAbstraction] {
    track()
    return characteristics
  }
}

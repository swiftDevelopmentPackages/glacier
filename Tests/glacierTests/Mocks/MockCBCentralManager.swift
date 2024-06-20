@testable import glacier
import CoreBluetooth

class MockCBCentralManager: MockBase, CBCentralManagerAbstraction {
  var authorizationState: AuthorizationState = .notDetermined
  var serverState: ServerState = .poweredOn
  var isScanning: Bool = false
  var delegate: CBCentralManagerDelegate?
  
  func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String : Any]?) {
    track()
  }
  
  func stopScan() {
    track()
  }
  
  func connect(_ peripheral: PeripheralProtocol, options: [String : Any]?) {
    track()
  }
  
  func cancelConnection(peripheral: PeripheralProtocol) {
    track()
  }
}

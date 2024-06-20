import Foundation
import CoreBluetooth
import Combine

// MARK: BluetoothInteractorState
public enum ServerState: CustomStringConvertible {
  case unauthorized, unknown, unsupported, resetting, poweredOff, poweredOn
  
  public var description: String {
    switch self {
    case .unauthorized:
      return "unauthorized"
    case .unknown:
      return "unknown"
    case .unsupported:
      return "unsupported"
    case .resetting:
      return "resetting"
    case .poweredOff:
      return "poweredOff"
    case .poweredOn:
      return "poweredOn"
    }
  }
}

public enum PeripheralState: CustomStringConvertible {
  case disconnected, connecting, connected, disconnecting
  
  public var description: String {
    switch self {
    case .disconnected:
      return "disconnected"
    case .connecting:
      return "connecting"
    case .connected:
      return "connected"
    case .disconnecting:
      return "disconnecting"
    }
  }
}

public enum AuthorizationState: CustomStringConvertible {
  case notDetermined, restricted, alwaysAllowed, denied
  
  public var description: String {
    switch self {
    case .notDetermined:
      return "notDetermined"
    case .restricted:
      return "restricted"
    case .alwaysAllowed:
      return "alwaysAllowed"
    case .denied:
      return "denied"
    }
  }
}

// MARK: CBCentralManagerAbstraction
public protocol CBCentralManagerAbstraction: AnyObject {
  var serverState: ServerState { get }
  var isScanning: Bool { get }
  var delegate: CBCentralManagerDelegate? { get set }
  
  func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String : Any]?)
  func stopScan()
  func connect(_ peripheral: PeripheralProtocol, options: [String : Any]?)
  func cancelConnection(peripheral: PeripheralProtocol)
}

extension CBCentralManager: CBCentralManagerAbstraction {
  public var serverState: ServerState {
    switch state {
    case .unauthorized:
      return .unauthorized
    case .unknown:
      return .unknown
    case .unsupported:
      return .unsupported
    case .resetting:
      return .resetting
    case .poweredOff:
      return .poweredOff
    case .poweredOn:
      return .poweredOn
    @unknown default:
      fatalError()
    }
  }
  
  public func connect(_ peripheral: PeripheralProtocol, options: [String : Any]?) {
    guard let cbPeripheral = peripheral.cbPeripheral as? CBPeripheral else { return }
    
    self.connect(cbPeripheral, options: options)
  }
  
  public func cancelConnection(peripheral: PeripheralProtocol) {
    guard let cbPeripheral = peripheral.cbPeripheral as? CBPeripheral else { return }
    
    self.cancelPeripheralConnection(cbPeripheral)
  }
}

extension CBManager {
  public static var authorizationState: AuthorizationState {
    switch CBManager.authorization {
    case .notDetermined:
      return .notDetermined
    case .restricted:
      return .restricted
    case .allowedAlways:
      return .alwaysAllowed
    case .denied:
      return .denied
    @unknown default:
      fatalError()
    }
  }
}

// MARK: CBPeripheralAbstraction
public protocol CBPeripheralAbstraction: AnyObject {
  var name: String? { get }
  var identifier: UUID { get }
  var delegate: CBPeripheralDelegate? { get set }
  var peripheralState: PeripheralState { get }
  
  func discoverServices(_ services: [CBUUID]?)
  func discoverCharacteristics(_ characteristics: [CBUUID]?, forService service: CBServiceAbstraction)
  func setNotifyValue(_ enabled:Bool, forCharacteristic characteristic: CBCharacteristicAbstraction)
  func readValueForCharacteristic(_ characteristic: CBCharacteristicAbstraction)
  func writeValue(_ data: Data, forCharacteristic characteristic: CBCharacteristicAbstraction, type: CBCharacteristicWriteType)
  func getServices() -> [CBServiceAbstraction]
}

extension CBPeripheral: CBPeripheralAbstraction {
  public var peripheralState: PeripheralState {
    switch state {
    case .connected:
      return .connected
    case .connecting:
      return .connecting
    case .disconnected:
      return .disconnected
    case .disconnecting:
      return .disconnecting
    @unknown default:
      fatalError()
    }
  }
  
  public func discoverCharacteristics(_ characteristics:[CBUUID]?, forService service: CBServiceAbstraction) {
    guard let cbService = service as? CBService else { return }
    self.discoverCharacteristics(characteristics, for: cbService)
  }
  
  public func setNotifyValue(_ enabled: Bool, forCharacteristic characteristic: CBCharacteristicAbstraction) {
    guard let cbCharacteristic = characteristic as? CBCharacteristic else { return }
    self.setNotifyValue(enabled, for: cbCharacteristic)
  }
  
  public func readValueForCharacteristic(_ characteristic: CBCharacteristicAbstraction) {
    guard let cbCharacteristic = characteristic as? CBCharacteristic else { return }
    self.readValue(for: cbCharacteristic)
  }
  
  public func writeValue(_ data: Data, forCharacteristic characteristic: CBCharacteristicAbstraction, type: CBCharacteristicWriteType) {
    guard let cbCharacteristic = characteristic as? CBCharacteristic else { return }
    self.writeValue(data, for: cbCharacteristic, type: type)
  }
  
  public func getServices() -> [CBServiceAbstraction] {
    guard let services = services else { return [] }
    return services.map{ $0 as CBServiceAbstraction }
  }
}

// MARK: CBServiceAbstraction
public protocol CBServiceAbstraction: AnyObject {
  var uuid: CBUUID { get }
  func getCharacteristics() -> [CBCharacteristicAbstraction]
}

extension CBService: CBServiceAbstraction {
  public func getCharacteristics() -> [CBCharacteristicAbstraction] {
    guard let characteristics = self.characteristics else { return [] }
    return characteristics.map{ $0 as CBCharacteristicAbstraction }
  }
}

// MARK: CBCharacteristicAbstraction
public protocol CBCharacteristicAbstraction: AnyObject {
  var uuid: CBUUID { get }
  var value: Data? { get }
  var properties: CBCharacteristicProperties { get }
  var isNotifying: Bool { get }
}

extension CBCharacteristic : CBCharacteristicAbstraction {}

import Foundation
import CoreBluetooth
import Combine

public protocol PeripheralInitialCommunicationProtocol {
  var servicesToDiscover: [CBUUID]? { get }
  var characteristicsToDiscover: [CBUUID]? { get }
  var readCharacteristicIdentifier: CBUUID { get }
  var writeCharacteristicIdentifier: CBUUID { get }
  var readCharacteristicPollingInterval: DispatchQueue.SchedulerTimeType.Stride { get }
  var pairingRequestPayload: Data { get }
  var pairingConfirmationPayload: Data { get }
}

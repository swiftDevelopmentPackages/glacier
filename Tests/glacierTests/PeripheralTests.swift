@testable import glacier
import XCTest
import CoreBluetooth
import Combine

class PeripheralTests: XCTestCase {
  private var peripheral: Peripheral!
  private var mockCBPeripheral: MockCBPeripheral!
  private var cancellables: Set<AnyCancellable>!

  override func setUp() {
    super.setUp()
    mockCBPeripheral = MockCBPeripheral.dummyCBPeripheral(identifier: "00000000-0000-0000-0000-000000000000")
    peripheral = Peripheral(cbPeripheral: mockCBPeripheral,
                            advertisementData: [:],
                            rssi: 5,
                            peripheralCommunication: MockPeripheralInitialCommunication())
    cancellables = Set<AnyCancellable>()
  }

  // MARK: Discover Services
  func test_givenPeripheral_andDisconnected_whenDiscoveringServices_shouldStopAndFail() {
    mockCBPeripheral.peripheralState = .disconnected
    let expectation = expectation(description: "peripheral service discovery is triggered when disconnected")

    peripheral.validatePairing()
      .sink(receiveCompletion: {
        if case let .failure(error as GlacierError) = $0,
           case .peripheralConnectionLossDuringPairing = error {
          XCTAssertEqual(self.mockCBPeripheral.calledMethods, [])
          expectation.fulfill()
        } else {
          XCTFail("Should not complete succesfully")
        }
      }, receiveValue: { _ in
        XCTFail("Should not complete succesfully")
      })
      .store(in: &cancellables)

    peripheral.discoverServices()
    waitForExpectations(timeout: 5)
  }

  func test_givenPeripheral_andConnected_whenDiscoveringServices_shouldRedirect() {
    mockCBPeripheral.peripheralState = .connected
    peripheral.discoverServices()
    XCTAssertEqual(mockCBPeripheral.calledMethods, ["discoverServices(_:)"])
  }

  func test_givenPeripheral_andReactsServiceDiscovery_thenShouldDiscoverCharacteristics() {
    mockCBPeripheral.services = [MockCBService(), MockCBService()]
    peripheral.reactServicesDiscovery(peripheral: mockCBPeripheral)
    XCTAssertEqual(mockCBPeripheral.calledMethods, ["getServices()",
                                                    "discoverCharacteristics(_:forService:)",
                                                    "discoverCharacteristics(_:forService:)"])
  }

  func test_givenPeripheral_andWithoutServices_andReactsServiceDiscovery_thenShouldNotDiscoverCharacteristics() {
    peripheral.reactServicesDiscovery(peripheral: mockCBPeripheral)
    XCTAssertEqual(mockCBPeripheral.calledMethods, ["getServices()"])
  }

  // MARK: Pairing State
  func test_givenPeripheral_whenInitialized_thenShouldBeUnpairedDefault() {
    if case let .unpaired(dialogueShown: isShown) = peripheral.pairingState {
      XCTAssertFalse(isShown)
    } else {
      XCTFail("initialized faulty")
    }
  }

  func test_givenPeripheral_whenResetPairingState_thenShouldRestoreToDefaults() {
    peripheral.pairingState = .paired
    peripheral.resetPairingState()
    if case let .unpaired(dialogueShown: isShown) = peripheral.pairingState {
      XCTAssertFalse(isShown)
    } else {
      XCTFail("didn't reset state")
    }
  }

  // MARK: Discover Characteristics
  func test_givenPeripheral_whenReactsCharacteristicDiscovery_andPaired_thenShouldStopInitializingChannels() {
    peripheral.pairingState = .paired

    let service = MockCBService()
    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
  }

  // MARK: Write Characteristics
  func test_givenPeripheral_whenReactsCharacteristicDiscovery_andUnpaired_andContainsInvalidWriteCharacteristicsUUID_thenShouldNotInitializeWriteChannel() {
    peripheral.pairingState = .unpaired(dialogueShown: false)

    let invalidWriteCharacteristic = MockCBCharacteristic()

    let service = MockCBService()
    service.characteristics = [invalidWriteCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // Write method is not called for pairing request
    XCTAssertEqual(mockCBPeripheral.calledMethods, [])
    XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
  }

  func test_givenPeripheral_whenReactsCharacteristicDiscovery_andPaired_andContainsInvalidWriteCharacteristicsProperty_thenShouldNotInitializeWriteChannel() {
    peripheral.pairingState = .paired

    let invalidWriteCharacteristic = MockCBCharacteristic()
    // valid UUID but wrong property
    invalidWriteCharacteristic.uuid = CBUUID(data: Data([0xC0, 0x00]))
    invalidWriteCharacteristic.properties = .read

    let service = MockCBService()
    service.characteristics = [invalidWriteCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // Write method is not called for pairing request
    XCTAssertEqual(mockCBPeripheral.calledMethods, [])
    XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
  }

  func test_givenPeripheral_whenReactsCharacteristicDiscovery_andPaired_andContainsValidWriteCharacteristics_thenShouldInitializeWriteChannel() {
    peripheral.pairingState = .unpaired(dialogueShown: false)

    let validWriteCharacteristic = MockCBCharacteristic()
    // valid UUID and property
    validWriteCharacteristic.uuid = CBUUID(data: Data([0xC0, 0x00]))
    validWriteCharacteristic.properties = .write

    let service = MockCBService()
    service.characteristics = [validWriteCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // Write method is called for pairing request
    XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
    XCTAssertEqual(mockCBPeripheral.calledMethods, ["setNotifyValue(_:forCharacteristic:)",
                                                    "writeValue(_:forCharacteristic:type:)"])
  }

  // MARK: Read Characteristics
  func test_givenPeripheral_whenReactsCharacteristicDiscovery_andUnpaired_andContainsInvalidReadCharacteristicsUUID_thenShouldNotInitializeReadChannel() {
    peripheral.pairingState = .unpaired(dialogueShown: false)

    let invalidReadCharacteristic = MockCBCharacteristic()

    let service = MockCBService()
    service.characteristics = [invalidReadCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // readValue method should not be called due to unassigned read channel
    XCTAssertEqual(mockCBPeripheral.calledMethods, [])
    XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
  }

  func test_givenPeripheral_whenReactsCharacteristicDiscovery_andUnpaired_andContainsInvalidReadCharacteristicsProperty_thenShouldNotInitializeReadChannel() {
    peripheral.pairingState = .unpaired(dialogueShown: false)

    let invalidReadCharacteristic = MockCBCharacteristic()
    // valid UUID but invalid property
    invalidReadCharacteristic.uuid = CBUUID(string: "00000000-0000-0000-0000-000000000000")
    invalidReadCharacteristic.properties = .write

    let service = MockCBService()
    service.characteristics = [invalidReadCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // readValue method should not be called due to unassigned read channel
    XCTAssertEqual(mockCBPeripheral.calledMethods, [])
    XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
  }

  func test_givenPeripheral_whenReactsCharacteristicDiscovery_andUnpaired_andContainsValidReadCharacteristics_thenShouldInitializeReadChannel() {
    peripheral.pairingState = .unpaired(dialogueShown: false)
    let expectation = expectation(description: "read channel initialization failed")

    let validReadCharacteristic = MockCBCharacteristic()
    // valid UUID and property
    validReadCharacteristic.uuid = CBUUID(string: "00000000-0000-0000-0000-000000000000")
    validReadCharacteristic.properties = .read

    let service = MockCBService()
    service.characteristics = [validReadCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // readValue method should be called after successful readCharacteristic Initialization
    peripheral.read()
      .handleEvents(receiveSubscription: { _ in
        XCTAssertEqual(self.mockCBPeripheral.calledMethods, ["readValueForCharacteristic(_:)"])
        XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
        expectation.fulfill()
      })
      .sink(receiveCompletion: { _ in },
            receiveValue: { _ in })
      .store(in: &cancellables)

    waitForExpectations(timeout: 5)
  }

  // MARK: Pairing Confirmation
  func test_givenPeripheral_whenAllCharacteristicsValid_andPairingConfirmed_thenShouldPerformExtraReadAndWriteChannelOperations() {
    peripheral.pairingState = .unpaired(dialogueShown: true)

    let validReadCharacteristic = MockCBCharacteristic()
    // valid UUID and property
    validReadCharacteristic.uuid = CBUUID(string: "00000000-0000-0000-0000-000000000000")
    validReadCharacteristic.properties = .notify

    let validWriteCharacteristic = MockCBCharacteristic()
    // valid UUID and property
    validWriteCharacteristic.uuid = CBUUID(data: Data([0xC0, 0x00]))
    validWriteCharacteristic.properties = .write

    let service = MockCBService()
    service.characteristics = [validReadCharacteristic, validWriteCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // This action triggers pairingConfirmation
    peripheral.reactPairingValueWrite(error: nil)

    XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
    XCTAssertEqual(mockCBPeripheral.calledMethods, ["setNotifyValue(_:forCharacteristic:)",
                                                    "writeValue(_:forCharacteristic:type:)",
                                                    "writeValue(_:forCharacteristic:type:)",
                                                    "setNotifyValue(_:forCharacteristic:)"])
  }

  // MARK: Read Operation

  func test_givenPeripheral_whenManualReading_andFailedToRead_thenShouldPropagateErrorResult() {
    let expectation = expectation(description: "manual read with expected error has failed")

    // --------- Setting the valid Read Channel -----------
    peripheral.pairingState = .unpaired(dialogueShown: false)

    let validReadCharacteristic = MockCBCharacteristic()
    // valid UUID and property
    validReadCharacteristic.uuid = CBUUID(string: "00000000-0000-0000-0000-000000000000")
    validReadCharacteristic.properties = .read

    let service = MockCBService()
    service.characteristics = [validReadCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // ------- Triggering Manual Read to test result
    peripheral.read()
      .sink(receiveCompletion: {
        if case .failure = $0 {
          XCTFail("should not complete with failure")
        }
      },
            receiveValue: {
        if case let .failure(error as MockError) = $0,
           case .dummy = error {
          XCTAssertEqual(self.mockCBPeripheral.calledMethods, ["readValueForCharacteristic(_:)"])
          XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
          expectation.fulfill()
        } else {
          XCTFail("should not return successful value update")
        }
      })
      .store(in: &cancellables)

    // ------- Simulating value update
    peripheral.reactValueUpdate(characteristic: validReadCharacteristic, error: MockError.dummy)

    waitForExpectations(timeout: 5)
  }

  func test_givenPeripheral_whenManualReading_andSuccesfullyRead_thenShouldPropagateData() {
    let expectation = expectation(description: "manual read with expected error has failed")

    // --------- Setting the valid Read Channel -----------
    peripheral.pairingState = .unpaired(dialogueShown: false)

    let validReadCharacteristic = MockCBCharacteristic()
    // valid UUID and property
    validReadCharacteristic.uuid = CBUUID(string: "00000000-0000-0000-0000-000000000000")
    validReadCharacteristic.properties = .read
    validReadCharacteristic.value = Data(base64Encoded: "base64String")

    let service = MockCBService()
    service.characteristics = [validReadCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // ------- Triggering Manual Read to test result
    peripheral.read()
      .sink(receiveCompletion: {
        if case .failure = $0 {
          XCTFail("should not complete with failure")
        }
      },
            receiveValue: {
        if case let .success(data) = $0 {
          XCTAssertEqual(self.mockCBPeripheral.calledMethods, ["readValueForCharacteristic(_:)"])
          XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
          XCTAssertEqual(data, Data(base64Encoded: "base64String"))

          expectation.fulfill()
        } else {
          XCTFail("should not return errored value update")
        }
      })
      .store(in: &cancellables)

    // ------- Simulating value update
    peripheral.reactValueUpdate(characteristic: validReadCharacteristic, error: nil)

    waitForExpectations(timeout: 5)
  }

  func test_givenPeripheral_whenOpenReadStream_andSuccesfullyRead_thenShouldPropagateData() {
    let expectation = expectation(description: "Open read stream with valid response has failed")

    // --------- Setting the valid Read Channel -----------
    peripheral.pairingState = .unpaired(dialogueShown: false)

    let validReadCharacteristic = MockCBCharacteristic()
    // valid UUID and property
    validReadCharacteristic.uuid = CBUUID(string: "00000000-0000-0000-0000-000000000000")
    validReadCharacteristic.properties = .read
    validReadCharacteristic.value = Data(base64Encoded: "base64String")

    let service = MockCBService()
    service.characteristics = [validReadCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // ------- Observing open read stream to test result
    peripheral.readValueStream
      .sink(receiveCompletion: { _ in
        XCTFail("should not complete an open stream")
      },
            receiveValue: {
        if case let .success(data) = $0 {
          XCTAssertEqual(self.mockCBPeripheral.calledMethods, ["readValueForCharacteristic(_:)"])
          XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
          XCTAssertEqual(data, Data(base64Encoded: "base64String"))

          expectation.fulfill()
        } else {
          XCTFail("should not return errored value update")
        }
      })
      .store(in: &cancellables)

    // ------- Simulating value update
    peripheral.reactValueUpdate(characteristic: validReadCharacteristic, error: nil)

    waitForExpectations(timeout: 5)
  }

  // MARK: Write Operation

  func test_givenPeripheral_whenWriteWithoutResponse_thenShouldFireAndForget() {
    // --------- Setting the valid Write Channel -----------
    peripheral.pairingState = .unpaired(dialogueShown: false)

    let validWriteCharacteristic = MockCBCharacteristic()
    // valid UUID and property
    validWriteCharacteristic.uuid = CBUUID(data: Data([0xC0, 0x00]))
    validWriteCharacteristic.properties = .write

    let service = MockCBService()
    service.characteristics = [validWriteCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // ------- Triggering write without response to trigger test result
    peripheral.writeWithoutResponse(data: Data())
    peripheral.writeWithoutResponse(data: Data())
    peripheral.writeWithoutResponse(data: Data())

    XCTAssertEqual(self.mockCBPeripheral.calledMethods, ["setNotifyValue(_:forCharacteristic:)",
                                                         "writeValue(_:forCharacteristic:type:)",

                                                         // last three are the write operations above
                                                         "writeValue(_:forCharacteristic:type:)",
                                                         "writeValue(_:forCharacteristic:type:)",
                                                         "writeValue(_:forCharacteristic:type:)"])
    XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
  }

  func test_givenPeripheral_whenWriteWithResponse_andFailedToWrite_thenShouldPropagateErrorResult() {
    let expectation = expectation(description: "write with response with expected error has failed")

    // --------- Setting the valid Write Channel -----------
    peripheral.pairingState = .unpaired(dialogueShown: false)

    let validWriteCharacteristic = MockCBCharacteristic()
    // valid UUID and property
    validWriteCharacteristic.uuid = CBUUID(data: Data([0xC0, 0x00]))
    validWriteCharacteristic.properties = .write

    let service = MockCBService()
    service.characteristics = [validWriteCharacteristic]

    peripheral.reactCharacteristicsDiscovery(peripheral: mockCBPeripheral, service: service)

    // ------- Triggering Manual Read to test result
    peripheral.writeWithResponse(data: Data())
      .sink(receiveCompletion: {
        if case .finished = $0 {
          XCTFail("should not complete succesfully")
        } else if case let .failure(error as MockError) = $0,
                  case .dummy = error {
          XCTAssertEqual(self.mockCBPeripheral.calledMethods, ["setNotifyValue(_:forCharacteristic:)",
                                                               "writeValue(_:forCharacteristic:type:)",

                                                               // last one is the write operation above
                                                               "writeValue(_:forCharacteristic:type:)"])
          XCTAssertEqual(service.calledMethods, ["getCharacteristics()"])
          expectation.fulfill()
        }
      },
            receiveValue: { _ in
        XCTFail("should not return successful write response")
      })
      .store(in: &cancellables)

    // ------- Simulating write response
    peripheral.reactValueWrite(error: MockError.dummy)

    waitForExpectations(timeout: 5)
  }
}

private class MockPeripheralInitialCommunication: PeripheralInitialCommunicationProtocol {
  var servicesToDiscover: [CBUUID]? { nil }
  var characteristicsToDiscover: [CBUUID]? { nil }
  var readCharacteristicIdentifier: CBUUID { CBUUID(string: "00000000-0000-0000-0000-000000000000") }
  var writeCharacteristicIdentifier: CBUUID { CBUUID(data: Data([0xC0, 0x00])) }
  var readCharacteristicPollingInterval: DispatchQueue.SchedulerTimeType.Stride { 10 }
  var pairingRequestPayload: Data { Data() }
  var pairingConfirmationPayload: Data { Data() }
}

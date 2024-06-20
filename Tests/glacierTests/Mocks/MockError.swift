import Foundation

enum MockError: Error {
  case dummy
}

extension MockError {
  public var localizedDescription: String {
    return "dummyError"
  }
}

import Foundation

open class MockBase {
  open private(set) var calledMethods = [String]()
  
  public init() {}
  
  public func track(_ calledFunction: String = #function) {
    calledMethods.append(calledFunction)
  }
  
  public func resetCalledMethods() {
    calledMethods = []
  }
}

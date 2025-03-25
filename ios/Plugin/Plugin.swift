import Capacitor
import CocoaAsyncSocket
import Foundation

/// Please read the Capacitor iOS Plugin Development Guide
/// here: https://capacitor.ionicframework.com/docs/plugins/ios
@objc(UdpPlugin)
public class UdpPlugin: CAPPlugin {
  private var sockets: [Int: UdpSocket] = .init()
  private var nextSocketId: Int = 0

  override public func load() {
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name(rawValue: "capacitor-udp-forward"), object: nil, queue: nil,
      using: handleUdpForward)
  }

  private func handleUdpForward(_ notification: Notification) {
    let socketId: Int = notification.userInfo?["socketId"] as? Int ?? -1
    var address: String = notification.userInfo?["address"] as? String ?? ""
    let port = notification.userInfo?["port"] as? Int ?? -1
    let socket = sockets[socketId]
    let data = notification.userInfo?["data"] as? Data ?? Data()
    if socket == nil || port < 0 || address == "" || socket?.isBound == false {
      return
    }
    if !(socket?.broadcastEnabled ?? false)
      && address.trimmingCharacters(in: .whitespacesAndNewlines) == "255.255.255.255"
    {
      return
    }
    if address.contains(":") && (!address.contains("%")) {
      address = address + "%en0"
    }
    socket?.socket?.send(
      data, toHost: address, port: (port as NSNumber).uint16Value, withTimeout: -1, tag: -1)
  }

  @objc func create(_ call: CAPPluginCall) {
    let properties = call.getObject("properties")
    let socket = UdpSocket(plugin: self, id: nextSocketId, properties: properties)
    nextSocketId += 1
    sockets[socket.socketId] = socket
    try? socket.socket?.enableReusePort(true)

    call.resolve([
      "socketId": socket.socketId, "ipv4": socket.getIPv4Address(), "ipv6": socket.getIPv6Address(),
    ])
  }

  @objc func update(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let properties: [String: Any] = call.getObject("properties") ?? [String: Any]()
    let socket = sockets[socketId]
    if socket != nil {
      socket?.setProperties(properties)
      call.resolve()
    } else {
      call.reject("no socket found")
    }
  }

  @objc func setPaused(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let paused = call.getBool("paused")
    let socket = sockets[socketId]
    if socket != nil && paused != nil {
      socket?.setPaused(paused ?? false)
      call.resolve()
    } else {
      call.reject("setPaused failed")
    }
  }

  @objc func bind(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let socket = sockets[socketId]
    var address = call.getString("address")
    let port = call.getInt("port") ?? -1
    if socket == nil || port < 0 {
      call.reject("Invalid Argument")
      return
    }
    if address == "0.0.0.0" {
      address = nil
    }
    do {
      try socket?.socket?.bind(toPort: (port as NSNumber).uint16Value, interface: address)
      if !(socket?.paused ?? false) {
        try? socket?.socket?.beginReceiving()
      }
      socket?.isBound = true
      call.resolve()
    } catch {
      call.reject("bind Error")
    }
  }

  @objc func send(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    var address = call.getString("address") ?? ""
    let port = call.getInt("port") ?? -1
    let socket = sockets[socketId]
    let dataString = call.getString("buffer") ?? ""
    let data = Data(base64Encoded: dataString, options: .ignoreUnknownCharacters) ?? Data()
    if socket == nil || port < 0 || address == "" {
      call.reject("Invalid Argument")
      return
    }
    if socket?.isBound == false {
      call.reject("Not bound yet")
      return
    }
    if !(socket?.broadcastEnabled ?? false)
      && address.trimmingCharacters(in: .whitespacesAndNewlines) == "255.255.255.255"
    {
      call.reject("Broadcast not allowed")
      return
    }
    if address.contains(":") && (!address.contains("%")) {
      address = address + "%en0"
    }
    socket?.socket?.send(
      data, toHost: address, port: (port as NSNumber).uint16Value, withTimeout: -1, tag: -1)
    call.resolve(["bytesSent": data.count])
  }

  private func closeSocket(_ socket: UdpSocket?) {
    if !(socket?.socket?.isClosed() ?? true) {
      socket?.socket?.closeAfterSending()
    }
  }

  @objc func close(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let socket = sockets[socketId]
    if socket == nil {
      call.reject("Invalid Argument")
      return
    }
    closeSocket(socket)
    sockets[socketId] = nil
    call.resolve()
  }

  @objc func closeAllSockets(_ call: CAPPluginCall) {
    for (socketId, socket) in sockets {
      closeSocket(socket)
      sockets[socketId] = nil
    }
    call.resolve([
      "success": "close all"
    ])
  }

  @objc func getInfo(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let socket = sockets[socketId]
    if socket == nil {
      call.reject("Invalid Argument")
      return
    }
    call.resolve(socket?.getInfo() ?? [String: Any]())
  }

  @objc func getSockets(_ call: CAPPluginCall) {
    var socketsInfo = [Any]()
    for (_, socket) in sockets {
      socketsInfo.append(socket.getInfo())
    }
    call.resolve(["sockets": socketsInfo])
  }

  @objc func setBroadcast(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let socket = sockets[socketId]
    let enabled = call.getBool("enabled")
    if socket == nil || enabled == nil {
      call.reject("Invalid Argument")
      return
    }
    socket?.broadcastEnabled = enabled ?? false
    try? socket?.socket?.enableBroadcast(enabled ?? false)
    call.resolve()
  }

  @objc func joinGroup(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let address = call.getString("address")
    let socket = sockets[socketId]
    if socket == nil || address == nil {
      call.reject("Invalid Argument")
      return
    }
    if socket?.multicastGroup.contains(address ?? "") ?? false {
      call.reject("Already bound")
      return
    }
    do {
      try socket?.socket?.joinMulticastGroup(address ?? "", onInterface: "en0")
      socket?.multicastGroup.insert(address ?? "")
      call.resolve()
    } catch {
      call.reject("joinGroup error")
    }
  }

  @objc func leaveGroup(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let address = call.getString("address")
    let socket = sockets[socketId]
    if socket == nil || address == nil {
      call.reject("Invalid Argument")
      return
    }
    if !(socket?.multicastGroup.contains(address ?? "") ?? false) {
      call.resolve()
      return
    }
    do {
      try socket?.socket?.leaveMulticastGroup(address ?? "", onInterface: "en0")
      socket?.multicastGroup.remove(address ?? "")
      call.resolve()
    } catch {
      call.reject("leaveGroup error")
    }
  }

  @objc func setMulticastTimeToLive(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let ttl = call.getInt("ttl") ?? -1
    let socket = sockets[socketId]
    if socket == nil || ttl == -1 {
      call.reject("Invalid Argument")
      return
    }

    socket?.socket?.perform { () in
      if socket?.socket?.isIPv4() ?? false {
        var ttlCpy: CUnsignedChar = (ttl as NSNumber).uint8Value
        if setsockopt(
          socket?.socket?.socket4FD() ?? 0, IPPROTO_IP, IP_MULTICAST_TTL, &ttlCpy,
          UInt32(MemoryLayout.size(ofValue: ttlCpy))) < 0
        {
          call.reject("ttl ipv4 error")
        }
      }
      if socket?.socket?.isIPv6() ?? false {
        var ttlCpy = ttl
        if setsockopt(
          socket?.socket?.socket6FD() ?? 0, IPPROTO_IPV6, IP_MULTICAST_TTL, &ttlCpy,
          UInt32(MemoryLayout.size(ofValue: ttlCpy))) < 0
        {
          call.reject("ttl ipv6 error")
        }
      }
      call.resolve()
    }
  }

  @objc func setMulticastLoopbackMode(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let enabled = call.getBool("enabled")
    let socket = sockets[socketId]
    if socket == nil || enabled == nil {
      call.reject("Invalid Argument")
      return
    }
    socket?.socket?.perform { () in
      if socket?.socket?.isIPv4() ?? false {
        var loop: CUnsignedChar = (enabled ?? false) ? 1 : 0
        if setsockopt(
          socket?.socket?.socket4FD() ?? 0, IPPROTO_IP, IP_MULTICAST_LOOP, &loop,
          UInt32(MemoryLayout.size(ofValue: loop))) < 0
        {
          call.reject("loopback ipv4 error")
        }
      }
      if socket?.socket?.isIPv6() ?? false {
        var loop: Int32 = (enabled ?? false) ? 1 : 0
        if setsockopt(
          socket?.socket?.socket6FD() ?? 0, IPPROTO_IPV6, IP_MULTICAST_LOOP, &loop,
          UInt32(MemoryLayout.size(ofValue: loop))) < 0
        {
          call.reject("loopback ipv6 error")
        }
      }
      call.resolve()
    }
  }

  @objc func getJoinedGroups(_ call: CAPPluginCall) {
    let socketId: Int = call.getInt("socketId") ?? -1
    let socket = sockets[socketId]
    let groups = socket?.multicastGroup ?? Set<String>()
    var groupArray = [String]()
    for group in groups {
      groupArray.append(group)
    }
    call.resolve(["groups": groupArray])
  }

  private class UdpSocket: NSObject, GCDAsyncUdpSocketDelegate {
    private weak var plugin: UdpPlugin?
    let socketId: Int
    private var name: String
    private var bufferSize: NSNumber
    var paused: Bool
    var socket: GCDAsyncUdpSocket?
    var broadcastEnabled: Bool
    var isBound: Bool
    var multicastGroup: Set<String>

    init(plugin: UdpPlugin, id: Int, properties: [String: Any]?) {
      socketId = id
      self.plugin = plugin
      bufferSize = 4096
      name = ""
      paused = false
      multicastGroup = Set<String>()
      broadcastEnabled = false
      isBound = false
      super.init()
      socket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
      try? socket?.enableBroadcast(false)
      setProperties(properties ?? [String: Any]())
    }

    func getInfo() -> [String: Any] {
      let localAddress = socket?.localHost()
      let localPort = socket?.localPort()
      var socketInfo: [String: Any] = [
        "socketId": socketId, "name": name, "bufferSize": bufferSize, "paused": paused,
      ]
      if localAddress != nil {
        socketInfo["localAddress"] = localAddress
        socketInfo["localPort"] = localPort
      }
      return socketInfo
    }

    func setProperties(_ properties: [String: Any]) {
      name = properties["name"] as? String ?? name
      bufferSize = properties["bufferSize"] as? NSNumber ?? bufferSize
      if bufferSize.intValue > UINT16_MAX {
        socket?.setMaxSendBufferSize(UInt16.max)
      } else {
        socket?.setMaxSendBufferSize(bufferSize.uint16Value)
      }
      if socket?.isIPv4() ?? false {
        if bufferSize.intValue > UINT16_MAX {
          socket?.setMaxReceiveIPv4BufferSize(UInt16.max)
        } else {
          socket?.setMaxReceiveIPv4BufferSize(bufferSize.uint16Value)
        }
      }
      if socket?.isIPv6() ?? false {
        if bufferSize.intValue > UINT32_MAX {
          socket?.setMaxReceiveIPv6BufferSize(UInt32.max)
        } else {
          socket?.setMaxReceiveIPv6BufferSize(bufferSize.uint32Value)
        }
      }
    }

    func setPaused(_ paused: Bool) {
      self.paused = paused
      if paused {
        socket?.pauseReceiving()
      } else {
        try? socket?.beginReceiving()
      }
    }

    func udpSocket(
      _: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data,
      withFilterContext _: Any?
    ) {
      var ret = [String: Any]()
      ret["socketId"] = socketId
      ret["remoteAddress"] = GCDAsyncUdpSocket.host(fromAddress: address)
      ret["remotePort"] = GCDAsyncUdpSocket.port(fromAddress: address)
      ret["buffer"] = data.base64EncodedString()
      plugin?.notifyListeners("receive", data: ret, retainUntilConsumed: false)
    }

    func udpSocketDidClose(_: GCDAsyncUdpSocket, withError _: Error?) {
      plugin?.notifyListeners(
        "receiveError", data: ["socketId": socketId, "message": "socket closed"],
        retainUntilConsumed: false)
    }

    func getIPv6Address() -> String? {
      var address: String?

      // Get list of all interfaces on the local machine:
      var ifaddr: UnsafeMutablePointer<ifaddrs>?
      guard getifaddrs(&ifaddr) == 0 else { return nil }
      guard let firstAddr = ifaddr else { return nil }

      // For each interface ...
      for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ifptr.pointee

        // Check for IPv4 or IPv6 interface:
        let addrFamily = interface.ifa_addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET6) {
          // Check interface name:
          let name = String(cString: interface.ifa_name)
          if name == "en0" {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
              interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
              &hostname, socklen_t(hostname.count),
              nil, socklen_t(0), NI_NUMERICHOST)
            address = String(cString: hostname)
          }
        }
      }
      freeifaddrs(ifaddr)
      if address != nil {
        let index = address!.firstIndex(of: "%") ?? address?.endIndex
        let beginning = address![..<index!]
        let shortAddress = String(beginning)
        return shortAddress

      } else {
        return nil
      }

      // beginning is "Hello"

      // Convert the result to a String for long-term storage.
    }

    func getIPv4Address() -> String? {
      var address: String?
      // Get list of all interfaces on the local machine:
      var ifaddr: UnsafeMutablePointer<ifaddrs>?
      guard getifaddrs(&ifaddr) == 0 else { return nil }
      guard let firstAddr = ifaddr else { return nil }

      // For each interface ...
      for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ifptr.pointee

        // Check for IPv4 or IPv6 interface:
        let addrFamily = interface.ifa_addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) {
          // Check interface name:
          let name = String(cString: interface.ifa_name)
          if name == "en0" {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
              interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
              &hostname, socklen_t(hostname.count),
              nil, socklen_t(0), NI_NUMERICHOST)
            address = String(cString: hostname)
          }
        }
      }
      freeifaddrs(ifaddr)
      return address
    }
  }
}

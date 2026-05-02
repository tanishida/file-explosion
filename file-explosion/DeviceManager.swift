import Foundation
import Combine

struct SavedDevice: Identifiable, Codable {
    let id: UUID
    var name: String
    var deviceId: String
}

class DeviceManager: ObservableObject {
    static let shared = DeviceManager()
    
    @Published var myDeviceId: String {
        didSet {
            UserDefaults.standard.set(myDeviceId, forKey: "MyDeviceId")
        }
    }
    
    @Published var savedDevices: [SavedDevice] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(savedDevices) {
                UserDefaults.standard.set(data, forKey: "SavedDevices")
            }
        }
    }
    
    init() {
        if let existingId = UserDefaults.standard.string(forKey: "MyDeviceId") {
            self.myDeviceId = existingId
        } else {
            let newId = UUID().uuidString
            self.myDeviceId = newId
            UserDefaults.standard.set(newId, forKey: "MyDeviceId")
        }
        
        if let data = UserDefaults.standard.data(forKey: "SavedDevices"),
           let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data) {
            self.savedDevices = decoded
        }
    }
    
    func addSavedDevice(name: String, deviceId: String) {
        let newDevice = SavedDevice(id: UUID(), name: name, deviceId: deviceId)
        savedDevices.append(newDevice)
    }
    
    func removeSavedDevice(at offsets: IndexSet) {
        savedDevices.remove(atOffsets: offsets)
    }
}

@preconcurrency import Contacts
import Foundation

@MainActor
final class ContactsService: ObservableObject {
    static let shared = ContactsService()

    @Published private(set) var authorized = false
    @Published private(set) var names: [String: String] = [:]

    nonisolated static func key(_ s: String) -> String {
        if s.contains("@") { return s.lowercased() }
        return String(s.filter(\.isNumber).suffix(9))
    }

    func name(for handle: String) -> String? {
        guard !handle.isEmpty else { return nil }
        return names[Self.key(handle)]
    }

    func displayName(for handle: String) -> String {
        name(for: handle) ?? handle
    }

    func load() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else { return }
            DispatchQueue.global(qos: .utility).async {
                var map: [String: String] = [:]
                let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                            CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
                let req = CNContactFetchRequest(keysToFetch: keys)
                try? store.enumerateContacts(with: req) { c, _ in
                    var n = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
                    if n.isEmpty { n = c.organizationName }
                    guard !n.isEmpty else { return }
                    for p in c.phoneNumbers { map[ContactsService.key(p.value.stringValue)] = n }
                    for e in c.emailAddresses { map[ContactsService.key(e.value as String)] = n }
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        ContactsService.shared.authorized = true
                        ContactsService.shared.names = map
                    }
                }
            }
        }
    }
}

func initials(_ name: String) -> String {
    let parts = name.split(separator: " ").prefix(2)
    let s = parts.compactMap { $0.first.map(String.init) }.joined()
    return s.isEmpty ? "#" : s.uppercased()
}

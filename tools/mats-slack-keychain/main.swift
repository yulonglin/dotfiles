import Foundation
import Security

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("mats-slack-keychain: \(message)\n").utf8))
    exit(1)
}

private let arguments = CommandLine.arguments
guard arguments.count == 3, ["get", "set"].contains(arguments[1]) else {
    fail("usage: mats-slack-keychain get|set SERVICE")
}

private let action = arguments[1]
private let service = arguments[2]
private let account = NSUserName()
private let baseQuery: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: service,
    kSecAttrAccount: account,
    kSecAttrSynchronizable: false,
]

if action == "get" {
    var query = baseQuery
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let secret = result as? Data else {
        fail("could not read \(service) (status \(status))")
    }
    FileHandle.standardOutput.write(secret)
    exit(0)
}

var secret = FileHandle.standardInput.readDataToEndOfFile()
while secret.last == 0x0a || secret.last == 0x0d {
    secret.removeLast()
}
guard !secret.isEmpty else {
    fail("refusing to store an empty secret")
}

let updateStatus = SecItemUpdate(
    baseQuery as CFDictionary,
    [kSecValueData: secret] as CFDictionary
)
if updateStatus == errSecItemNotFound {
    var addQuery = baseQuery
    addQuery[kSecValueData] = secret
    addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
        fail("could not create \(service) (status \(addStatus))")
    }
} else if updateStatus != errSecSuccess {
    fail("could not update \(service) (status \(updateStatus))")
}

print("Stored \(service) in the local Login Keychain")

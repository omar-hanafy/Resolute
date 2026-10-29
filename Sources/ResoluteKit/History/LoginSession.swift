import Foundation

/// The login this process belongs to. The app and every command run in the same login
/// share it; a logout, or a restart, gives the next login another one.
public enum LoginSession {
    /// The Mac's boot session and the audit session of this login, such as
    /// "AE062952-A3E9-47CA-80BB-A00418E712FE/100027". Nil when either can't be read.
    public static var current: String? {
        guard let boot = bootSessionUUID() else { return nil }
        var info = auditinfo_addr()
        guard getaudit_addr(&info, Int32(MemoryLayout<auditinfo_addr>.size)) == 0 else { return nil }
        return "\(boot)/\(info.ai_asid)"
    }

    /// Audit session IDs start over after a restart, so the boot tells two logins apart that
    /// happen to share one.
    private static func bootSessionUUID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        let uuid = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return uuid.isEmpty ? nil : uuid
    }
}

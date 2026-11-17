import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService`.
///
/// ADR 0001 notes the risk: the app is ad-hoc signed, and registration may be
/// refused on that basis. Failures are surfaced rather than swallowed so the
/// settings toggle can show the truth instead of silently lying.
///
/// Lives in ShieldUI although it draws nothing: that is the only target both
/// executables share.
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the status actually achieved, which may differ from what was
    /// asked for — running outside an app bundle, for instance, cannot
    /// register at all.
    @discardableResult
    public static func set(_ enabled: Bool) -> Result<Bool, Error> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(isEnabled)
        } catch {
            return .failure(error)
        }
    }
}

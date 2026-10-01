import Foundation

public extension TrackerState {
    /// Creates persistence snapshots for all tracked windows.
    func snapshots() -> [TrackedWindowSnapshot] {
        windows.values.map { window in
            let closeSentAt: Date? = switch window.closeState {
            case let .sent(sentAt, _):
                sentAt
            case let .declined(declinedAt):
                declinedAt
            default:
                nil
            }

            return TrackedWindowSnapshot(
                key: window.key,
                bundleID: window.bundleID,
                processLaunchDate: apps[window.key.pid]?.launchDate,
                firstSeen: window.firstSeen,
                lastActive: window.lastActive,
                closeSentAt: closeSentAt
            )
        }
    }
}

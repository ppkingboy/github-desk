import AppKit

enum AppTheme {
    static let accent = NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.45, alpha: 1)
    static let warning = NSColor(calibratedRed: 0.92, green: 0.55, blue: 0.16, alpha: 1)
    static let danger = NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.25, alpha: 1)
    static let info = NSColor(calibratedRed: 0.19, green: 0.48, blue: 0.82, alpha: 1)
}

extension RepositoryStatus {
    var color: NSColor {
        switch self {
        case .localOnly: return AppTheme.info
        case .unmatchedRemote: return AppTheme.warning
        case .needsSync: return AppTheme.warning
        case .synced: return AppTheme.accent
        }
    }

    var systemImage: String {
        switch self {
        case .localOnly: return "folder.badge.plus"
        case .unmatchedRemote: return "link.badge.plus"
        case .needsSync: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle"
        }
    }
}

extension LocalRepository {
    var syncSummary: String {
        if isDirty {
            return "\(changedFileCount) 个文件待提交"
        }
        if ahead > 0 && behind > 0 {
            return "领先 \(ahead)，落后 \(behind)"
        }
        if ahead > 0 {
            return "领先 \(ahead) 个提交"
        }
        if behind > 0 {
            return "落后 \(behind) 个提交"
        }
        if !hasUpstream {
            return "尚未关联远程分支"
        }
        return "本地与远程一致"
    }

    var shortLastCommitDate: String {
        guard let lastCommitDate else { return "暂无提交" }
        return String(lastCommitDate.prefix(10))
    }
}

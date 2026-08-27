import SwiftUI
import TapgoCore

/// Inline row for an approval request.
///
/// When the harness raises an approval (`approvalPolicy` != `never`),
/// this row is rendered with interactive 批准 / 拒绝 buttons. The
/// buttons call `SessionStore.respondToApproval`, which forwards the
/// decision to the harness and updates the in-chat item. When no
/// approval is pending (e.g. auto-approve, or an already-decided item
/// from the trajectory), it renders a status badge instead.
struct ApprovalRow: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    let request: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.shield")
                Text(approvalTitle)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .bold()
                Spacer()
                statusPill
            }
            Text(request.reason)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            switch request.payload {
            case .command(let ce):
                Text(L10n.commandDisplay(ce.command))
                    .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                    .padding(6)
                    .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 4))
            case .fileChange(let fc):
                Text(L10n.fileChangeDisplay(fc.kind.rawValue, fc.path))
                    .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
            case .toolCall(let tc):
                Text("\(tc.name)(\(tc.arguments))")
                    .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                    .lineLimit(2)
            }
            if isPending {
                HStack(spacing: 8) {
                    Button {
                        store.respondToApproval(request, approve: true)
                    } label: {
                        Label(L10n.approve, systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        store.respondToApproval(request, approve: false)
                    } label: {
                        Label(L10n.deny, systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
            .shadow(color: DSHTheme.cardShadow, radius: 3, x: 0, y: 1)
    }

    private var isPending: Bool {
        store.pendingApprovals[request.id] != nil
    }

    @ViewBuilder
    private var statusPill: some View {
        if isPending {
            Text(L10n.approvalPending)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.18), in: Capsule())
                .foregroundStyle(.orange)
        } else {
            let (label, color) = decisionBadge
            Text(label)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.18), in: Capsule())
                .foregroundStyle(color)
        }
    }

    private var decisionBadge: (String, Color) {
        switch request.decision {
        case .approved:          return (L10n.approvalApproved, .green)
        case .denied:            return (L10n.approvalDenied, .red)
        case .approvedForSession: return (L10n.approvalApprovedForSession, .green)
        case .cancelled:         return (L10n.approvalCancelled, .secondary)
        case nil:                return (L10n.approvalAutoApproved, .green)
        }
    }

    private var approvalTitle: String {
        switch request.kind {
        case .commandExecution: return L10n.approvalCommandRequested
        case .fileChange: return L10n.approvalFileChangeRequested
        case .toolCall: return L10n.approvalToolCallRequested
        }
    }
}

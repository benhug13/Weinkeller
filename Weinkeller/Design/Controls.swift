import SwiftUI

/// Der eine auffällige Knopf einer Seite. Alles andere bleibt ruhig.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Theme.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.wineLit, Theme.wine],
                                         startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
            .shadow(color: Theme.wine.opacity(0.45), radius: 14, y: 6)
            .opacity(enabled ? 1 : 0.4)
        }
        .disabled(!enabled)
    }
}

/// Zurückhaltender Knopf aus Glas — für alles, was nicht die Hauptsache ist.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
                }
                Text(title).font(.system(size: 15))
            }
            .foregroundStyle(role == .destructive ? Color(hex: 0xD1687E) : Theme.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .glassPanel(radius: 16, highlight: 0.22, shadow: false)
        }
    }
}

/// Eine Zeile „Bezeichnung … Wert" in einer Glaskarte.
struct SpecRow: View {
    let key: String
    let value: String
    var accent: Color?
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(accent ?? Theme.cream)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(.white.opacity(0.07)).frame(height: 0.7)
                    .padding(.leading, 16)
            }
        }
    }
}

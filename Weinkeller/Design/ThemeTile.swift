import SwiftUI

/// Ein Designvorschlag als kleines Muster: Grund, eine Karte, zwei Schriftzeilen und der
/// Weinrot-Knopf — so sieht man die Wirkung, bevor man umschaltet.
///
/// Die Farben kommen hier **fest** aus dem Farbsatz, nicht über `Theme`: das Muster für
/// „Hell" muss auch dann hell sein, wenn die App gerade schwarz ist.
struct ThemeTile: View {
    let option: Appearance
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            preview
                .frame(height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Theme.wineLit : Theme.edge(0.14),
                                      lineWidth: selected ? 2 : 0.8)
                }

            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.cream)
                    Text(option.caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.wineLit)
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var preview: some View {
        switch option {
        case .schwarz: Sample(palette: .schwarz)
        case .keller:  Sample(palette: .keller)
        case .hell:    Sample(palette: .hell)
        case .system:
            // Halb Tag, halb Nacht — genau das macht „Automatisch".
            HStack(spacing: 0) {
                Sample(palette: .hell).frame(maxWidth: .infinity, alignment: .leading).clipped()
                Sample(palette: .schwarz).frame(maxWidth: .infinity, alignment: .trailing).clipped()
            }
        }
    }

    private struct Sample: View {
        let palette: Palette

        var body: some View {
            ZStack(alignment: .topLeading) {
                Color(hex: palette.bg)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(Color(hex: palette.cream)).frame(width: 46, height: 5)
                    Capsule().fill(Color(hex: palette.muted)).frame(width: 30, height: 4)
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(Color(hex: palette.wine))
                        .frame(width: 38, height: 11)
                }
                .padding(9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: palette.panel))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(palette.isDark ? Color.white.opacity(0.10)
                                                             : Color.black.opacity(0.08),
                                              lineWidth: 0.7)
                        }
                }
                .padding(9)
            }
        }
    }
}

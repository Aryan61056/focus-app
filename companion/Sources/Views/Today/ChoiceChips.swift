import SwiftUI

struct ChoiceChips<Value: Hashable>: View {
    let options: [(label: LocalizedStringKey, value: Value)]
    @Binding var selection: Value
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i], selected = o.value == selection
                Button { withAnimation(Motion.land) { selection = o.value } } label: {
                    Text(o.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Palette.onAccent : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected { Capsule().fill(Palette.accent).matchedGeometryEffect(id: "chip", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScale(scale: 0.95))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .selectionFeedback(selection)
    }
}

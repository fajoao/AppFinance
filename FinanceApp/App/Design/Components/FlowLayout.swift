import SwiftUI

/// Quebra os itens em linhas (chips que não cabem passam para a linha de baixo).
struct FlowLayout: Layout {
    var spacing: CGFloat = Space.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

#Preview("Fluxo de chips") {
    FlowLayout {
        ForEach(["Moradia", "Mercado", "Transporte", "Lazer", "Saúde", "Educação", "Outros", "Uma categoria muito longa mesmo"], id: \.self) { name in
            Chip(title: name) {}
        }
    }
    .padding()
    .background(Color.canvas)
}

#Preview("Fluxo de chips, vazio e escuro") {
    VStack {
        FlowLayout { EmptyView() }
        FlowLayout { Chip(title: "Único", isSelected: true) {} }
    }
    .padding()
    .background(Color.canvas)
    .preferredColorScheme(.dark)
}

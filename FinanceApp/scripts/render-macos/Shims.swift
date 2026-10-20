import SwiftUI
// Somente para o harness de renderização offscreen (ImageRenderer não desenha ScrollView/List).
struct ScrollView<Content: View>: View {
    let content: Content
    init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(spacing: 0) { content }.frame(maxWidth: .infinity, alignment: .topLeading) }
}
struct List<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(spacing: 0) { content } }
}

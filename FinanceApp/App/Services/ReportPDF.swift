import SwiftUI

/// Exportação de relatórios em PDF, desenhando páginas SwiftUI com `ImageRenderer` em um contexto PDF do
/// CoreGraphics (A4, 595 x 842 pt). Funciona no iOS 16+ e fica no app porque depende de SwiftUI.
@MainActor
enum ReportPDFExporter {
    static let pageSize = CGSize(width: 595, height: 842)
    static let linesPerPage = 36

    /// nil se o contexto PDF não pôde ser criado.
    static func makePDF(_ document: ReportDocument) -> Data? {
        let pages = document.pages(linesPerPage: linesPerPage)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle as String: document.title] as CFDictionary)
        else { return nil }
        for (index, lines) in pages.enumerated() {
            let page = ReportPageView(lines: lines, pageNumber: index + 1, pageCount: pages.count)
                .frame(width: pageSize.width, height: pageSize.height)
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { size, draw in
                ctx.beginPDFPage(nil)
                ctx.translateBy(x: (pageSize.width - size.width) / 2, y: (pageSize.height - size.height) / 2)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return data as Data
    }

    static func write(_ document: ReportDocument, baseName: String, today: Date,
                      directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        guard let data = makePDF(document) else { throw CocoaError(.fileWriteUnknown) }
        let c = FinanceCalendar.components(today)
        let url = directory.appendingPathComponent(String(format: "%@-%04d-%02d-%02d.pdf", baseName, c.year, c.month, c.day))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Uma página do PDF. Cores fixas (preto sobre branco): o PDF é impresso/compartilhado, não segue o tema do app.
struct ReportPageView: View {
    let lines: [ReportLine]
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line.kind {
                case .title:
                    Text(line.left).font(.system(size: 20, weight: .bold)).foregroundStyle(.black)
                case .subtitle:
                    HStack { Text(line.left); Spacer(); Text(line.right) }
                        .font(.system(size: 10)).foregroundStyle(.gray).padding(.bottom, 8)
                case .heading:
                    Text(line.left).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black).padding(.top, 10)
                case .row:
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.left).lineLimit(2)
                        Spacer(minLength: 12)
                        Text(line.right).monospacedDigit()
                    }
                    .font(.system(size: 11)).foregroundStyle(.black)
                case .note:
                    Text(line.left).font(.system(size: 9)).foregroundStyle(.gray).padding(.top, 12)
                }
            }
            Spacer(minLength: 0)
            Text("Página \(pageNumber) de \(pageCount)").font(.system(size: 9)).foregroundStyle(.gray)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}

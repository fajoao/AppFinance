import Foundation

// Gera os vetores dourados a partir do Core Swift real. Uso: golden-gen <diretório de saída>
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
foundationCases()
ledgerCases()
cardCases()
planningCases()
moreCases()
ioCases()
syncCases()
try writeCases(to: outDir)

import SwiftUI

/// Seletor global de período: ‹ Outubro de 2026 › + chip "Voltar para hoje" fora do mês atual.
/// Toque no título abre a sheet com grade de meses (3x4), ano e botão "Hoje". O estado é `AppStore.viewedMonth`.
/// Ids: period.picker, period.prev, period.next, period.backToToday (chip), period.sheet, period.today, period.month.N, period.year.
struct MonthPicker: View {
    @Environment(AppStore.self) private var store
    @State private var showsSheet = false
    /// false quando o seletor fica dentro de uma rolagem que já tem margem horizontal.
    var inset = true

    var body: some View {
        let month = store.viewedMonth
        VStack(spacing: Space.xs) {
            HStack(spacing: 0) {
                Button { store.stepViewedMonth(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: Space.minTouchTarget, height: Space.minTouchTarget).contentShape(Rectangle())
                }
                .disabled(!PeriodSelection.canMove(month, by: -1))
                .accessibilityLabel("Mês anterior")
                .accessibilityIdentifier("period.prev")

                Button { showsSheet = true } label: {
                    HStack(spacing: Space.xs) {
                        Text(PeriodSelection.title(month)).font(.headline).foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.center)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Color.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: Space.minTouchTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PeriodSelection.accessibilityLabel(month))
                .accessibilityIdentifier("period.picker")

                Button { store.stepViewedMonth(by: 1) } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                        .frame(width: Space.minTouchTarget, height: Space.minTouchTarget).contentShape(Rectangle())
                }
                .disabled(!PeriodSelection.canMove(month, by: 1))
                .accessibilityLabel("Próximo mês")
                .accessibilityIdentifier("period.next")
            }
            .foregroundStyle(Color.brandPrimary)
            if !store.isViewingCurrentMonth {
                Chip(title: "Voltar para hoje", systemImage: "arrow.uturn.backward", isSelected: true) { store.resetViewedMonth() }
                    .accessibilityLabel("Voltar para hoje, \(PeriodSelection.title(store.currentMonth))")
                    .accessibilityIdentifier("period.backToToday")
            }
        }
        .padding(.horizontal, inset ? Space.screenMargin : 0)
        .padding(.top, Space.xs)
        .sheet(isPresented: $showsSheet) {
            MonthPickerSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Radius.sheet)
        }
    }
}

/// Sheet do seletor: ano (setas) + grade 3x4 de meses. Tocar num mês aplica e fecha; "Hoje" volta ao mês atual.
struct MonthPickerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var year = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: 3)

    var body: some View {
        let viewed = store.viewedMonth
        VStack(spacing: Space.xl) {
            HStack {
                Text("Selecionar mês").font(.headline).foregroundStyle(Color.textPrimary)
                Spacer()
                Button("Hoje") { store.resetViewedMonth(); dismiss() }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityHint("Volta para \(PeriodSelection.title(store.currentMonth))")
                    .accessibilityIdentifier("period.today")
            }
            HStack {
                Button { year -= 1 } label: { Image(systemName: "chevron.left").frame(width: Space.minTouchTarget, height: Space.minTouchTarget) }
                    .disabled(!PeriodSelection.canSelectYear(year - 1))
                    .accessibilityLabel("Ano anterior").accessibilityIdentifier("period.year.prev")
                Spacer()
                Text(verbatim: "\(year)").font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(Color.textPrimary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String("Ano ") + String(year))
                    .accessibilityValue(String(year))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: if PeriodSelection.canSelectYear(year + 1) { year += 1 }
                        case .decrement: if PeriodSelection.canSelectYear(year - 1) { year -= 1 }
                        @unknown default: break
                        }
                    }
                    .accessibilityIdentifier("period.year")
                Spacer()
                Button { year += 1 } label: { Image(systemName: "chevron.right").frame(width: Space.minTouchTarget, height: Space.minTouchTarget) }
                    .disabled(!PeriodSelection.canSelectYear(year + 1))
                    .accessibilityLabel("Próximo ano").accessibilityIdentifier("period.year.next")
            }
            .foregroundStyle(Color.brandPrimary)
            ScrollView {
                LazyVGrid(columns: columns, spacing: Space.sm) {
                    ForEach(1...12, id: \.self) { m in
                        let selected = year == viewed.year && m == viewed.month
                        let isNow = year == store.currentMonth.year && m == store.currentMonth.month
                        Button {
                            store.setViewedMonth(PeriodSelection.select(month: m, year: year))
                            dismiss()
                        } label: {
                            Text(PeriodSelection.gridLabel(month: m)).font(.body.weight(.medium))
                                .foregroundStyle(selected ? Color.brandPrimary : Color.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(selected ? Color.brandSoft : Color.sunken, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(selected ? Color.brandPrimary : (isNow ? Color.border : Color.clear), lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(PeriodSelection.monthAccessibilityLabel(month: m, year: year) + (isNow ? ", mês atual" : ""))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("period.month.\(m)")
                    }
                }
            }
        }
        .padding(Space.screenMargin)
        .background(Color.canvas)
        .onAppear { year = store.viewedMonth.year }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("period.sheet")
    }
}

#Preview("Seletor de período") {
    VStack { MonthPicker(); Spacer() }.previewing(PreviewData.demo).environment(Router())
}

#Preview("Sheet do seletor, escuro") {
    MonthPickerSheet().previewing(PreviewData.demo, dark: true)
}

import SwiftUI

extension MemberRole {
    var title: String {
        switch self {
        case .admin: return "Administrador"
        case .member: return "Membro"
        case .dependent: return "Dependente"
        }
    }
    var symbol: String {
        switch self {
        case .admin: return "star.circle"
        case .member: return "person.circle"
        case .dependent: return "figure.and.child.holdinghands"
        }
    }
}

enum MemberTarget: Identifiable, Hashable {
    case new, detail(UUID)
    var id: String { switch self { case .new: return "new"; case .detail(let id): return id.uuidString } }
}

/// family.home: grupo familiar local com perfis, papéis, visão família × individual e atalhos.
struct FamilyView: View {
    @Environment(AppStore.self) private var store
    @State private var target: MemberTarget?
    @State private var householdName = ""
    @State private var adminName = ""
    @State private var showErrors = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if store.hasHousehold { content } else { setup }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnTap()
        .background(Color.canvas)
        .navigationTitle(store.household?.name ?? "Família")
        .inlineNavigationTitle()
        .sheet(item: $target) { t in
            switch t {
            case .new: MemberFormSheet().presentationDetents([.medium, .large]).presentationCornerRadius(Radius.sheet)
            case .detail(let id): MemberDetailSheet(memberId: id).presentationDetents([.medium, .large]).presentationCornerRadius(Radius.sheet)
            }
        }
        .accessibilityIdentifier("family.home")
    }

    // MARK: Criar grupo

    private var setup: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            EmptyState(symbol: "person.2", title: "Crie o grupo familiar",
                       message: "Tudo fica neste aparelho. Cada pessoa tem um perfil, com contas e categorias privadas ou compartilhadas.")
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            LabeledField(label: "Nome da família", text: $householdName, prompt: "Ex.: Família Silva",
                         error: showErrors && householdName.trimmingCharacters(in: .whitespaces).isEmpty ? "Dê um nome para a família." : nil,
                         identifier: "family.setup.name")
            LabeledField(label: "Seu nome", text: $adminName, prompt: "Ex.: Ana",
                         error: showErrors && adminName.trimmingCharacters(in: .whitespaces).isEmpty ? "Informe seu nome." : nil,
                         identifier: "family.setup.admin")
            Button("Criar grupo familiar") {
                guard !householdName.trimmingCharacters(in: .whitespaces).isEmpty, !adminName.trimmingCharacters(in: .whitespaces).isEmpty
                else { showErrors = true; return }
                if store.attempt({ try store.createHousehold(name: householdName, adminName: adminName) }) { store.show("Grupo familiar criado.") }
            }
            .buttonStyle(.primary).accessibilityIdentifier("family.setup.create")
        }
    }

    // MARK: Grupo criado

    @ViewBuilder
    private var content: some View {
        profileAndScope
        members
        shortcuts
        accountsPrivacy
    }

    private var profileAndScope: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let me = store.activeMember {
                HStack(spacing: Space.md) {
                    Image(systemName: me.role.symbol).font(.title2).foregroundStyle(Color.brandPrimary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Perfil ativo").font(.footnote).foregroundStyle(Color.textSecondary)
                        Text("\(me.name), \(me.role.title.lowercased())").font(.headline).foregroundStyle(Color.textPrimary)
                    }
                    Spacer()
                    Menu {
                        ForEach(store.members) { m in
                            Button { store.setActiveMember(m.id) } label: { Label(m.name, systemImage: m.id == me.id ? "checkmark" : m.role.symbol) }
                        }
                    } label: { Text("Trocar").font(.subheadline.weight(.semibold)) }
                        .accessibilityIdentifier("family.switchProfile")
                }
                .padding(Space.lg)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("family.activeProfile")
            }
            if store.canViewFamily {
                Picker("Visão", selection: Binding(get: { store.preferences.viewScope }, set: { store.setViewScope($0) })) {
                    ForEach(ViewScopePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).accessibilityIdentifier("family.scope")
                Text(store.isFamilyView ? "Visão da família: soma só contas e categorias compartilhadas. O que é privado não aparece."
                                        : "Visão individual: lançamentos e contas de \(store.activeMember?.name ?? "você"), incluindo as privadas.")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
            } else {
                Label("Dependentes enxergam apenas a própria visão.", systemImage: "lock").font(.footnote).foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var members: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Pessoas")
            ListGroup {
                SeparatedRows(items: store.members, inset: 56) { m in
                    Button { target = .detail(m.id) } label: {
                        ListRow(title: m.name, subtitle: memberSubtitle(m)) {
                            Image(systemName: m.role.symbol).foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                        } trailing: {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(store.money(store.memberSpent(m))).font(.body).foregroundStyle(Color.textPrimary).monospacedDigit()
                                Text("no mês").font(.footnote).foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("family.member.\(m.name)")
                }
            }
            if store.activeMember.map({ FamilyEngine.can($0.role, .manageMembers) }) == true {
                Button { target = .new } label: { Label("Adicionar pessoa", systemImage: "person.badge.plus") }
                    .buttonStyle(.secondary).accessibilityIdentifier("family.addMember")
            }
        }
    }

    private func memberSubtitle(_ m: FamilyMember) -> String {
        var s = m.role.title
        if let limit = m.monthlySpendingLimit { s += ", limite \(store.money(limit)) por mês" }
        return s
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Ferramentas")
            ListGroup {
                link(SettlementView(), "Dividir despesas e acertar contas", "Quem deve a quem, com o mínimo de transferências", "arrow.left.arrow.right", "family.link.settle")
                RowSeparator(inset: 56)
                link(AllowanceView(), "Mesada", "Transferência automática para a conta do dependente", "calendar.badge.clock", "family.link.allowance")
                RowSeparator(inset: 56)
                link(ApprovalsView(), "Aprovações", store.pendingApprovals.isEmpty ? "Gastos acima do limite dos dependentes" : "\(store.pendingApprovals.count) aguardando", "checkmark.seal", "family.link.approvals")
                RowSeparator(inset: 56)
                link(KidsGoalsView(), "Metas dos filhos", "Metas e aportes de cada dependente", "target", "family.link.kidsGoals")
            }
        }
    }

    private func link<D: View>(_ destination: D, _ title: String, _ subtitle: String, _ symbol: String, _ id: String) -> some View {
        NavigationLink { destination } label: {
            ListRow(title: title, subtitle: subtitle) {
                Image(systemName: symbol).foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
            } trailing: {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary).accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private var accountsPrivacy: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Contas: privadas e compartilhadas")
            ListGroup {
                SeparatedRows(items: store.accounts.filter { !$0.isArchived && ($0.visibility == .shared || $0.ownerId == store.viewerId) }, inset: 56) { a in
                    ListRow(title: a.name, subtitle: "\(a.visibility.displayName)" + (a.ownerId.flatMap { store.lookup.members[$0]?.name }.map { ", de \($0)" } ?? "")) {
                        Image(systemName: a.visibility == .personal ? "lock" : "person.2").foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                    } trailing: {
                        if a.ownerId == nil || a.ownerId == store.viewerId {
                            Menu {
                                Button(a.visibility == .shared ? "Tornar privada" : "Tornar compartilhada") {
                                    store.attempt { try store.setAccountVisibility(id: a.id, a.visibility == .shared ? .personal : .shared) }
                                }
                            } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Color.brandPrimary).frame(width: 44, height: 44) }
                                .accessibilityLabel("Visibilidade de \(a.name)")
                                .accessibilityIdentifier("family.account.menu.\(a.name)")
                        }
                    }
                }
            }
            Text("Contas privadas só aparecem para o dono, nem o administrador as vê.")
                .font(.footnote).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
        }
    }
}

/// family.member.form: nova pessoa.
struct MemberFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role: MemberRole = .member
    @State private var limitText = ""
    @State private var showErrors = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    LabeledField(label: "Nome", text: $name, prompt: "Ex.: Bruno",
                                 error: showErrors && name.trimmingCharacters(in: .whitespaces).isEmpty ? "Informe o nome." : nil, identifier: "family.member.form.name")
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Papel")
                        FlowLayout {
                            ForEach(MemberRole.allCases, id: \.self) { r in
                                Chip(title: r.title, systemImage: r.symbol, isSelected: role == r) { role = r }
                                    .accessibilityIdentifier("family.member.form.role.\(r.rawValue)")
                            }
                        }
                        Text(roleHelp).font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    if role == .dependent {
                        LabeledField(label: "Limite de gastos por mês (opcional)", text: $limitText, prompt: "0,00", isDecimal: true,
                                     identifier: "family.member.form.limit")
                    }
                    Button("Adicionar") { save() }.buttonStyle(.primary).accessibilityIdentifier("family.member.form.save")
                }
                .padding(Space.screenMargin)
            }
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle("Nova pessoa")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .toastHost()
        .accessibilityIdentifier("family.member.form")
    }

    private var roleHelp: String {
        switch role {
        case .admin: return "Gerencia pessoas, mesadas e aprovações."
        case .member: return "Lança, divide despesas e aprova gastos de dependentes."
        case .dependent: return "Só lança os próprios gastos. Acima do limite mensal, o gasto espera aprovação."
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { showErrors = true; return }
        let limit = limitText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Money.parse(limitText, style: .comma)
        if store.attempt({ _ = try store.addMember(name: name, role: role, monthlyLimit: role == .dependent ? limit : nil) }) {
            store.show("Pessoa adicionada."); dismiss()
        }
    }
}

/// Detalhe da pessoa: usar este perfil, mudar papel, limite e remover.
struct MemberDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let memberId: UUID
    @State private var limitText = ""
    @State private var confirmRemove = false

    private var canManage: Bool { store.activeMember.map { FamilyEngine.can($0.role, .manageMembers) } ?? false }

    var body: some View {
        NavigationStack {
            Group {
                if let m = store.members.first(where: { $0.id == memberId }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.xl) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(m.name).font(.title2.weight(.semibold)).foregroundStyle(Color.textPrimary)
                                Text(m.role.title).font(.subheadline).foregroundStyle(Color.textSecondary)
                            }
                            ListGroup {
                                ListRow(title: "Gasto no mês") { EmptyView() } trailing: { Text(store.money(store.memberSpent(m))).monospacedDigit() }
                                if let limit = m.monthlySpendingLimit {
                                    RowSeparator()
                                    ListRow(title: "Limite mensal") { EmptyView() } trailing: { Text(store.money(limit)).monospacedDigit() }
                                }
                            }
                            if store.activeMember?.id != m.id {
                                Button("Usar este perfil") { store.setActiveMember(m.id); dismiss() }
                                    .buttonStyle(.primary).accessibilityIdentifier("family.member.detail.use")
                            }
                            if canManage {
                                VStack(alignment: .leading, spacing: Space.sm) {
                                    SectionHeader("Papel")
                                    FlowLayout {
                                        ForEach(MemberRole.allCases, id: \.self) { r in
                                            Chip(title: r.title, isSelected: m.role == r) {
                                                store.attempt { try store.changeRole(memberId: m.id, to: r) }
                                            }
                                            .accessibilityIdentifier("family.member.detail.role.\(r.rawValue)")
                                        }
                                    }
                                }
                                if m.role == .dependent {
                                    VStack(alignment: .leading, spacing: Space.sm) {
                                        LabeledField(label: "Limite de gastos por mês", text: $limitText, prompt: "Sem limite", isDecimal: true,
                                                     identifier: "family.member.detail.limit")
                                        Button("Salvar limite") {
                                            let t = limitText.trimmingCharacters(in: .whitespaces)
                                            let value = t.isEmpty ? nil : Money.parse(t, style: .comma)
                                            if store.attempt({ try store.setSpendingLimit(memberId: m.id, limit: value) }) { store.show("Limite salvo.") }
                                        }
                                        .buttonStyle(.secondary).accessibilityIdentifier("family.member.detail.saveLimit")
                                    }
                                }
                                Button("Remover da família") { confirmRemove = true }
                                    .buttonStyle(LinkButtonStyle(tone: .danger)).frame(maxWidth: .infinity)
                                    .accessibilityIdentifier("family.member.detail.remove")
                            }
                        }
                        .padding(Space.screenMargin)
                    }
                    .dismissesKeyboardOnTap()
                    .onAppear { limitText = m.monthlySpendingLimit.map { MoneyDisplay.number($0) } ?? "" }
                } else {
                    EmptyState(symbol: "questionmark.circle", title: "Pessoa não encontrada")
                }
            }
            .background(Color.canvas)
            .navigationTitle("Pessoa")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .confirmationDialog("Remover esta pessoa?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remover", role: .destructive) { if store.attempt({ try store.removeMember(id: memberId) }) { dismiss() } }
            } message: { Text("Os lançamentos dela continuam, sem atribuição.") }
        }
        .toastHost()
        .accessibilityIdentifier("family.member.detail")
    }
}

/// Metas e aportes dos dependentes.
struct KidsGoalsView: View {
    @Environment(AppStore.self) private var store
    @State private var contributing: Goal?
    @State private var newGoalFor: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if store.dependents.isEmpty {
                    EmptyState(symbol: "figure.and.child.holdinghands", title: "Nenhum dependente",
                               message: "Adicione uma criança ou adolescente como dependente para criar metas para ela.")
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                }
                ForEach(store.dependents) { kid in
                    KidGoalsSection(kid: kid, onAdd: { newGoalFor = kid.id }, onContribute: { contributing = $0 })
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Metas dos filhos")
        .inlineNavigationTitle()
        .sheet(item: $contributing) { goal in
            ContributeSheet(goalId: goal.id).presentationDetents([.medium, .large]).presentationCornerRadius(Radius.sheet)
        }
        .sheet(item: Binding(get: { newGoalFor.map { GoalOwner(id: $0) } }, set: { newGoalFor = $0?.id })) { owner in
            GoalEditSheet(goalId: nil, memberId: owner.id).presentationDetents([.medium, .large]).presentationCornerRadius(Radius.sheet)
        }
        .accessibilityIdentifier("family.kidsGoals")
    }
}

/// Metas de um dependente.
struct KidGoalsSection: View {
    @Environment(AppStore.self) private var store
    let kid: FamilyMember
    let onAdd: () -> Void
    let onContribute: (Goal) -> Void

    var body: some View {
        let goals = store.goals(for: kid.id)
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: kid.name) {
                Button("Nova meta", action: onAdd).font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("family.kidsGoals.add.\(kid.name)")
            }
            if goals.isEmpty {
                Text("Sem metas ainda.").font(.subheadline).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
            }
            ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                GoalBlock(goal: goal, index: index) { onContribute(goal) }
            }
        }
    }
}

struct GoalOwner: Identifiable { let id: UUID }

#Preview("Família") {
    NavigationStack { FamilyView() }.previewing(PreviewData.family)
}

#Preview("Família, criar grupo") {
    NavigationStack { FamilyView() }.previewing(PreviewData.demo)
}

#Preview("Família, escuro, texto grande") {
    NavigationStack { FamilyView() }.previewing(PreviewData.family, dark: true).dynamicTypeSize(.accessibility2)
}

#Preview("Nova pessoa") {
    MemberFormSheet().previewing(PreviewData.demo)
}

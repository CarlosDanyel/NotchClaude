import SwiftUI

struct NotchHeaderView: View {
    @ObservedObject var model: NotchViewModel
    let controller: NotchController
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                tab(.tasks, symbol: "list.bullet.rectangle.portrait.fill", title: "Tarefas")
                tab(.compose, symbol: "plus.bubble.fill", title: "Nova")
            }
            .padding(2)
            .background(Capsule().fill(Theme.card))

            Spacer(minLength: model.geometry.notchSize.width + 24)

            usage

            NotchIconButton(symbol: "gearshape.fill", help: "Ajustes", size: 24) {
                controller.showSettings()
            }
        }
        .padding(.horizontal, NotchViewModel.contentPadding - 4)
        .padding(.top, 4)
    }

    private func tab(_ page: NotchViewModel.Page, symbol: String, title: String) -> some View {
        let selected = model.page == page
        return Button {
            withAnimation(Theme.openSpring) { model.page = page }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                if selected {
                    Text(title).font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.75))
            .padding(.horizontal, selected ? 10 : 8)
            .frame(height: 22)
            .background(Capsule().fill(selected ? Color.white : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    @ViewBuilder
    private var usage: some View {
        if store.limit.isBlocked(), let until = store.limit.blockedUntil {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.needle.fill").font(.system(size: 10, weight: .bold))
                Text("Tokens esgotados · \(Formatters.clock(until))")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(Theme.danger)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(Theme.danger.opacity(0.15)))
            .help("\(store.limit.kindLabel) atingido. As tarefas atrasadas rodam automaticamente \(Formatters.resetDescription(until)).")
        } else {
            HStack(spacing: 10) {
                UsageBar(label: "5h", window: store.usage?.fiveHour)
                UsageBar(label: "Sem", window: store.usage?.sevenDay)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(Theme.card))
        }
    }
}

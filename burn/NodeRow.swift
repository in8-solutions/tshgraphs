import SwiftUI

struct NodeRow: View {
    let node: JobNode
    @Binding var selection: Int?
    let jobsWithCharts: Set<Int>
    @State private var isExpanded: Bool = false

    private var hasChart: Bool {
        jobsWithCharts.contains(node.id)
    }

    var body: some View {
        if node.children.isEmpty {
            HStack {
                Image(systemName: "chevron.right")
                    .opacity(0)
                HStack {
                    Text(node.name)
                        .foregroundStyle(hasChart ? Color.green : Color.primary)
                    Spacer()
                    if selection == node.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selection == node.id {
                        selection = nil
                    } else {
                        selection = node.id
                    }
                }
            }
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children, id: \.self) { child in
                    NodeRow(node: child, selection: $selection, jobsWithCharts: jobsWithCharts)
                        .padding(.leading, 12)
                }
            } label: {
                HStack {
                    Text(node.name)
                    Spacer()
                    if selection == node.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
            }
        }
    }
}

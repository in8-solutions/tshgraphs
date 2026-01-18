import SwiftUI

struct NodeRow: View {
    let node: JobNode
    @Binding var selection: Int?
    @State private var isExpanded: Bool = false

    var body: some View {
        if node.children.isEmpty {
            // Leaf: no disclosure indicator but aligned with a hidden chevron
            HStack {
                Image(systemName: "chevron.right")
                    .opacity(0)
                HStack {
                    Text(node.name)
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
            // Non-leaf: show disclosure with children; allow tapping label to expand/collapse
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children, id: \.self) { child in
                    NodeRow(node: child, selection: $selection)
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

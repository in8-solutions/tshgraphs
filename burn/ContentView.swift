//
//  ContentView.swift
//  burn (macOS)
//

import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var vm = BurnViewModel()

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    vm.goToManageCeiling()
                } label: {
                    Label("Manage Ceiling", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 6)

                Text("Select Job").font(.headline)
                List(selection: Binding(get: { vm.selectedJobId.map { Set([$0]) } ?? [] }, set: { sel in
                    vm.requestJobChange(to: sel.first)
                })) {
                    ForEach(vm.jobTree, id: \.self) { node in
                        NodeRow(node: node, selection: $vm.selectedJobId, jobsWithCharts: vm.jobsWithCharts)
                    }
                }
            }
            .padding()
            .navigationTitle("Jobs")
        } detail: {
            if vm.route == .chart {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Query Stop")
                            DatePicker("", selection: $vm.endDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                        Spacer()
                        Button(action: { Task { await vm.generateChart() } }) {
                            if vm.isLoading { ProgressView() } else { Text("Generate Burn Chart") }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(vm.selectedJobId == nil || !(vm.popStartDate != nil && vm.popEndDate != nil && vm.popStartDate! <= vm.popEndDate!))
                        Button(action: {
                            Task {
                                guard !vm.cumulativeSeries.isEmpty else { return }
                                let (ok, message) = await ChartSaver.saveChartToPhotos(
                                    title: vm.selectedJobName ?? "Cumulative Hours",
                                    employees: vm.employeeNames,
                                    series: vm.cumulativeSeries,
                                    start: vm.popStartDate ?? vm.startDate,
                                    end: vm.popEndDate ?? vm.endDate,
                                    projectedStartIndex: vm.projectedStartIndex,
                                    ceilingSeries: vm.ceilingSeries,
                                    ceiling75Series: vm.ceiling75Series,
                                    monthlySeries: vm.monthlySeries,
                                    cumulativeActualSeries: vm.cumulativeActualSeries
                                )
                                vm.alertTitle = ok ? "Success" : "Error"
                                vm.alertMessage = message
                            }
                        }) {
                            Text("Save Chart to Photos")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.cumulativeSeries.isEmpty)
                    }

                    if !vm.cumulativeSeries.isEmpty {
                        ChartCard(
                            title: vm.selectedJobName ?? "Cumulative Hours",
                            employees: vm.employeeNames,
                            series: vm.cumulativeSeries,
                            start: vm.popStartDate ?? vm.startDate,
                            end: vm.popEndDate ?? vm.endDate,
                            projectedStartIndex: vm.projectedStartIndex,
                            ceilingSeries: vm.ceilingSeries,
                            ceiling75Series: vm.ceiling75Series,
                            monthlySeries: vm.monthlySeries,
                            cumulativeActualSeries: vm.cumulativeActualSeries
                        )
                        .frame(minHeight: 420)
                    } else {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No data yet.")
                                Text("Pick a job, set PoP dates in Manage Ceiling, choose Query Stop, then click Generate.")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                    }

                    Spacer()
                }
                .padding()
                .navigationTitle("Burn Chart")
            } else {
                ManageCeilingView(vm: vm)
            }
        }
        .task { await vm.loadConfigAndJobs() }
        .alert(isPresented: Binding(get: { vm.alertMessage != nil }, set: { _ in vm.alertTitle = nil; vm.alertMessage = nil })) {
            Alert(title: Text(vm.alertTitle ?? "Notice"), message: Text(vm.alertMessage ?? ""), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog("You have unsaved changes.", isPresented: $vm.showUnsavedConfirm, titleVisibility: .visible) {
            Button("Save", role: .none) { vm.confirmSaveThenProceed() }
            Button("Discard Changes", role: .destructive) { vm.confirmDiscardThenProceed() }
            Button("Cancel", role: .cancel) { vm.cancelProceed() }
        } message: {
            Text("Save your edits before leaving this screen?")
        }
    }
}


#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}

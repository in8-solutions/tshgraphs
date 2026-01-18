import SwiftUI

/// Editor for per‑job Ceiling releases. The job tree remains in the left pane;
/// this view manages the detail for the selected job.
struct ManageCeilingView: View {
    @ObservedObject var vm: BurnViewModel

    // New entry draft
    @State private var draftDate: Date = Date()
    @State private var draftHours: String = ""
    @State private var draftNote: String = ""

    @State private var showDeleteConfirm: Bool = false
    @State private var deleteId: UUID? = nil
    @State private var showSavedBadge: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.selectedJobId == nil {
                Text("Pick a job to manage ceiling.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                header
                popSection
                releasesList
                addRow
                controls
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Manage Ceiling")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    vm.requestRouteChange(to: .chart)
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .alert("Delete this release?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = deleteId, let i = vm.ceilingReleases.firstIndex(where: { $0.id == id }) {
                    vm.ceilingReleases.remove(at: i)
                    vm.isDirty = true
                }
                deleteId = nil
            }
            Button("Cancel", role: .cancel) { deleteId = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .onChange(of: vm.selectedJobId) { _, _ in
            // Reset draft when switching jobs
            draftDate = Date(); draftHours = ""; draftNote = ""
            showSavedBadge = false
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Managing ceiling for: \(vm.selectedJobName ?? "Selected Job")")
                    .font(.headline)
                if vm.isDirty {
                    Text("You have unsaved changes")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if showSavedBadge {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .transition(.opacity)
                    .accessibilityLabel("Changes saved")
            }
        }
    }

    private var popSection: some View {
        GroupBox("Period of Performance") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("PoP Start")
                            .frame(width: 80, alignment: .leading)
                        DatePicker("", selection: popStartBinding, displayedComponents: .date)
                            .labelsHidden()
                            .onChange(of: vm.popStartDate) { _, _ in vm.isDirty = true; showSavedBadge = false }
                    }
                    HStack(spacing: 6) {
                        Text("PoP End")
                            .frame(width: 80, alignment: .leading)
                        DatePicker("", selection: popEndBinding, displayedComponents: .date)
                            .labelsHidden()
                            .onChange(of: vm.popEndDate) { _, _ in vm.isDirty = true; showSavedBadge = false }
                    }
                    Spacer(minLength: 0)
                }

                if !hasValidPoP {
                    Text(popValidationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var releasesList: some View {
        GroupBox {
            if vm.ceilingReleases.isEmpty {
                Text("No releases yet. Add one below.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("Date").frame(width: 140, alignment: .leading)
                        Text("± Hours").frame(width: 120, alignment: .leading)
                        Text("Note").frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        Text("")
                            .frame(width: 44)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    ForEach(vm.ceilingReleases) { release in
                        HStack(alignment: .center, spacing: 8) {
                            DatePicker("", selection: dateBinding(for: release.id), displayedComponents: .date)
                                .labelsHidden()
                                .frame(width: 140, alignment: .leading)

                            TextField("0", text: hoursTextBinding(for: release.id))
                                .frame(width: 120)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { vm.isDirty = true }

                            TextField("Optional note", text: noteBinding(for: release.id))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { vm.isDirty = true }

                            Spacer(minLength: 0)

                            Button(role: .destructive) {
                                deleteId = release.id
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 44)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Total")
                            .frame(width: 140, alignment: .leading)
                        Text(totalReleaseHours.hoursFormatted)
                            .frame(width: 120, alignment: .leading)
                            .bold()
                        Spacer(minLength: 0)
                        Text("") // placeholder to align with delete column
                            .frame(width: 44)
                    }
                }
            }
        }
    }

    private var addRow: some View {
        GroupBox {
            HStack(spacing: 8) {
                DatePicker("", selection: $draftDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 140, alignment: .leading)
                TextField("0", text: $draftHours)
                    .frame(width: 120)
                    .textFieldStyle(.roundedBorder)
                TextField("Optional note", text: $draftNote)
                    .textFieldStyle(.roundedBorder)
                Spacer(minLength: 0)
                Button {
                    let trimmed = draftHours.trimmingCharacters(in: .whitespaces)
                    let val = Double(trimmed) ?? 0
                    let note = draftNote.trimmingCharacters(in: .whitespaces)
                    vm.ceilingReleases.append(CeilingRelease(date: draftDate, hours: val, note: note.isEmpty ? nil : note))
                    vm.isDirty = true
                    // reset
                    draftDate = Date()
                    draftHours = ""
                    draftNote = ""
                } label: {
                    Label("Add Release", systemImage: "plus")
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Button {
                vm.saveCeiling()
                withAnimation { showSavedBadge = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { showSavedBadge = false }
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedJobId == nil || !isAllHoursValid || !vm.isDirty || !hasValidPoP)

            Button(role: .destructive) {
                vm.discardEdits()
            } label: {
                Text("Discard")
            }
            .disabled(!vm.isDirty)
        }
    }

    // MARK: - Totals
    private var totalReleaseHours: Double {
        vm.ceilingReleases.reduce(0) { $0 + $1.hours }
    }

    // MARK: - PoP Bindings & Validation
    private var popStartBinding: Binding<Date> {
        Binding<Date>(
            get: { vm.popStartDate ?? Date() },
            set: { vm.popStartDate = $0; vm.isDirty = true }
        )
    }
    private var popEndBinding: Binding<Date> {
        Binding<Date>(
            get: { vm.popEndDate ?? Date() },
            set: { vm.popEndDate = $0; vm.isDirty = true }
        )
    }
    private var hasValidPoP: Bool {
        CeilingStore.isValidPoP(vm.popStartDate, vm.popEndDate)
    }
    private var popValidationMessage: String {
        if vm.popStartDate == nil || vm.popEndDate == nil { return "Set both PoP Start and PoP End." }
        if let s = vm.popStartDate, let e = vm.popEndDate, s > e { return "PoP Start must be on or before PoP End." }
        return ""
    }

    // MARK: - Validation & Bindings

    private var isAllHoursValid: Bool {
        let t = draftHours.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || Double(t) != nil
    }

    private func index(for id: UUID) -> Int? {
        vm.ceilingReleases.firstIndex(where: { $0.id == id })
    }

    private func dateBinding(for id: UUID) -> Binding<Date> {
        Binding<Date>(
            get: { index(for: id).map { vm.ceilingReleases[$0].date } ?? Date() },
            set: { new in if let i = index(for: id) { vm.ceilingReleases[i].date = new; vm.isDirty = true } }
        )
    }

    private func hoursTextBinding(for id: UUID) -> Binding<String> {
        Binding<String>(
            get: { index(for: id).map { String(vm.ceilingReleases[$0].hours) } ?? "" },
            set: { text in if let v = Double(text), let i = index(for: id) { vm.ceilingReleases[i].hours = v; vm.isDirty = true } }
        )
    }

    private func noteBinding(for id: UUID) -> Binding<String> {
        Binding<String>(
            get: { index(for: id).map { vm.ceilingReleases[$0].note ?? "" } ?? "" },
            set: { text in if let i = index(for: id) { vm.ceilingReleases[i].note = text.isEmpty ? nil : text; vm.isDirty = true } }
        )
    }
}

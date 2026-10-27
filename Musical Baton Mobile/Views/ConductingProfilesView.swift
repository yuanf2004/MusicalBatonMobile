import SwiftUI

struct ConductingProfilesView: View {
    let store: ConductingProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ConductingProfile?
    @State private var deleting: ConductingProfile?

    var body: some View {
        List {
            Section {
                Text("Save your beat count, sounds, and preferred sensitivity. These profiles are manual settings; gesture training is not included yet.")
                    .foregroundStyle(.secondary)
                if let error = store.error { Text(error).foregroundStyle(.red) }
                Button("New Profile", systemImage: "plus") { editing = ConductingProfile() }
            }
            Section("Saved profiles") {
                ForEach(store.profiles) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { store.select(profile.id) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name).font(.headline)
                                    Text("\(profile.beatsPerMeasure) beats · \(profile.sensitivity.title)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.selectedID == profile.id { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                        .buttonStyle(.borderless)
                        HStack {
                            Button("Edit") { editing = profile }
                            Spacer()
                            Button("Delete", role: .destructive) { deleting = profile }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                if store.profiles.isEmpty { Text("Create a profile to get started.") }
            }
        }
        .navigationTitle("Conducting Profiles")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $editing) { profile in
            NavigationStack { ConductingProfileEditor(store: store, profile: profile) }
        }
        .confirmationDialog("Delete this profile?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Profile", role: .destructive) {
                if let deleting { store.delete(deleting.id) }
                deleting = nil
            }
        }
    }
}

private struct ConductingProfileEditor: View {
    let store: ConductingProfileStore
    @State var profile: ConductingProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $profile.name)
                Picker("Beats per measure", selection: $profile.beatsPerMeasure) {
                    ForEach(2...4, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Sensitivity", selection: $profile.sensitivity) {
                    ForEach(DetectionSensitivity.allCases) { Text($0.title).tag($0) }
                }
                Text("Gentle detects smaller strokes but can produce extra beats. Deliberate requires firmer motion.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Sounds") {
                Picker("Beat 1", selection: $profile.downbeatSound) {
                    ForEach(ClickVoice.allCases) { Text($0.title).tag($0) }
                }
                Picker("Other beats", selection: $profile.otherBeatSound) {
                    ForEach(ClickVoice.allCases) { Text($0.title).tag($0) }
                }
                Text("Beat 1 is accented. Preview both sounds after enabling the profile in Conducting Mode.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Edit Profile")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if store.save(profile) { dismiss() } }.disabled(!profile.isValid)
            }
        }
    }
}

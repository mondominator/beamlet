import SwiftUI

struct ContactsView: View {
    @Environment(BeamletAPI.self) private var api

    @State private var contacts: [BeamletUser] = []
    @State private var isLoading = true
    @State private var contactToRemove: BeamletUser?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading contacts...")
            } else if contacts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No contacts yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Add contacts from Settings to start sharing")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    ForEach(contacts) { contact in
                        HStack(spacing: 14) {
                            AvatarView(name: contact.name, size: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(.headline)
                                if let date = contact.createdAt {
                                    Text("Connected \(date, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                contactToRemove = contact
                            } label: {
                                Label("Remove", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Contacts")
        .task {
            contacts = (try? await api.listUsers()) ?? []
            isLoading = false
        }
        .confirmationDialog(
            "Remove Contact",
            isPresented: Binding(
                get: { contactToRemove != nil },
                set: { if !$0 { contactToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let contact = contactToRemove {
                Button("Remove \(contact.name)", role: .destructive) {
                    Task {
                        try? await api.deleteContact(contact.id)
                        contacts.removeAll { $0.id == contact.id }
                        contactToRemove = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    contactToRemove = nil
                }
            }
        } message: {
            Text("You won't be able to send files to this person until you reconnect.")
        }
    }
}

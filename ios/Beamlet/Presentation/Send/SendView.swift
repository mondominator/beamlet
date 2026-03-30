import SwiftUI
import PhotosUI

struct SendView: View {
    @Environment(BeamletAPI.self) private var api
    @State private var viewModel: SendViewModel?

    var body: some View {
        NavigationStack {
            if let vm = viewModel {
                Form {
                    Section("Recipient") {
                        if vm.users.isEmpty {
                            ProgressView("Loading users...")
                        } else {
                            Picker("Send to", selection: Bindable(vm).selectedUser) {
                                Text("Select recipient").tag(nil as BeamletUser?)
                                ForEach(vm.users) { user in
                                    Text(user.name).tag(user as BeamletUser?)
                                }
                            }
                        }
                    }

                    Section("Content") {
                        PhotosPicker(selection: Bindable(vm).selectedPhoto, matching: .any(of: [.images, .videos])) {
                            HStack {
                                Image(systemName: vm.selectedPhotoData != nil ? "checkmark.circle.fill" : "photo")
                                    .foregroundStyle(vm.selectedPhotoData != nil ? .green : .secondary)
                                Text(vm.selectedPhotoData != nil ? "Photo selected" : "Choose photo or video")
                            }
                        }
                        .onChange(of: vm.selectedPhoto) {
                            Task { await vm.loadPhotoData() }
                        }

                        TextField("Message (optional)", text: Bindable(vm).message, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    if let error = vm.error {
                        Section {
                            Text(error).foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button {
                            Task { await vm.send() }
                        } label: {
                            if vm.isSending {
                                HStack { ProgressView(); Text("Sending...") }
                            } else {
                                Label("Send", systemImage: "paperplane.fill")
                            }
                        }
                        .disabled(!vm.canSend)
                    }
                }
                .navigationTitle("Send")
                .alert("Sent!", isPresented: Bindable(vm).showSuccess) {
                    Button("OK") { vm.reset() }
                } message: {
                    Text("File sent successfully")
                }
                .task { await vm.loadUsers() }
            } else {
                LoadingView()
                    .task { viewModel = SendViewModel(api: api) }
            }
        }
    }
}

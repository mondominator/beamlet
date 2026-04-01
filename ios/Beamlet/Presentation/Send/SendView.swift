import SwiftUI
import PhotosUI

struct SendView: View {
    @Environment(BeamletAPI.self) private var api
    @Environment(NearbyService.self) private var nearbyService: NearbyService?
    @State private var viewModel: SendViewModel?
    @State private var showSendAnimation = false

    var body: some View {
        NavigationStack {
            if let vm = viewModel {
                Form {
                    if let nearby = nearbyService?.nearbyUsers, !nearby.isEmpty {
                        Section("Nearby") {
                            ForEach(nearby) { user in
                                Button {
                                    vm.selectedUser = vm.users.first(where: { $0.id == user.id })
                                        ?? BeamletUser(id: user.id, name: user.name, createdAt: nil)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(user.isContact ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                            Text(user.name.prefix(1).uppercased())
                                                .font(.headline)
                                                .foregroundStyle(user.isContact ? .blue : .secondary)
                                        }
                                        VStack(alignment: .leading) {
                                            Text(user.name)
                                                .foregroundStyle(.primary)
                                            Text(user.isContact ? "Contact" : "Nearby")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

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
                .overlay {
                    if showSendAnimation {
                        SendSuccessOverlay()
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: vm.showSuccess) { _, success in
                    if success {
                        // Haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        // Visual animation
                        withAnimation(.spring(response: 0.3)) {
                            showSendAnimation = true
                        }
                        // Auto-dismiss after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation {
                                showSendAnimation = false
                            }
                            vm.showSuccess = false
                            vm.reset()
                        }
                    }
                }
                .task { await vm.loadUsers() }
                .onChange(of: vm.users) {
                    nearbyService?.updateContacts(vm.users)
                }
            } else {
                LoadingView()
                    .task { viewModel = SendViewModel(api: api) }
            }
        }
    }
}

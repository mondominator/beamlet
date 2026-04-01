import SwiftUI
import PhotosUI
import AudioToolbox
import UniformTypeIdentifiers

struct SendView: View {
    @Environment(BeamletAPI.self) private var api
    @Environment(NearbyService.self) private var nearbyService: NearbyService?
    @State private var viewModel: SendViewModel?
    @State private var showSendAnimation = false
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            if let vm = viewModel {
                Form {
                    if let nearby = nearbyService?.nearbyUsers, !nearby.isEmpty {
                        Section("Nearby") {
                            ForEach(nearby) { user in
                                let beamletUser = vm.users.first(where: { $0.id == user.id })
                                    ?? BeamletUser(id: user.id, name: user.name, createdAt: nil)
                                Button {
                                    vm.toggleUser(beamletUser)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(vm.isSelected(beamletUser) ? Color.blue.opacity(0.2) : (user.isContact ? Color.blue.opacity(0.08) : Color.gray.opacity(0.1)))
                                                .frame(width: 40, height: 40)
                                            if vm.isSelected(beamletUser) {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.blue)
                                            } else {
                                                Text(user.name.prefix(1).uppercased())
                                                    .font(.headline)
                                                    .foregroundStyle(user.isContact ? .blue : .secondary)
                                            }
                                        }
                                        VStack(alignment: .leading) {
                                            Text(user.name)
                                                .foregroundStyle(.primary)
                                            Text(user.isContact ? "Contact" : "Nearby")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if vm.isSelected(beamletUser) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        if vm.users.isEmpty {
                            ProgressView("Loading contacts...")
                        } else {
                            ForEach(vm.users) { user in
                                Button {
                                    vm.toggleUser(user)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            if vm.isSelected(user) {
                                                Circle()
                                                    .fill(Color.blue.opacity(0.2))
                                                    .frame(width: 36, height: 36)
                                                    .overlay(
                                                        Image(systemName: "checkmark")
                                                            .font(.caption.bold())
                                                            .foregroundStyle(.blue)
                                                    )
                                            } else {
                                                AvatarView(name: user.name, size: 36)
                                            }
                                        }
                                        Text(user.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if vm.isSelected(user) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Recipients")
                            Spacer()
                            if !vm.selectedUsers.isEmpty {
                                Text("\(vm.selectedUsers.count) selected")
                                    .foregroundStyle(.blue)
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
                            vm.selectedFileURL = nil // Clear file if photo selected
                            Task { await vm.loadPhotoData() }
                        }

                        Button {
                            showFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: vm.selectedFileURL != nil ? "checkmark.circle.fill" : "doc")
                                    .foregroundStyle(vm.selectedFileURL != nil ? .green : .secondary)
                                Text(vm.selectedFileName ?? "Choose file")
                            }
                        }

                        TextField("Message (optional)", text: Bindable(vm).message, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    .fileImporter(
                        isPresented: $showFilePicker,
                        allowedContentTypes: [.item],
                        allowsMultipleSelection: false
                    ) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            _ = url.startAccessingSecurityScopedResource()
                            vm.selectedFileURL = url
                            vm.selectedFileName = url.lastPathComponent
                            vm.selectedFileMimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                            vm.selectedPhoto = nil
                            vm.selectedPhotoData = nil
                        }
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
                        // Haptic + sound feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        AudioServicesPlaySystemSound(1001) // "sent" swoosh
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

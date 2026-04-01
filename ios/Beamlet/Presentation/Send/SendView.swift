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
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationStack {
            if let vm = viewModel {
                Form {
                    if let nearby = nearbyService?.nearbyUsers, !nearby.isEmpty {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(nearby) { user in
                                        let beamletUser = vm.users.first(where: { $0.id == user.id })
                                            ?? BeamletUser(id: user.id, name: user.name, createdAt: nil)
                                        Button {
                                            vm.toggleUser(beamletUser)
                                            let generator = UIImpactFeedbackGenerator(style: .light)
                                            generator.impactOccurred()
                                        } label: {
                                            VStack(spacing: 4) {
                                                PulsingAvatarView(
                                                    name: user.name,
                                                    isContact: user.isContact,
                                                    isSelected: vm.isSelected(beamletUser)
                                                )
                                                Text(user.name)
                                                    .font(.caption2)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 80)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        } header: {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundStyle(.teal)
                                Text("Nearby")
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
                        // Unified attachment button
                        if let name = vm.attachmentDisplayName {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(name)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    vm.clearAttachment()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Menu {
                                Button {
                                    showPhotoPicker = true
                                } label: {
                                    Label("Photo or Video", systemImage: "photo")
                                }
                                Button {
                                    showFilePicker = true
                                } label: {
                                    Label("File or Document", systemImage: "doc")
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "paperclip")
                                        .foregroundStyle(.secondary)
                                    Text("Add attachment")
                                        .foregroundStyle(.primary)
                                }
                            }
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
                .photosPicker(isPresented: $showPhotoPicker, selection: Bindable(vm).selectedPhoto, matching: .any(of: [.images, .videos]))
                .onChange(of: vm.selectedPhoto) {
                    vm.selectedFileURL = nil
                    Task { await vm.loadPhotoData() }
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

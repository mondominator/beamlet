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

    private let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            if let vm = viewModel {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            // MARK: - Step 1: Pick attachment
                            VStack(spacing: 12) {
                                if let name = vm.attachmentDisplayName {
                                    // Attachment selected
                                    HStack(spacing: 12) {
                                        Image(systemName: vm.selectedPhotoData != nil ? "photo.fill" : "doc.fill")
                                            .font(.title2)
                                            .foregroundStyle(.blue)
                                            .frame(width: 48, height: 48)
                                            .background(.blue.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(name)
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(1)
                                            Text("Ready to send")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button {
                                            vm.clearAttachment()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(14)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .padding(.horizontal)
                                } else {
                                    // Picker buttons
                                    HStack(spacing: 12) {
                                        Button { showPhotoPicker = true } label: {
                                            VStack(spacing: 8) {
                                                Image(systemName: "photo.on.rectangle")
                                                    .font(.title2)
                                                Text("Photo or Video")
                                                    .font(.caption)
                                            }
                                            .foregroundStyle(.blue)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 20)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                        }
                                        .buttonStyle(.plain)

                                        Button { showFilePicker = true } label: {
                                            VStack(spacing: 8) {
                                                Image(systemName: "doc")
                                                    .font(.title2)
                                                Text("File")
                                                    .font(.caption)
                                            }
                                            .foregroundStyle(.blue)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 20)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal)
                                }
                            }

                            // MARK: - Step 2: Pick recipients
                            if vm.attachmentDisplayName != nil {
                                VStack(spacing: 16) {
                                    // Nearby
                                    if let nearby = nearbyService?.nearbyUsers, !nearby.isEmpty {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Label {
                                                Text("Nearby")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                            } icon: {
                                                Image(systemName: "antenna.radiowaves.left.and.right")
                                                    .foregroundStyle(.teal)
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal)

                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 4) {
                                                    ForEach(nearby) { user in
                                                        let beamletUser = vm.users.first(where: { $0.id == user.id })
                                                            ?? BeamletUser(id: user.id, name: user.name, createdAt: nil)
                                                        Button {
                                                            vm.toggleUser(beamletUser)
                                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                                                .padding(.horizontal)
                                            }
                                        }
                                    }

                                    // Contacts grid
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text("Send to")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            if !vm.selectedUsers.isEmpty {
                                                Text("\(vm.selectedUsers.count) selected")
                                                    .font(.caption)
                                                    .foregroundStyle(.blue)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(.blue.opacity(0.1))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .padding(.horizontal)

                                        if vm.isLoadingUsers {
                                            HStack {
                                                Spacer()
                                                ProgressView("Loading contacts...")
                                                    .padding(.vertical, 20)
                                                Spacer()
                                            }
                                        } else if vm.users.isEmpty {
                                            VStack(spacing: 10) {
                                                Image(systemName: "person.2.slash")
                                                    .font(.largeTitle)
                                                    .foregroundStyle(.secondary)
                                                Text("No contacts yet")
                                                    .font(.headline)
                                                    .foregroundStyle(.secondary)
                                                Text("Add a contact in Settings to start sharing.")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 30)
                                        } else {
                                            LazyVGrid(columns: columns, spacing: 16) {
                                                ForEach(vm.users) { user in
                                                    Button {
                                                        vm.toggleUser(user)
                                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    } label: {
                                                        VStack(spacing: 6) {
                                                            ZStack(alignment: .bottomTrailing) {
                                                                AvatarView(name: user.name, size: 56)
                                                                if vm.isSelected(user) {
                                                                    Image(systemName: "checkmark.circle.fill")
                                                                        .font(.system(size: 18))
                                                                        .foregroundStyle(.white, .blue)
                                                                        .offset(x: 2, y: 2)
                                                                }
                                                            }
                                                            Text(user.name)
                                                                .font(.caption)
                                                                .foregroundStyle(.primary)
                                                                .lineLimit(1)
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                        .animation(.easeInOut(duration: 0.3), value: vm.attachmentDisplayName != nil)
                    }

                    // MARK: - Send button
                    if vm.attachmentDisplayName != nil {
                        VStack(spacing: 0) {
                            Divider()

                            if let error = vm.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.top, 8)
                            }

                            Button {
                                Task { await vm.send() }
                            } label: {
                                if vm.isSending {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                } else {
                                    Label("Send", systemImage: "paperplane.fill")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            LinearGradient(
                                                colors: vm.canSend
                                                    ? [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.23, green: 0.51, blue: 0.96)]
                                                    : [.gray.opacity(0.3), .gray.opacity(0.3)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                            .disabled(!vm.canSend)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                        .background(.bar)
                        .transition(.move(edge: .bottom))
                    }
                }
                .photosPicker(isPresented: $showPhotoPicker, selection: Bindable(vm).selectedPhoto, matching: .any(of: [.images, .videos]))
                .onChange(of: vm.selectedPhoto) {
                    // Clear file attachment (if switching from file to photo)
                    vm.clearFileAttachment()
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
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        AudioServicesPlaySystemSound(1001)
                        withAnimation(.spring(response: 0.3)) {
                            showSendAnimation = true
                        }
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

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
                        VStack(spacing: 20) {
                            // Nearby section
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
                                    Text("Contacts")
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

                                if vm.users.isEmpty {
                                    HStack {
                                        Spacer()
                                        ProgressView("Loading contacts...")
                                            .padding(.vertical, 20)
                                        Spacer()
                                    }
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
                        .padding(.top, 16)
                        .padding(.bottom, 100) // Space for bottom bar
                    }

                    // Bottom bar: attachment + send
                    VStack(spacing: 12) {
                        Divider()

                        HStack(spacing: 12) {
                            // Attachment
                            if let name = vm.attachmentDisplayName {
                                HStack(spacing: 8) {
                                    Image(systemName: "paperclip")
                                        .foregroundStyle(.blue)
                                    Text(name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Button {
                                        vm.clearAttachment()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
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
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                            }

                            Spacer()

                            if let error = vm.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            }

                            // Send button
                            Button {
                                Task { await vm.send() }
                            } label: {
                                if vm.isSending {
                                    ProgressView()
                                        .frame(width: 48, height: 48)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .frame(width: 48, height: 48)
                                        .background(
                                            LinearGradient(
                                                colors: vm.canSend
                                                    ? [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.23, green: 0.51, blue: 0.96)]
                                                    : [.gray.opacity(0.3), .gray.opacity(0.3)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .clipShape(Circle())
                                }
                            }
                            .disabled(!vm.canSend)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .background(.bar)
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
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
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

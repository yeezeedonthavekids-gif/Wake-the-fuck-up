import PhotosUI
import SwiftUI

struct ItemLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach($model.data.items) { $item in
                    NavigationLink { ItemEditorView(item: $item) } label: {
                        HStack {
                            Image(systemName: item.symbol).frame(width: 28)
                            Text(item.name)
                            Spacer()
                            if item.photoFile != nil { Image(systemName: "photo").foregroundStyle(Palette.text3) }
                            if !item.inRandomPool { Text("Not used").font(.caption).foregroundStyle(Palette.text3) }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let photo = model.data.items[index].photoFile { model.persistence.deletePhoto(photo) }
                    }
                    model.data.items.remove(atOffsets: offsets)
                }
            } header: {
                Text("Items")
            } footer: {
                Text("“Find an item” picks from the items marked as used. Don't add photos of people, private documents or sensitive places.")
            }
            Section("Add an item") {
                HStack {
                    TextField("For example: glasses", text: $newName)
                    Button("Add") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        model.data.items.append(HouseholdItem(name: String(name.prefix(40)), symbol: "cube", keywords: [name.lowercased()]))
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || model.data.items.count >= 60)
                }
            }
        }
        .wakeForm()
        .navigationTitle("Item library")
        .toolbar { EditButton() }
    }
}

struct ItemEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var item: HouseholdItem
    @State private var pickedPhoto: PhotosPickerItem? = nil
    @State private var takingPhoto = false
    @State private var photoError: String? = nil

    private static let symbols = ["cube", "mouth", "waterbottle", "comb", "book.closed", "shoe", "key", "eyeglasses",
                                  "cup.and.saucer", "tshirt", "backpack", "headphones", "pills", "leaf", "toilet", "sink"]

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $item.name)
                Toggle("Use in random targets", isOn: $item.inRandomPool)
            }
            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            item.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(item.symbol == symbol ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                    }
                }
            }
            Section {
                TextField("Words to recognize, comma separated", text: Binding(
                    get: { item.keywords.joined(separator: ", ") },
                    set: { item.keywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }
                ))
            } header: {
                Text("Photo check")
            } footer: {
                Text("In Photo check mode, WakeUp classifies your photo on this iPhone and looks for these words (for example “bottle”). If none match, you confirm it yourself.")
            }
            Section {
                if let file = item.photoFile, let image = UIImage(contentsOfFile: model.persistence.photoURL(file).path) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 12))
                    Button("Remove photo", role: .destructive) {
                        model.persistence.deletePhoto(file)
                        item.photoFile = nil
                    }
                }
                PhotosPicker("Choose from library", selection: $pickedPhoto, matching: .images)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take a photo") {
                        Task { if await CameraAccess.request() { takingPhoto = true } else { photoError = "Camera access is off for WakeUp." } }
                    }
                }
                if let photoError { Text(photoError).font(.footnote).foregroundStyle(Palette.bad) }
            } header: {
                Text("Reference photo (optional)")
            } footer: {
                Text("Shown next to your photo during Photo check. Stored only on this iPhone.")
            }
            Section {
                QRCodeCard(title: item.name, code: item.qrCode)
            } header: {
                Text("QR code for this item")
            } footer: {
                Text("Print it and stick it on the item to use the “Scan the item's QR code” mode.")
            }
        }
        .wakeForm()
        .navigationTitle(item.name)
        .onChange(of: pickedPhoto) { _, picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    save(image)
                } else {
                    photoError = "That photo couldn't be loaded."
                }
            }
        }
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraPhotoPicker { image in
                takingPhoto = false
                if let image { save(image) }
            }
            .ignoresSafeArea()
        }
    }

    /// Stores a small JPEG, replacing any earlier photo.
    private func save(_ image: UIImage) {
        let maxSide: CGFloat = 800
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.75) else { return }
        do {
            if let old = item.photoFile { model.persistence.deletePhoto(old) }
            item.photoFile = try model.persistence.savePhoto(jpeg, for: item.id)
            photoError = nil
        } catch {
            photoError = "The photo couldn't be saved: \(error.localizedDescription)"
        }
    }
}

struct QRDestinationsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newName = ""
    @State private var testing: QRDestination? = nil
    @State private var testResult: String? = nil

    var body: some View {
        List {
            Section {
                ForEach(model.data.destinations) { destination in
                    VStack(alignment: .leading, spacing: 10) {
                        QRCodeCard(title: destination.name, code: destination.code)
                        Button("Test scan") { testing = destination }
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { model.data.destinations.remove(atOffsets: $0) }
                if let testResult { Text(testResult).font(.footnote) }
            } header: {
                Text("Your destinations")
            } footer: {
                Text("Codes are generated on this iPhone. They only mean something to WakeUp, and need no internet.")
            }
            Section("Add a destination") {
                HStack {
                    TextField("For example: bathroom mirror", text: $newName)
                    Button("Add") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        model.data.destinations.append(QRDestination(name: String(name.prefix(40))))
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || model.data.destinations.count >= 20)
                }
            }
        }
        .wakeForm()
        .navigationTitle("QR destinations")
        .toolbar { EditButton() }
        .sheet(item: $testing) { destination in
            QRScannerSheet { code in
                testResult = code == destination.code ? "✓ That's the code for \(destination.name)." : "That code isn't the one for \(destination.name)."
            }
        }
    }
}

/// A QR code with share and print options.
struct QRCodeCard: View {
    let title: String
    let code: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let image = QRCodeImage.make(code) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 110, height: 110)
                    .accessibilityLabel("QR code for \(title)")
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text("Share it to print, or save it to Photos.").font(.footnote).foregroundStyle(Palette.text2)
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("WakeUp code: \(title)", image: Image(uiImage: image))) {
                        Label("Share or print", systemImage: "square.and.arrow.up")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } else {
                Text("The QR code couldn't be generated.").foregroundStyle(Palette.bad)
            }
        }
    }
}

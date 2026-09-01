import SwiftUI
import PhotosUI

/// Feedback form. Category → message → optional email → optional screenshot → send.
/// Submitting opens a pre-filled Mail compose URL and shows the thanks screen.
struct FeedbackView: View {
    enum Category: String, CaseIterable {
        case bug = "Bug"
        case idea = "Idea"
        case other = "Other"
    }

    @State private var category: Category = .bug
    @State private var message = ""
    @State private var email = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoData: Data? = nil
    @State private var showThanks = false

    private let recipientEmail = "dennis.kiefer.1986@googlemail.com"

    private var canSubmit: Bool { !message.trimmingCharacters(in: .whitespaces).isEmpty }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        if showThanks {
            ThanksView()
        } else {
            formView
        }
    }

    private var formView: some View {
        List {
            // Category picker
            Section {
                Picker("Category", selection: $category) {
                    ForEach(Category.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Category")
            }

            // Message
            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Describe the issue or idea…")
                                .foregroundStyle(Color(.placeholderText))
                                .font(.body)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Message")
            }

            // Email
            Section {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Contact (optional)")
            }

            // Screenshot
            Section {
                if let photoData, let uiImage = UIImage(data: photoData) {
                    HStack {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("screenshot.png")
                        Spacer()
                        Button("Remove", role: .destructive) {
                            self.photoItem = nil
                            self.photoData = nil
                        }
                        .font(.callout)
                    }
                } else {
                    PhotosPicker(selection: $photoItem, matching: .screenshots) {
                        Label("Add Screenshot", systemImage: "camera")
                    }
                }
            } header: {
                Text("Attachment")
            }

            // Device info footer
            Section {
                EmptyView()
            } footer: {
                Text("Device and app version are included automatically — \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion) · chocks \(appVersion).")
            }

            // Submit
            Section {
                Button {
                    submit()
                } label: {
                    Text("Send Feedback")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: photoItem) { _, newItem in
            Task {
                photoData = try? await newItem?.loadTransferable(type: Data.self)
            }
        }
    }

    private func submit() {
        // Build mailto URL and open it; fall back gracefully if Mail isn't available.
        let subject = "chocks Feedback – \(category.rawValue)"
        let device = "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion) · chocks \(appVersion)"
        let body = """
        \(message)

        ––
        Category: \(category.rawValue)
        Contact: \(email.isEmpty ? "(not provided)" : email)
        Device: \(device)
        """

        var components = URLComponents(string: "mailto:\(recipientEmail)")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]

        if let url = components.url {
            UIApplication.shared.open(url)
        }

        withAnimation { showThanks = true }
    }
}

/// Shown after feedback is submitted.
private struct ThanksView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Circle()
                .fill(Color.accentColor)
                .frame(width: 88, height: 88)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                )
                .padding(.bottom, 24)

            Text("Thanks for the feedback")
                .font(.system(size: 24, weight: .bold))
                .padding(.bottom, 10)

            Text("We read every message. If you added an email, we may follow up.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .navigationBarBackButtonHidden()
    }
}

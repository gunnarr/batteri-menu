import AppKit
import BatteriCore
import SwiftUI

/// Drives the sign-in window: Apple ID and password first, then the verification code.
@MainActor
final class SignInModel: ObservableObject {
    enum Step { case credentials, code }

    @Published var step: Step = .credentials
    @Published var appleID = ""
    @Published var password = ""
    @Published var code = ""
    @Published var isWorking = false
    @Published var errorMessage: String?

    private let session: LoginSession
    private let onSignedIn: () -> Void

    init(engine: EngineCommand, appleID: String?, onSignedIn: @escaping () -> Void) {
        session = LoginSession(command: engine)
        self.appleID = appleID ?? ""
        self.onSignedIn = onSignedIn
    }

    var canContinue: Bool {
        guard !isWorking else { return false }
        switch step {
        case .credentials: return appleID.contains("@") && !password.isEmpty
        case .code: return code.count == 6
        }
    }

    func submit() {
        guard canContinue else { return }
        isWorking = true
        errorMessage = nil
        Task {
            let reply: LoginReply
            switch step {
            case .credentials:
                reply = await session.start(
                    appleID: appleID.trimmingCharacters(in: .whitespaces), password: password
                )
            case .code:
                reply = await session.submit(code: code)
            }
            isWorking = false
            handle(reply)
        }
    }

    func cancel() {
        Task { await session.cancel() }
    }

    private func handle(_ reply: LoginReply) {
        switch reply {
        case .signedIn:
            password = ""
            onSignedIn()
        case .needsCode(let retry):
            password = ""
            code = ""
            step = .code
            errorMessage = retry ? "That code didn’t work. A new code has been sent." : nil
        case .failed(let failure):
            step = .credentials
            code = ""
            errorMessage = SignInModel.message(for: failure)
        }
    }

    static func message(for failure: LoginFailure) -> String {
        switch failure {
        case .badCredentials:
            return "The Apple Account or password is incorrect."
        case .securityKey:
            return "This account requires a security key, which Batteri doesn’t support."
        case .unsupportedVerification:
            return "This account uses an older verification method that Batteri doesn’t support."
        case .engine:
            return "Batteri couldn’t start signing in. Try again."
        case .other:
            return "Signing in failed. Check your internet connection and try again."
        }
    }
}

struct SignInView: View {
    @ObservedObject var model: SignInModel
    let onCancel: () -> Void
    @FocusState private var focus: Field?

    private enum Field { case appleID, password, code }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.step == .credentials ? "Sign in to iCloud" : "Enter the verification code")
                        .font(.title3.weight(.semibold))
                    Text(explanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Form {
                switch model.step {
                case .credentials:
                    TextField("Apple Account", text: $model.appleID, prompt: Text("name@example.com"))
                        .textContentType(.username)
                        .focused($focus, equals: .appleID)
                    SecureField("Password", text: $model.password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                case .code:
                    TextField("Code", text: $model.code, prompt: Text("6 digits"))
                        .textContentType(.oneTimeCode)
                        .focused($focus, equals: .code)
                        .onChange(of: model.code) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(6))
                            if digits != value { model.code = digits }
                        }
                }
            }
            .disabled(model.isWorking)
            .onSubmit { model.submit() }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if model.isWorking {
                    ProgressView().controlSize(.small)
                    Text(model.step == .credentials ? "Signing in…" : "Checking…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(model.step == .credentials ? "Continue" : "Sign In") { model.submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { focus = model.appleID.isEmpty ? .appleID : .password }
        .onChange(of: model.step) { _, step in
            focus = step == .code ? .code : .password
        }
    }

    private var explanation: String {
        switch model.step {
        case .credentials:
            return "Batteri reads the battery levels of your devices from iCloud, like Find My does. "
                + "Your password is only used to sign in and is never stored."
        case .code:
            return "Apple has sent a six-digit code to your devices. Enter it here to finish signing in."
        }
    }
}

extension NSWindow {
    /// Shows the window in front of other apps. Batteri is usually not the active app when
    /// it needs to show a window, and macOS may decline to activate it, so the window is
    /// also ordered to the front on its own.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}

/// The sign-in window. Built with AppKit so it can be shown at launch, which a menu bar
/// app cannot do with a SwiftUI scene alone.
@MainActor
final class SignInWindow: NSObject, NSWindowDelegate {
    static let shared = SignInWindow()

    private var window: NSWindow?
    private var model: SignInModel?

    func show(engine: EngineCommand, onSignedIn: @escaping () -> Void) {
        if let window {
            window.bringToFront()
            return
        }
        let model = SignInModel(engine: engine, appleID: Account.standard().appleID) { [weak self] in
            self?.close()
            onSignedIn()
        }
        let view = SignInView(model: model) { [weak self] in self?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Batteri"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        window.bringToFront()
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model?.cancel()
        model = nil
        window = nil
    }
}

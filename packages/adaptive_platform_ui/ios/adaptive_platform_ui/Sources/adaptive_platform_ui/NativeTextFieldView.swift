import Flutter
import UIKit

/// A system text control. UIKit supplies editing, selection, keyboard and chrome.
class NativeTextFieldView: NSObject, FlutterPlatformView, UITextFieldDelegate, UITextViewDelegate {
    private let container: UIView
    private let channel: FlutterMethodChannel
    private let field = UITextField()
    private var textView: UITextView?
    private var readOnly = false
    private var applyingValue = false
    private var inputAction = "done"
    private var control: UIView { (textView as UIView?) ?? field }

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        container = UIView(frame: frame)
        channel = FlutterMethodChannel(name: "adaptive_platform_ui/text_field_\(viewId)", binaryMessenger: messenger)
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(nativeFontChanged), name: AdaptiveNativeFonts.didChange, object: nil)
        let config = args as? [String: Any] ?? [:]
        if config["multiline"] as? Bool == true {
            let editor = UITextView()
            editor.delegate = self
            editor.backgroundColor = .clear
            textView = editor
        } else {
            field.delegate = self
            field.borderStyle = .roundedRect
            field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        }
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.topAnchor.constraint(equalTo: container.topAnchor),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        configure(config)
        setValue(config)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            let values = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "setValue": self.setValue(values); result(nil)
            case "configure": self.configure(values); result(nil)
            case "setFocus":
                if values["focused"] as? Bool == true { self.control.becomeFirstResponder() }
                else { self.control.resignFirstResponder() }
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }

    /// The last configuration from Flutter, reapplied when the native font changes.
    private var lastConfig: [String: Any] = [:]

    @objc private func nativeFontChanged() {
        configure(lastConfig)
    }

    private func configure(_ config: [String: Any]) {
        lastConfig = config
        container.overrideUserInterfaceStyle = config["isDark"] as? Bool == true ? .dark : .light
        readOnly = config["readOnly"] as? Bool ?? false
        inputAction = config["inputAction"] as? String ?? "done"
        let enabled = config["enabled"] as? Bool ?? true
        let color = (config["textColor"] as? Int).map { UIColor(argb: $0) } ?? .label
        let size = CGFloat((config["fontSize"] as? Double) ?? 17)
        let weights: [UIFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let index = min(8, max(0, config["fontWeight"] as? Int ?? 3))
        let font = AdaptiveNativeFonts.font(size: size, weight: weights[index])
        let alignment: NSTextAlignment
        switch config["textAlign"] as? String {
        case "center": alignment = .center
        case "right", "end": alignment = .right
        case "justify": alignment = .justified
        default: alignment = .natural
        }
        let keyboard: UIKeyboardType
        switch config["keyboard"] as? String {
        case "number": keyboard = config["decimal"] as? Bool == true ? .decimalPad : (config["signed"] as? Bool == true ? .numbersAndPunctuation : .numberPad)
        case "phone": keyboard = .phonePad
        case "emailAddress": keyboard = .emailAddress
        case "url": keyboard = .URL
        case "visiblePassword": keyboard = .asciiCapable
        case "name": keyboard = .namePhonePad
        default: keyboard = .default
        }
        let returnKey: UIReturnKeyType
        switch inputAction {
        case "go": returnKey = .go
        case "search": returnKey = .search
        case "send": returnKey = .send
        case "next": returnKey = .next
        case "continueAction": returnKey = .continue
        case "join": returnKey = .join
        case "route": returnKey = .route
        case "emergencyCall": returnKey = .emergencyCall
        case "newline", "none", "unspecified": returnKey = .default
        default: returnKey = .done
        }
        let capitalization: UITextAutocapitalizationType
        switch config["capitalization"] as? String {
        case "characters": capitalization = .allCharacters
        case "words": capitalization = .words
        case "sentences": capitalization = .sentences
        default: capitalization = .none
        }
        let correction: UITextAutocorrectionType = config["autocorrect"] as? Bool == false ? .no : .default
        let hint = (config["autofillHints"] as? [String])?.first
        let contentType: UITextContentType?
        switch hint {
        case "username": contentType = .username
        case "password": contentType = .password
        case "newPassword": contentType = .newPassword
        case "oneTimeCode": contentType = .oneTimeCode
        case "email": contentType = .emailAddress
        case "telephoneNumber", "tel": contentType = .telephoneNumber
        case "name": contentType = .name
        case "givenName": contentType = .givenName
        case "familyName": contentType = .familyName
        case "streetAddressLine1": contentType = .streetAddressLine1
        case "streetAddressLine2": contentType = .streetAddressLine2
        case "addressCity": contentType = .addressCity
        case "addressState": contentType = .addressState
        case "postalCode": contentType = .postalCode
        case "countryName": contentType = .countryName
        case "creditCardNumber": contentType = .creditCardNumber
        default: contentType = nil
        }
        if let editor = textView {
            editor.font = font
            editor.textColor = color
            editor.textAlignment = alignment
            editor.keyboardType = keyboard
            editor.returnKeyType = returnKey
            editor.autocapitalizationType = capitalization
            editor.autocorrectionType = correction
            editor.textContentType = contentType
            editor.isSecureTextEntry = config["obscureText"] as? Bool ?? false
            editor.isEditable = enabled && !readOnly
            editor.isSelectable = enabled
            // UITextView has no public placeholder API; keep it accessible.
            editor.accessibilityLabel = config["placeholder"] as? String
        } else {
            field.font = font
            field.textColor = color
            field.textAlignment = alignment
            field.keyboardType = keyboard
            field.returnKeyType = returnKey
            field.autocapitalizationType = capitalization
            field.autocorrectionType = correction
            field.textContentType = contentType
            field.isSecureTextEntry = config["obscureText"] as? Bool ?? false
            field.isEnabled = enabled
            field.inputView = readOnly ? UIView() : nil
            field.placeholder = config["placeholder"] as? String
        }
    }

    private func setValue(_ config: [String: Any]) {
        applyingValue = true
        defer { applyingValue = false }
        let text = config["text"] as? String ?? ""
        if let editor = textView {
            if editor.text != text { editor.text = text }
            let count = (text as NSString).length
            let start = min(count, max(0, config["selectionStart"] as? Int ?? count))
            let end = min(count, max(start, config["selectionEnd"] as? Int ?? start))
            editor.selectedRange = NSRange(location: start, length: end - start)
        } else {
            if field.text != text { field.text = text }
            let count = (text as NSString).length
            let start = min(count, max(0, config["selectionStart"] as? Int ?? count))
            let end = min(count, max(start, config["selectionEnd"] as? Int ?? start))
            if let from = field.position(from: field.beginningOfDocument, offset: start),
               let to = field.position(from: field.beginningOfDocument, offset: end) {
                field.selectedTextRange = field.textRange(from: from, to: to)
            }
        }
    }

    private func emitValue() {
        guard !applyingValue else { return }
        let text: String
        let start: Int
        let end: Int
        if let editor = textView {
            text = editor.text
            start = editor.selectedRange.location
            end = start + editor.selectedRange.length
        } else {
            text = field.text ?? ""
            let selection = field.selectedTextRange
            start = selection.map { field.offset(from: field.beginningOfDocument, to: $0.start) } ?? text.utf16.count
            end = selection.map { field.offset(from: field.beginningOfDocument, to: $0.end) } ?? start
        }
        let marked = (textView?.markedTextRange ?? field.markedTextRange) != nil
        channel.invokeMethod("editingChanged", arguments: ["text": text, "selectionStart": start, "selectionEnd": end, "composing": marked])
    }

    @objc private func editingChanged() { emitValue() }
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool { !readOnly }
    func textFieldDidBeginEditing(_ textField: UITextField) { channel.invokeMethod("focusChanged", arguments: ["focused": true]); channel.invokeMethod("tap", arguments: nil) }
    func textFieldDidEndEditing(_ textField: UITextField) { channel.invokeMethod("focusChanged", arguments: ["focused": false]) }
    func textFieldDidChangeSelection(_ textField: UITextField) { emitValue() }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        channel.invokeMethod("submitted", arguments: ["text": textField.text ?? ""])
        if inputAction != "next" { textField.resignFirstResponder() }
        return true
    }
    func textViewDidChange(_ textView: UITextView) { emitValue() }
    func textViewDidChangeSelection(_ textView: UITextView) { emitValue() }
    func textViewDidBeginEditing(_ textView: UITextView) { channel.invokeMethod("focusChanged", arguments: ["focused": true]); channel.invokeMethod("tap", arguments: nil) }
    func textViewDidEndEditing(_ textView: UITextView) { channel.invokeMethod("focusChanged", arguments: ["focused": false]) }
}

class NativeTextFieldViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger; super.init() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        NativeTextFieldView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
}

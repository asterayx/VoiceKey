//
//  DraftCanvasView.swift
//  VoiceKeyboard
//
//  Editable text area within the keyboard extension where users preview,
//  edit, and confirm STT results before inserting into the host app.
//
//  Layout:
//  ┌──────────────────────────────────────────────────┐
//  │ [status indicator]  editable text area    [✓] [✕] │
//  └──────────────────────────────────────────────────┘
//

import UIKit

final class DraftCanvasView: UIView {

    // MARK: - Callbacks

    /// Called when user confirms — text should be inserted into host app.
    var onConfirm: ((String) -> Void)?
    /// Called when user cancels — discard draft.
    var onCancel: (() -> Void)?

    // MARK: - State

    /// The current text in the canvas.
    var text: String {
        get { textView.text ?? "" }
        set { textView.text = newValue }
    }

    /// The currently selected text in the canvas (for edit commands).
    var selectedText: String {
        guard let range = textView.selectedTextRange else { return "" }
        return textView.text(in: range) ?? ""
    }

    private var statusText: String = "" {
        didSet { statusLabel.text = statusText }
    }

    // MARK: - Subviews

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.showsVerticalScrollIndicator = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        return tv
    }()

    private lazy var confirmButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "checkmark.circle.fill")
        config.preferredSymbolConfigurationForImage = .init(pointSize: 20, weight: .medium)
        config.baseBackgroundColor = .systemGreen
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var cancelButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark.circle.fill")
        config.preferredSymbolConfigurationForImage = .init(pointSize: 18, weight: .regular)
        config.baseForegroundColor = .tertiaryLabel
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return btn
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setup() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 0.5

        addSubview(statusLabel)
        addSubview(textView)
        addSubview(confirmButton)
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),

            cancelButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            cancelButton.widthAnchor.constraint(equalToConstant: 28),
            cancelButton.heightAnchor.constraint(equalToConstant: 28),

            confirmButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -4),
            confirmButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            confirmButton.widthAnchor.constraint(equalToConstant: 32),
            confirmButton.heightAnchor.constraint(equalToConstant: 32),

            textView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    // MARK: - Public API

    func showWaiting() {
        statusText = "等待录音结果..."
        textView.text = ""
        confirmButton.isEnabled = false
    }

    func showRecording() {
        statusText = "● 录音中..."
        statusLabel.textColor = .systemRed
    }

    func showProcessing() {
        statusText = "处理中..."
        statusLabel.textColor = .systemOrange
    }

    func showResult(_ result: String) {
        statusText = "识别完成"
        statusLabel.textColor = .systemGreen
        textView.text = result
        confirmButton.isEnabled = true
    }

    func showPartial(committed: String, partial: String) {
        let attributed = NSMutableAttributedString(
            string: committed,
            attributes: [
                .foregroundColor: UIColor.label,
                .font: UIFont.systemFont(ofSize: 15)
            ]
        )
        if !partial.isEmpty {
            attributed.append(NSAttributedString(
                string: partial,
                attributes: [
                    .foregroundColor: UIColor.tertiaryLabel,
                    .font: UIFont.italicSystemFont(ofSize: 15)
                ]
            ))
        }
        textView.attributedText = attributed
    }

    func showError(_ message: String) {
        statusText = "错误: \(message)"
        statusLabel.textColor = .systemRed
    }

    func clear() {
        statusText = ""
        statusLabel.textColor = .secondaryLabel
        textView.text = ""
        textView.attributedText = nil
        confirmButton.isEnabled = false
    }

    // MARK: - Actions

    @objc private func confirmTapped() {
        let finalText = textView.text ?? ""
        guard !finalText.isEmpty else { return }
        onConfirm?(finalText)
    }

    @objc private func cancelTapped() {
        clear()
        onCancel?()
    }
}

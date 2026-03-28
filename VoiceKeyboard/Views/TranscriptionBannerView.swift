//
//  TranscriptionBannerView.swift
//  VoiceKeyboard
//
//  Created by Peng Chen on 28/3/26.
//
//  Displays real-time STT output at the top of the keyboard.
//
//  Layout:
//  ┌─────────────────────────────────────────── ✕ ──┐
//  │ committed text (dark)  partial text (gray...)   │
//  └────────────────────────────────────────────────┘
//
//  - committedText: final tokens accumulated so far (dark label colour)
//  - partialText:   current non-final tokens (tertiary label colour, italic)
//  - Tapping the × clears both and fires onClear.
//  - If text overflows it scrolls horizontally.
//

import UIKit

final class TranscriptionBannerView: UIView {

    // MARK: - Callbacks

    var onClear: (() -> Void)?

    // MARK: - State

    private(set) var committedText: String = ""
    private(set) var partialText: String = ""

    func update(committed: String, partial: String) {
        committedText = committed
        partialText   = partial
        refreshLabel()
    }

    func clear() {
        committedText = ""
        partialText   = ""
        refreshLabel()
    }

    // MARK: - Subviews

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator   = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let textLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.font = .systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var clearButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark.circle.fill")
        config.preferredSymbolConfigurationForImage = .init(pointSize: 16, weight: .regular)
        config.baseForegroundColor = .tertiaryLabel
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        return btn
    }()

    private let micIndicator: UIView = {
        let v = UIView()
        v.backgroundColor = .systemRed
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
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
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 0.5

        addSubview(micIndicator)
        addSubview(scrollView)
        addSubview(clearButton)
        scrollView.addSubview(textLabel)

        NSLayoutConstraint.activate([
            // Mic indicator — left edge
            micIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            micIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            micIndicator.widthAnchor.constraint(equalToConstant: 8),
            micIndicator.heightAnchor.constraint(equalToConstant: 8),

            // Clear button — right edge
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 36),
            clearButton.heightAnchor.constraint(equalToConstant: 44),

            // ScrollView between indicator and button
            scrollView.leadingAnchor.constraint(equalTo: micIndicator.trailingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            // TextLabel fills scrollView content
            textLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            textLabel.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            // Allow label to grow wider than scrollView (enables horizontal scroll)
            textLabel.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        startMicPulse()
    }

    // MARK: - Display

    private func refreshLabel() {
        let attributed = NSMutableAttributedString(
            string: committedText,
            attributes: [
                .foregroundColor: UIColor.label,
                .font: UIFont.systemFont(ofSize: 15, weight: .regular)
            ]
        )

        if !partialText.isEmpty {
            let partialAttr = NSAttributedString(
                string: partialText,
                attributes: [
                    .foregroundColor: UIColor.tertiaryLabel,
                    .font: UIFont.italicSystemFont(ofSize: 15)
                ]
            )
            attributed.append(partialAttr)
        }

        if attributed.length == 0 {
            let placeholder = NSAttributedString(
                string: "Listening...",
                attributes: [
                    .foregroundColor: UIColor.quaternaryLabel,
                    .font: UIFont.italicSystemFont(ofSize: 14)
                ]
            )
            textLabel.attributedText = placeholder
        } else {
            textLabel.attributedText = attributed
            // Auto-scroll to end so latest text is visible
            let rightEdge = CGPoint(
                x: max(0, scrollView.contentSize.width - scrollView.bounds.width),
                y: 0
            )
            scrollView.setContentOffset(rightEdge, animated: false)
        }
    }

    // MARK: - Mic pulse animation

    private func startMicPulse() {
        UIView.animate(
            withDuration: 0.8,
            delay: 0,
            options: [.autoreverse, .repeat, .allowUserInteraction],
            animations: { self.micIndicator.alpha = 0.2 }
        )
    }

    // MARK: - Actions

    @objc private func clearTapped() {
        clear()
        onClear?()
    }
}

//
//  CandidateBarView.swift
//  VoiceKeyboard
//
//  Created by Peng Chen on 28/3/26.
//
//  Horizontal scrollable bar showing Pinyin candidate characters.
//
//  Layout:
//  ┌──────────────────────────────────────────────────┐
//  │ [拼] [pin]  |  [你] [尼] [逆] [泥] [昵] [倪]    │
//  └──────────────────────────────────────────────────┘
//    pinyinLabel    candidate buttons (scrollable)
//

import UIKit

final class CandidateBarView: UIView {

    // MARK: - Callback

    /// Called when the user taps a candidate character.
    var onSelect: ((String) -> Void)?

    // MARK: - Subviews

    private let pinyinLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let divider: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator   = false
        sv.alwaysBounceHorizontal = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setup() {
        backgroundColor = .systemBackground
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 0.5

        addSubview(pinyinLabel)
        addSubview(divider)
        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            // Pinyin label — fixed width left column
            pinyinLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pinyinLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinyinLabel.widthAnchor.constraint(equalToConstant: 44),

            // Separator
            divider.leadingAnchor.constraint(equalTo: pinyinLabel.trailingAnchor, constant: 4),
            divider.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 0.5),
            divider.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.6),

            // Scrollable candidate area
            scrollView.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // StackView inside scrollView
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -4),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    // MARK: - Public API

    func setCandidates(_ candidates: [String], pinyin: String) {
        pinyinLabel.text = pinyin.isEmpty ? nil : pinyin

        // Remove old candidate buttons
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for character in candidates {
            let btn = makeCandidateButton(character)
            stackView.addArrangedSubview(btn)
        }

        // Reset scroll to start
        scrollView.setContentOffset(.zero, animated: false)
    }

    // MARK: - Private helpers

    private func makeCandidateButton(_ character: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = character
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)

        let btn = UIButton(configuration: config)
        btn.titleLabel?.font = .systemFont(ofSize: 18)
        btn.layer.cornerRadius = 6
        btn.layer.masksToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
        btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true

        btn.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)

        // Press highlight
        btn.configurationUpdateHandler = { button in
            var c = button.configuration
            c?.background.backgroundColor = button.isHighlighted
                ? UIColor.systemBlue.withAlphaComponent(0.15)
                : .clear
            button.configuration = c
        }

        return btn
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }

        // Brief highlight animation
        UIView.animate(withDuration: 0.1) {
            sender.alpha = 0.5
        } completion: { _ in
            UIView.animate(withDuration: 0.1) { sender.alpha = 1 }
        }

        onSelect?(title)
    }
}

//
//  TranscriptionBannerView.swift
//  VoiceKeyboard
//
//  Created by Peng Chen on 28/3/26.
//
//  Three-state transcription display above the keyboard:
//
//  .recording:   [●pulse] real-time STT text (scrolling) [✕]
//  .processing:  [spinner] "Processing..." progress bar   [✕]
//  .error:       [!] error message  [Retry] [Cancel]
//

import UIKit

// MARK: - Banner State

enum BannerState {
    case recording
    case processing
    case error(String)
}

final class TranscriptionBannerView: UIView {

    // MARK: - Callbacks

    var onClear: (() -> Void)?
    var onRetry: (() -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - State

    private(set) var committedText: String = ""
    private(set) var partialText: String = ""
    private(set) var bannerState: BannerState = .recording

    func update(committed: String, partial: String) {
        committedText = committed
        partialText   = partial
        refreshDisplay()
    }

    func clear() {
        committedText = ""
        partialText   = ""
        refreshDisplay()
    }

    func setState(_ state: BannerState) {
        bannerState = state
        refreshDisplay()
    }

    /// Set processing progress (0.0–1.0).
    func setProgress(_ progress: Float) {
        progressBar.setProgress(progress, animated: true)
    }

    // MARK: - Subviews

    // Recording state views
    private let micIndicator: UIView = {
        let v = UIView()
        v.backgroundColor = .systemRed
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

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

    // Processing state views
    private let processingContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private let spinnerView: UIActivityIndicatorView = {
        let v = UIActivityIndicatorView(style: .medium)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.hidesWhenStopped = true
        return v
    }()

    private let processingLabel: UILabel = {
        let label = UILabel()
        label.text = "正在处理..."
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .default)
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.tintColor = .systemBlue
        pv.progress = 0
        return pv
    }()

    // Error state views
    private let errorContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .systemRed
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var retryButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "重试"
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        let btn = UIButton(configuration: config)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var cancelButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "取消"
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        let btn = UIButton(configuration: config)
        btn.titleLabel?.font = .systemFont(ofSize: 13)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return btn
    }()

    // Recording state container
    private let recordingContainer: UIView = {
        let v = UIView()
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

        // --- Recording container ---
        addSubview(recordingContainer)
        recordingContainer.addSubview(micIndicator)
        recordingContainer.addSubview(scrollView)
        recordingContainer.addSubview(clearButton)
        scrollView.addSubview(textLabel)

        // --- Processing container ---
        addSubview(processingContainer)
        processingContainer.addSubview(spinnerView)
        processingContainer.addSubview(processingLabel)
        processingContainer.addSubview(progressBar)

        // --- Error container ---
        addSubview(errorContainer)
        errorContainer.addSubview(errorLabel)
        errorContainer.addSubview(retryButton)
        errorContainer.addSubview(cancelButton)

        // Container constraints (fill parent)
        for container in [recordingContainer, processingContainer, errorContainer] {
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: leadingAnchor),
                container.trailingAnchor.constraint(equalTo: trailingAnchor),
                container.topAnchor.constraint(equalTo: topAnchor),
                container.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        // Recording layout
        NSLayoutConstraint.activate([
            micIndicator.leadingAnchor.constraint(equalTo: recordingContainer.leadingAnchor, constant: 10),
            micIndicator.centerYAnchor.constraint(equalTo: recordingContainer.centerYAnchor),
            micIndicator.widthAnchor.constraint(equalToConstant: 8),
            micIndicator.heightAnchor.constraint(equalToConstant: 8),

            clearButton.trailingAnchor.constraint(equalTo: recordingContainer.trailingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: recordingContainer.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 36),
            clearButton.heightAnchor.constraint(equalToConstant: 44),

            scrollView.leadingAnchor.constraint(equalTo: micIndicator.trailingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: recordingContainer.topAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: recordingContainer.bottomAnchor, constant: -6),

            textLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            textLabel.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            textLabel.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        // Processing layout
        NSLayoutConstraint.activate([
            spinnerView.leadingAnchor.constraint(equalTo: processingContainer.leadingAnchor, constant: 12),
            spinnerView.centerYAnchor.constraint(equalTo: processingContainer.centerYAnchor, constant: -8),

            processingLabel.leadingAnchor.constraint(equalTo: spinnerView.trailingAnchor, constant: 8),
            processingLabel.centerYAnchor.constraint(equalTo: spinnerView.centerYAnchor),

            progressBar.leadingAnchor.constraint(equalTo: processingContainer.leadingAnchor, constant: 12),
            progressBar.trailingAnchor.constraint(equalTo: processingContainer.trailingAnchor, constant: -12),
            progressBar.bottomAnchor.constraint(equalTo: processingContainer.bottomAnchor, constant: -8),
        ])

        // Error layout
        NSLayoutConstraint.activate([
            errorLabel.leadingAnchor.constraint(equalTo: errorContainer.leadingAnchor, constant: 12),
            errorLabel.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: retryButton.leadingAnchor, constant: -8),

            cancelButton.trailingAnchor.constraint(equalTo: errorContainer.trailingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor),

            retryButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -4),
            retryButton.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor),
        ])

        startMicPulse()
    }

    // MARK: - Display

    private func refreshDisplay() {
        switch bannerState {
        case .recording:
            recordingContainer.isHidden = false
            processingContainer.isHidden = true
            errorContainer.isHidden = true
            spinnerView.stopAnimating()
            refreshLabel()

        case .processing:
            recordingContainer.isHidden = true
            processingContainer.isHidden = false
            errorContainer.isHidden = true
            spinnerView.startAnimating()
            progressBar.progress = 0

        case .error(let message):
            recordingContainer.isHidden = true
            processingContainer.isHidden = true
            errorContainer.isHidden = false
            spinnerView.stopAnimating()
            errorLabel.text = message
        }
    }

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
            DispatchQueue.main.async {
                let rightEdge = CGPoint(
                    x: max(0, self.scrollView.contentSize.width - self.scrollView.bounds.width),
                    y: 0
                )
                self.scrollView.setContentOffset(rightEdge, animated: false)
            }
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

    @objc private func retryTapped() {
        onRetry?()
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}

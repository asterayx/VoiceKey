//
//  KeyboardView.swift
//  VoiceKeyboard
//
//  Created by Peng Chen on 28/3/26.
//
//  Full QWERTY keyboard supporting English and Chinese Pinyin input.
//
//  Key rows:
//  Row 0:  q  w  e  r  t  y  u  i  o  p
//  Row 1:   a  s  d  f  g  h  j  k  l
//  Row 2:  ⇧  z  x  c  v  b  n  m  ⌫
//  Row 3:  🌐  123  中/EN  ──space──  🎤  ⏎
//
//  In Chinese mode, typed letters accumulate in a Pinyin buffer and
//  are shown in CandidateBarView. Selecting a candidate clears the buffer.
//

import UIKit

// MARK: - Key model

enum KeyboardKey: Equatable {
    case letter(String)      // "a"–"z"
    case digit(String)       // "0"–"9" (number row, future)
    case space
    case `return`
    case delete
    case shift
    case nextKeyboard
    case changeMode          // 123 toggle (reserved for M3)
    case switchLanguage      // 中/EN
    case mic
}

enum KeyboardMode {
    case english
    case chinesePinyin
}

// MARK: - Delegate

protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didTap key: KeyboardKey)
}

// MARK: - KeyboardView

final class KeyboardView: UIView {

    weak var delegate: KeyboardViewDelegate?

    // MARK: - State

    var mode: KeyboardMode = .english {
        didSet { if oldValue != mode { refreshLanguageButton() } }
    }

    var isShifted: Bool = false {
        didSet { updateKeyLabels() }
    }

    var isCapsLocked: Bool = false {
        didSet { updateShiftButton() }
    }

    var isRecording: Bool = false {
        didSet { updateMicButton() }
    }

    var needsInputModeSwitchKey: Bool = false {
        didSet { nextKeyboardButton.isHidden = !needsInputModeSwitchKey }
    }

    // MARK: - Rows layout

    private static let row0Keys: [String] = ["q","w","e","r","t","y","u","i","o","p"]
    private static let row1Keys: [String] = ["a","s","d","f","g","h","j","k","l"]
    private static let row2Letters: [String] = ["z","x","c","v","b","n","m"]

    // MARK: - Button references

    private var letterButtons: [String: UIButton] = [:]   // keyed by lowercase letter
    private var shiftButton:   UIButton!
    private var deleteButton:  UIButton!
    private var spaceButton:   UIButton!
    private var returnButton:  UIButton!
    private var micButton:     UIButton!
    private var nextKeyboardButton: UIButton!
    private var langButton:    UIButton!

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func buildLayout() {
        backgroundColor = .systemGroupedBackground

        let outerStack = UIStackView()
        outerStack.axis = .vertical
        outerStack.spacing = 8
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)

        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            outerStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        outerStack.addArrangedSubview(makeRow0())
        outerStack.addArrangedSubview(makeRow1())
        outerStack.addArrangedSubview(makeRow2())
        outerStack.addArrangedSubview(makeRow3())
    }

    // Row 0: q–p  (10 equal keys)
    private func makeRow0() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually
        for letter in Self.row0Keys {
            let btn = makeLetterButton(letter)
            letterButtons[letter] = btn
            stack.addArrangedSubview(btn)
        }
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return stack
    }

    // Row 1: a–l  (9 keys, centred with spacers)
    private func makeRow1() -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        for letter in Self.row1Keys {
            let btn = makeLetterButton(letter)
            letterButtons[letter] = btn
            stack.addArrangedSubview(btn)
        }
        container.addSubview(stack)
        container.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Centred with ~5% margin on each side
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.92),
        ])
        return container
    }

    // Row 2: ⇧  z–m  ⌫
    private func makeRow2() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Shift button
        shiftButton = makeActionButton(symbol: "shift", label: "⇧", wide: true)
        shiftButton.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
        stack.addArrangedSubview(shiftButton)

        // Letter keys (fill equally in the middle)
        let letterStack = UIStackView()
        letterStack.axis = .horizontal
        letterStack.spacing = 6
        letterStack.distribution = .fillEqually
        for letter in Self.row2Letters {
            let btn = makeLetterButton(letter)
            letterButtons[letter] = btn
            letterStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(letterStack)

        // Delete button
        deleteButton = makeActionButton(symbol: "delete.left", label: "⌫", wide: true)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        // Long-press for continuous delete
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        deleteButton.addGestureRecognizer(longPress)
        stack.addArrangedSubview(deleteButton)

        // Shift and delete take the same width; letter stack fills the rest
        shiftButton.widthAnchor.constraint(equalTo: deleteButton.widthAnchor).isActive = true

        return stack
    }

    // Row 3: 🌐  123  中/EN  ──space──  🎤  ⏎
    private func makeRow3() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Next keyboard (globe)
        nextKeyboardButton = makeActionButton(symbol: "globe", label: nil, wide: false)
        nextKeyboardButton.isHidden = true    // shown only when needsInputModeSwitchKey
        stack.addArrangedSubview(nextKeyboardButton)

        // 123 (placeholder for M3)
        let numBtn = makeActionButton(symbol: nil, label: "123", wide: false)
        numBtn.addTarget(self, action: #selector(numTapped), for: .touchUpInside)
        stack.addArrangedSubview(numBtn)

        // Language switch
        langButton = makeActionButton(symbol: nil, label: "中", wide: false)
        langButton.addTarget(self, action: #selector(langTapped), for: .touchUpInside)
        stack.addArrangedSubview(langButton)

        // Space (flexible)
        spaceButton = UIButton(type: .system)
        spaceButton.setTitle("space", for: .normal)
        spaceButton.titleLabel?.font = .systemFont(ofSize: 16)
        spaceButton.tintColor = .label
        spaceButton.backgroundColor = .white
        spaceButton.layer.cornerRadius = 5
        spaceButton.layer.shadowColor = UIColor.black.cgColor
        spaceButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        spaceButton.layer.shadowOpacity = 0.3
        spaceButton.layer.shadowRadius = 0
        spaceButton.translatesAutoresizingMaskIntoConstraints = false
        spaceButton.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        stack.addArrangedSubview(spaceButton)

        // Mic
        micButton = makeActionButton(symbol: "mic.fill", label: nil, wide: false)
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        stack.addArrangedSubview(micButton)

        // Return
        returnButton = makeActionButton(symbol: nil, label: "return", wide: false)
        returnButton.titleLabel?.font = .systemFont(ofSize: 14)
        returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        stack.addArrangedSubview(returnButton)

        // Width constraints: fixed-width for action keys, flexible space
        let fixedWidth: CGFloat = 44
        nextKeyboardButton.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        numBtn.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        langButton.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        micButton.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        returnButton.widthAnchor.constraint(equalToConstant: 72).isActive = true

        return stack
    }

    // MARK: - Button factories

    private func makeLetterButton(_ letter: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = letter.uppercased()
        config.baseBackgroundColor = .white
        config.baseForegroundColor = .label
        config.background.cornerRadius = 5
        config.background.shadowColor = .black
        config.background.shadowRadius = 0

        let btn = UIButton(configuration: config)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 1)
        btn.layer.shadowOpacity = 0.3
        btn.layer.shadowRadius = 0

        btn.addTarget(self, action: #selector(letterTapped(_:)), for: .touchUpInside)

        // Store the lowercase letter as accessibilityIdentifier for lookup
        btn.accessibilityIdentifier = letter

        // Highlight feedback
        btn.configurationUpdateHandler = { button in
            var c = button.configuration
            c?.baseBackgroundColor = button.isHighlighted ? UIColor.systemGray4 : .white
            button.configuration = c
        }

        return btn
    }

    private func makeActionButton(symbol: String?, label: String?, wide: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIColor(white: 0.78, alpha: 1)
        config.baseForegroundColor = .label
        config.background.cornerRadius = 5

        if let symbol {
            config.image = UIImage(systemName: symbol)
            config.preferredSymbolConfigurationForImage = .init(pointSize: 15, weight: .regular)
        } else if let label {
            config.title = label
        }

        let btn = UIButton(configuration: config)
        btn.titleLabel?.font = .systemFont(ofSize: 15)
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 1)
        btn.layer.shadowOpacity = 0.3
        btn.layer.shadowRadius = 0

        btn.configurationUpdateHandler = { button in
            var c = button.configuration
            c?.baseBackgroundColor = button.isHighlighted
                ? UIColor(white: 0.60, alpha: 1)
                : UIColor(white: 0.78, alpha: 1)
            button.configuration = c
        }
        return btn
    }

    // MARK: - State updates

    private func updateKeyLabels() {
        for (letter, btn) in letterButtons {
            let title = (isShifted || isCapsLocked) ? letter.uppercased() : letter
            var config = btn.configuration
            config?.title = title
            btn.configuration = config
        }
        updateShiftButton()
    }

    private func updateShiftButton() {
        let symbolName: String
        if isCapsLocked { symbolName = "capslock.fill" }
        else if isShifted { symbolName = "shift.fill" }
        else { symbolName = "shift" }
        var config = shiftButton.configuration
        config?.image = UIImage(systemName: symbolName)
        shiftButton.configuration = config
        shiftButton.tintColor = isCapsLocked ? .systemBlue : .label
    }

    private func updateMicButton() {
        let symbolName = isRecording ? "stop.circle.fill" : "mic.fill"
        var config = micButton.configuration
        config?.image = UIImage(systemName: symbolName)
        config?.baseForegroundColor = isRecording ? .systemRed : .label
        micButton.configuration = config
    }

    private func refreshLanguageButton() {
        var config = langButton.configuration
        config?.title = (mode == .english) ? "中" : "EN"
        langButton.configuration = config
    }

    // MARK: - Actions

    @objc private func letterTapped(_ sender: UIButton) {
        guard let letter = sender.accessibilityIdentifier else { return }
        let output = (isShifted || isCapsLocked) ? letter.uppercased() : letter
        if isShifted && !isCapsLocked {
            isShifted = false
        }
        delegate?.keyboardView(self, didTap: .letter(output))
    }

    @objc private func shiftTapped() {
        if isCapsLocked {
            isCapsLocked = false
            isShifted = false
        } else if isShifted {
            isCapsLocked = true
        } else {
            isShifted = true
        }
    }

    @objc private func deleteTapped() {
        delegate?.keyboardView(self, didTap: .delete)
    }

    private var deleteTimer: Timer?

    @objc private func deleteLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.delegate?.keyboardView(self!, didTap: .delete)
            }
        case .ended, .cancelled:
            deleteTimer?.invalidate()
            deleteTimer = nil
        default: break
        }
    }

    @objc private func spaceTapped() {
        delegate?.keyboardView(self, didTap: .space)
    }

    @objc private func returnTapped() {
        delegate?.keyboardView(self, didTap: .return)
    }

    @objc private func micTapped() {
        delegate?.keyboardView(self, didTap: .mic)
    }

    @objc private func langTapped() {
        delegate?.keyboardView(self, didTap: .switchLanguage)
    }

    @objc private func numTapped() {
        delegate?.keyboardView(self, didTap: .changeMode)
    }
}

//
//  KeyboardView.swift
//  VoiceKeyboard
//
//  Created by Peng Chen on 28/3/26.
//
//  Full keyboard supporting English, Chinese Pinyin, number, and symbol modes.
//
//  Letter mode:
//  Row 0:  q  w  e  r  t  y  u  i  o  p
//  Row 1:   a  s  d  f  g  h  j  k  l
//  Row 2:  ⇧  z  x  c  v  b  n  m  ⌫
//  Row 3:  🌐  123  Lang  ──space──  ✏️  🎤  ⏎
//
//  Number mode:
//  Row 0:  1  2  3  4  5  6  7  8  9  0
//  Row 1:  -  /  :  ;  (  )  $  &  @  "
//  Row 2:  #+=  .  ,  ?  !  '  ⌫
//  Row 3:  🌐  ABC  Lang  ──space──  ✏️  🎤  ⏎
//
//  Symbol mode:
//  Row 0:  [  ]  {  }  #  %  ^  *  +  =
//  Row 1:  _  \  |  ~  <  >  €  £  ¥  •
//  Row 2:  123  .  ,  ?  !  '  ⌫
//  Row 3:  🌐  ABC  Lang  ──space──  ✏️  🎤  ⏎
//

import UIKit

// MARK: - Key model

enum KeyboardKey: Equatable {
    case letter(String)
    case digit(String)
    case symbol(String)
    case space
    case `return`
    case delete
    case shift
    case nextKeyboard
    case changeMode       // 123 / ABC / #+= toggle
    case switchLanguage
    case mic
    case edit             // ✏️ edit mode button
}

enum KeyboardMode: Equatable {
    case english
    case chinesePinyin
    case numbers
    case symbols
}

// MARK: - Mic visual state

enum MicVisualState {
    case idle
    case recording
    case processing
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
        didSet { if oldValue != mode { rebuildKeyboard() } }
    }

    var isShifted: Bool = false {
        didSet { updateKeyLabels() }
    }

    var isCapsLocked: Bool = false {
        didSet { updateShiftButton() }
    }

    var micState: MicVisualState = .idle {
        didSet { updateMicButton() }
    }

    /// Kept for backward compat — maps to micState
    var isRecording: Bool {
        get { micState == .recording }
        set { micState = newValue ? .recording : .idle }
    }

    var needsInputModeSwitchKey: Bool = false {
        didSet { nextKeyboardButton?.isHidden = !needsInputModeSwitchKey }
    }

    /// Short label for the current language (displayed on lang button).
    var currentLanguageLabel: String = "中" {
        didSet { refreshLanguageButton() }
    }

    // MARK: - Layout data

    private static let row0Letters = ["q","w","e","r","t","y","u","i","o","p"]
    private static let row1Letters = ["a","s","d","f","g","h","j","k","l"]
    private static let row2Letters = ["z","x","c","v","b","n","m"]

    private static let row0Numbers = ["1","2","3","4","5","6","7","8","9","0"]
    private static let row1Numbers = ["-","/",":",";","(",")","\u{0024}","&","@","\""]
    private static let row2Numbers = [".",",","?","!","'"]

    private static let row0Symbols = ["[","]","{","}","#","%","^","*","+","="]
    private static let row1Symbols = ["_","\\","|","~","<",">","\u{20AC}","\u{00A3}","\u{00A5}","\u{2022}"]
    private static let row2Symbols = [".",",","?","!","'"]

    // MARK: - Button references

    private var letterButtons: [String: UIButton] = [:]
    private var shiftButton: UIButton?
    private var deleteButton: UIButton?
    private var spaceButton: UIButton?
    private var returnButton: UIButton?
    private var micButton: UIButton?
    private var nextKeyboardButton: UIButton?
    private var langButton: UIButton?
    private var modeButton: UIButton?
    private var editButton: UIButton?

    private var outerStack: UIStackView?

    /// The mode to return to when leaving numbers/symbols
    private var previousLetterMode: KeyboardMode = .english

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Full rebuild

    private func rebuildKeyboard() {
        outerStack?.removeFromSuperview()
        letterButtons.removeAll()
        shiftButton = nil
        deleteButton = nil
        spaceButton = nil
        returnButton = nil
        micButton = nil
        nextKeyboardButton = nil
        langButton = nil
        modeButton = nil
        editButton = nil
        deleteTimer?.invalidate()
        deleteTimer = nil

        buildLayout()
    }

    private func buildLayout() {
        backgroundColor = .systemGroupedBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        outerStack = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        switch mode {
        case .english, .chinesePinyin:
            stack.addArrangedSubview(makeLetterRow(Self.row0Letters))
            stack.addArrangedSubview(makeLetterRow(Self.row1Letters, centered: true))
            stack.addArrangedSubview(makeRow2Letters())
            stack.addArrangedSubview(makeRow3())
        case .numbers:
            stack.addArrangedSubview(makeCharRow(Self.row0Numbers))
            stack.addArrangedSubview(makeCharRow(Self.row1Numbers))
            stack.addArrangedSubview(makeRow2NumSym(Self.row2Numbers, toggleLabel: "#+="))
            stack.addArrangedSubview(makeRow3())
        case .symbols:
            stack.addArrangedSubview(makeCharRow(Self.row0Symbols))
            stack.addArrangedSubview(makeCharRow(Self.row1Symbols))
            stack.addArrangedSubview(makeRow2NumSym(Self.row2Symbols, toggleLabel: "123"))
            stack.addArrangedSubview(makeRow3())
        }
    }

    // MARK: - Letter rows

    private func makeLetterRow(_ letters: [String], centered: Bool = false) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually

        for letter in letters {
            let btn = makeLetterButton(letter)
            letterButtons[letter] = btn
            stack.addArrangedSubview(btn)
        }
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true

        if centered {
            let container = UIView()
            stack.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(stack)
            container.heightAnchor.constraint(equalToConstant: 44).isActive = true
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                stack.topAnchor.constraint(equalTo: container.topAnchor),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                stack.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.92),
            ])
            return container
        }
        return stack
    }

    // Row 2 for letter modes: ⇧ z–m ⌫
    private func makeRow2Letters() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let shift = makeActionButton(symbol: "shift", label: nil, wide: true)
        shift.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
        shiftButton = shift
        stack.addArrangedSubview(shift)

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

        let del = makeDeleteButton()
        stack.addArrangedSubview(del)

        shift.widthAnchor.constraint(equalTo: del.widthAnchor).isActive = true
        return stack
    }

    // MARK: - Number/Symbol rows

    private func makeCharRow(_ chars: [String]) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true

        for ch in chars {
            let btn = makeCharButton(ch)
            stack.addArrangedSubview(btn)
        }
        return stack
    }

    // Row 2 for number/symbol: toggle + chars + ⌫
    private func makeRow2NumSym(_ chars: [String], toggleLabel: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let toggle = makeActionButton(symbol: nil, label: toggleLabel, wide: true)
        toggle.addTarget(self, action: #selector(numSymToggleTapped), for: .touchUpInside)
        stack.addArrangedSubview(toggle)

        let charStack = UIStackView()
        charStack.axis = .horizontal
        charStack.spacing = 6
        charStack.distribution = .fillEqually
        for ch in chars {
            let btn = makeCharButton(ch)
            charStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(charStack)

        let del = makeDeleteButton()
        stack.addArrangedSubview(del)

        toggle.widthAnchor.constraint(equalTo: del.widthAnchor).isActive = true
        return stack
    }

    // MARK: - Row 3 (shared): 🌐 | 123/ABC | Lang | space | ✏️ | 🎤 | ⏎

    private func makeRow3() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Next keyboard (globe)
        let globe = makeActionButton(symbol: "globe", label: nil, wide: false)
        globe.isHidden = !needsInputModeSwitchKey
        nextKeyboardButton = globe
        stack.addArrangedSubview(globe)

        // Mode toggle (123 / ABC)
        let modeLabel: String
        switch mode {
        case .english, .chinesePinyin: modeLabel = "123"
        case .numbers, .symbols:       modeLabel = "ABC"
        }
        let modeBtn = makeActionButton(symbol: nil, label: modeLabel, wide: false)
        modeBtn.addTarget(self, action: #selector(modeTapped), for: .touchUpInside)
        modeButton = modeBtn
        stack.addArrangedSubview(modeBtn)

        // Language
        let lang = makeActionButton(symbol: nil, label: currentLanguageLabel, wide: false)
        lang.addTarget(self, action: #selector(langTapped), for: .touchUpInside)
        langButton = lang
        stack.addArrangedSubview(lang)

        // Space (flexible)
        let space = UIButton(type: .system)
        space.setTitle("space", for: .normal)
        space.titleLabel?.font = .systemFont(ofSize: 16)
        space.tintColor = .label
        space.backgroundColor = .white
        space.layer.cornerRadius = 5
        space.layer.shadowColor = UIColor.black.cgColor
        space.layer.shadowOffset = CGSize(width: 0, height: 1)
        space.layer.shadowOpacity = 0.3
        space.layer.shadowRadius = 0
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        spaceButton = space
        stack.addArrangedSubview(space)

        // Edit button
        let edit = makeActionButton(symbol: "pencil", label: nil, wide: false)
        edit.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        editButton = edit
        stack.addArrangedSubview(edit)

        // Mic
        let mic = makeActionButton(symbol: "mic.fill", label: nil, wide: false)
        mic.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micButton = mic
        updateMicButton()
        stack.addArrangedSubview(mic)

        // Return
        let ret = makeActionButton(symbol: nil, label: "return", wide: false)
        ret.titleLabel?.font = .systemFont(ofSize: 14)
        ret.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        returnButton = ret
        stack.addArrangedSubview(ret)

        // Widths
        let fixedWidth: CGFloat = 40
        globe.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        modeBtn.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        lang.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        edit.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        mic.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        ret.widthAnchor.constraint(equalToConstant: 64).isActive = true

        return stack
    }

    // MARK: - Button factories

    private func makeLetterButton(_ letter: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        let display = (isShifted || isCapsLocked) ? letter.uppercased() : letter
        config.title = display
        config.baseBackgroundColor = .white
        config.baseForegroundColor = .black
        config.background.cornerRadius = 5

        let btn = UIButton(configuration: config)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 1)
        btn.layer.shadowOpacity = 0.3
        btn.layer.shadowRadius = 0
        btn.accessibilityIdentifier = letter
        btn.addTarget(self, action: #selector(letterTapped(_:)), for: .touchUpInside)
        btn.configurationUpdateHandler = { button in
            var c = button.configuration
            c?.baseBackgroundColor = button.isHighlighted ? .systemGray4 : .white
            button.configuration = c
        }
        return btn
    }

    private func makeCharButton(_ char: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = char
        config.baseBackgroundColor = .white
        config.baseForegroundColor = .black
        config.background.cornerRadius = 5

        let btn = UIButton(configuration: config)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 1)
        btn.layer.shadowOpacity = 0.3
        btn.layer.shadowRadius = 0
        btn.addTarget(self, action: #selector(charTapped(_:)), for: .touchUpInside)
        btn.configurationUpdateHandler = { button in
            var c = button.configuration
            c?.baseBackgroundColor = button.isHighlighted ? .systemGray4 : .white
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

    private func makeDeleteButton() -> UIButton {
        let del = makeActionButton(symbol: "delete.left", label: nil, wide: true)
        del.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        del.addGestureRecognizer(longPress)
        deleteButton = del
        return del
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
        guard let shiftButton else { return }
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
        guard let micButton else { return }
        let symbolName: String
        let color: UIColor
        switch micState {
        case .idle:
            symbolName = "mic.fill"
            color = .label
        case .recording:
            symbolName = "stop.circle.fill"
            color = .systemRed
        case .processing:
            symbolName = "hourglass"
            color = .systemOrange
        }
        var config = micButton.configuration
        config?.image = UIImage(systemName: symbolName)
        config?.baseForegroundColor = color
        micButton.configuration = config
    }

    private func refreshLanguageButton() {
        guard let langButton else { return }
        var config = langButton.configuration
        config?.title = currentLanguageLabel
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

    @objc private func charTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) ?? sender.configuration?.title else { return }
        // Numbers are digits, others are symbols
        if title.count == 1, let scalar = title.unicodeScalars.first,
           CharacterSet.decimalDigits.contains(scalar) {
            delegate?.keyboardView(self, didTap: .digit(title))
        } else {
            delegate?.keyboardView(self, didTap: .symbol(title))
        }
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
                guard let self else { return }
                self.delegate?.keyboardView(self, didTap: .delete)
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

    @objc private func editTapped() {
        delegate?.keyboardView(self, didTap: .edit)
    }

    @objc private func langTapped() {
        delegate?.keyboardView(self, didTap: .switchLanguage)
    }

    @objc private func modeTapped() {
        switch mode {
        case .english, .chinesePinyin:
            previousLetterMode = mode
            mode = .numbers
        case .numbers, .symbols:
            mode = previousLetterMode
        }
        delegate?.keyboardView(self, didTap: .changeMode)
    }

    @objc private func numSymToggleTapped() {
        mode = (mode == .numbers) ? .symbols : .numbers
    }
}

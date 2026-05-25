import AppKit
import SwiftUI

struct CompressionLevelSlider: NSViewRepresentable {
    @Binding var level: Int

    func makeCoordinator() -> Coordinator { Coordinator(level: $level) }

    func makeNSView(context: Context) -> TickSliderView {
        let view = TickSliderView()
        view.slider.target = context.coordinator
        view.slider.action = #selector(Coordinator.sliderChanged(_:))
        view.slider.doubleValue = Double(level)
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: TickSliderView, context: Context) {
        view.slider.doubleValue = Double(level)
        view.updateLabelColors(activeIndex: level - 1)
    }

    final class Coordinator: NSObject {
        @Binding var level: Int
        weak var view: TickSliderView?

        init(level: Binding<Int>) { self._level = level }

        @MainActor @objc func sliderChanged(_ sender: NSSlider) {
            level = sender.integerValue
            view?.updateLabelColors(activeIndex: level - 1)
        }
    }
}

final class TickSliderView: NSView {
    let slider: NSSlider
    private let leftNumber: NSTextField
    private let rightNumber: NSTextField
    private let leftHint: NSTextField
    private let rightHint: NSTextField

    override init(frame: NSRect) {
        slider = NSSlider(value: 3, minValue: 1, maxValue: 6,
                          target: nil, action: nil)
        slider.numberOfTickMarks = 6
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.controlSize = .regular
        slider.translatesAutoresizingMaskIntoConstraints = false

        leftNumber = Self.makeLabel("1", size: 10)
        rightNumber = Self.makeLabel("6", size: 10, alignment: .right)
        leftHint = Self.makeLabel("Best Quality", size: 9)
        rightHint = Self.makeLabel("Lowest Quality", size: 9, alignment: .right)

        super.init(frame: frame)

        addSubview(slider)
        addSubview(leftNumber)
        addSubview(rightNumber)
        addSubview(leftHint)
        addSubview(rightHint)

        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            slider.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 38)
    }

    override func layout() {
        super.layout()

        // Numbers flanking the slider at mid-height
        let sliderFrame = slider.frame
        let numY = sliderFrame.midY - 6

        leftNumber.frame = NSRect(x: 0, y: numY, width: 18, height: 12)
        rightNumber.frame = NSRect(x: bounds.width - 18, y: numY, width: 18, height: 12)

        // Hints just below the slider
        leftHint.sizeToFit()
        leftHint.frame.origin = NSPoint(x: leftNumber.frame.minX, y: sliderFrame.minY - 14)

        rightHint.sizeToFit()
        rightHint.frame.origin = NSPoint(x: rightNumber.frame.maxX - rightHint.frame.width, y: sliderFrame.minY - 14)
    }

    private static func makeLabel(_ text: String, size: CGFloat, alignment: NSTextAlignment = .left) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = .tertiaryLabelColor
        label.alignment = alignment
        label.usesSingleLineMode = true
        label.lineBreakMode = .byClipping
        return label
    }

    func updateLabelColors(activeIndex: Int) { }
}

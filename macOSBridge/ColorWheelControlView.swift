import Foundation
import AppKit

class ColorWheelControlView: NSView {
    private var selectedColor: NSColor = .white
    private var brightness: CGFloat = 1.0
    var onColorChanged: ((NSColor) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?
    private var isDragging = false
    private var indicatorLayer: CAShapeLayer?
    private var currentHue: CGFloat = 0.0
    private var currentSaturation: CGFloat = 1.0
    private var colorWheelLayer: CAGradientLayer?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupColorWheel()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupColorWheel()
    }
    
    private func setupColorWheel() {
        wantsLayer = true
        
        // Create circular color wheel
        let wheelLayer = CAShapeLayer()
        let radius = min(bounds.width, bounds.height)/2 - 3
        let center = CGPoint(x: bounds.width/2, y: bounds.height/2)
        
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        wheelLayer.path = path
        
        // Create gradient for color wheel
        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        
        // Create hue gradient with more colors for better resolution
        let hueColors = stride(from: 0, to: 360, by: 5).map { hue in
            NSColor(hue: CGFloat(hue) / 360.0, saturation: 1.0, brightness: 1.0, alpha: 1.0).cgColor
        }
        gradient.colors = hueColors
        gradient.mask = wheelLayer
        
        layer?.addSublayer(gradient)
        self.colorWheelLayer = gradient
        
        // Create color indicator
        createColorIndicator()
        
        // Apply the radial overlay after everything is set up
        DispatchQueue.main.async { [weak self] in
            self?.updateColorWheelAppearance()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        // Don't set isDragging yet - wait for actual movement
        let location = convert(event.locationInWindow, from: nil)
        updateIndicatorPositionFromLocation(location)
        updateColorFromLocation(location)
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Set isDragging on first drag event
        if !isDragging {
            isDragging = true
            onDragStarted?()
        }
        
        let location = convert(event.locationInWindow, from: nil)
        // Update indicator immediately for smooth visual feedback
        updateIndicatorPositionFromLocation(location)
        // Update color immediately for immediate visual feedback
        updateColorFromLocation(location)
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        onDragEnded?()
    }
    
    private func updateColorFromLocation(_ location: NSPoint) {
        let center = CGPoint(x: bounds.width/2, y: bounds.height/2)
        let radius = min(bounds.width, bounds.height)/2 - 3
        
        // Calculate distance from center
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance <= radius {
            // Calculate hue (angle)
            let angle = atan2(dy, dx) * 180 / .pi
            let hue = (angle + 360).truncatingRemainder(dividingBy: 360)
            
            // Calculate saturation (distance from center, normalized)
            let saturation = min(1.0, distance / radius)
            
            // Update current values
            currentHue = hue / 360.0
            currentSaturation = saturation
            
            // Update color
            selectedColor = NSColor(hue: currentHue, saturation: currentSaturation, brightness: brightness, alpha: 1.0)
            
            // Only update visual appearance when not dragging to avoid lag
            if !isDragging {
                updateColorWheelAppearance()
            }
            
            // Only log occasionally to avoid performance impact
            if isDragging && Int(hue) % 10 == 0 {
                // Removed debug print for cleaner console
            }
            
            // Notify delegate (this may trigger HomeKit updates)
            onColorChanged?(selectedColor)
        }
    }
    
    private func updateColorWheelAppearance() {
        // Update the color wheel to show a radial gradient from white center to saturated edges
        guard let gradient = colorWheelLayer else { return }
        
        // Create a radial overlay that goes from white in center to transparent at edges
        let overlayLayer = CAShapeLayer()
        let radius = min(bounds.width, bounds.height)/2 - 3
        let center = CGPoint(x: bounds.width/2, y: bounds.height/2)
        
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        overlayLayer.path = path
        
        // Create a radial gradient overlay from white center to transparent edges
        let overlayGradient = CAGradientLayer()
        overlayGradient.frame = bounds
        overlayGradient.type = .radial
        overlayGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        overlayGradient.endPoint = CGPoint(x: 1, y: 1)
        
        // Create a completely smooth gradient from white center to transparent edges
        let colors = stride(from: 0.0, to: 1.0, by: 0.02).map { progress in
            // Use a stronger curve: more white in center, more pronounced effect
            let alpha = pow(1.0 - progress, 1.1) // Stronger curve for more pronounced white center
            return NSColor(white: 1.0, alpha: alpha).cgColor
        }
        
        overlayGradient.colors = colors
        overlayGradient.locations = stride(from: 0.0, to: 1.0, by: 0.02).map { NSNumber(value: $0) }
        overlayGradient.mask = overlayLayer
        
        // Remove any existing overlay but keep the gradient and indicator
        layer?.sublayers?.removeAll { sublayer in
            // Keep the main gradient and indicator, remove only overlays
            return sublayer != gradient && sublayer != indicatorLayer && sublayer != overlayGradient
        }
        layer?.addSublayer(overlayGradient)
        
        // Ensure the indicator is always on top
        if let indicator = indicatorLayer {
            layer?.addSublayer(indicator)
        }
    }
    
    private func updateIndicatorPositionFromLocation(_ location: NSPoint) {
        guard let indicator = indicatorLayer else { return }
        
        let center = CGPoint(x: bounds.width/2, y: bounds.height/2)
        let radius = min(bounds.width, bounds.height)/2 - 3
        
        // Calculate distance from center
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance <= radius {
            // Calculate hue (angle)
            let angle = atan2(dy, dx) * 180 / .pi
            let hue = (angle + 360).truncatingRemainder(dividingBy: 360)
            
            // Calculate saturation (distance from center, normalized)
            let saturation = min(1.0, distance / radius)
            
            // Update indicator position immediately for smooth visual feedback
            let tempHue = hue / 360.0
            let tempSaturation = saturation
            
            // Calculate position directly for maximum speed
            let angleRadians = tempHue * 2 * .pi
            let indicatorDistance = tempSaturation * radius
            
            let x = center.x + cos(angleRadians) * indicatorDistance
            let y = center.y + sin(angleRadians) * indicatorDistance
            
            // Update position immediately without animation for responsiveness
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            indicator.position = CGPoint(x: x, y: y)
            CATransaction.commit()
        }
    }
    
    private func updateIndicatorPositionWithValues(hue: CGFloat, saturation: CGFloat) {
        guard let indicator = indicatorLayer else { return }
        
        let center = CGPoint(x: bounds.width/2, y: bounds.height/2)
        let radius = min(bounds.width, bounds.height)/2 - 3
        
        // Calculate position based on provided hue and saturation
        let angle = hue * 2 * .pi
        let distance = saturation * radius
        
        let x = center.x + cos(angle) * distance
        let y = center.y + sin(angle) * distance
        
        indicator.position = CGPoint(x: x, y: y)
    }
    
    func setColor(_ color: NSColor, brightness: CGFloat) {
        self.selectedColor = color
        self.brightness = brightness
        
        // Extract hue and saturation from the color
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var currentBrightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        color.getHue(&hue, saturation: &saturation, brightness: &currentBrightness, alpha: &alpha)
        
        currentHue = hue
        currentSaturation = saturation
        
        // Only update indicator position and appearance when not dragging
        if !isDragging {
            updateIndicatorPosition()
            updateColorWheelAppearance()
        }
    }
    
    private func createColorIndicator() {
        let indicator = CAShapeLayer()
        indicator.fillColor = NSColor.white.cgColor
        indicator.strokeColor = NSColor.black.cgColor
        indicator.lineWidth = 2.0
        
        // Create a small circle for the indicator
        let indicatorSize: CGFloat = 8.0
        let indicatorPath = CGMutablePath()
        indicatorPath.addEllipse(in: CGRect(x: -indicatorSize/2, y: -indicatorSize/2, width: indicatorSize, height: indicatorSize))
        indicator.path = indicatorPath
        
        layer?.addSublayer(indicator)
        self.indicatorLayer = indicator
        
        // Set initial position
        updateIndicatorPosition()
    }
    
    private func updateIndicatorPosition() {
        updateIndicatorPositionWithValues(hue: currentHue, saturation: currentSaturation)
    }
} 
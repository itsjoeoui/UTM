//
// Copyright © 2022 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import SwiftTerm
import SwiftUI

@objc class VMDisplayTerminalViewController: VMDisplayViewController {
    private var terminalView: TerminalView!
    var vmSerialPort: CSPort {
        willSet {
            vmSerialPort.delegate = nil
            newValue.delegate = self
            terminalView.getTerminal().resetToInitialState()
            terminalView.getTerminal().softReset()
        }
    }
    
    private var style: UTMConfigurationTerminal?
    private var keyboardDelta: CGFloat = 0
    
    required init(port: CSPort, style: UTMConfigurationTerminal? = nil) {
        self.vmSerialPort = port
        super.init(nibName: nil, bundle: nil)
        port.delegate = self
        self.style = style
    }
    
    required init?(coder: NSCoder) {
        return nil
    }
    
    override func loadView() {
        super.loadView()
        terminalView = TerminalView(frame: makeFrame (keyboardDelta: 0))
        terminalView.terminalDelegate = self
        view.insertSubview(terminalView, at: 0)
        styleTerminal()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboardMonitor()
    }
    
    override func enterLive() {
        super.enterLive()
        DispatchQueue.main.async {
            let terminalSize = CGSize(width: self.terminalView.getTerminal().cols, height: self.terminalView.getTerminal().rows)
            self.delegate.displayViewSize = terminalSize
        }
    }
    
    override func showKeyboard() {
        super.showKeyboard()
        terminalView.becomeFirstResponder()
    }
    
    override func hideKeyboard() {
        super.hideKeyboard()
        _ = terminalView.resignFirstResponder()
    }
}

// MARK: - Layout terminal
extension VMDisplayTerminalViewController {
    var useAutoLayout: Bool {
        get { true }
    }
    
    func makeFrame (keyboardDelta: CGFloat, _ fn: String = #function, _ ln: Int = #line) -> CGRect
    {
        if useAutoLayout {
            return CGRect.zero
        } else {
            return CGRect (x: view.safeAreaInsets.left,
                           y: view.safeAreaInsets.top,
                           width: view.frame.width - view.safeAreaInsets.left - view.safeAreaInsets.right,
                           height: view.frame.height - view.safeAreaInsets.top - keyboardDelta)
        }
    }
    
    func setupKeyboardMonitor ()
    {
        if #available(iOS 15.0, *), useAutoLayout {
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            terminalView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
            terminalView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            terminalView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            
            terminalView.keyboardLayoutGuide.topAnchor.constraint(equalTo: terminalView.bottomAnchor).isActive = true
        } else {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillShow),
                name: UIWindow.keyboardWillShowNotification,
                object: nil)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHide),
                name: UIWindow.keyboardWillHideNotification,
                object: nil)
        }
    }
    
    @objc private func keyboardWillShow(_ notification: NSNotification) {
        guard let keyboardValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        
        let keyboardScreenEndFrame = keyboardValue.cgRectValue
        let keyboardViewEndFrame = view.convert(keyboardScreenEndFrame, from: view.window)
        keyboardDelta = keyboardViewEndFrame.height
        terminalView.frame = makeFrame(keyboardDelta: keyboardViewEndFrame.height)
    }
    
    @objc private func keyboardWillHide(_ notification: NSNotification) {
        //let key = UIResponder.keyboardFrameBeginUserInfoKey
        keyboardDelta = 0
        terminalView.frame = makeFrame(keyboardDelta: 0)
    }
}

// MARK: - Style terminal
extension VMDisplayTerminalViewController {
    private func styleTerminal() {
        guard let style = style else {
            return
        }
        let fontSize = style.fontSize
        let fontName = style.font.rawValue
        if fontName != "" {
            let orig = terminalView.font
            let new = UIFont(name: fontName, size: CGFloat(fontSize)) ?? orig
            terminalView.font = new
        } else {
            let orig = terminalView.font
            let new = UIFont(descriptor: orig.fontDescriptor, size: CGFloat(fontSize))
            terminalView.font = new
        }
        if let consoleTextColor = style.foregroundColor,
           let textColor = Color(hexString: consoleTextColor),
           let consoleBackgroundColor = style.backgroundColor,
           let backgroundColor = Color(hexString: consoleBackgroundColor) {
            terminalView.nativeForegroundColor = UIColor(textColor)
            terminalView.nativeBackgroundColor = UIColor(backgroundColor)
        }
    }
}

// MARK: - TerminalViewDelegate
extension VMDisplayTerminalViewController: TerminalViewDelegate {
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        delegate.displayViewSize = CGSize(width: newCols, height: newRows)
    }
    
    func setTerminalTitle(source: TerminalView, title: String) {
    }
    
    func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
    }
    
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
    }
    
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        delegate.displayDidAssertUserInteraction()
        vmSerialPort.write(Data(data))
    }
    
    func scrolled(source: TerminalView, position: Double) {
        delegate.displayDidAssertUserInteraction()
    }
    
    func bell(source: TerminalView) {
    }
}

// MARK: - CSPortDelegate
extension VMDisplayTerminalViewController: CSPortDelegate {
    func portDidDisconect(_ port: CSPort) {
    }
    
    func port(_ port: CSPort, didError error: String) {
        delegate.serialDidError(error)
    }
    
    func port(_ port: CSPort, didRecieveData data: Data) {
        if let terminalView = terminalView {
            let arr = [UInt8](data)[...]
            DispatchQueue.main.async {
                terminalView.feed(byteArray: arr)
            }
        }
    }
}

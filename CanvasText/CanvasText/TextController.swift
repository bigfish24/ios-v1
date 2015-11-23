//
//  TextController.swift
//  Canvas
//
//  Created by Sam Soffes on 11/10/15.
//  Copyright © 2015 Canvas Labs, Inc. All rights reserved.
//

import Foundation
import WebKit

protocol TextControllerDelegate: class {
	func textControllerDidChangeText(textController: TextController)
	func textControllerDidUpdateSelection(textController: TextController)
}


class TextController {
	
	// MARK: - Properties

	var backingText: String {
		didSet {
			backingTextDidChange()
		}
	}
	
	var backingSelection: NSRange {
		didSet {
			displaySelection = backingRangeToDisplayRange(backingSelection)
			delegate?.textControllerDidUpdateSelection(self)
		}
	}
	
	private(set) var displayText: String
	
	private(set) var displaySelection: NSRange
	
	private(set) var nodes = [Node]()
	
	weak var delegate: TextControllerDelegate?
	
	var transportController: TransportController?
	
	
	// MARK: - Initializers
	
	init(backingText: String = "", delegate: TextControllerDelegate? = nil) {
		self.backingText = backingText
		self.delegate = delegate

		backingSelection = .zero
		displayText = ""
		displaySelection = .zero
		backingTextDidChange()
	}
	
	
	// MARK: - Realtime
	
	func connect(accessToken accessToken: String, collectionID: String, canvasID: String, setup: WKWebView -> Void) {
		let controller = TransportController(serverURL: NSURL(string: "wss://api.usecanvas.com/realtime")!, accessToken: accessToken, collectionID: collectionID, canvasID: canvasID)
		controller.delegate = self
		setup(controller.webView)
		controller.reload()
		transportController = controller
	}
	
	
	// MARK: - Editing
	
	func change(range range: NSRange, replacementText text: String) {
		let backingRange = displayRangeToBackingRange(range)
		
		// Insert
		if range.length == 0 {
			transportController?.submitOperation(.Insert(location: UInt(backingRange.location), string: text))
		}
			
		// Remove
		else {
			transportController?.submitOperation(.Remove(location: UInt(backingRange.location), length: UInt(backingRange.length)))
		}
	}
	
	
	// MARK: - Ranges
	
	func backingRangeToDisplayRange(backingRange: NSRange) -> NSRange {
		var displayRange = backingRange

		for node in nodes {
			if let node = node as? Delimitable {
				if node.delimiterRange.location > backingRange.location {
					break
				}

				displayRange.location -= node.delimiterRange.length
			}

			if let node = node as? Prefixable {
				if node.prefixRange.location > backingRange.location {
					break
				}

				displayRange.location -= node.prefixRange.length
			}
		}
		
		return displayRange
	}
	
	func displayRangeToBackingRange(displayRange: NSRange) -> NSRange {
		var backingRange = displayRange

		for node in nodes {
			if let node = node as? Delimitable {
				if node.delimiterRange.location > backingRange.location {
					break
				}

				backingRange.location += node.delimiterRange.length
			}

			if let node = node as? Prefixable {
				if node.prefixRange.location > backingRange.location {
					break
				}

				backingRange.location += node.prefixRange.length
			}
		}
		
		return backingRange
	}
	
	
	// MARK: - Private
	
	private func backingTextDidChange() {
		// Convert to Foundation string so we can work with `NSRange` instead of `Range` since the TextKit APIs take
		// `NSRange` instead `Range`. Bummer.
		let text = backingText as NSString
		
		// We're going to rebuild `nodes` and `displayText` from the new `backingText`.
		var nodes = [Node]()
		
		// Enumerate the string blocks of the `backingText`.
		text.enumerateSubstringsInRange(NSRange(location: 0, length: text.length), options: [.ByLines]) { substring, substringRange, _, _ in
			// Ensure we have a substring to work with
			guard let substring = substring else { return }

			// Setup a scanner
			let scanner = NSScanner(string: substring)
			scanner.charactersToBeSkipped = nil

			for type in nodeParseOrder {
				if let node = type.init(string: substring, enclosingRange: substringRange) {
					nodes.append(node)
					return
				}
			}
		}
		
		self.nodes = nodes
		displayText = nodes.flatMap { $0.contentInString(backingText) }.joinWithSeparator("\n")
		
		delegate?.textControllerDidChangeText(self)
	}
}


extension TextController: TransportControllerDelegate {
	func transportController(controller: TransportController, didReceiveSnapshot text: String) {
		backingText = text
	}
	
	func transportController(controller: TransportController, didReceiveOperation operation: Operation) {
		var backingText = self.backingText
		var backingSelection = self.backingSelection
		
		switch operation {
		case .Insert(let location, let string):
			// Shift selection
			let length = string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
			if Int(location) < backingSelection.location {
				backingSelection.location += string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
			}
			
			// Extend selection
			backingSelection.length += NSIntersectionRange(backingSelection, NSRange(location: location, length: length)).length
			
			// Update text
			let index = backingText.startIndex.advancedBy(Int(location))
			let range = Range<String.Index>(start: index, end: index)
			backingText = backingText.stringByReplacingCharactersInRange(range, withString: string)
		case .Remove(let location, let length):
			// Shift selection
			if Int(location) < backingSelection.location {
				backingSelection.location -= Int(length)
			}
			
			// Extend selection
			backingSelection.length -= NSIntersectionRange(backingSelection, NSRange(location: location, length: length)).length
			
			// Update text
			let index = backingText.startIndex.advancedBy(Int(location))
			let range = Range<String.Index>(start: index, end: index.advancedBy(Int(length)))
			backingText = backingText.stringByReplacingCharactersInRange(range, withString: "")
		}
		
		// Apply changes
		self.backingText = backingText
		self.backingSelection = backingSelection
	}
}

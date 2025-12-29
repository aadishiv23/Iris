# UIKit Chat View Implementation Guide

A comprehensive guide to creating a UIKit-based chat view as an alternative to the SwiftUI `ChatConversationView`, controlled by a feature flag.

---

## Table of Contents

1. [Project Setup](#1-project-setup)
2. [Feature Flag Implementation](#2-feature-flag-implementation)
3. [UIKit Foundation](#3-uikit-foundation)
4. [SwiftUI Bridge](#4-swiftui-bridge)
5. [Conditional Rendering](#5-conditional-rendering)
6. [Collection View Setup](#6-collection-view-setup)
7. [User Message Cell](#7-user-message-cell)
8. [Assistant Message Cell](#8-assistant-message-cell)
9. [Typing Indicator Cell](#9-typing-indicator-cell)
10. [Glass Input View](#10-glass-input-view)
11. [Thinking Block View](#11-thinking-block-view)
12. [Image Grid View](#12-image-grid-view)
13. [Scroll Behavior](#13-scroll-behavior)
14. [Testing Checklist](#14-testing-checklist)

---

## 1. Project Setup

### Create the folder structure

In Xcode, create the following folder structure:

```
Iris/
└── Chat/
    └── UIKit/                          # New folder
        ├── UIKitChatViewController.swift
        ├── UIKitChatViewRepresentable.swift
        ├── Cells/                      # New folder
        │   ├── UserMessageCell.swift
        │   ├── AssistantMessageCell.swift
        │   └── TypingIndicatorCell.swift
        └── Views/                      # New folder
            ├── UIKitGlassInputView.swift
            ├── UIKitThinkingView.swift
            ├── UIKitImageGridView.swift
            └── BubbleShapeLayer.swift
```

**How to create in Xcode:**
1. Right-click on `Iris/Chat/` in the Project Navigator
2. Select "New Group" → Name it "UIKit"
3. Right-click on "UIKit" → "New Group" → Name it "Cells"
4. Right-click on "UIKit" → "New Group" → Name it "Views"
5. Create Swift files in each folder as listed above

---

## 2. Feature Flag Implementation

### Step 2.1: Add FeatureFlags to AppConfig.swift

**File:** `Iris/AppConfig.swift`

**What to add:** Add this enum at the top of the file, before or after the existing `AppConfig` struct:

```swift
import SwiftUI

// MARK: - Feature Flags

enum FeatureFlags {
    /// When true, uses UIKit-based chat view instead of SwiftUI
    @AppStorage("useUIKitChatView") static var useUIKitChatView: Bool = false
}
```

### Step 2.2: Add Toggle in DebugLogView

**File:** `Iris/Debug/DebugLogView.swift`

**What to find:** Look for the main `TabView` or `List` in the body. The file currently has two tabs: "All Logs" and "Files".

**What to add:** Add a new section at the TOP of the view body, before the TabView. You need to wrap everything in a `VStack` or `NavigationStack`:

```swift
var body: some View {
    NavigationStack {
        VStack(spacing: 0) {
            // NEW: Experimental Features Section
            experimentalFeaturesSection

            Divider()

            // Existing TabView content...
            TabView {
                // ... existing log content
            }
        }
        .navigationTitle("Debug")
        // ... existing modifiers
    }
}

// Add this computed property
private var experimentalFeaturesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Experimental")
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 12)

        Toggle(isOn: FeatureFlags.$useUIKitChatView) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Use UIKit Chat View")
                    .font(.body)
                Text("Uses UICollectionView instead of SwiftUI for the chat interface")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }
    .background(Color(.secondarySystemBackground))
}
```

**Alternative (simpler):** If you prefer, just add a List section at the top:

```swift
var body: some View {
    NavigationStack {
        List {
            Section("Experimental") {
                Toggle("Use UIKit Chat View", isOn: FeatureFlags.$useUIKitChatView)
            }

            // Then move existing content into List sections...
        }
    }
}
```

---

## 3. UIKit Foundation

### Step 3.1: Create UIKitChatViewController

**File:** `Iris/Chat/UIKit/UIKitChatViewController.swift`

```swift
import UIKit
import Combine

// MARK: - Delegate Protocol

protocol UIKitChatViewControllerDelegate: AnyObject {
    func chatViewController(_ controller: UIKitChatViewController, didSendMessage text: String)
    func chatViewControllerDidRequestStop(_ controller: UIKitChatViewController)
    func chatViewControllerDidRequestImagePicker(_ controller: UIKitChatViewController)
    func chatViewController(_ controller: UIKitChatViewController, didRemoveImageWithID id: UUID)
}

// MARK: - View Controller

final class UIKitChatViewController: UIViewController {

    // MARK: - Types

    enum Section: Int, CaseIterable {
        case messages
        case typingIndicator
    }

    enum Item: Hashable {
        case message(UUID)
        case typingIndicator
    }

    // MARK: - Properties

    weak var delegate: UIKitChatViewControllerDelegate?

    // Data (updated from SwiftUI)
    private(set) var messages: [Message] = []
    private(set) var isGenerating: Bool = false
    private(set) var pendingImages: [PendingImage] = []

    // UI Components
    private var collectionView: UICollectionView!
    private var inputView: UIKitGlassInputView!
    private var scrollToBottomButton: UIButton!

    // Data Source
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    // Scroll State
    private var isNearBottom: Bool = true
    private var followStreaming: Bool = false
    private let nearBottomThreshold: CGFloat = 80

    // Keyboard
    private var keyboardHeight: CGFloat = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCollectionView()
        setupDataSource()
        setupInputView()
        setupScrollToBottomButton()
        setupKeyboardObservers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateScrollToBottomButtonPosition()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
    }

    private func setupCollectionView() {
        let layout = createCompositionalLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true

        // Register cells
        collectionView.register(UserMessageCell.self, forCellWithReuseIdentifier: UserMessageCell.reuseIdentifier)
        collectionView.register(AssistantMessageCell.self, forCellWithReuseIdentifier: AssistantMessageCell.reuseIdentifier)
        collectionView.register(TypingIndicatorCell.self, forCellWithReuseIdentifier: TypingIndicatorCell.reuseIdentifier)

        view.addSubview(collectionView)
    }

    private func createCompositionalLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { sectionIndex, environment in
            let section = Section(rawValue: sectionIndex)!

            switch section {
            case .messages:
                // Self-sizing items
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .estimated(100)
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)

                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .estimated(100)
                )
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = 18 // Match SwiftUI 18pt spacing
                section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
                return section

            case .typingIndicator:
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .estimated(44)
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])

                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
                return section
            }
        }
    }

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self = self else { return nil }

            switch item {
            case .message(let id):
                guard let message = self.messages.first(where: { $0.id == id }) else {
                    return nil
                }

                if message.role == .user {
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: UserMessageCell.reuseIdentifier,
                        for: indexPath
                    ) as! UserMessageCell
                    cell.configure(with: message)
                    return cell
                } else {
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: AssistantMessageCell.reuseIdentifier,
                        for: indexPath
                    ) as! AssistantMessageCell
                    cell.configure(with: message, isStreaming: self.isGenerating)
                    return cell
                }

            case .typingIndicator:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: TypingIndicatorCell.reuseIdentifier,
                    for: indexPath
                ) as! TypingIndicatorCell
                cell.startAnimating()
                return cell
            }
        }
    }

    private func setupInputView() {
        inputView = UIKitGlassInputView()
        inputView.translatesAutoresizingMaskIntoConstraints = false
        inputView.delegate = self
        view.addSubview(inputView)

        NSLayoutConstraint.activate([
            inputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: inputView.topAnchor)
        ])
    }

    private func setupScrollToBottomButton() {
        scrollToBottomButton = UIButton(type: .system)
        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false

        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        scrollToBottomButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: config), for: .normal)
        scrollToBottomButton.tintColor = .white
        scrollToBottomButton.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        scrollToBottomButton.layer.cornerRadius = 20
        scrollToBottomButton.layer.shadowColor = UIColor.black.cgColor
        scrollToBottomButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        scrollToBottomButton.layer.shadowRadius = 4
        scrollToBottomButton.layer.shadowOpacity = 0.2
        scrollToBottomButton.alpha = 0

        scrollToBottomButton.addTarget(self, action: #selector(scrollToBottomTapped), for: .touchUpInside)

        view.addSubview(scrollToBottomButton)

        NSLayoutConstraint.activate([
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 40),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: 40),
            scrollToBottomButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func updateScrollToBottomButtonPosition() {
        // Position above input view
        scrollToBottomButton.frame.origin.y = inputView.frame.minY - 48
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    // MARK: - Keyboard Handling

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboardHeight = keyboardFrame.height
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        keyboardHeight = 0
    }

    // MARK: - Public Update Methods

    func updateMessages(_ newMessages: [Message]) {
        let oldCount = messages.count
        messages = newMessages

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.messages])
        snapshot.appendItems(newMessages.map { .message($0.id) }, toSection: .messages)

        // Show typing indicator if generating and last message is empty assistant
        let showTypingIndicator = isGenerating && (newMessages.last?.role == .assistant && (newMessages.last?.content.isEmpty ?? true))
        if showTypingIndicator {
            snapshot.appendSections([.typingIndicator])
            snapshot.appendItems([.typingIndicator], toSection: .typingIndicator)
        }

        dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
            guard let self = self else { return }

            // Auto-scroll if near bottom or following streaming
            if self.isNearBottom || self.followStreaming {
                self.scrollToBottom(animated: true)
            }
        }

        // Start following streaming when new user message added
        if newMessages.count > oldCount && newMessages.last?.role == .user {
            followStreaming = true
        }
    }

    func updateGenerating(_ generating: Bool) {
        isGenerating = generating
        inputView.isGenerating = generating

        if !generating {
            followStreaming = false
        }

        // Refresh to show/hide typing indicator
        updateMessages(messages)
    }

    func updateInputText(_ text: String) {
        inputView.text = text
    }

    func updatePendingImages(_ images: [PendingImage]) {
        pendingImages = images
        inputView.pendingImages = images
    }

    // MARK: - Scroll

    private func scrollToBottom(animated: Bool) {
        let contentHeight = collectionView.contentSize.height
        let frameHeight = collectionView.frame.height
        let inputHeight = inputView.frame.height

        if contentHeight > frameHeight - inputHeight {
            let offset = CGPoint(x: 0, y: contentHeight - frameHeight + inputHeight + collectionView.contentInset.bottom)
            collectionView.setContentOffset(offset, animated: animated)
        }
    }

    @objc private func scrollToBottomTapped() {
        scrollToBottom(animated: true)
        followStreaming = true
    }

    private func updateScrollButtonVisibility() {
        let contentHeight = collectionView.contentSize.height
        let offset = collectionView.contentOffset.y
        let frameHeight = collectionView.frame.height

        let distanceFromBottom = contentHeight - offset - frameHeight
        isNearBottom = distanceFromBottom < nearBottomThreshold

        UIView.animate(withDuration: 0.2) {
            self.scrollToBottomButton.alpha = self.isNearBottom ? 0 : 1
        }
    }
}

// MARK: - UICollectionViewDelegate

extension UIKitChatViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateScrollButtonVisibility()

        // If user scrolls up, stop following streaming
        if scrollView.isTracking || scrollView.isDragging {
            if !isNearBottom {
                followStreaming = false
            }
        }
    }
}

// MARK: - UIKitGlassInputViewDelegate

extension UIKitChatViewController: UIKitGlassInputViewDelegate {
    func inputViewDidSend(_ view: UIKitGlassInputView) {
        delegate?.chatViewController(self, didSendMessage: view.text)
    }

    func inputViewDidStop(_ view: UIKitGlassInputView) {
        delegate?.chatViewControllerDidRequestStop(self)
    }

    func inputViewDidRequestImagePicker(_ view: UIKitGlassInputView) {
        delegate?.chatViewControllerDidRequestImagePicker(self)
    }

    func inputView(_ view: UIKitGlassInputView, didRemoveImageWithID id: UUID) {
        delegate?.chatViewController(self, didRemoveImageWithID: id)
    }

    func inputViewTextDidChange(_ view: UIKitGlassInputView, text: String) {
        // This is called when text changes in UIKit
        // We'll sync back to SwiftUI via delegate
    }
}
```

---

## 4. SwiftUI Bridge

### Step 4.1: Create UIKitChatViewRepresentable

**File:** `Iris/Chat/UIKit/UIKitChatViewRepresentable.swift`

```swift
import SwiftUI
import PhotosUI

struct UIKitChatViewRepresentable: UIViewControllerRepresentable {

    // MARK: - Properties (mirror ChatConversationView exactly)

    let messages: [Message]
    let isGenerating: Bool
    @Binding var inputText: String
    @Binding var pendingImages: [PendingImage]

    let onSend: () -> Void
    let onStop: () -> Void
    let onPickImages: ([PhotosPickerItem]) -> Void
    let onRemoveImage: (UUID) -> Void

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIKitChatViewController {
        let controller = UIKitChatViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIKitChatViewController, context: Context) {
        // Update messages if changed
        if controller.messages.map(\.id) != messages.map(\.id) ||
           controller.messages.last?.content != messages.last?.content {
            controller.updateMessages(messages)
        }

        // Update generating state
        if controller.isGenerating != isGenerating {
            controller.updateGenerating(isGenerating)
        }

        // Update pending images
        if controller.pendingImages.map(\.id) != pendingImages.map(\.id) {
            controller.updatePendingImages(pendingImages)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIKitChatViewControllerDelegate {
        var parent: UIKitChatViewRepresentable

        init(_ parent: UIKitChatViewRepresentable) {
            self.parent = parent
        }

        func chatViewController(_ controller: UIKitChatViewController, didSendMessage text: String) {
            parent.inputText = text
            parent.onSend()
        }

        func chatViewControllerDidRequestStop(_ controller: UIKitChatViewController) {
            parent.onStop()
        }

        func chatViewControllerDidRequestImagePicker(_ controller: UIKitChatViewController) {
            // Present PHPicker
            presentImagePicker(from: controller)
        }

        func chatViewController(_ controller: UIKitChatViewController, didRemoveImageWithID id: UUID) {
            parent.onRemoveImage(id)
        }

        private func presentImagePicker(from controller: UIViewController) {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 4

            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            controller.present(picker, animated: true)
        }
    }
}

// MARK: - PHPickerViewControllerDelegate

extension UIKitChatViewRepresentable.Coordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        // Convert PHPickerResult to PhotosPickerItem is not directly possible
        // We need to load the images ourselves and pass them back

        Task { @MainActor in
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                        guard let image = image as? UIImage else { return }

                        DispatchQueue.main.async {
                            // Create a PendingImage from the loaded UIImage
                            let pendingImage = PendingImage(image: image)
                            self?.parent.pendingImages.append(pendingImage)
                        }
                    }
                }
            }
        }
    }
}
```

**Note:** You may need to adjust `PendingImage` initialization depending on how your model is structured. Check `Iris/Chat/ViewModels/ChatViewModel.swift` to see how `PendingImage` is created.

---

## 5. Conditional Rendering

### Step 5.1: Modify ChatView.swift

**File:** `Iris/Chat/ChatViews/ChatView.swift`

**What to find:** Look for where `ChatConversationView` is used. It's likely in a `ZStack` or as the main content.

**What to add:**

1. First, add the import and property at the top of the struct:

```swift
import SwiftUI

struct ChatView: View {
    // ... existing properties

    // ADD THIS: Feature flag
    @AppStorage("useUIKitChatView") private var useUIKitChatView: Bool = false

    // ... rest of properties
}
```

2. Find where `ChatConversationView` is used and replace with conditional:

**Before:**
```swift
ChatConversationView(
    messages: viewModel.messages,
    isGenerating: viewModel.isGeneratingResponse,
    inputText: $viewModel.inputText,
    pendingImages: $viewModel.pendingImages,
    onSend: { viewModel.sendMessage() },
    onStop: { viewModel.stopGeneration() },
    onPickImages: { items in
        Task { await viewModel.addPickedItems(items) }
    },
    onRemoveImage: { id in viewModel.removePendingImage(id) }
)
```

**After:**
```swift
chatContentView
```

**And add this computed property to the struct:**

```swift
@ViewBuilder
private var chatContentView: some View {
    if useUIKitChatView {
        UIKitChatViewRepresentable(
            messages: viewModel.messages,
            isGenerating: viewModel.isGeneratingResponse,
            inputText: $viewModel.inputText,
            pendingImages: $viewModel.pendingImages,
            onSend: { viewModel.sendMessage() },
            onStop: { viewModel.stopGeneration() },
            onPickImages: { items in
                Task { await viewModel.addPickedItems(items) }
            },
            onRemoveImage: { id in viewModel.removePendingImage(id) }
        )
    } else {
        ChatConversationView(
            messages: viewModel.messages,
            isGenerating: viewModel.isGeneratingResponse,
            inputText: $viewModel.inputText,
            pendingImages: $viewModel.pendingImages,
            onSend: { viewModel.sendMessage() },
            onStop: { viewModel.stopGeneration() },
            onPickImages: { items in
                Task { await viewModel.addPickedItems(items) }
            },
            onRemoveImage: { id in viewModel.removePendingImage(id) }
        )
    }
}
```

---

## 6. Collection View Setup

The collection view is already set up in `UIKitChatViewController`. Key aspects:

### Compositional Layout

```swift
// Messages section: Self-sizing cells with 18pt spacing
let section = NSCollectionLayoutSection(group: group)
section.interGroupSpacing = 18  // Matches SwiftUI LazyVStack spacing
section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
```

### Diffable Data Source

```swift
// Two sections: messages and typing indicator
enum Section: Int, CaseIterable {
    case messages
    case typingIndicator
}

// Items can be either a message or the typing indicator
enum Item: Hashable {
    case message(UUID)
    case typingIndicator
}
```

---

## 7. User Message Cell

### Step 7.1: Create BubbleShapeLayer

**File:** `Iris/Chat/UIKit/Views/BubbleShapeLayer.swift`

```swift
import UIKit

final class BubbleShapeLayer: CAShapeLayer {

    /// Updates the bubble path to match SwiftUI BubbleShape
    /// - Parameters:
    ///   - bounds: The bounds of the bubble
    ///   - radius: Corner radius (default 20 to match SwiftUI)
    ///   - isPinched: Whether to pinch the bottom-right corner (user messages)
    func updatePath(for bounds: CGRect, radius: CGFloat = 20, isPinched: Bool = true) {
        let path = UIBezierPath()

        // Start at top-left, after the corner
        path.move(to: CGPoint(x: bounds.minX + radius, y: bounds.minY))

        // Top edge
        path.addLine(to: CGPoint(x: bounds.maxX - radius, y: bounds.minY))

        // Top-right corner
        path.addArc(
            withCenter: CGPoint(x: bounds.maxX - radius, y: bounds.minY + radius),
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )

        if isPinched {
            // Pinched bottom-right: straight line to corner (no curve)
            path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        } else {
            // Normal bottom-right corner
            path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - radius))
            path.addArc(
                withCenter: CGPoint(x: bounds.maxX - radius, y: bounds.maxY - radius),
                radius: radius,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: true
            )
        }

        // Bottom edge
        path.addLine(to: CGPoint(x: bounds.minX + radius, y: bounds.maxY))

        // Bottom-left corner
        path.addArc(
            withCenter: CGPoint(x: bounds.minX + radius, y: bounds.maxY - radius),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )

        // Left edge
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + radius))

        // Top-left corner
        path.addArc(
            withCenter: CGPoint(x: bounds.minX + radius, y: bounds.minY + radius),
            radius: radius,
            startAngle: .pi,
            endAngle: -.pi / 2,
            clockwise: true
        )

        path.close()

        self.path = path.cgPath
    }
}
```

### Step 7.2: Create UserMessageCell

**File:** `Iris/Chat/UIKit/Cells/UserMessageCell.swift`

```swift
import UIKit

final class UserMessageCell: UICollectionViewCell {

    static let reuseIdentifier = "UserMessageCell"

    // MARK: - UI Components

    private let containerView = UIView()
    private let bubbleView = UIView()
    private let textLabel = UILabel()
    private let timestampLabel = UILabel()
    private let imageGridView = UIKitImageGridView()

    // Layers
    private let gradientLayer = CAGradientLayer()
    private let bubbleShapeLayer = BubbleShapeLayer()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        // Container for right-alignment
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Bubble view
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(bubbleView)

        // Gradient background
        gradientLayer.colors = [
            UIColor.systemBlue.cgColor,
            UIColor.systemIndigo.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        bubbleView.layer.insertSublayer(gradientLayer, at: 0)

        // Bubble shape mask
        bubbleView.layer.mask = bubbleShapeLayer

        // Image grid (hidden by default)
        imageGridView.translatesAutoresizingMaskIntoConstraints = false
        imageGridView.isHidden = true
        bubbleView.addSubview(imageGridView)

        // Text label
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textColor = .white
        textLabel.font = .systemFont(ofSize: 17)
        textLabel.numberOfLines = 0
        bubbleView.addSubview(textLabel)

        // Timestamp
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.font = .systemFont(ofSize: 12)
        timestampLabel.textColor = .secondaryLabel
        containerView.addSubview(timestampLabel)

        // Constraints
        NSLayoutConstraint.activate([
            // Container right-aligned, max 80% width
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8),

            // Bubble
            bubbleView.topAnchor.constraint(equalTo: containerView.topAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Image grid at top of bubble (if visible)
            imageGridView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            imageGridView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            imageGridView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),

            // Text below images (or at top if no images)
            textLabel.topAnchor.constraint(equalTo: imageGridView.bottomAnchor, constant: 8),
            textLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            textLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            textLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),

            // Timestamp below bubble
            timestampLabel.topAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 4),
            timestampLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            timestampLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Context menu
        let interaction = UIContextMenuInteraction(delegate: self)
        bubbleView.addInteraction(interaction)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bubbleView.bounds
        bubbleShapeLayer.updatePath(for: bubbleView.bounds, isPinched: true)
    }

    // MARK: - Configure

    func configure(with message: Message) {
        textLabel.text = message.content

        // Format timestamp
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        timestampLabel.text = formatter.string(from: message.createdAt)

        // Configure images
        if let attachments = message.attachments, !attachments.isEmpty {
            imageGridView.isHidden = false
            imageGridView.configure(with: attachments)
        } else {
            imageGridView.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        textLabel.text = nil
        timestampLabel.text = nil
        imageGridView.isHidden = true
    }
}

// MARK: - UIContextMenuInteractionDelegate

extension UserMessageCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copyAction = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                UIPasteboard.general.string = self?.textLabel.text
            }
            return UIMenu(children: [copyAction])
        }
    }
}
```

---

## 8. Assistant Message Cell

### Step 8.1: Create AssistantMessageCell

**File:** `Iris/Chat/UIKit/Cells/AssistantMessageCell.swift`

```swift
import UIKit

final class AssistantMessageCell: UICollectionViewCell {

    static let reuseIdentifier = "AssistantMessageCell"

    // MARK: - UI Components

    private let containerView = UIView()
    private let contentStackView = UIStackView()
    private let timestampLabel = UILabel()

    private var thinkingViews: [UIKitThinkingView] = []
    private var messageID: UUID?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        // Container for left-alignment
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Stack for content segments
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .vertical
        contentStackView.spacing = 8
        contentStackView.alignment = .leading
        containerView.addSubview(contentStackView)

        // Timestamp
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.font = .systemFont(ofSize: 12)
        timestampLabel.textColor = .secondaryLabel
        containerView.addSubview(timestampLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.9),

            contentStackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            timestampLabel.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 4),
            timestampLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            timestampLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Context menu
        let interaction = UIContextMenuInteraction(delegate: self)
        containerView.addInteraction(interaction)
    }

    // MARK: - Configure

    func configure(with message: Message, isStreaming: Bool) {
        messageID = message.id

        // Clear existing content
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        thinkingViews.removeAll()

        // Parse content for thinking blocks
        let segments = parseContent(message.content, isStreaming: isStreaming)

        for segment in segments {
            switch segment {
            case .text(let text):
                let label = createTextLabel(with: text)
                contentStackView.addArrangedSubview(label)

            case .thinking(let content, let isActive):
                let thinkingView = UIKitThinkingView()
                thinkingView.configure(content: content, isStreaming: isActive)
                contentStackView.addArrangedSubview(thinkingView)
                thinkingViews.append(thinkingView)
            }
        }

        // Format timestamp
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        timestampLabel.text = formatter.string(from: message.createdAt)
    }

    private func createTextLabel(with text: String) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 17)
        label.textColor = .label

        // Try to render as markdown
        if let attributed = try? NSAttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            label.attributedText = attributed
        } else {
            label.text = text
        }

        return label
    }

    // MARK: - Content Parsing

    enum ContentSegment {
        case text(String)
        case thinking(content: String, isStreaming: Bool)
    }

    private func parseContent(_ content: String, isStreaming: Bool) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var remaining = content

        // Pattern to match <think>...</think> blocks
        let pattern = "<think>(.*?)</think>"
        let unclosedPattern = "<think>(.*?)$"

        while !remaining.isEmpty {
            // Try to find a complete <think> block
            if let range = remaining.range(of: pattern, options: .regularExpression) {
                // Text before thinking block
                let textBefore = String(remaining[..<range.lowerBound])
                if !textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(textBefore))
                }

                // Extract thinking content
                let match = String(remaining[range])
                if let thinkStart = match.range(of: "<think>"),
                   let thinkEnd = match.range(of: "</think>") {
                    let thinkContent = String(match[thinkStart.upperBound..<thinkEnd.lowerBound])
                    segments.append(.thinking(content: thinkContent, isStreaming: false))
                }

                remaining = String(remaining[range.upperBound...])
            }
            // Check for unclosed <think> tag (streaming)
            else if isStreaming, let range = remaining.range(of: unclosedPattern, options: .regularExpression) {
                // Text before thinking block
                let textBefore = String(remaining[..<range.lowerBound])
                if !textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(textBefore))
                }

                // Extract streaming thinking content
                if let thinkStart = remaining.range(of: "<think>") {
                    let thinkContent = String(remaining[thinkStart.upperBound...])
                    segments.append(.thinking(content: thinkContent, isStreaming: true))
                }

                remaining = ""
            }
            else {
                // No more thinking blocks, add remaining text
                if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(remaining))
                }
                remaining = ""
            }
        }

        return segments
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        thinkingViews.removeAll()
        timestampLabel.text = nil
        messageID = nil
    }
}

// MARK: - UIContextMenuInteractionDelegate

extension AssistantMessageCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let copyAction = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                // Get full text content
                var fullText = ""
                self?.contentStackView.arrangedSubviews.forEach { view in
                    if let label = view as? UILabel {
                        fullText += (label.text ?? "") + "\n"
                    }
                }
                UIPasteboard.general.string = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // TODO: Add metrics action

            return UIMenu(children: [copyAction])
        }
    }
}
```

---

## 9. Typing Indicator Cell

### Step 9.1: Create TypingIndicatorCell

**File:** `Iris/Chat/UIKit/Cells/TypingIndicatorCell.swift`

```swift
import UIKit

final class TypingIndicatorCell: UICollectionViewCell {

    static let reuseIdentifier = "TypingIndicatorCell"

    // MARK: - UI Components

    private let containerView = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let dotsStackView = UIStackView()
    private var dotViews: [UIView] = []

    // Animation
    private var displayLink: CADisplayLink?
    private let animationSpeed: Double = 6.0
    private var startTime: CFTimeInterval = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopAnimating()
    }

    // MARK: - Setup

    private func setupViews() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Blur background
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        containerView.addSubview(blurView)

        // Dots stack
        dotsStackView.translatesAutoresizingMaskIntoConstraints = false
        dotsStackView.axis = .horizontal
        dotsStackView.spacing = 6
        dotsStackView.alignment = .center
        blurView.contentView.addSubview(dotsStackView)

        // Create 3 dots
        for _ in 0..<3 {
            let dot = UIView()
            dot.backgroundColor = .secondaryLabel
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8)
            ])
            dotsStackView.addArrangedSubview(dot)
            dotViews.append(dot)
        }

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            blurView.topAnchor.constraint(equalTo: containerView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            dotsStackView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 10),
            dotsStackView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 14),
            dotsStackView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -14),
            dotsStackView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -10)
        ])
    }

    // MARK: - Animation

    func startAnimating() {
        guard displayLink == nil else { return }

        startTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(updateAnimation))
        displayLink?.add(to: .main, forMode: .common)
    }

    func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil

        // Reset dots
        dotViews.forEach { dot in
            dot.transform = .identity
            dot.alpha = 0.5
        }
    }

    @objc private func updateAnimation() {
        let time = CACurrentMediaTime() - startTime

        for (index, dot) in dotViews.enumerated() {
            let phase = time * animationSpeed - Double(index) * 0.6
            let offsetY = -3 * sin(phase)
            let alpha = 0.5 + 0.5 * sin(phase)

            dot.transform = CGAffineTransform(translationX: 0, y: CGFloat(offsetY))
            dot.alpha = CGFloat(alpha)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopAnimating()
    }
}
```

---

## 10. Glass Input View

### Step 10.1: Create UIKitGlassInputView

**File:** `Iris/Chat/UIKit/Views/UIKitGlassInputView.swift`

```swift
import UIKit

protocol UIKitGlassInputViewDelegate: AnyObject {
    func inputViewDidSend(_ view: UIKitGlassInputView)
    func inputViewDidStop(_ view: UIKitGlassInputView)
    func inputViewDidRequestImagePicker(_ view: UIKitGlassInputView)
    func inputView(_ view: UIKitGlassInputView, didRemoveImageWithID id: UUID)
    func inputViewTextDidChange(_ view: UIKitGlassInputView, text: String)
}

final class UIKitGlassInputView: UIView {

    weak var delegate: UIKitGlassInputViewDelegate?

    // MARK: - Public Properties

    var isGenerating: Bool = false {
        didSet { updateSendButton() }
    }

    var text: String {
        get { textView.text }
        set { textView.text = newValue }
    }

    var pendingImages: [PendingImage] = [] {
        didSet { updatePendingImages() }
    }

    // MARK: - UI Components

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let imagePickerButton = UIButton(type: .system)
    private let textView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let imagesScrollView = UIScrollView()
    private let imagesStackView = UIStackView()

    // Layout
    private var textViewHeightConstraint: NSLayoutConstraint!
    private let minTextViewHeight: CGFloat = 36
    private let maxTextViewHeight: CGFloat = 120

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = .clear

        // Blur background
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        // Image picker button
        imagePickerButton.translatesAutoresizingMaskIntoConstraints = false
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        imagePickerButton.setImage(UIImage(systemName: "photo", withConfiguration: imageConfig), for: .normal)
        imagePickerButton.tintColor = .systemBlue
        imagePickerButton.addTarget(self, action: #selector(imagePickerTapped), for: .touchUpInside)
        addSubview(imagePickerButton)

        // Images scroll view (for pending images)
        imagesScrollView.translatesAutoresizingMaskIntoConstraints = false
        imagesScrollView.showsHorizontalScrollIndicator = false
        imagesScrollView.isHidden = true
        addSubview(imagesScrollView)

        imagesStackView.translatesAutoresizingMaskIntoConstraints = false
        imagesStackView.axis = .horizontal
        imagesStackView.spacing = 8
        imagesScrollView.addSubview(imagesStackView)

        // Text view
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .systemFont(ofSize: 17)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 18
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.delegate = self
        textView.isScrollEnabled = false
        addSubview(textView)

        // Send button
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        updateSendButton()
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        addSubview(sendButton)

        // Constraints
        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: minTextViewHeight)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imagePickerButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            imagePickerButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            imagePickerButton.widthAnchor.constraint(equalToConstant: 44),
            imagePickerButton.heightAnchor.constraint(equalToConstant: 44),

            imagesScrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            imagesScrollView.leadingAnchor.constraint(equalTo: imagePickerButton.trailingAnchor, constant: 8),
            imagesScrollView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            imagesScrollView.heightAnchor.constraint(equalToConstant: 60),

            imagesStackView.topAnchor.constraint(equalTo: imagesScrollView.topAnchor),
            imagesStackView.leadingAnchor.constraint(equalTo: imagesScrollView.leadingAnchor),
            imagesStackView.trailingAnchor.constraint(equalTo: imagesScrollView.trailingAnchor),
            imagesStackView.bottomAnchor.constraint(equalTo: imagesScrollView.bottomAnchor),
            imagesStackView.heightAnchor.constraint(equalTo: imagesScrollView.heightAnchor),

            textView.topAnchor.constraint(equalTo: imagesScrollView.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: imagePickerButton.trailingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            textViewHeightConstraint,

            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func updateSendButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)

        if isGenerating {
            sendButton.setImage(UIImage(systemName: "stop.fill", withConfiguration: config), for: .normal)
            sendButton.tintColor = .systemRed
        } else {
            sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
            sendButton.tintColor = .systemBlue
        }

        // Enable/disable based on content
        let hasContent = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
        sendButton.isEnabled = isGenerating || hasContent
        sendButton.alpha = sendButton.isEnabled ? 1.0 : 0.5
    }

    private func updatePendingImages() {
        // Clear existing
        imagesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        imagesScrollView.isHidden = pendingImages.isEmpty

        for pendingImage in pendingImages {
            let imageView = UIImageView(image: pendingImage.image)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 8
            imageView.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 50),
                imageView.heightAnchor.constraint(equalToConstant: 50)
            ])

            // Remove button overlay
            let removeButton = UIButton(type: .close)
            removeButton.translatesAutoresizingMaskIntoConstraints = false
            removeButton.tag = pendingImage.id.hashValue
            removeButton.addTarget(self, action: #selector(removeImageTapped(_:)), for: .touchUpInside)

            let container = UIView()
            container.addSubview(imageView)
            container.addSubview(removeButton)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

                removeButton.topAnchor.constraint(equalTo: container.topAnchor),
                removeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 4)
            ])

            imagesStackView.addArrangedSubview(container)
        }

        updateSendButton()
    }

    // MARK: - Actions

    @objc private func imagePickerTapped() {
        delegate?.inputViewDidRequestImagePicker(self)
    }

    @objc private func sendTapped() {
        if isGenerating {
            delegate?.inputViewDidStop(self)
        } else {
            delegate?.inputViewDidSend(self)
        }
    }

    @objc private func removeImageTapped(_ sender: UIButton) {
        // Find the image by hash
        if let image = pendingImages.first(where: { $0.id.hashValue == sender.tag }) {
            delegate?.inputView(self, didRemoveImageWithID: image.id)
        }
    }

    // MARK: - Text View Height

    private func updateTextViewHeight() {
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude))
        let newHeight = min(max(size.height, minTextViewHeight), maxTextViewHeight)

        if textViewHeightConstraint.constant != newHeight {
            textViewHeightConstraint.constant = newHeight
            textView.isScrollEnabled = newHeight >= maxTextViewHeight
        }
    }
}

// MARK: - UITextViewDelegate

extension UIKitGlassInputView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateTextViewHeight()
        updateSendButton()
        delegate?.inputViewTextDidChange(self, text: textView.text)
    }
}
```

---

## 11. Thinking Block View

### Step 11.1: Create UIKitThinkingView

**File:** `Iris/Chat/UIKit/Views/UIKitThinkingView.swift`

```swift
import UIKit

final class UIKitThinkingView: UIView {

    // MARK: - Properties

    private var isExpanded: Bool = false
    private var isStreamingContent: Bool = false

    // MARK: - UI Components

    private let headerButton = UIButton(type: .system)
    private let chevronImageView = UIImageView()
    private let contentContainer = UIView()
    private let contentTextView = UITextView()
    private let shimmerLabel = UILabel()

    // Animation
    private var shimmerLayer: CAGradientLayer?

    // Constraints
    private var expandedConstraint: NSLayoutConstraint!
    private var collapsedConstraint: NSLayoutConstraint!

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = UIColor.systemPurple.withAlphaComponent(0.1)
        layer.cornerRadius = 12
        clipsToBounds = true

        // Header button
        headerButton.translatesAutoresizingMaskIntoConstraints = false
        headerButton.contentHorizontalAlignment = .leading

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "brain")
        config.imagePadding = 8
        config.baseForegroundColor = .systemPurple
        headerButton.configuration = config

        headerButton.addTarget(self, action: #selector(headerTapped), for: .touchUpInside)
        addSubview(headerButton)

        // Chevron
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.image = UIImage(systemName: "chevron.right")
        chevronImageView.tintColor = .systemPurple
        chevronImageView.contentMode = .scaleAspectFit
        addSubview(chevronImageView)

        // Content container
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.clipsToBounds = true
        addSubview(contentContainer)

        // Content text view
        contentTextView.translatesAutoresizingMaskIntoConstraints = false
        contentTextView.isEditable = false
        contentTextView.isScrollEnabled = true
        contentTextView.backgroundColor = .clear
        contentTextView.font = .systemFont(ofSize: 14)
        contentTextView.textColor = .secondaryLabel
        contentContainer.addSubview(contentTextView)

        // Shimmer label (for streaming)
        shimmerLabel.translatesAutoresizingMaskIntoConstraints = false
        shimmerLabel.text = "Thinking..."
        shimmerLabel.font = .systemFont(ofSize: 14, weight: .medium)
        shimmerLabel.textColor = .systemPurple
        shimmerLabel.isHidden = true
        addSubview(shimmerLabel)

        // Constraints
        expandedConstraint = contentContainer.heightAnchor.constraint(equalToConstant: 150)
        collapsedConstraint = contentContainer.heightAnchor.constraint(equalToConstant: 0)
        collapsedConstraint.isActive = true

        NSLayoutConstraint.activate([
            headerButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            headerButton.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -8),

            chevronImageView.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
            chevronImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevronImageView.widthAnchor.constraint(equalToConstant: 16),
            chevronImageView.heightAnchor.constraint(equalToConstant: 16),

            shimmerLabel.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
            shimmerLabel.leadingAnchor.constraint(equalTo: headerButton.trailingAnchor, constant: 8),

            contentContainer.topAnchor.constraint(equalTo: headerButton.bottomAnchor, constant: 8),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            contentTextView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentTextView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentTextView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentTextView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    // MARK: - Configure

    func configure(content: String, isStreaming: Bool) {
        isStreamingContent = isStreaming
        contentTextView.text = content

        if isStreaming {
            headerButton.configuration?.title = nil
            shimmerLabel.isHidden = false
            startShimmerAnimation()
        } else {
            headerButton.configuration?.title = "Thinking"
            shimmerLabel.isHidden = true
            stopShimmerAnimation()
        }
    }

    // MARK: - Actions

    @objc private func headerTapped() {
        isExpanded.toggle()

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.collapsedConstraint.isActive = !self.isExpanded
            self.expandedConstraint.isActive = self.isExpanded

            let rotation = self.isExpanded ? CGFloat.pi / 2 : 0
            self.chevronImageView.transform = CGAffineTransform(rotationAngle: rotation)

            self.superview?.layoutIfNeeded()
        }
    }

    // MARK: - Shimmer Animation

    private func startShimmerAnimation() {
        guard shimmerLayer == nil else { return }

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor.systemPurple.withAlphaComponent(0.3).cgColor,
            UIColor.systemPurple.withAlphaComponent(0.8).cgColor,
            UIColor.systemPurple.withAlphaComponent(0.3).cgColor
        ]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.frame = shimmerLabel.bounds.insetBy(dx: -20, dy: 0)

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.5, 0, 0.5]
        animation.toValue = [0.5, 1, 1.5]
        animation.duration = 1.5
        animation.repeatCount = .infinity

        gradient.add(animation, forKey: "shimmer")
        shimmerLabel.layer.mask = gradient
        shimmerLayer = gradient
    }

    private func stopShimmerAnimation() {
        shimmerLayer?.removeAllAnimations()
        shimmerLabel.layer.mask = nil
        shimmerLayer = nil
    }
}
```

---

## 12. Image Grid View

### Step 12.1: Create UIKitImageGridView

**File:** `Iris/Chat/UIKit/Views/UIKitImageGridView.swift`

```swift
import UIKit

final class UIKitImageGridView: UIView {

    private var imageViews: [UIImageView] = []
    private var countLabel: UILabel?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with attachments: [MessageAttachment]) {
        // Clear existing
        subviews.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()
        countLabel = nil

        guard !attachments.isEmpty else { return }

        let images = attachments.compactMap { $0.image }

        switch images.count {
        case 1:
            layoutSingleImage(images[0])
        case 2:
            layoutTwoImages(images)
        case 3:
            layoutThreeImages(images)
        default:
            layoutFourPlusImages(images)
        }
    }

    // MARK: - Layouts

    private func layoutSingleImage(_ image: UIImage) {
        let imageView = createImageView(image: image)
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 180),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 220)
        ])
    }

    private func layoutTwoImages(_ images: [UIImage]) {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.distribution = .fillEqually
        addSubview(stack)

        for image in images.prefix(2) {
            let imageView = createImageView(image: image)
            stack.addArrangedSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.heightAnchor.constraint(equalToConstant: 110),
                imageView.widthAnchor.constraint(equalToConstant: 110)
            ])
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func layoutThreeImages(_ images: [UIImage]) {
        let mainStack = UIStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .vertical
        mainStack.spacing = 4
        addSubview(mainStack)

        // Top row: 2 images
        let topStack = UIStackView()
        topStack.axis = .horizontal
        topStack.spacing = 4
        topStack.distribution = .fillEqually

        for image in images.prefix(2) {
            let imageView = createImageView(image: image)
            topStack.addArrangedSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.heightAnchor.constraint(equalToConstant: 110),
                imageView.widthAnchor.constraint(equalToConstant: 110)
            ])
        }
        mainStack.addArrangedSubview(topStack)

        // Bottom row: 1 image
        if images.count > 2 {
            let imageView = createImageView(image: images[2])
            mainStack.addArrangedSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.heightAnchor.constraint(equalToConstant: 100),
                imageView.widthAnchor.constraint(equalToConstant: 224)
            ])
        }

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func layoutFourPlusImages(_ images: [UIImage]) {
        let mainStack = UIStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .vertical
        mainStack.spacing = 4
        addSubview(mainStack)

        // 2x2 grid
        for row in 0..<2 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 4
            rowStack.distribution = .fillEqually

            for col in 0..<2 {
                let index = row * 2 + col
                if index < images.count {
                    let imageView = createImageView(image: images[index])
                    rowStack.addArrangedSubview(imageView)
                    NSLayoutConstraint.activate([
                        imageView.heightAnchor.constraint(equalToConstant: 110),
                        imageView.widthAnchor.constraint(equalToConstant: 110)
                    ])

                    // Add count overlay on 4th image if more than 4
                    if index == 3 && images.count > 4 {
                        addCountOverlay(to: imageView, count: images.count - 4)
                    }
                }
            }
            mainStack.addArrangedSubview(rowStack)
        }

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Helpers

    private func createImageView(image: UIImage) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageViews.append(imageView)
        return imageView
    }

    private func addCountOverlay(to imageView: UIImageView, count: Int) {
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlay.layer.cornerRadius = 8
        imageView.addSubview(overlay)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "+\(count)"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        overlay.addSubview(label)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])

        countLabel = label
    }
}
```

---

## 13. Scroll Behavior

The scroll behavior is implemented in `UIKitChatViewController`. Key features:

### Near-Bottom Detection
```swift
private func updateScrollButtonVisibility() {
    let contentHeight = collectionView.contentSize.height
    let offset = collectionView.contentOffset.y
    let frameHeight = collectionView.frame.height

    let distanceFromBottom = contentHeight - offset - frameHeight
    isNearBottom = distanceFromBottom < nearBottomThreshold  // 80pt

    UIView.animate(withDuration: 0.2) {
        self.scrollToBottomButton.alpha = self.isNearBottom ? 0 : 1
    }
}
```

### Follow Streaming
```swift
// Start following when user sends a message
if newMessages.count > oldCount && newMessages.last?.role == .user {
    followStreaming = true
}

// Stop following when user manually scrolls up
func scrollViewDidScroll(_ scrollView: UIScrollView) {
    if scrollView.isTracking || scrollView.isDragging {
        if !isNearBottom {
            followStreaming = false
        }
    }
}

// Auto-scroll when following
if self.isNearBottom || self.followStreaming {
    self.scrollToBottom(animated: true)
}
```

---

## 14. Testing Checklist

After implementing all components, verify:

### Feature Flag
- [ ] Toggle appears in Debug Log view
- [ ] Toggle persists across app launches
- [ ] Switching toggle changes chat implementation

### Messages
- [ ] User messages: blue gradient, right-aligned, pinched corner
- [ ] Assistant messages: left-aligned, plain background
- [ ] Timestamps appear below messages
- [ ] Markdown renders correctly in assistant messages

### Images
- [ ] 1 image: 220x180 layout
- [ ] 2 images: side-by-side 110x110
- [ ] 3 images: 2 on top, 1 below
- [ ] 4+ images: 2x2 grid with +N overlay

### Thinking Blocks
- [ ] `<think>` tags parsed correctly
- [ ] Collapsible with chevron rotation
- [ ] Shimmer animation while streaming

### Typing Indicator
- [ ] Shows when generating and last message empty
- [ ] 3-dot bounce animation
- [ ] Hides when content arrives

### Input
- [ ] Text field expands with content
- [ ] Image picker opens and adds images
- [ ] Send/stop button toggles correctly
- [ ] Pending images show with remove button

### Scrolling
- [ ] Scroll-to-bottom button appears when scrolled up
- [ ] Auto-scrolls during streaming
- [ ] User scroll interrupts auto-scroll
- [ ] Manual scroll-to-bottom resumes following

---

## Next Steps After Implementation

1. **Performance Testing**: Compare scroll performance with SwiftUI version
2. **Memory Profiling**: Check for cell reuse issues
3. **A/B Testing**: If desired, add analytics to compare user engagement
4. **Iterate**: Based on testing, decide whether to make UIKit the default

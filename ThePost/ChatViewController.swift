//
//  ChatViewController.swift
//  ThePost
//
//  Created by Andrew Robinson on 1/8/17.
//  Copyright © 2017 The Post. All rights reserved.
//

import UIKit
import Firebase
import JSQMessagesViewController

class ChatViewController: JSQMessagesViewController, UIDynamicAnimatorDelegate {
    
    var conversation: Conversation! {
        didSet {
            title = conversation.otherPersonName
        }
    }
    
    var greenButton: UIButton!
    var outlineButton: UIButton!
    
    var soldContainer: UIView!
    var soldImageView: UIImageView!
    var writeAReviewButton: UIButton!
    
    var soldImageViewMidConstraint: NSLayoutConstraint!
    
    private var conversationRef: FIRDatabaseReference? {
        didSet {
            messageRef = conversationRef!.child("messages")
            userTypingRef = conversationRef!.child("typingIndicator").child(senderId)
            otherUserTypingQueryRef = conversationRef!.child("typingIndicator").child(conversation.otherPersonId)
            
            observeMessages()
        }
    }
    private var messageRef: FIRDatabaseReference!
    private var messageQueryRef: FIRDatabaseQuery!
    private var userTypingRef: FIRDatabaseReference!
    private var otherUserTypingQueryRef: FIRDatabaseQuery!
    
    private var productIsSoldRef: FIRDatabaseReference!
    
    private var messages = [JSQMessage]()
    
    private var outgoingBubble: JSQMessagesBubbleImage!
    private var incomingBubble: JSQMessagesBubbleImage!
    
    private var localTyping = false
    private var isTyping: Bool {
        get {
            return localTyping
        }
        set {
            localTyping = newValue
            if conversationRef != nil {
                userTypingRef.setValue(newValue)
            }
        }
    }
    
    private var animator: UIDynamicAnimator!
    
    private var isProductOwner = false
    private var isProductSold = false {
        didSet {
            if isProductSold {
                
                let ogCenter = soldImageView.center
                let containerOgFrame = soldContainer.frame
                soldImageViewMidConstraint.constant = -soldContainer.frame.width
                soldContainer.frame = CGRect(x: soldContainer.frame.origin.x,
                                             y: soldContainer.frame.origin.y,
                                             width: 0,
                                             height: soldContainer.frame.height)
                
                UIView.animate(withDuration: 0.5, animations: {
                    self.greenButton.alpha = 0.0
                    self.outlineButton.alpha = 0.0
                    
                    self.soldContainer.alpha = 1.0
                    self.soldImageView.alpha = 1.0
                    
                    self.soldContainer.frame = containerOgFrame
                    self.view.layoutIfNeeded()
                }, completion: { done in
                    let snap = UISnapBehavior(item: self.soldImageView, snapTo: ogCenter)
                    snap.damping = 1.0
                    self.animator.addBehavior(snap)
                })
                
            } else {
                let originalContainerFrame = soldContainer.frame
                UIView.animate(withDuration: 0.25, animations: {
                    self.greenButton.alpha = 1.0
                    self.outlineButton.alpha = 1.0
                    self.soldContainer.frame = CGRect(x: self.soldContainer.frame.origin.x,
                                                      y: self.soldContainer.frame.origin.y - self.soldContainer.frame.height,
                                                      width: self.soldContainer.frame.width,
                                                      height: self.soldContainer.frame.height)
                }, completion: { done in
                    self.soldContainer.alpha = 0.0
                    self.soldContainer.frame = originalContainerFrame
                })
            }
        }
    }
    
    private var inputBarDefaultHeight: CGFloat!
    
    // MARK: - View lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        animator = UIDynamicAnimator()
        animator.delegate = self
        
        senderId = FIRAuth.auth()!.currentUser!.uid
        senderDisplayName = conversation.otherPersonName
        
        if conversation.id != "" {
            conversationRef = FIRDatabase.database().reference().child("chats").child(conversation.id)
        }
        
        productIsSoldRef = FIRDatabase.database().reference().child("products").child(conversation.productID).child("isSold")
        getProductDetails()
        
        collectionView.backgroundColor = #colorLiteral(red: 0.1870684326, green: 0.2210902572, blue: 0.2803535461, alpha: 1)
        
        inputToolbar.contentView.backgroundColor = #colorLiteral(red: 0.9098039216, green: 0.9058823529, blue: 0.8235294118, alpha: 1)
        inputToolbar.contentView.textView.backgroundColor = #colorLiteral(red: 0.1882352941, green: 0.2196078431, blue: 0.2784313725, alpha: 1)
        inputToolbar.contentView.textView.textColor = #colorLiteral(red: 0.9098039216, green: 0.9058823529, blue: 0.8235294118, alpha: 1)
        
        if let message = conversation.firstMessage, message != "" {
            inputToolbar.contentView.textView.text = message
            
            inputBarDefaultHeight = inputToolbar.preferredDefaultHeight
            inputToolbar.preferredDefaultHeight = 120.0
        }
        
        outgoingBubble = setupOutgoingBubble()
        incomingBubble = setupIncomingBubble()
        
        collectionView!.collectionViewLayout.outgoingAvatarViewSize = .zero
        collectionView!.collectionViewLayout.incomingAvatarViewSize = .zero
        
        greenButton.roundCorners(radius: 8.0)
        greenButton.alpha = 0.0
        
        outlineButton.roundCorners(radius: 8.0)
        outlineButton.alpha = 0.0
        outlineButton.layer.borderColor = outlineButton.titleLabel!.textColor.cgColor
        outlineButton.layer.borderWidth = 1.0
        
        soldContainer.alpha = 0.0
        soldImageView.alpha = 0.0
        
        writeAReviewButton.alpha = 0.0
        writeAReviewButton.roundCorners(radius: 8.0)
        writeAReviewButton.layer.borderColor = outlineButton.titleLabel!.textColor.cgColor
        writeAReviewButton.layer.borderWidth = 1.0
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        collectionView.collectionViewLayout.springinessEnabled = true
        
        if conversation.id != "" {
            observeTyping()
        }
    }
    
    deinit {
        messageQueryRef.removeAllObservers()
        otherUserTypingQueryRef.removeAllObservers()
        productIsSoldRef.removeAllObservers()
    }
    
    // MARK: - Animator delegate
    
    func dynamicAnimatorDidPause(_ animator: UIDynamicAnimator) {
        if !isProductOwner {
            writeAReviewButton.addTarget(self, action: #selector(writeAReviewButtonPressed), for: .touchUpInside)
            
            UIView.animate(withDuration: 0.25, animations: {
                self.soldImageView.alpha = 0.0
                self.writeAReviewButton.alpha = 1.0
            })
        }
    }
    
    // MARK: - JSQCollectionView datasource
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageDataForItemAt indexPath: IndexPath!) -> JSQMessageData! {
        return messages[indexPath.row]
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAt: indexPath) as! JSQMessagesCollectionViewCell
        let message = messages[indexPath.row]
        
        if message.senderId == senderId {
            cell.textView!.textColor = UIColor.white
        } else {
            cell.textView!.textColor = UIColor.black
        }
        
        return cell
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageBubbleImageDataForItemAt indexPath: IndexPath!) -> JSQMessageBubbleImageDataSource! {
        var imageToReturn: JSQMessageBubbleImageDataSource
        if messages[indexPath.row].senderId == senderId {
            imageToReturn = outgoingBubble
        } else {
            imageToReturn = incomingBubble
        }
        
        return imageToReturn
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, avatarImageDataForItemAt indexPath: IndexPath!) -> JSQMessageAvatarImageDataSource! {
        return nil
    }
    
    // MARK: - JSQBubble Colors
    
    private func setupOutgoingBubble() -> JSQMessagesBubbleImage {
        return JSQMessagesBubbleImageFactory().outgoingMessagesBubbleImage(with: #colorLiteral(red: 0.8470588235, green: 0.337254902, blue: 0.2156862745, alpha: 1))
    }
    
    private func setupIncomingBubble() -> JSQMessagesBubbleImage {
        return JSQMessagesBubbleImageFactory().incomingMessagesBubbleImage(with: #colorLiteral(red: 0.9098039216, green: 0.9058823529, blue: 0.8235294118, alpha: 1))
    }
    
    // MARK: - JSQMessages Actions
    
    override func didPressSend(_ button: UIButton!, withMessageText text: String!, senderId: String!, senderDisplayName: String!, date: Date!) {
        
        if conversationRef == nil {
            conversationRef = FIRDatabase.database().reference().child("chats").childByAutoId()
            
            let userChatsRef = FIRDatabase.database().reference().child("user-chats")
            let childUpdate = [conversationRef!.key: true]
            
            userChatsRef.child(conversation.otherPersonId).updateChildValues(childUpdate)
            userChatsRef.child(senderId).updateChildValues(childUpdate)
            
            inputToolbar.preferredDefaultHeight = inputBarDefaultHeight
        }
        
        let itemRef = messageRef.childByAutoId()
        
        let messageItem = ["senderId": senderId, "senderName": senderDisplayName, "text": text] as [String: String]
        
        itemRef.setValue(messageItem)
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
        
        finishSendingMessage()
        
        isTyping = false
    }
    
    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)
        
        isTyping = textView.text != ""
    }
    
    // MARK: - Other Actions
    
    @objc private func greenButtonPressed() {
        if greenButton.currentTitle == "Mark Sold" {
            let productRef = FIRDatabase.database().reference()
            let childUpdates = ["products/\(conversation.productID!)/isSold": true,
                                "user-products/\(senderId!)/\(conversation.productID!)/isSold": true]
            productRef.updateChildValues(childUpdates)
        } else if greenButton.currentTitle == "View Profile" {
            // TODO: View profile...
        }
    }
    
    @objc private func outlinedButtonPressed() {
        if outlineButton.currentTitle == "View Product" {
            // TODO: View product...
        }
    }
    
    @objc private func writeAReviewButtonPressed() {
        // TODO: Open Write A Review...
    }
    
    // MARK: - Helpers
    
    private func addMessage(withId id: String, name: String, text: String) {
        if let message = JSQMessage(senderId: id, displayName: name, text: text) {
            messages.append(message)
        }
    }
    
    private func observeMessages() {
        messageQueryRef = messageRef.queryLimited(toLast: 25)
        
        messageQueryRef.observe(.childAdded, with: { snapshot in
            if let messageDict = snapshot.value as? [String: String] {
                if let id = messageDict["senderId"], let name = messageDict["senderName"], let text = messageDict["text"] {
                    self.addMessage(withId: id, name: name, text: text)
                    self.finishReceivingMessage()
                }
            }
        })
        
    }
    
    private func observeTyping() {
        userTypingRef.onDisconnectRemoveValue()
        
        otherUserTypingQueryRef.observe(.value, with: { snapshot in
            if let isTyping = snapshot.value as? Bool {
                self.showTypingIndicator = isTyping
                self.scrollToBottom(animated: true)
            }
        })
    }
    
    private func getProductDetails() {
        let productRef = FIRDatabase.database().reference().child("products").child(conversation.productID)
        productRef.observeSingleEvent(of: .value, with: { snapshot in
            if let productDict = snapshot.value as? [String: Any] {
                if let ownerID = productDict["owner"] as? String {
                    var greenText = ""
                    var outlineText = ""
                    if ownerID == self.senderId {
                        greenText = "Mark Sold"
                        outlineText = "View Product"
                        self.isProductOwner = true
                    } else {
                        greenText = "View Profile"
                        outlineText = "View Product"
                    }
                    
                    if let isSold = productDict["isSold"] as? Bool{
                        if isSold {
                            self.isProductSold = true
                        } else {
                            self.isProductSold = false
                        }
                    } else {
                        self.isProductSold = false
                    }
                    
                    if !self.isProductSold {
                        self.setupIsSoldObserver()
                    }
                    
                    self.greenButton.addTarget(self, action: #selector(self.greenButtonPressed), for: .touchUpInside)
                    self.outlineButton.addTarget(self, action: #selector(self.outlinedButtonPressed), for: .touchUpInside)
                    
                    DispatchQueue.main.async {
                        self.greenButton.setTitle(greenText, for: .normal)
                        self.outlineButton.setTitle(outlineText, for: .normal)
                    }
                }
            }
        })
    }
    
    private func setupIsSoldObserver() {
        productIsSoldRef.observe(.value, with: { snapshot in
            if let isSold = snapshot.value as? Bool {
                if isSold  {
                    self.isProductSold = true
                }
            }
        })
    }
    
}

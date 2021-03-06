//
//  ZomMessagesViewController.swift
//  Zom
//
//  Created by N-Pex on 2015-11-11.
//
//

import UIKit
import ChatSecureCore
import JSQMessagesViewController
import OTRAssets
import BButton
import AFNetworking

var ZomMessagesViewController_associatedObject1: UInt8 = 0

extension OTRMessagesViewController {
    
    private static var swizzle: () {
        
        ZomUtil.swizzle(self, originalSelector: #selector(OTRMessagesViewController.collectionView(_:messageDataForItemAt:)), swizzledSelector:#selector(OTRMessagesViewController.zom_collectionView(_:messageDataForItemAtIndexPath:)))
    }
    
    open override class func initialize() {
        
        // make sure this isn't a subclass
        if self !== OTRMessagesViewController.self {
            return
        }
        OTRMessagesViewController.swizzle
    }
    
    var shieldIcon:UIImage? {
        get {
            return objc_getAssociatedObject(self, &ZomMessagesViewController_associatedObject1) as? UIImage ?? nil
        }
        set {
            objc_setAssociatedObject(self, &ZomMessagesViewController_associatedObject1, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    public func zom_collectionView(_ collectionView: JSQMessagesCollectionView, messageDataForItemAtIndexPath indexPath: NSIndexPath) -> ChatSecureCore.JSQMessageData {
        let ret = self.zom_collectionView(collectionView, messageDataForItemAtIndexPath: indexPath)
        if let text = ret.text?() {
            if ZomStickerMessage.isValidStickerShortCode(text) {
                return ZomStickerMessage(message: ret)
            }
        }
        return ret
    }
    
    func textAttachment(image: UIImage, fontSize: CGFloat) -> NSTextAttachment {
        var font:UIFont? = UIFont(name: kFontAwesomeFont, size: fontSize)
        if (font == nil) {
            font = UIFont.systemFont(ofSize: fontSize)
        }
        let textAttachment = NSTextAttachment()
        textAttachment.image = image
        let aspect = image.size.width / image.size.height
        let height = font?.capHeight
        textAttachment.bounds = CGRect(x:0,y:0,width:(height! * aspect),height:height!).integral
        return textAttachment
    }
    
    func getTintedShieldIcon() -> UIImage {
        if (self.shieldIcon == nil) {
            let image = UIImage.init(named: "ic_security_white_36pt")
            self.shieldIcon = image?.tint(UIColor.lightGray, blendMode: CGBlendMode.multiply)
        }
        return shieldIcon!
    }
}

open class ZomMessagesViewController: OTRMessagesHoldTalkViewController, UIGestureRecognizerDelegate, ZomPickStickerViewControllerDelegate {
    
    private var hasFixedTitleViewConstraints:Bool = false
    private var attachmentPickerController:OTRAttachmentPicker? = nil
    private var attachmentPickerView:AttachmentPicker? = nil
    private var attachmentPickerTapRecognizer:UITapGestureRecognizer? = nil
    private var noNetworkView:UITextView?
    private var preparingView:UIView?
    private var pendingApprovalView:UIView?
    private var singleCheckIcon:UIImage?
    private var doubleCheckIcon:UIImage?
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        self.cameraButton?.setTitle(NSString.fa_string(forFontAwesomeIcon: FAIcon.FAPlusSquareO), for: .normal)
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AFNetworkReachabilityManager.shared().setReachabilityStatusChange { (status:AFNetworkReachabilityStatus) in
            self.setHasNetwork(AFNetworkReachabilityManager.shared().isReachable)
        }
        AFNetworkReachabilityManager.shared().startMonitoring()
        
        // Don't allow sending to archived
        super.readOnlyDatabaseConnection.read { (transaction) in
            if let threadOwner = self.threadObject(with: transaction), threadOwner.isArchived {
                self.inputToolbar.isHidden = true
            } else {
                self.inputToolbar.isHidden = false
            }
        }
    }
    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AFNetworkReachabilityManager.shared().stopMonitoring()
    }
    
    open func attachmentPicker(_ attachmentPicker: OTRAttachmentPicker!, addAdditionalOptions alertController: UIAlertController!) {
        
        let sendStickerAction: UIAlertAction = UIAlertAction(title: NSLocalizedString("Sticker", comment: "Label for button to open up sticker library and choose sticker"), style: UIAlertActionStyle.default, handler: { (UIAlertAction) -> Void in
            let storyboard = UIStoryboard(name: "StickerShare", bundle: Bundle.main)
            let vc = storyboard.instantiateInitialViewController()
            self.present(vc!, animated: true, completion: nil)
        })
        alertController.addAction(sendStickerAction)
    }
    
    @IBAction func unwindPickSticker(_ unwindSegue: UIStoryboardSegue) {
    }
    
    open func didPickSticker(_ sticker: String, inPack pack: String) {
        super.didPressSend(super.sendButton, withMessageText: ":" + pack + "-" + sticker + ":", senderId: super.senderId, senderDisplayName: super.senderDisplayName, date: Date())
    }
    
    override open func refreshTitleView() -> Void {
        super.refreshTitleView()
        if (OTRAccountsManager.allAccounts().count < 2) {
            // Hide the account name if only one
            if let view = self.navigationItem.titleView as? OTRTitleSubtitleView {
                view.subtitleLabel.isHidden = true
                view.subtitleImageView.isHidden = true
                if (!hasFixedTitleViewConstraints && view.constraints.count > 0) {
                    var removeThese:[NSLayoutConstraint] = [NSLayoutConstraint]()
                    for constraint:NSLayoutConstraint in view.constraints {
                        if ((constraint.firstItem as? NSObject != nil && constraint.firstItem as! NSObject == view.titleLabel) || (constraint.secondItem as? NSObject != nil && constraint.secondItem as! NSObject == view.titleLabel)) {
                            if (constraint.isActive && (constraint.firstAttribute == NSLayoutAttribute.top || constraint.firstAttribute == NSLayoutAttribute.bottom)) {
                                removeThese.append(constraint)
                            }
                        }
                    }
                    view.removeConstraints(removeThese)
                    let c:NSLayoutConstraint = NSLayoutConstraint(item: view.titleLabel, attribute: NSLayoutAttribute.centerY, relatedBy: NSLayoutRelation.equal, toItem: view.titleLabel.superview, attribute: NSLayoutAttribute.centerY, multiplier: 1, constant: 0)
                    view.addConstraint(c);
                    hasFixedTitleViewConstraints = true
                }
            }
        }
    }
    
    override open func setupDefaultSendButton() {
        // Override this to always show Camera and Mic icons. We never get here
        // in a "knock" scenario.
        self.inputToolbar?.contentView?.leftBarButtonItem = self.cameraButton
        self.inputToolbar?.contentView?.leftBarButtonItem.isEnabled = false
        if (self.state.hasText) {
            self.inputToolbar?.contentView?.rightBarButtonItem = self.sendButton
            self.inputToolbar?.sendButtonLocation = JSQMessagesInputSendButtonLocation.right
            self.inputToolbar?.contentView?.rightBarButtonItem.isEnabled = self.state.isThreadOnline
        } else {
            self.inputToolbar?.contentView?.rightBarButtonItem = self.microphoneButton
            self.inputToolbar?.contentView?.rightBarButtonItem.isEnabled = false
        }
    }
    
    override open func didPressAccessoryButton(_ sender: UIButton!) {
        if (sender == self.cameraButton) {
            let pickerView = getPickerView()
            self.view.addSubview(pickerView)
            var newFrame = pickerView.frame;
            let toolbarBottom = self.inputToolbar.frame.origin.y + self.inputToolbar.frame.size.height
            newFrame.origin.y = toolbarBottom - newFrame.size.height;
            UIView.animate(withDuration: 0.3, animations: {
                pickerView.frame = newFrame;
            }) 
        } else {
            super.didPressAccessoryButton(sender)
        }
    }
    
    func getPickerView() -> UIView {
        if (self.attachmentPickerView == nil) {
            self.attachmentPickerView = UINib(nibName: "AttachmentPicker", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as? AttachmentPicker
            self.attachmentPickerView!.frame.size.width = self.view.frame.width
            self.attachmentPickerView!.frame.size.height = 100
            let toolbarBottom = self.inputToolbar.frame.origin.y + self.inputToolbar.frame.size.height
            self.attachmentPickerView!.frame.origin.y = toolbarBottom // Start hidden (below screen)
         
            if (!UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.photoLibrary)) {
                self.attachmentPickerView!.removePhotoButton()
            }
            if (!UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera)) {
                self.attachmentPickerView!.removeCameraButton()
            }
            
            self.attachmentPickerTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.onTap(_:)))
            self.attachmentPickerTapRecognizer!.cancelsTouchesInView = true
            self.attachmentPickerTapRecognizer!.delegate = self
            self.view.addGestureRecognizer(self.attachmentPickerTapRecognizer!)
        }
        return self.attachmentPickerView!
    }
    
    func onTap(_ sender: UIGestureRecognizer) {
        closePickerView()
    }
    
    func closePickerView() {
        // Tapped outside attachment picker. Close it.
        if (self.attachmentPickerTapRecognizer != nil) {
            self.view.removeGestureRecognizer(self.attachmentPickerTapRecognizer!)
            self.attachmentPickerTapRecognizer = nil
        }
        if (self.attachmentPickerView != nil) {
            var newFrame = self.attachmentPickerView!.frame;
            let toolbarBottom = self.inputToolbar.frame.origin.y + self.inputToolbar.frame.size.height
            newFrame.origin.y = toolbarBottom
            UIView.animate(withDuration: 0.3, animations: {
                    self.attachmentPickerView!.frame = newFrame;
                },
                                       completion: { (success) in
                                        self.attachmentPickerView?.removeFromSuperview()
                                        self.attachmentPickerView = nil
            })
        }
    }
    
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    @IBAction func attachmentPickerSelectPhotoWithSender(_ sender: AnyObject) {
        closePickerView()
        attachmentPicker().showImagePicker(for: UIImagePickerControllerSourceType.photoLibrary)
    }
    
    @IBAction func attachmentPickerTakePhotoWithSender(_ sender: AnyObject) {
        closePickerView()
        attachmentPicker().showImagePicker(for: UIImagePickerControllerSourceType.camera)
    }
    
    func attachmentPicker() -> OTRAttachmentPicker {
        if (self.attachmentPickerController == nil) {
            self.attachmentPickerController = OTRAttachmentPicker(parentViewController: self.parent?.parent, delegate: (self as! OTRAttachmentPickerDelegate))
        }
        return self.attachmentPickerController!
    }
    
    @IBAction func attachmentPickerStickerWithSender(_ sender: AnyObject) {
        closePickerView()
        let storyboard = UIStoryboard(name: "StickerShare", bundle: Bundle.main)
        let vc = storyboard.instantiateInitialViewController()
        self.present(vc!, animated: true, completion: nil)
    }
    
    public func setupInfoButton() {
        let image = UIImage(named: "OTRInfoIcon", in: OTRAssets.resourcesBundle, compatibleWith: nil)
        let item = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(infoButtonPressed(_:)))
        self.navigationItem.rightBarButtonItem = item
    }
    
    
    @objc open override func infoButtonPressed(_ sender: Any?) {

        var threadOwner: OTRThreadOwner? = nil
        var _account: OTRAccount? = nil
        self.readOnlyDatabaseConnection.read { (t) in
            threadOwner = self.threadObject(with: t)
            _account = self.account(with: t)
        }
        guard let buddy = threadOwner as? OTRBuddy, let account = _account else {
            return
        }
        let profileVC = ZomProfileViewController(nibName: nil, bundle: nil)
        let otrKit = OTRProtocolManager.sharedInstance().encryptionManager.otrKit
        let info = ZomProfileViewControllerInfo.createInfo(buddy, accountName: account.username, protocolString: account.protocolTypeString(), otrKit: otrKit, hasSession: true)
        profileVC.setupWithInfo(info: info)
        
        self.navigationController?.pushViewController(profileVC, animated: true)
    }
    
    open override func deliveryStatusString(for message: OTROutgoingMessage) -> NSAttributedString? {
        if (message.dateSent != nil) {
            if (message.isDelivered) {
                if self.doubleCheckIcon == nil {
                    self.doubleCheckIcon = UIImage.init(named: "ic_delivered_grey")
                }
                if let image = self.doubleCheckIcon {
                    let attachment = self.textAttachment(image: image, fontSize: 12)
                    return NSAttributedString(attachment: attachment)
                }
            } else {
                if self.singleCheckIcon == nil {
                    self.singleCheckIcon = UIImage.init(named: "ic_sent_grey")
                }
                if let image = self.singleCheckIcon {
                    let attachment = self.textAttachment(image: image, fontSize: 12)
                    return NSAttributedString(attachment: attachment)
                }
            }
        }
        return nil
    }
    
    open override func encryptionStatusString(forMessage message: OTRMessageProtocol) -> NSAttributedString? {
        switch message.messageSecurity {
        case .OMEMO: fallthrough
        case .OTR:
            let attachment = textAttachment(image: getTintedShieldIcon(), fontSize: 12)
            return NSAttributedString(attachment: attachment)
        default:
            return nil
        }
    }
    
    func setHasNetwork(_ hasNetwork:Bool) {
        if (hasNetwork) {
            if let view = self.noNetworkView {
                UIView.animate(withDuration: 0.5, animations: { 
                    self.noNetworkView?.frame.origin.y = -30
                }, completion: { (success) in
                    view.isHidden = true
                })
            }
        } else {
            if (self.noNetworkView == nil) {
                self.noNetworkView = UITextView(frame: CGRect(x: 0, y: -30, width: self.navigationController?.navigationBar.frame.width ?? 0, height: 30))
                self.noNetworkView?.backgroundColor = UIColor(netHex: 0xff4a4a4a)
                self.noNetworkView?.text = "No Internet"
                self.noNetworkView?.textColor = UIColor.white
                self.noNetworkView?.textAlignment = NSTextAlignment.center
                self.view.addSubview(self.noNetworkView!)
            }
            if let view = self.noNetworkView {
                view.isHidden = false
                UIView.animate(withDuration: 0.5, animations: {
                    self.noNetworkView?.frame.origin.y = 0
                }, completion: { (success) in
                })
            }
        }
    }
    
    override open func didUpdateState() {
        super.didUpdateState()
        self.readOnlyDatabaseConnection.asyncRead { [weak self] (transaction) in
            guard let strongSelf = self else { return }
            guard let threadKey = strongSelf.threadKey else { return }
            guard let buddy = transaction.object(forKey: threadKey, inCollection: strongSelf.threadCollection) as? OTRBuddy else { return }
            
            DispatchQueue.main.async {
                if (strongSelf.state.isThreadOnline && buddy.preferredSecurity != OTRSessionSecurity.plaintextOnly) {
                    // Find out if we have previous fingerprints, i.e. if this is
                    // THE VERY FIRST encrypted session we are trying to create.
                    let otrMessageTransportSecurity = buddy.bestTransportSecurity(with: transaction)
                    if (otrMessageTransportSecurity != OTRMessageTransportSecurity.plaintext && otrMessageTransportSecurity != OTRMessageTransportSecurity.plaintextWithOTR) {
                        // We have fingerprints, hide the preparing view
                        strongSelf.updatePreparingView(false)
                    } else {
                        strongSelf.updatePreparingView(true)
                    }
                } else {
                    // Plaintext only, don't show the preparing view
                    strongSelf.updatePreparingView(false)
                }
                
                if let xmppbuddy = buddy as? OTRXMPPBuddy, xmppbuddy.pendingApproval {
                    if strongSelf.pendingApprovalView == nil {
                        strongSelf.pendingApprovalView = UINib(nibName: "WaitingForApprovalView", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as? UIView
                        strongSelf.view.addSubview(strongSelf.pendingApprovalView!)
                    }
                    strongSelf.pendingApprovalView!.frame = strongSelf.view.bounds
                    strongSelf.view.bringSubview(toFront: strongSelf.pendingApprovalView!)
                } else {
                    if strongSelf.pendingApprovalView != nil {
                        strongSelf.pendingApprovalView?.removeFromSuperview()
                        strongSelf.pendingApprovalView = nil
                    }
                }
            }
        }
    }
    
    func updatePreparingView(_ show:Bool) {
        if (!show) {
            if let view = self.preparingView {
                UIView.animate(withDuration: 0.5, animations: {
                    self.preparingView?.alpha = 0.0
                }, completion: { (success) in
                    view.isHidden = true
                })
                self.preparingView = nil
            }
        } else {
            if (self.preparingView == nil) {
                self.preparingView = UINib(nibName: "PreparingSessionView",
                    bundle: Bundle.main
                    ).instantiate(withOwner: nil, options: nil)[0] as? UIView
                let size = self.preparingView?.systemLayoutSizeFitting(UILayoutFittingCompressedSize)
                self.preparingView?.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: size!.height)
                self.preparingView?.alpha = 0.0
                self.view.addSubview(self.preparingView!)
            }
            if let view = self.preparingView {
                view.isHidden = false
                UIView.animate(withDuration: 0.5, animations: {
                    self.preparingView?.alpha = 1
                }, completion: { (success) in
                })
            }
        }
    }
    
    override open func didPressMigratedSwitch() {
        // Archive this convo
        self.readWriteDatabaseConnection.readWrite { (transaction) in
            let thread = self.threadObject(with: transaction)
            if let buddy = thread as? OTRXMPPBuddy {
                buddy.isArchived = true
                buddy.save(with: transaction)
            }
        }
        super.didPressMigratedSwitch()
    }
    
    open override func didSetupMappings(_ handler: OTRYapViewHandler!) {
        super.didSetupMappings(handler)
        let numberMappingsItems = handler.mappings?.numberOfItems(inSection: 0) ?? 0
        if numberMappingsItems > 0 {
            self.checkRangeForMigrationMessage(range: NSMakeRange(0, Int(numberMappingsItems)))
        }
    }
    
    open override func didReceiveChanges(_ handler: OTRYapViewHandler!, sectionChanges: [YapDatabaseViewSectionChange]!, rowChanges: [YapDatabaseViewRowChange]!) {
        var collectionViewNumberOfItems = 0
        var numberMappingsItems = 0
        if rowChanges.count > 0 {
            collectionViewNumberOfItems = self.collectionView.numberOfItems(inSection: 0)
            numberMappingsItems = Int(self.viewHandler.mappings?.numberOfItems(inSection: 0) ?? 0)
        }
        super.didReceiveChanges(handler, sectionChanges: sectionChanges, rowChanges: rowChanges)
        if numberMappingsItems > collectionViewNumberOfItems, numberMappingsItems > 0 {
                self.checkRangeForMigrationMessage(range: NSMakeRange(collectionViewNumberOfItems, numberMappingsItems - collectionViewNumberOfItems))
        }
    }
    
    // If we find any incoming migration link messages, show the "your friend has migrated" header
    // to allow the user to start chatting with the new account instead.
    func checkRangeForMigrationMessage(range: NSRange) {
        DispatchQueue.global().async {

            let types: NSTextCheckingResult.CheckingType = [.link]
            let detector = try? NSDataDetector(types: types.rawValue)
                for i in range.location..<(range.location + range.length) {
                    if let message = self.message(at: IndexPath(row: i, section: 0)), message.isMessageIncoming, let text = message.messageText {
                        
                        detector?.enumerateMatches(in: text, range: NSMakeRange(0, text.utf16.count)) {
                            (result, _, _) in
                            if let res = result, let url = res.url, let nsurl = NSURL(string: url.absoluteString) {
                                if nsurl.otr_isInviteLink {
                                    nsurl.otr_decodeShareLink({ (jid, queryItems:[URLQueryItem]?) in
                                        if let query = queryItems, NSURL.otr_queryItemsContainMigrationHint(query) {
                                            DispatchQueue.main.async {
                                                self.showJIDForwardingHeader(withNewJID: jid)
                                            }
                                        }
                                    })
                                }
                            }
                        }
                    }
                }
        }
    }
}

extension UIImage
{
    func tint(_ color: UIColor, blendMode: CGBlendMode) -> UIImage
    {
        let drawRect = CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height)
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        let context = UIGraphicsGetCurrentContext()
        context!.scaleBy(x: 1.0, y: -1.0)
        context!.translateBy(x: 0.0, y: -self.size.height)
        context!.clip(to: drawRect, mask: cgImage!)
        color.setFill()
        UIRectFill(drawRect)
        draw(in: drawRect, blendMode: blendMode, alpha: 1.0)
        let tintedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return tintedImage!
    }
}


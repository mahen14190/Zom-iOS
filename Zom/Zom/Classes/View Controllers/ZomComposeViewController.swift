//
//  ZomComposeViewController.swift
//  Zom
//
//  Created by N-Pex on 2015-11-24.
//
//

import UIKit
import ChatSecureCore

open class ZomComposeViewController: OTRComposeViewController {
    
    static var extensionName:String = "Zom" + OTRAllBuddiesDatabaseViewExtensionName
    static var filteredExtensionName:String = "Zom" + OTRFilteredBuddiesName
    open static var openInGroupMode:Bool = false
    var archivedFriendInfoView:UIView?
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        DispatchQueue.main.async {
            self.setupZomSortedView()
        }
        if (ZomComposeViewController.openInGroupMode) {
            ZomComposeViewController.openInGroupMode = false
            self.switchSelectionMode()
        }
        navigationItem.title = NSLocalizedString("Choose a Friend", comment: "When selecting friend")
    }

    override open func viewWillLayoutSubviews() {
        if self.inboxArchiveControl.selectedSegmentIndex == 1, !UserDefaults.standard.bool(forKey: "zom_ArchivedFriendInfoViewShown") {
            if archivedFriendInfoView == nil {
                archivedFriendInfoView = UINib(nibName: "ArchivedFriendInfoView", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as? UIView
                if let view = archivedFriendInfoView {
                    view.translatesAutoresizingMaskIntoConstraints = false
                    self.view.addSubview(view)
                    
                    let hconstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:|[view]|", options: NSLayoutFormatOptions.alignAllLeading, metrics: nil, views: ["view":view])
                    NSLayoutConstraint.activate(hconstraints)
                }
            }
        } else if archivedFriendInfoView != nil {
            archivedFriendInfoView?.removeFromSuperview()
            archivedFriendInfoView = nil
        }
    }
    
    override open func viewDidLayoutSubviews() {
        if let view = archivedFriendInfoView {
            var frame = self.tableView.frame
            frame = frame.offsetBy(dx: 0, dy: view.frame.height)
            self.tableView.frame = frame
        }
    }
    
    override open func updateInboxArchiveFilteringAndShowArchived(_ showArchived: Bool) {
        super.updateInboxArchiveFilteringAndShowArchived(showArchived)
        OTRDatabaseManager.shared.readWriteDatabaseConnection?.asyncReadWrite({ (transaction) in
            if let fvt = transaction.ext(ZomComposeViewController.filteredExtensionName) as? YapDatabaseFilteredViewTransaction {
                fvt.setFiltering(self.getFilteringBlock(showArchived), versionTag:NSUUID().uuidString)
            }
        })
        self.view.setNeedsLayout()
    }
    
    func setupZomSortedView() {
        // This sets up a database view that is identical to the original "OTRAllBuddiesDatabaseView" but
        // with the difference that  XMPPBuddies that are avaiting approval are ordered to the top of the list.
        //
        if OTRDatabaseManager.shared.database?.registeredExtension(ZomComposeViewController.extensionName) == nil {
            if let originalView:YapDatabaseAutoView = OTRDatabaseManager.sharedInstance().database?.registeredExtension(OTRAllBuddiesDatabaseViewExtensionName) as? YapDatabaseAutoView {
                let sorting = YapDatabaseViewSorting.withObjectBlock({ (transaction, group, collection1, group1, object1, collection2, group2, object2) -> ComparisonResult in
                    let pendingApproval1 = (object1 as? OTRXMPPBuddy)?.pendingApproval ?? false
                    let pendingApproval2 = (object2 as? OTRXMPPBuddy)?.pendingApproval ?? false
                    if (pendingApproval1 && !pendingApproval2) {
                        return .orderedAscending
                    } else if (!pendingApproval1 && pendingApproval2) {
                        return .orderedDescending
                    }
                    if let originalBlock = originalView.sorting.block as? YapDatabaseViewSortingWithObjectBlock {
                        return originalBlock(transaction, group, collection1, group1, object1, collection2, group2, object2)
                    }
                    return ComparisonResult.orderedSame
                })
                let options = YapDatabaseViewOptions()
                options.isPersistent = false
                let newView = YapDatabaseAutoView(grouping: originalView.grouping, sorting: sorting, versionTag: "1", options: options)
                OTRDatabaseManager.sharedInstance().database?.register(newView, withName: ZomComposeViewController.extensionName)
            }
        }
        
        if OTRDatabaseManager.shared.database?.registeredExtension(ZomComposeViewController.filteredExtensionName) == nil, OTRDatabaseManager.shared.database?.registeredExtension(OTRFilteredBuddiesName) != nil {
            let options = YapDatabaseViewOptions()
            options.isPersistent = false
            let filtering = getFilteringBlock(false)
            let filteredView = YapDatabaseFilteredView(parentViewName: ZomComposeViewController.extensionName, filtering: filtering!, versionTag: NSUUID().uuidString, options: options)
            OTRDatabaseManager.sharedInstance().database?.register(filteredView, withName: ZomComposeViewController.filteredExtensionName)
        }
        
        self.viewHandler = OTRYapViewHandler.init(databaseConnection: OTRDatabaseManager.sharedInstance().longLivedReadOnlyConnection!, databaseChangeNotificationName: DatabaseNotificationName.LongLivedTransactionChanges)
        self.viewHandler.delegate = self as? OTRYapViewHandlerDelegateProtocol
        self.viewHandler.setup(ZomComposeViewController.filteredExtensionName, groups: [OTRBuddyGroup])
    }
    
    open override func canAddBuddies() -> Bool {
        if (parent is UINavigationController) {
            // When opened from the "chats" tab, we don't want to show the "Add friend" button!
            return false
        }
        return true; // Always show add
    }
    
    open override func addBuddy(_ accountsAbleToAddBuddies: [OTRAccount]?) {
        if let accounts = accountsAbleToAddBuddies {
            if (accounts.count > 0)
            {
                ZomNewBuddyViewController.addBuddyToDefaultAccount(self.navigationController)
            }
        }
    }
    
    @IBAction func didPressGotIt(_ sender: AnyObject) {
        UserDefaults.standard.set(true, forKey: "zom_ArchivedFriendInfoViewShown")
        self.view.setNeedsLayout()
    }
    
}

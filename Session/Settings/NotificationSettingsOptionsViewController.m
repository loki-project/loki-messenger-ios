//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "NotificationSettingsOptionsViewController.h"
#import "Session-Swift.h"
#import "SignalApp.h"
#import <SessionMessagingKit/Environment.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

@implementation NotificationSettingsOptionsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self updateTableContents];

    [LKViewControllerUtilities setUpDefaultSessionStyleForVC:self withTitle:NSLocalizedString(@"Content", @"") customBackButton:NO customBackground:NO];
    self.tableView.backgroundColor = UIColor.clearColor;
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak NotificationSettingsOptionsViewController *weakSelf = self;

    OWSTableSection *section = [OWSTableSection new];
    // section.footerTitle = NSLocalizedString(@"NOTIFICATIONS_FOOTER_WARNING", nil);

    OWSPreferences *prefs = Environment.shared.preferences;
    NotificationType selectedNotifType = [prefs notificationPreviewType];
    for (NSNumber *option in
        @[ @(NotificationNamePreview), @(NotificationNameNoPreview), @(NotificationNoNameNoPreview) ]) {
        NotificationType notificationType = (NotificationType)option.intValue;

        [section addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 UITableViewCell *cell = [OWSTableItem newCell];
                                 cell.tintColor = LKColors.accent;
                                 [[cell textLabel] setText:[prefs nameForNotificationPreviewType:notificationType]];
                                 if (selectedNotifType == notificationType) {
                                     cell.accessoryType = UITableViewCellAccessoryCheckmark;
                                 }
                                 cell.accessibilityIdentifier
                                     = ACCESSIBILITY_IDENTIFIER_WITH_NAME(NotificationSettingsOptionsViewController,
                                         NSStringForNotificationType(notificationType));
                                 return cell;
                             }
                             actionBlock:^{
                                 [weakSelf setNotificationType:notificationType];
                             }]];
    }
    [contents addSection:section];

    self.contents = contents;
}

- (void)setNotificationType:(NotificationType)notificationType
{
    [Environment.shared.preferences setNotificationPreviewType:notificationType];

    [self.navigationController popViewControllerAnimated:YES];
}

@end

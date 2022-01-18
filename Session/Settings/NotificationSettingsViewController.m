//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

@import PromiseKit;

#import "NotificationSettingsViewController.h"
#import "NotificationSettingsOptionsViewController.h"
#import "OWSSoundSettingsViewController.h"
#import <SessionMessagingKit/Environment.h>
#import <SessionMessagingKit/OWSPreferences.h>
#import <SessionMessagingKit/OWSSounds.h>
#import <SignalUtilitiesKit/UIUtil.h>
#import "Session-Swift.h"

@implementation NotificationSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self updateTableContents];

    [LKViewControllerUtilities setUpDefaultSessionStyleForVC:self withTitle:NSLocalizedString(@"vc_notification_settings_title", @"") customBackButton:YES customBackground:NO];
    self.tableView.backgroundColor = UIColor.clearColor;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak NotificationSettingsViewController *weakSelf = self;

    OWSPreferences *prefs = Environment.shared.preferences;

    OWSTableSection *strategySection = [OWSTableSection new];
    strategySection.headerTitle = NSLocalizedString(@"preferences_notifications_strategy_category_title", @"");
    [strategySection addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"vc_notification_settings_notification_mode_title", @"")
                              accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"push_notification_strategy")
                              isOnBlock:^{
                                  return [NSUserDefaults.standardUserDefaults boolForKey:@"isUsingFullAPNs"];
                              }
                              isEnabledBlock:^{
                                  return YES;
                              }
                              target:weakSelf
                              selector:@selector(didToggleAPNsSwitch:)]];
    strategySection.footerTitle = @"You’ll be notified of new messages reliably and immediately using Apple’s notification servers.";
    [contents addSection:strategySection];

    // Sounds section.

    OWSTableSection *soundsSection = [OWSTableSection new];
    soundsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_SECTION_SOUNDS", @"Header Label for the sounds section of settings views.");
    [soundsSection
        addItem:[OWSTableItem disclosureItemWithText:
                                  NSLocalizedString(@"SETTINGS_ITEM_NOTIFICATION_SOUND",
                                      @"Label for settings view that allows user to change the notification sound.")
                                          detailText:[OWSSounds displayNameForSound:[OWSSounds globalNotificationSound]]
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"message_sound")
                                         actionBlock:^{
                                             OWSSoundSettingsViewController *vc = [OWSSoundSettingsViewController new];
                                             [weakSelf.navigationController pushViewController:vc animated:YES];
                                         }]];

    NSString *inAppSoundsLabelText = NSLocalizedString(@"NOTIFICATIONS_SECTION_INAPP",
        @"Table cell switch label. When disabled, Signal will not play notification sounds while the app is in the "
        @"foreground.");
    [soundsSection addItem:[OWSTableItem switchItemWithText:inAppSoundsLabelText
                               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"in_app_sounds")
                               isOnBlock:^{
                                   return [prefs soundInForeground];
                               }
                               isEnabledBlock:^{
                                   return YES;
                               }
                               target:weakSelf
                               selector:@selector(didToggleSoundNotificationsSwitch:)]];
    [contents addSection:soundsSection];

    OWSTableSection *backgroundSection = [OWSTableSection new];
    backgroundSection.headerTitle = NSLocalizedString(@"SETTINGS_NOTIFICATION_CONTENT_TITLE", @"table section header");
    [backgroundSection
        addItem:[OWSTableItem
                     disclosureItemWithText:NSLocalizedString(@"NOTIFICATIONS_SHOW", nil)
                                 detailText:[prefs nameForNotificationPreviewType:[prefs notificationPreviewType]]
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"options")
                                actionBlock:^{
                                    NotificationSettingsOptionsViewController *vc =
                                        [NotificationSettingsOptionsViewController new];
                                    [weakSelf.navigationController pushViewController:vc animated:YES];
                                }]];
    backgroundSection.footerTitle
        = NSLocalizedString(@"The information shown in notifications when your phone is locked.", @"");
    [contents addSection:backgroundSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)didToggleSoundNotificationsSwitch:(UISwitch *)sender
{
    [Environment.shared.preferences setSoundInForeground:sender.on];
}

- (void)didToggleAPNsSwitch:(UISwitch *)sender
{
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"isUsingFullAPNs"];
    OWSSyncPushTokensJob *syncTokensJob = [[OWSSyncPushTokensJob alloc] initWithAccountManager:AppEnvironment.shared.accountManager preferences:Environment.shared.preferences];
    syncTokensJob.uploadOnlyIfStale = NO;
    [[syncTokensJob run] retainUntilComplete];
}

@end
